#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#                 NRB PTERODACTYL INSTALLER
# ============================================================
# Installs the official Pterodactyl Panel release.
#
# Official Panel:
# https://github.com/pterodactyl/panel
# ============================================================

PANEL_DIR="/var/www/pterodactyl"
PANEL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
MYSQL_DB="panel"
MYSQL_USER="pterodactyl"

echo
echo "============================================================"
echo "              NRB PTERODACTYL INSTALLER"
echo "============================================================"
echo

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Please run this installer as root."
    echo "Example: sudo bash pipatroductal.sh"
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot detect operating system."
    exit 1
fi

source /etc/os-release

case "$ID" in
    ubuntu|debian)
        OS="$ID"
        ;;
    *)
        echo "ERROR: This installer supports Ubuntu and Debian."
        echo "Detected: $ID"
        exit 1
        ;;
esac

echo "[+] Operating system: $PRETTY_NAME"

read -rp "Enter your Panel domain/IP: " FQDN
[[ -n "$FQDN" ]] || { echo "ERROR: Domain/IP cannot be empty."; exit 1; }

read -rp "Enter admin email: " ADMIN_EMAIL
read -rp "Enter admin username: " ADMIN_USERNAME
read -rp "Enter admin first name: " ADMIN_FIRSTNAME
read -rp "Enter admin last name: " ADMIN_LASTNAME

while true; do
    read -rsp "Enter admin password: " ADMIN_PASSWORD
    echo
    read -rsp "Confirm admin password: " ADMIN_PASSWORD2
    echo

    if [[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD2" && -n "$ADMIN_PASSWORD" ]]; then
        break
    fi
    echo "ERROR: Passwords do not match."
done

read -rp "Timezone [UTC]: " TIMEZONE
TIMEZONE="${TIMEZONE:-UTC}"

echo
echo "============================================================"
echo "Installation settings"
echo "============================================================"
echo "Panel URL : http://$FQDN"
echo "Database  : $MYSQL_DB"
echo "DB User   : $MYSQL_USER"
echo "Timezone  : $TIMEZONE"
echo "============================================================"
echo

read -rp "Continue installation? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Installation cancelled."; exit 0; }

echo
echo "[1/10] Updating system..."
apt-get update -y
apt-get upgrade -y

echo
echo "[2/10] Installing required packages..."
apt-get install -y \
    curl ca-certificates gnupg lsb-release apt-transport-https \
    software-properties-common unzip tar git cron nginx \
    mariadb-server redis-server openssl

echo
echo "[3/10] Configuring PHP repository..."

if [[ "$OS" == "ubuntu" ]]; then
    add-apt-repository -y universe
    if ! grep -Rqs "ondrej/php" /etc/apt/sources.list.d/; then
        add-apt-repository -y ppa:ondrej/php
    fi
elif [[ "$OS" == "debian" ]]; then
    curl -fsSL https://packages.sury.org/php/apt.gpg \
        -o /etc/apt/trusted.gpg.d/php.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/php.list
fi

apt-get update -y

echo
echo "[4/10] Installing PHP 8.3..."
apt-get install -y \
    php8.3 php8.3-cli php8.3-common php8.3-gd \
    php8.3-mysql php8.3-mbstring php8.3-bcmath \
    php8.3-xml php8.3-fpm php8.3-curl php8.3-zip

echo
echo "[5/10] Installing Composer..."
if ! command -v composer >/dev/null 2>&1; then
    curl -sS https://getcomposer.org/installer \
        | php -- --install-dir=/usr/local/bin --filename=composer
    chmod +x /usr/local/bin/composer
fi
composer --version

echo
echo "[6/10] Starting services..."
systemctl enable --now mariadb
systemctl enable --now redis-server
systemctl enable --now nginx
systemctl enable --now php8.3-fpm
systemctl enable --now cron

echo
echo "[7/10] Configuring MariaDB..."
MYSQL_PASSWORD="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"

mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\`
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1'
    IDENTIFIED BY '${MYSQL_PASSWORD}';
ALTER USER '${MYSQL_USER}'@'127.0.0.1'
    IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.*
    TO '${MYSQL_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

echo "[+] Database created."

echo
echo "[8/10] Downloading official Pterodactyl Panel..."
mkdir -p "$PANEL_DIR"
cd "$PANEL_DIR"
rm -f panel.tar.gz

curl -fL "$PANEL_URL" -o panel.tar.gz
tar -xzvf panel.tar.gz
rm -f panel.tar.gz

chmod -R 755 storage bootstrap/cache
cp .env.example .env

echo
echo "[9/10] Installing Panel dependencies..."
COMPOSER_ALLOW_SUPERUSER=1 composer install \
    --no-dev --optimize-autoloader

echo
echo "[10/10] Configuring Pterodactyl..."
php artisan key:generate --force

php artisan p:environment:setup \
    --author="$ADMIN_EMAIL" \
    --url="http://$FQDN" \
    --timezone="$TIMEZONE" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="127.0.0.1" \
    --redis-pass="null" \
    --redis-port="6379" \
    --telemetry=true \
    --settings-ui=true

php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="$MYSQL_DB" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD"

php artisan migrate --seed --force

php artisan p:user:make \
    --email="$ADMIN_EMAIL" \
    --username="$ADMIN_USERNAME" \
    --name-first="$ADMIN_FIRSTNAME" \
    --name-last="$ADMIN_LASTNAME" \
    --password="$ADMIN_PASSWORD" \
    --admin=1

chown -R www-data:www-data "$PANEL_DIR"
chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

CRON_LINE="* * * * * php $PANEL_DIR/artisan schedule:run >> /dev/null 2>&1"
(
    crontab -u www-data -l 2>/dev/null || true
    echo "$CRON_LINE"
) | crontab -u www-data -

cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pteroq

rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${FQDN};

    root ${PANEL_DIR}/public;
    index index.php;

    client_max_body_size 100m;
    client_body_timeout 120s;

    access_log /var/log/nginx/pterodactyl.access.log;
    error_log /var/log/nginx/pterodactyl.error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }

    location = /robots.txt {
        access_log off;
        log_not_found off;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf \
    /etc/nginx/sites-enabled/pterodactyl.conf

nginx -t
systemctl restart nginx
systemctl restart php8.3-fpm
systemctl restart pteroq

cat > /root/nrb-pterodactyl-install.txt <<EOF
============================================================
NRB PTERODACTYL INSTALLATION
============================================================

Panel URL:
http://${FQDN}

Admin Email:
${ADMIN_EMAIL}

Admin Username:
${ADMIN_USERNAME}

Database:
${MYSQL_DB}

Database User:
${MYSQL_USER}

Database Password:
${MYSQL_PASSWORD}

Panel Directory:
${PANEL_DIR}

Queue Service:
pteroq

============================================================
KEEP THIS FILE SECURE.
============================================================
EOF

chmod 600 /root/nrb-pterodactyl-install.txt

echo
echo "============================================================"
echo "             INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Official Pterodactyl Panel installed."
echo
echo "Panel URL:"
echo "http://${FQDN}"
echo
echo "Admin username:"
echo "${ADMIN_USERNAME}"
echo
echo "Credentials saved to:"
echo "/root/nrb-pterodactyl-install.txt"
echo
echo "============================================================"
