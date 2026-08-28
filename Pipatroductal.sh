install_pterodactyl_panel() {
    clear

    echo "=============================================="
    echo "       NRB - PTERODACTYL PANEL INSTALLER"
    echo "              STAGE 1"
    echo "=============================================="
    echo

    if [ "$(id -u)" -ne 0 ]; then
        echo "[ERROR] Run this installer as root."
        return 1
    fi

    PANEL_DIR="/var/www/pterodactyl"

    if [ -f "$PANEL_DIR/artisan" ]; then
        echo "[ERROR] Pterodactyl Panel is already installed."
        echo
        echo "Use the NRB Panel Update option instead."
        return 1
    fi

    export DEBIAN_FRONTEND=noninteractive

    # ==========================================================
    # STAGE 1 - SYSTEM UPDATE
    # ==========================================================

    echo
    echo "[1/8] Updating system packages..."
    apt-get update -y
    apt-get upgrade -y

    # ==========================================================
    # STAGE 2 - REQUIRED PACKAGES
    # ==========================================================

    echo
    echo "[2/8] Installing required packages..."

    apt-get install -y \
        curl \
        wget \
        git \
        unzip \
        tar \
        gzip \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        nginx \
        mariadb-server \
        redis-server

    # ==========================================================
    # STAGE 3 - DOCKER
    # ==========================================================

    echo
    echo "[3/8] Installing Docker..."

    install -m 0755 -d /etc/apt/keyrings

    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
        curl -fsSL https://download.docker.com/linux/$ID/gpg \
            -o /etc/apt/keyrings/docker.asc

        chmod a+r /etc/apt/keyrings/docker.asc
    fi

    . /etc/os-release

    if [ "$ID" != "ubuntu" ] && [ "$ID" != "debian" ]; then
        echo "[ERROR] This installer supports Debian and Ubuntu."
        return 1
    fi

    cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID ${VERSION_CODENAME} stable
EOF

    apt-get update -y

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable --now docker

    if ! systemctl is-active --quiet docker; then
        echo "[ERROR] Docker failed to start."
        return 1
    fi

    echo "[OK] Docker is running."

    # ==========================================================
    # STAGE 4 - PHP
    # ==========================================================

    echo
    echo "[4/8] Installing PHP and required extensions..."

    apt-get install -y \
        php \
        php-cli \
        php-fpm \
        php-mysql \
        php-gd \
        php-mbstring \
        php-bcmath \
        php-xml \
        php-curl \
        php-zip \
        php-intl \
        php-sqlite3 \
        php-redis

    systemctl enable --now php*-fpm

    # ==========================================================
    # STAGE 5 - COMPOSER
    # ==========================================================

    echo
    echo "[5/8] Installing Composer..."

    if ! command -v composer >/dev/null 2>&1; then
        EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"

        php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"

        ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

        if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
            echo "[ERROR] Composer installer verification failed."
            rm -f /tmp/composer-setup.php
            return 1
        fi

        php /tmp/composer-setup.php \
            --install-dir=/usr/local/bin \
            --filename=composer

        rm -f /tmp/composer-setup.php
    fi

    echo "[OK] Composer installed."

    # ==========================================================
    # STAGE 6 - DATABASE
    # ==========================================================

    echo
    echo "[6/8] Configuring MariaDB..."

    systemctl enable --now mariadb
    systemctl enable --now redis-server

    DB_NAME="panel"
    DB_USER="pterodactyl"
    DB_PASSWORD="$(openssl rand -hex 24)"

    mysql <<MYSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL

    echo "[OK] Database created."

    # ==========================================================
    # STAGE 7 - PTERODACTYL PANEL
    # ==========================================================

    echo
    echo "[7/8] Installing latest Pterodactyl Panel..."

    mkdir -p /var/www

    cd /var/www || return 1

    curl -fL \
        https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz \
        -o /tmp/pterodactyl-panel.tar.gz

    if [ ! -s /tmp/pterodactyl-panel.tar.gz ]; then
        echo "[ERROR] Failed to download Pterodactyl Panel."
        return 1
    fi

    mkdir -p "$PANEL_DIR"

    tar -xzf /tmp/pterodactyl-panel.tar.gz \
        -C "$PANEL_DIR" \
        --strip-components=1

    rm -f /tmp/pterodactyl-panel.tar.gz

    cd "$PANEL_DIR" || return 1

    cp .env.example .env

    composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction

    php artisan key:generate --force

    # ==========================================================
    # PANEL ENVIRONMENT
    # ==========================================================

    echo
    echo "=============================================="
    echo "       PTERODACTYL PANEL CONFIGURATION"
    echo "=============================================="
    echo

    read -rp "Panel APP URL (example: https://panel.example.com): " PANEL_URL

    if [ -z "$PANEL_URL" ]; then
        echo "[ERROR] Panel URL cannot be empty."
        return 1
    fi

    php artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database="$DB_NAME" \
        --username="$DB_USER" \
        --password="$DB_PASSWORD"

    php artisan p:environment:setup \
        --author="$PANEL_URL" \
        --url="$PANEL_URL" \
        --timezone="Asia/Kolkata" \
        --cache="redis" \
        --session="redis" \
        --queue="redis" \
        --redis-host="127.0.0.1" \
        --redis-port="6379" \
        --redis-password=""

    # ==========================================================
    # DATABASE MIGRATION
    # ==========================================================

    echo
    echo "[OK] Running database migrations..."

    php artisan migrate --seed --force

    # ==========================================================
    # PERMISSIONS
    # ==========================================================

    chown -R www-data:www-data "$PANEL_DIR/storage"
    chown -R www-data:www-data "$PANEL_DIR/bootstrap/cache"

    chmod -R 755 "$PANEL_DIR/storage"
    chmod -R 755 "$PANEL_DIR/bootstrap/cache"

    # ==========================================================
    # NGINX
    # ==========================================================

    echo
    echo "[OK] Configuring Nginx..."

    PHP_FPM_SOCKET="$(find /run/php -name 'php*-fpm.sock' | head -1)"

    if [ -z "$PHP_FPM_SOCKET" ]; then
        echo "[ERROR] PHP-FPM socket not found."
        return 1
    fi

    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name _;

    root $PANEL_DIR/public;
    index index.php;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCKET;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default

    ln -sf \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf

    nginx -t

    if [ $? -ne 0 ]; then
        echo "[ERROR] Nginx configuration test failed."
        return 1
    fi

    systemctl enable --now nginx
    systemctl restart nginx

    # ==========================================================
    # ADMIN ACCOUNT
    # ==========================================================

    echo
    echo "=============================================="
    echo "          CREATE PANEL ADMIN"
    echo "=============================================="
    echo

    php artisan p:user:make

    # ==========================================================
    # CACHE
    # ==========================================================

    echo
    echo "[8/8] Finalizing Panel..."

    php artisan config:clear
    php artisan cache:clear
    php artisan view:clear

    php artisan config:cache
    php artisan route:cache
    php artisan view:cache

    # ==========================================================
    # FINAL VERIFICATION
    # ==========================================================

    echo
    echo "=============================================="
    echo "       NRB PTERODACTYL PANEL READY"
    echo "=============================================="
    echo

    echo "Panel directory:"
    echo "  $PANEL_DIR"
    echo

    echo "Panel URL:"
    echo "  $PANEL_URL"
    echo

    echo "Database:"
    echo "  $DB_NAME"
    echo

    echo "Database user:"
    echo "  $DB_USER"
    echo

    echo "Database password:"
    echo "  $DB_PASSWORD"
    echo

    echo "Docker:"
    docker --version
    echo

    echo "PHP:"
    php -v | head -1
    echo

    echo "Pterodactyl:"
    php artisan --version
    echo

    echo "Nginx:"
    systemctl is-active nginx
    echo

    echo "MariaDB:"
    systemctl is-active mariadb
    echo

    echo "Redis:"
    systemctl is-active redis-server
    echo

    echo "=============================================="
    echo "       STAGE 1 COMPLETE"
    echo "=============================================="
    echo
    echo "Wings has NOT been installed."
    echo "Wings will be configured in Stage 2."
    echo
}
