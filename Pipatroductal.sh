#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# NRB - PTERODACTYL PANEL INSTALLER V2
# PANEL ONLY - WINGS IS NOT INSTALLED
#
# Installation path:
#   /var/www/pterodactyl
#
# Supported:
#   Debian / Ubuntu
#
# Run as root.
# ============================================================

PANEL_DIR="/var/www/pterodactyl"
PANEL_ARCHIVE="/tmp/pterodactyl-panel.tar.gz"
PHP_VERSION="8.3"
DB_NAME="panel"
DB_USER="pterodactyl"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${YELLOW}[NRB]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*"; }

trap 'fail "Installation failed at line $LINENO. No further stages will run."' ERR

if [ "$(id -u)" -ne 0 ]; then
    fail "Run this script as root."
    exit 1
fi

if [ ! -r /etc/os-release ]; then
    fail "Cannot detect the operating system."
    exit 1
fi

source /etc/os-release

case "${ID}" in
    ubuntu|debian) ;;
    *)
        fail "Unsupported OS: ${PRETTY_NAME:-$ID}"
        exit 1
        ;;
esac

if [ -f "$PANEL_DIR/artisan" ]; then
    fail "Pterodactyl Panel already exists at $PANEL_DIR."
    exit 1
fi

echo
echo "============================================================"
echo "        NRB PTERODACTYL PANEL INSTALLER V2"
echo "                    PANEL ONLY"
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. Basic packages
# ------------------------------------------------------------
info "[1/9] Updating package lists and installing prerequisites..."

apt-get update -y
apt-get install -y \
    ca-certificates \
    curl \
    wget \
    gnupg \
    unzip \
    tar \
    gzip \
    git \
    openssl \
    lsb-release \
    software-properties-common

# ------------------------------------------------------------
# 2. PHP 8.3
# ------------------------------------------------------------
info "[2/9] Installing PHP ${PHP_VERSION} and required extensions..."

if [ "$ID" = "ubuntu" ]; then
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt-get update -y
else
    # Debian: packages.sury.org provides maintained PHP packages.
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://packages.sury.org/php/apt.gpg \
        -o /etc/apt/keyrings/sury-php.gpg
    chmod a+r /etc/apt/keyrings/sury-php.gpg

    cat > /etc/apt/sources.list.d/php-sury.list <<EOF
deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ ${VERSION_CODENAME} main
EOF

    apt-get update -y
fi

apt-get install -y \
    "php${PHP_VERSION}" \
    "php${PHP_VERSION}-cli" \
    "php${PHP_VERSION}-fpm" \
    "php${PHP_VERSION}-mysql" \
    "php${PHP_VERSION}-gd" \
    "php${PHP_VERSION}-mbstring" \
    "php${PHP_VERSION}-bcmath" \
    "php${PHP_VERSION}-xml" \
    "php${PHP_VERSION}-curl" \
    "php${PHP_VERSION}-zip" \
    "php${PHP_VERSION}-intl" \
    "php${PHP_VERSION}-redis"

PHP_BIN="/usr/bin/php${PHP_VERSION}"
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"

if [ ! -x "$PHP_BIN" ]; then
    fail "PHP ${PHP_VERSION} was not installed."
    exit 1
fi

systemctl enable --now "$PHP_FPM_SERVICE"

PHP_ACTUAL="$("$PHP_BIN" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"

case "$PHP_ACTUAL" in
    8.2|8.3) ;;
    *)
        fail "Unsupported PHP version detected: $PHP_ACTUAL"
        exit 1
        ;;
esac

ok "PHP $PHP_ACTUAL installed."

# ------------------------------------------------------------
# 3. Composer 2
# ------------------------------------------------------------
info "[3/9] Installing Composer 2..."

if ! command -v composer >/dev/null 2>&1; then
    EXPECTED_SIGNATURE="$(curl -fsSL https://composer.github.io/installer.sig)"
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php

    ACTUAL_SIGNATURE="$("$PHP_BIN" -r \
        "echo hash_file('sha384', '/tmp/composer-setup.php');")"

    if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
        rm -f /tmp/composer-setup.php
        fail "Composer installer signature verification failed."
        exit 1
    fi

    "$PHP_BIN" /tmp/composer-setup.php \
        --install-dir=/usr/local/bin \
        --filename=composer

    rm -f /tmp/composer-setup.php
fi

composer --version
ok "Composer installed."

# ------------------------------------------------------------
# 4. MariaDB + Redis
# ------------------------------------------------------------
info "[4/9] Installing MariaDB and Redis..."

apt-get install -y mariadb-server redis-server

systemctl enable --now mariadb
systemctl enable --now redis-server

DB_PASSWORD="$(openssl rand -hex 32)"

mysql <<MYSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1'
    IDENTIFIED BY '${DB_PASSWORD}';

ALTER USER '${DB_USER}'@'127.0.0.1'
    IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL

ok "MariaDB and Redis are ready."

# ------------------------------------------------------------
# 5. Nginx
# ------------------------------------------------------------
info "[5/9] Installing Nginx..."

apt-get install -y nginx
systemctl enable --now nginx

# ------------------------------------------------------------
# 6. Download latest Panel
# ------------------------------------------------------------
info "[6/9] Downloading the latest Pterodactyl Panel release..."

mkdir -p /var/www "$PANEL_DIR"

curl -fL \
    https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz \
    -o "$PANEL_ARCHIVE"

test -s "$PANEL_ARCHIVE"

tar -xzf "$PANEL_ARCHIVE" \
    -C "$PANEL_DIR" \
    --strip-components=1

rm -f "$PANEL_ARCHIVE"

cd "$PANEL_DIR"

cp .env.example .env

composer install \
    --no-dev \
    --optimize-autoloader \
    --no-interaction

"$PHP_BIN" artisan key:generate --force

ok "Panel installed in $PANEL_DIR."

# ------------------------------------------------------------
# 7. Panel configuration
# ------------------------------------------------------------
info "[7/9] Panel configuration..."

echo
read -rp "Panel URL (example: https://panel.example.com): " PANEL_URL
read -rp "Admin email: " ADMIN_EMAIL

if [ -z "$PANEL_URL" ] || [ -z "$ADMIN_EMAIL" ]; then
    fail "Panel URL and admin email are required."
    exit 1
fi

"$PHP_BIN" artisan p:environment:database \
    --host=127.0.0.1 \
    --port=3306 \
    --database="$DB_NAME" \
    --username="$DB_USER" \
    --password="$DB_PASSWORD"

"$PHP_BIN" artisan p:environment:setup \
    --author="$ADMIN_EMAIL" \
    --url="$PANEL_URL" \
    --timezone="Asia/Kolkata" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="127.0.0.1" \
    --redis-port="6379" \
    --redis-password=""

info "Running migrations..."
"$PHP_BIN" artisan migrate --seed --force

# ------------------------------------------------------------
# 8. Permissions, cron, queue and Nginx
# ------------------------------------------------------------
info "[8/9] Configuring permissions, cron, queue and Nginx..."

chown -R www-data:www-data \
    "$PANEL_DIR/storage" \
    "$PANEL_DIR/bootstrap/cache"

chmod -R 755 \
    "$PANEL_DIR/storage" \
    "$PANEL_DIR/bootstrap/cache"

cat > /etc/cron.d/pterodactyl <<EOF
* * * * * www-data cd ${PANEL_DIR} && ${PHP_BIN} artisan schedule:run >> /dev/null 2>&1
EOF

chmod 644 /etc/cron.d/pterodactyl

PHP_FPM_SOCKET="/run/php/php${PHP_VERSION}-fpm.sock"

if [ ! -S "$PHP_FPM_SOCKET" ]; then
    fail "PHP-FPM socket not found: $PHP_FPM_SOCKET"
    exit 1
fi

cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name _;

    root ${PANEL_DIR}/public;
    index index.php;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_FPM_SOCKET};
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/pterodactyl.conf \
    /etc/nginx/sites-enabled/pterodactyl.conf

nginx -t
systemctl restart nginx

cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=${PHP_BIN} ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pteroq.service

# ------------------------------------------------------------
# 9. Admin + final verification
# ------------------------------------------------------------
info "[9/9] Creating the Panel administrator..."

echo
"$PHP_BIN" artisan p:user:make

info "Optimizing Panel..."
"$PHP_BIN" artisan config:clear
"$PHP_BIN" artisan cache:clear
"$PHP_BIN" artisan view:clear
"$PHP_BIN" artisan config:cache
"$PHP_BIN" artisan route:cache
"$PHP_BIN" artisan view:cache

echo
echo "============================================================"
echo "             NRB PANEL INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Panel path:       $PANEL_DIR"
echo "Panel URL:        $PANEL_URL"
echo "PHP:              $PHP_ACTUAL"
echo "Docker:           NOT INSTALLED BY THIS PANEL STAGE"
echo "MariaDB:          $(systemctl is-active mariadb)"
echo "Redis:            $(systemctl is-active redis-server)"
echo "Nginx:            $(systemctl is-active nginx)"
echo "Pterodactyl queue:$(systemctl is-active pteroq)"
echo
echo "Database name:    $DB_NAME"
echo "Database user:    $DB_USER"
echo "Database password:$DB_PASSWORD"
echo
echo "Installation path:"
echo "  $PANEL_DIR"
echo
echo "WINGS: NOT INSTALLED"
echo
echo "============================================================"
