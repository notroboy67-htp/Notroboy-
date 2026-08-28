update_pterodactyl() {
    clear

    echo "=============================================="
    echo "       NRB - PTERODACTYL PANEL UPDATE"
    echo "=============================================="
    echo

    PANEL_DIR="/var/www/pterodactyl"

    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        echo "[ERROR] Please run this option as root."
        return 1
    fi

    # Check installation
    if [ ! -d "$PANEL_DIR" ] || [ ! -f "$PANEL_DIR/artisan" ]; then
        echo "[ERROR] Pterodactyl Panel installation was not found."
        return 1
    fi

    cd "$PANEL_DIR" || return 1

    echo "[1/6] Detecting installed version..."

    CURRENT_VERSION=$(php artisan --version 2>/dev/null \
        | sed -nE 's/.*version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')

    if [ -z "$CURRENT_VERSION" ]; then
        echo "[ERROR] Could not determine installed Pterodactyl version."
        return 1
    fi

    echo "[OK] Installed version: v$CURRENT_VERSION"

    echo
    echo "[2/6] Checking latest Pterodactyl release..."

    LATEST_VERSION=$(curl -fsSL \
        https://api.github.com/repos/pterodactyl/panel/releases/latest \
        | grep '"tag_name":' \
        | head -1 \
        | sed -E 's/.*"v([^"]+)".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        echo "[ERROR] Unable to determine latest release."
        return 1
    fi

    echo "[OK] Latest version: v$LATEST_VERSION"

    echo
    echo "[3/6] Comparing versions..."

    if [ "$(printf '%s\n' "$CURRENT_VERSION" "$LATEST_VERSION" | sort -V | tail -1)" = "$CURRENT_VERSION" ]; then
        echo
        echo "=============================================="
        echo "          PTERODACTYL IS UP TO DATE"
        echo "=============================================="
        echo
        echo "Installed : v$CURRENT_VERSION"
        echo "Latest    : v$LATEST_VERSION"
        echo
        return 0
    fi

    echo
    echo "Update available:"
    echo "  v$CURRENT_VERSION -> v$LATEST_VERSION"
    echo

    read -rp "Continue with update? [y/N]: " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Update cancelled."
        return 0
    fi

    echo
    echo "[4/6] Enabling maintenance mode..."

    php artisan down || true

    echo
    echo "[5/6] Downloading latest Panel..."

    BACKUP_DIR="/root/pterodactyl-backup-$(date +%Y%m%d-%H%M%S)"

    mkdir -p "$BACKUP_DIR"

    # Backup important configuration
    if [ -f .env ]; then
        cp .env "$BACKUP_DIR/.env"
    fi

    echo "[OK] Backup created at:"
    echo "     $BACKUP_DIR"

    # Download release
    TMP_FILE="/tmp/pterodactyl-panel.tar.gz"

    rm -f "$TMP_FILE"

    curl -fL \
        https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz \
        -o "$TMP_FILE"

    if [ ! -s "$TMP_FILE" ]; then
        echo "[ERROR] Panel download failed."

        php artisan up || true
        return 1
    fi

    # Preserve .env
    mv .env "$BACKUP_DIR/.env.update-backup" 2>/dev/null || true

    # Extract new Panel files
    tar -xzf "$TMP_FILE" -C "$PANEL_DIR"

    # Restore .env
    if [ -f "$BACKUP_DIR/.env.update-backup" ]; then
        mv "$BACKUP_DIR/.env.update-backup" "$PANEL_DIR/.env"
    fi

    rm -f "$TMP_FILE"

    echo
    echo "[OK] Panel files updated."

    echo
    echo "[6/6] Updating dependencies and database..."

    chmod -R 755 storage bootstrap/cache

    composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction

    if [ $? -ne 0 ]; then
        echo "[ERROR] Composer update failed."
        php artisan up || true
        return 1
    fi

    php artisan migrate --seed --force

    if [ $? -ne 0 ]; then
        echo "[ERROR] Database migration failed."
        php artisan up || true
        return 1
    fi

    # Clear Laravel caches
    php artisan view:clear
    php artisan config:clear
    php artisan route:clear

    # Rebuild optimized caches
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache

    # Fix permissions
    chown -R www-data:www-data \
        "$PANEL_DIR/storage" \
        "$PANEL_DIR/bootstrap/cache"

    echo
    echo "Restarting web services..."

    systemctl restart nginx 2>/dev/null || true
    systemctl restart php*-fpm 2>/dev/null || true

    php artisan up

    FINAL_VERSION=$(php artisan --version 2>/dev/null \
        | sed -nE 's/.*version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')

    echo
    echo "=============================================="
    echo "       PTERODACTYL UPDATE COMPLETE"
    echo "=============================================="
    echo
    echo "Previous : v$CURRENT_VERSION"
    echo "Current  : v${FINAL_VERSION:-$LATEST_VERSION}"
    echo
    echo "Backup:"
    echo "$BACKUP_DIR"
    echo
    echo "=============================================="
}
