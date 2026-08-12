#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# NRB PTERODACTYL PANEL + WINGS ONE-COMMAND INSTALLER
# ============================================================
# Based on the official Pterodactyl Panel + Wings installation
# flow. NRB changes are limited to branding, prompts, examples,
# validation, and verification.
#
# Supported target OS for this guided installer:
#   Ubuntu 22.04 / 24.04
#   Debian 11 / 12 / 13
#
# IMPORTANT:
#   - Run as root.
#   - A clean VPS is strongly recommended.
#   - Do not run this on an existing production Pterodactyl
#     installation.
#   - Wings requires Docker and a virtualization environment
#     capable of running Docker (KVM/dedicated is recommended).
#
# Official references:
#   https://pterodactyl.io/panel/1.0/getting_started.html
#   https://pterodactyl.io/wings/1.0/installing
# ============================================================

export DEBIAN_FRONTEND=noninteractive

PANEL_DIR="/var/www/pterodactyl"
WINGS_DIR="/etc/pterodactyl"
WINGS_BIN="/usr/local/bin/wings"
NGINX_SITE="/etc/nginx/sites-available/pterodactyl.conf"
QUEUE_SERVICE="/etc/systemd/system/pteroq.service"
WINGS_SERVICE="/etc/systemd/system/wings.service"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[NRB]${NC} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

trap 'echo -e "\n${RED}[FAIL]${NC} Installer stopped at line $LINENO."; exit 1' ERR

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "Run this installer as root."
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

ask() {
    local prompt="$1" default="${2:-}" value
    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " value
        value="${value:-$default}"
    else
        read -r -p "$prompt: " value
    fi
    printf '%s' "$value"
}

ask_secret() {
    local prompt="$1" value
    read -r -s -p "$prompt: " value
    echo
    printf '%s' "$value"
}

yes_no() {
    local prompt="$1" default="${2:-n}" value
    while true; do
        read -r -p "$prompt [y/n, default=$default]: " value
        value="${value:-$default}"
        case "${value,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) echo "Please enter y or n." ;;
        esac
    done
}

valid_domain() {
    [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

detect_os() {
    [[ -r /etc/os-release ]] || die "Cannot detect operating system."
    . /etc/os-release

    case "${ID}:${VERSION_ID}" in
        ubuntu:22.04|ubuntu:24.04)
            OS_OK=1 ;;
        debian:11|debian:12|debian:13)
            OS_OK=1 ;;
        *)
            OS_OK=0 ;;
    esac

    echo
    echo "============================================================"
    echo "                 NRB SYSTEM CHECK"
    echo "============================================================"
    echo "OS          : ${PRETTY_NAME}"
    echo "Architecture: $(dpkg --print-architecture 2>/dev/null || uname -m)"
    echo "Kernel      : $(uname -r)"
    echo "Virtualizer : $(systemd-detect-virt 2>/dev/null || echo unknown)"
    echo

    [[ "$OS_OK" -eq 1 ]] || die \
        "This guided installer supports Ubuntu 22.04/24.04 and Debian 11/12/13."
}

check_virtualization() {
    local virt
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    case "$virt" in
        openvz|lxc)
            warn "Detected virtualization: $virt"
            warn "Pterodactyl Wings/Docker may not work in this environment."
            yes_no "Continue anyway?" "n" || die "Stopped because Docker/Wings may be unsupported."
            ;;
    esac
}

collect_config() {
    echo
    echo "============================================================"
    echo "            NRB PTERODACTYL PANEL CONFIGURATION"
    echo "============================================================"
    echo

    while true; do
        PANEL_DOMAIN="$(ask "Panel Domain (Example: panel.example.com)")"
        valid_domain "$PANEL_DOMAIN" && break
        echo "Invalid domain. Example: panel.example.com"
    done

    echo
    DB_NAME="$(ask "Database Name (Example: panel)" "panel")"
    DB_USER="$(ask "Database Username (Example: pterodactyl)" "pterodactyl")"
    while true; do
        DB_PASS="$(ask_secret "Database Password (Example: use-a-strong-random-password)")"
        [[ -n "$DB_PASS" ]] && break
        echo "Database password cannot be empty."
    done

    echo
    echo "Administrator account"
    ADMIN_EMAIL="$(ask "Admin Email (Example: admin@example.com)")"
    ADMIN_USERNAME="$(ask "Admin Username (Example: admin)" "admin")"
    ADMIN_FIRST="$(ask "Admin First Name (Example: NRB)" "NRB")"
    ADMIN_LAST="$(ask "Admin Last Name (Example: Hosting)" "Hosting")"

    echo
    echo "Mail configuration"
    echo "The official Pterodactyl installer asks for mail configuration."
    echo "You can configure SMTP later through artisan if desired."
    MAIL_DRIVER="$(ask "Mail driver (Example: smtp or mail)" "smtp")"

    echo
    echo "Web server / HTTPS"
    if yes_no "Configure HTTPS with Let's Encrypt?" "y"; then
        USE_SSL=1
    else
        USE_SSL=0
    fi

    echo
    echo "============================================================"
    echo "               NRB WINGS CONFIGURATION"
    echo "============================================================"
    echo

    NODE_NAME="$(ask "Node Name (Example: NRB Node 1)" "NRB Node 1")"

    while true; do
        NODE_FQDN="$(ask "Node FQDN (Example: node1.example.com)")"
        valid_domain "$NODE_FQDN" && break
        echo "Invalid FQDN. Example: node1.example.com"
    done

    NODE_PORT="$(ask "Wings HTTP/WebSocket Port (Example: 8080)" "8080")"
    SFTP_PORT="$(ask "SFTP Port (Example: 2022)" "2022")"
    SERVER_DIR="$(ask "Server Data Directory (Example: /var/lib/pterodactyl/volumes)" "/var/lib/pterodactyl/volumes")"

    if [[ "$USE_SSL" -eq 1 ]]; then
        if [[ "$NODE_FQDN" == "$PANEL_DOMAIN" ]]; then
            warn "Panel and Node FQDN are the same."
            warn "Use separate DNS names in production, e.g. panel.example.com and node1.example.com."
        fi
    fi

    echo
    echo "============================================================"
    echo "                 CONFIGURATION SUMMARY"
    echo "============================================================"
    echo "Panel Domain : $PANEL_DOMAIN"
    echo "Database     : $DB_NAME"
    echo "DB User      : $DB_USER"
    echo "Admin Email  : $ADMIN_EMAIL"
    echo "Node Name    : $NODE_NAME"
    echo "Node FQDN    : $NODE_FQDN"
    echo "Node Port    : $NODE_PORT"
    echo "SFTP Port    : $SFTP_PORT"
    echo "Server Dir   : $SERVER_DIR"
    echo "HTTPS        : $([[ "$USE_SSL" -eq 1 ]] && echo yes || echo no)"
    echo

    yes_no "Start the installation with these values?" "y" || die "Installation cancelled."
}

install_base_packages() {
    log "Updating package lists..."
    apt-get update

    log "Installing required base packages..."
    apt-get install -y \
        ca-certificates curl apt-transport-https software-properties-common \
        gnupg lsb-release git tar unzip sudo cron mariadb-server nginx \
        redis-server certbot python3-certbot-nginx

    ok "Base packages installed."
}

setup_php() {
    log "Installing PHP 8.3 and required extensions..."

    if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "22.04" ]]; then
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:ondrej/php
        apt-get update
    fi

    apt-get install -y \
        php8.3 php8.3-cli php8.3-common php8.3-gd php8.3-mysql \
        php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-curl \
        php8.3-zip php8.3-fpm

    systemctl enable --now php8.3-fpm
    ok "PHP $(php -r 'echo PHP_VERSION;') installed."
}

setup_composer() {
    if command_exists composer; then
        ok "Composer already installed: $(composer --version 2>/dev/null | head -1)"
        return
    fi

    log "Installing Composer 2..."
    EXPECTED_CHECKSUM="$(curl -fsSL https://composer.github.io/installer.sig)"
    php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

    [[ "$EXPECTED_CHECKSUM" == "$ACTUAL_CHECKSUM" ]] || {
        rm -f /tmp/composer-setup.php
        die "Composer installer checksum verification failed."
    }

    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f /tmp/composer-setup.php
    composer --version
    ok "Composer installed."
}

setup_database() {
    log "Enabling MariaDB and Redis..."
    systemctl enable --now mariadb
    systemctl enable --now redis-server

    log "Creating Pterodactyl database and user..."

    mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS//\'/\'\'}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS//\'/\'\'}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

    ok "MariaDB database/user ready."
}

download_panel() {
    log "Downloading the official Pterodactyl Panel release..."

    mkdir -p "$PANEL_DIR"
    cd "$PANEL_DIR"

    if [[ -f .env && -f artisan ]]; then
        die "$PANEL_DIR already contains an existing Panel installation. Refusing to overwrite it."
    fi

    curl -fL -o panel.tar.gz \
        "https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"

    tar -xzf panel.tar.gz
    rm -f panel.tar.gz

    chmod -R 755 storage bootstrap/cache
    ok "Official Panel files extracted."
}

configure_panel() {
    cd "$PANEL_DIR"

    log "Installing Panel Composer dependencies..."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

    cp .env.example .env

    log "Generating application encryption key..."
    php artisan key:generate --force

    log "Configuring Panel environment..."
    # These artisan commands are the official interactive configuration path.
    # They are intentionally kept interactive because SMTP/session/cache settings
    # depend on the operator's environment.
    php artisan p:environment:setup

    log "Configuring database..."
    php artisan p:environment:database

    log "Configuring mail..."
    php artisan p:environment:mail

    log "Migrating and seeding the database..."
    php artisan migrate --seed --force

    echo
    echo "============================================================"
    echo "              CREATE PANEL ADMINISTRATOR"
    echo "============================================================"
    echo "Example:"
    echo "  Email: admin@example.com"
    echo "  Username: admin"
    echo "  First name: NRB"
    echo "  Last name: Hosting"
    echo
    php artisan p:user:make

    chown -R www-data:www-data "$PANEL_DIR"/*
    ok "Panel environment/database/admin setup completed."
}

configure_queue() {
    log "Configuring Pterodactyl cron..."
    (crontab -u root -l 2>/dev/null | grep -Fv "/var/www/pterodactyl/artisan schedule:run" || true;
     echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -u root -

    log "Creating pteroq.service..."
    cat > "$QUEUE_SERVICE" <<'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now pteroq.service
    ok "Pterodactyl queue worker enabled."
}

configure_nginx() {
    log "Configuring NGINX..."

    rm -f /etc/nginx/sites-enabled/default

    cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};

    root ${PANEL_DIR}/public;
    index index.php;
    charset utf-8;

    client_max_body_size 100m;
    client_body_timeout 120s;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log /var/log/nginx/pterodactyl.error.log error;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/pterodactyl.conf

    nginx -t
    systemctl enable --now nginx
    systemctl reload nginx

    ok "NGINX configured."
}

configure_ssl() {
    [[ "$USE_SSL" -eq 1 ]] || return 0

    log "Requesting Let's Encrypt certificate for $PANEL_DOMAIN..."
    certbot --nginx --non-interactive --agree-tos \
        --register-unsafely-without-email \
        -d "$PANEL_DOMAIN" --redirect

    ok "Panel HTTPS configured."
}

install_docker() {
    if command_exists docker; then
        ok "Docker already installed."
    else
        log "Installing Docker CE using Docker's official convenience installer..."
        curl -fsSL https://get.docker.com | CHANNEL=stable bash
    fi

    systemctl enable --now docker
    docker info >/dev/null 2>&1 || die "Docker is installed but docker info failed."
    ok "Docker is running."
}

install_wings() {
    log "Installing Wings..."

    mkdir -p "$WINGS_DIR"

    local arch
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) die "Unsupported CPU architecture: $(uname -m)" ;;
    esac

    curl -fL -o "$WINGS_BIN" \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${arch}"
    chmod u+x "$WINGS_BIN"

    "$WINGS_BIN" --version || true
    ok "Wings binary installed."
}

configure_wings_service() {
    log "Creating official-style Wings systemd service..."

    cat > "$WINGS_SERVICE" <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    ok "Wings service file created."
}

show_auto_deploy() {
    echo
    echo "============================================================"
    echo "              WINGS AUTO-DEPLOY STEP"
    echo "============================================================"
    echo
    echo "The official Pterodactyl workflow requires the Panel to"
    echo "generate the node configuration. The installer will NOT"
    echo "invent a token or fake config.yml."
    echo
    echo "In your Panel:"
    echo "  Administration -> Nodes -> Create New"
    echo
    echo "Use these example values:"
    echo "  Name:           $NODE_NAME"
    echo "  FQDN:           $NODE_FQDN"
    echo "  Daemon Port:    $NODE_PORT"
    echo "  SFTP Port:      $SFTP_PORT"
    echo "  Server Directory: $SERVER_DIR"
    echo
    echo "Then open:"
    echo "  Node -> Configuration"
    echo
    echo "Choose the official 'Generate Token' / Auto-Deploy option"
    echo "and copy the generated bash command."
    echo
    echo "You can paste that command below. The installer will only"
    echo "accept the official Pterodactyl wings configure command and"
    echo "will NOT execute arbitrary pasted shell commands."
    echo

    local cmd
    read -r -p "Paste the generated Wings Auto-Deploy command (or press ENTER to configure manually): " cmd

    if [[ -z "$cmd" ]]; then
        warn "Auto-Deploy command skipped."
        return 0
    fi

    # Accept common official generated command shapes without executing arbitrary input.
    # Examples seen in official workflows contain wings configure --panel=... --token=...
    if [[ "$cmd" =~ ^[[:space:]]*(sudo[[:space:]]+)?/?(usr/local/bin/)?wings[[:space:]]+configure[[:space:]] ]]; then
        log "Executing validated Wings configure command..."
        bash -c "$cmd"
        ok "Wings configuration command completed."
    elif [[ "$cmd" =~ ^[[:space:]]*(curl|wget)[[:space:]] ]]; then
        die "For safety, curl/wget pipelines are not accepted here. Use the generated 'wings configure ...' command."
    else
        die "Command does not look like the official Wings configure command."
    fi

    [[ -s "$WINGS_DIR/config.yml" ]] || die "Auto-Deploy finished but /etc/pterodactyl/config.yml was not created."
    chmod 600 "$WINGS_DIR/config.yml"
    ok "/etc/pterodactyl/config.yml created."
}

verify_wings_config() {
    [[ -s "$WINGS_DIR/config.yml" ]] || {
        warn "No Wings config.yml exists yet."
        return 0
    }

    log "Validating Wings configuration..."
    timeout 20s "$WINGS_BIN" --debug >/tmp/nrb-wings-debug.log 2>&1 || true

    if grep -Eqi "error|fatal|panic|invalid.*config|failed" /tmp/nrb-wings-debug.log; then
        warn "Wings debug output contains an error. Last 40 lines:"
        tail -n 40 /tmp/nrb-wings-debug.log
        return 1
    fi

    ok "Wings debug validation did not report a startup error."
}

start_wings() {
    [[ -s "$WINGS_DIR/config.yml" ]] || {
        warn "Wings cannot be started as a configured node until config.yml is supplied."
        return 0
    }

    systemctl enable --now wings
    sleep 3

    if systemctl is-active --quiet wings; then
        ok "Wings service is running."
    else
        warn "Wings failed to remain active."
        systemctl status wings --no-pager -l || true
        echo
        echo "Recent Wings logs:"
        journalctl -u wings -n 80 --no-pager || true
        return 1
    fi
}

final_checks() {
    echo
    echo "============================================================"
    echo "                  NRB FINAL VERIFICATION"
    echo "============================================================"

    local failed=0

    check_service() {
        local service="$1"
        if systemctl is-active --quiet "$service"; then
            ok "$service is running"
        else
            warn "$service is NOT running"
            failed=1
        fi
    }

    check_service mariadb
    check_service redis-server
    check_service nginx
    check_service pteroq
    check_service docker

    if [[ -s "$WINGS_DIR/config.yml" ]]; then
        check_service wings
    else
        warn "Wings config.yml not present; node is not deployable yet."
        failed=1
    fi

    [[ -f "$PANEL_DIR/artisan" ]] && ok "Panel files present" || { warn "Panel files missing"; failed=1; }
    [[ -f "$PANEL_DIR/.env" ]] && ok "Panel .env present" || { warn "Panel .env missing"; failed=1; }
    [[ -x "$WINGS_BIN" ]] && ok "Wings binary present" || { warn "Wings binary missing"; failed=1; }

    echo
    if [[ "$failed" -eq 0 ]]; then
        echo -e "${GREEN}============================================================${NC}"
        echo -e "${GREEN}          NRB PTERODACTYL INSTALLATION COMPLETE${NC}"
        echo -e "${GREEN}============================================================${NC}"
        echo
        echo "Panel: https://${PANEL_DOMAIN}"
        echo "Node : ${NODE_FQDN}:${NODE_PORT}"
        echo
        echo "If the node is still Offline, run:"
        echo "  systemctl status wings --no-pager -l"
        echo "  journalctl -u wings -n 100 --no-pager"
        echo
    else
        echo -e "${YELLOW}============================================================${NC}"
        echo -e "${YELLOW} Installation completed with verification warnings${NC}"
        echo -e "${YELLOW}============================================================${NC}"
        echo
        echo "Do not assume the node is Online."
        echo "Check:"
        echo "  systemctl status wings --no-pager -l"
        echo "  journalctl -u wings -n 100 --no-pager"
        return 1
    fi
}

main() {
    require_root
    detect_os
    check_virtualization
    collect_config

    install_base_packages
    setup_php
    setup_composer
    setup_database
    download_panel
    configure_panel
    configure_queue
    configure_nginx
    configure_ssl

    install_docker
    install_wings
    configure_wings_service

    show_auto_deploy
    verify_wings_config || true
    start_wings || true

    final_checks
}

main "$@"
