#!/usr/bin/env bash
# =============================================================================
# NRB ONE-COMMAND INSTALLER
# Multi-installer for VPS / Hosting panels
#
# Includes:
#   1. Pterodactyl Panel
#   2. Pterodactyl Wings
#   3. Skyport Panel
#   4. Skyport Daemon
#   5. No-KVM QEMU VPS Manager
#   6. System dependency installer
#
# Usage:
#   chmod +x nrb-installer.sh
#   sudo ./nrb-installer.sh
#
# One-command after uploading to GitHub:
#   bash <(curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/nrb-installer.sh)
# =============================================================================

set -Eeuo pipefail

APP_NAME="NRB ONE-COMMAND INSTALLER"
LOG_FILE="/var/log/nrb-installer.log"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/nrb-installer.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ----------------------------- Colors ----------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

trap 'echo -e "${RED}[ERROR]${NC} Installer stopped at line $LINENO. Check $LOG_FILE"' ERR

# ----------------------------- Helpers ---------------------------------------
require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Run as root: sudo bash nrb-installer.sh"
    fi
}

detect_os() {
    [[ -f /etc/os-release ]] || die "Cannot detect operating system."
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    info "Detected: ${PRETTY_NAME:-$OS_ID $OS_VERSION}"
}

apt_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y "$@"
}

check_debian_like() {
    [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]] || \
        die "This installer section currently supports Debian/Ubuntu."
}

pause() {
    echo
    read -r -p "Press ENTER to return to the menu..." _
}

banner() {
    clear || true
    cat <<'EOF'
=======================================================================
 _   _ ____  ____     ___  _   _ _____
| \ | |  _ \| __ )   / _ \| \ | | ____|
|  \| | |_) |  _ \  | | | |  \| |  _|
| |\  |  _ <| |_) | | |_| | |\  | |___
|_| \_|_| \_\____/   \___/|_| \_|_____|

              ONE-COMMAND HOSTING INSTALLER
=======================================================================
 Pterodactyl | Wings | Skyport | No-KVM VPS | Dependencies
=======================================================================
EOF
}

install_base() {
    require_root
    detect_os
    check_debian_like

    info "Installing common utilities..."
    apt_install curl wget git unzip tar ca-certificates gnupg lsb-release \
        software-properties-common jq openssl nano vim htop

    ok "Base dependencies installed."
}

install_docker() {
    require_root
    check_debian_like

    if command -v docker >/dev/null 2>&1; then
        ok "Docker is already installed."
    else
        info "Installing Docker CE..."
        curl -fsSL https://get.docker.com/ | CHANNEL=stable bash
    fi

    systemctl enable --now docker
    docker --version
    ok "Docker is ready."
}

install_node22() {
    require_root
    check_debian_like

    info "Installing Node.js 22..."
    mkdir -p /etc/apt/keyrings

    if [[ ! -f /etc/apt/keyrings/nodesource.gpg ]]; then
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
            | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    fi

    cat >/etc/apt/sources.list.d/nodesource.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main
EOF

    apt-get update -y
    apt-get install -y nodejs git
    node --version
    npm --version
    ok "Node.js is ready."
}

# -------------------------- Pterodactyl --------------------------------------
install_pterodactyl_panel() {
    require_root
    detect_os
    check_debian_like

    if [[ "$OS_ID" == "ubuntu" && "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
        warn "Official Pterodactyl docs currently list Ubuntu 22.04/24.04 as supported."
    fi

    if [[ "$OS_ID" == "debian" && "$OS_VERSION" != "11" && "$OS_VERSION" != "12" && "$OS_VERSION" != "13" ]]; then
        warn "Official Pterodactyl docs currently list Debian 11/12/13 as supported."
    fi

    echo
    echo "Pterodactyl Panel setup"
    echo "The official installation requires a domain/IP and database settings."
    echo

    read -r -p "Panel domain (example.com): " PANEL_DOMAIN
    [[ -n "$PANEL_DOMAIN" ]] || die "Domain cannot be empty."

    read -r -p "Database name [panel]: " DB_NAME
    DB_NAME="${DB_NAME:-panel}"

    read -r -p "Database user [pterodactyl]: " DB_USER
    DB_USER="${DB_USER:-pterodactyl}"

    read -r -s -p "Database password: " DB_PASS
    echo
    [[ -n "$DB_PASS" ]] || die "Database password cannot be empty."

    read -r -p "Admin email: " ADMIN_EMAIL
    [[ -n "$ADMIN_EMAIL" ]] || die "Admin email cannot be empty."

    info "Installing Pterodactyl dependencies..."
    apt_install curl apt-transport-https ca-certificates gnupg \
        mariadb-server nginx tar unzip git redis-server

    # PHP 8.3 repository for Debian/Ubuntu where required.
    if ! command -v php >/dev/null 2>&1 || [[ "$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" != "8.3" ]]; then
        if [[ "$OS_ID" == "ubuntu" ]]; then
            apt_install software-properties-common
            add-apt-repository -y ppa:ondrej/php
            apt-get update -y
        else
            apt_install lsb-release apt-transport-https ca-certificates
            curl -fsSL https://packages.sury.org/php/apt.gpg \
                | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg
            echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
                >/etc/apt/sources.list.d/php.list
            apt-get update -y
        fi
    fi

    apt_install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip}

    if ! command -v composer >/dev/null 2>&1; then
        curl -sS https://getcomposer.org/installer \
            | php -- --install-dir=/usr/local/bin --filename=composer
    fi

    systemctl enable --now mariadb redis-server nginx php8.3-fpm

    info "Creating Pterodactyl database..."
    mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl

    info "Downloading the latest Pterodactyl Panel release..."
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzf panel.tar.gz
    rm -f panel.tar.gz

    chmod -R 755 storage bootstrap/cache
    cp -n .env.example .env || true

    info "Installing PHP dependencies..."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

    php artisan key:generate --force

    # Configure core values through the official artisan commands.
    php artisan p:environment:setup --url="http://${PANEL_DOMAIN}" \
        --timezone="UTC" --cache="redis" --session="redis" --queue="redis" --settings-ui=true

    php artisan p:environment:database \
        --host="127.0.0.1" --port="3306" \
        --database="${DB_NAME}" --username="${DB_USER}" --password="${DB_PASS}"

    php artisan migrate --seed --force

    chown -R www-data:www-data /var/www/pterodactyl

    # Basic NGINX configuration.
    cat >/etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};

    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log;

    client_max_body_size 100m;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/default

    nginx -t
    systemctl restart nginx php8.3-fpm

    # Queue worker.
    cat >/etc/systemd/system/pteroq.service <<'EOF'
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

    ok "Pterodactyl Panel files and services are installed."
    warn "Create the first admin with: cd /var/www/pterodactyl && php artisan p:user:make"
    warn "For HTTPS, configure a valid certificate for ${PANEL_DOMAIN} before enabling SSL."
    echo "Panel URL: http://${PANEL_DOMAIN}"
}

install_wings() {
    require_root
    detect_os
    check_debian_like
    install_docker

    mkdir -p /etc/pterodactyl

    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64) WINGS_ARCH="amd64" ;;
        aarch64|arm64) WINGS_ARCH="arm64" ;;
        *) die "Unsupported architecture for Wings: $ARCH" ;;
    esac

    info "Downloading Pterodactyl Wings..."
    curl -L -o /usr/local/bin/wings \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"
    chmod u+x /usr/local/bin/wings

    cat >/etc/systemd/system/wings.service <<'EOF'
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
    systemctl enable wings

    ok "Wings installed."
    warn "Create a node in Pterodactyl, then place its generated config.yml at:"
    echo "      /etc/pterodactyl/config.yml"
    echo "Then run: systemctl start wings"
}

# ----------------------------- Skyport ----------------------------------------
install_skyport_panel() {
    require_root
    detect_os
    check_debian_like

    install_docker
    install_node22

    mkdir -p /etc/skyport

    if [[ -d /etc/skyport/.git ]]; then
        info "Skyport directory already exists; pulling updates..."
        git -C /etc/skyport pull --ff-only || warn "Could not fast-forward Skyport repository."
    else
        info "Downloading Skyport Panel..."
        rm -rf /etc/skyport
        git clone https://github.com/skyport-team/panel /etc/skyport
    fi

    cd /etc/skyport
    npm install

    if [[ ! -f config.json && -f example_config.json ]]; then
        cp example_config.json config.json
    fi

    npm link || true
    npm run seed
    npm run createUser

    npm install -g pm2
    pm2 delete skyport >/dev/null 2>&1 || true
    pm2 start index.js --name skyport
    pm2 save

    ok "Skyport Panel installed."
    echo "Default documented port: 3001"
    echo "Config: /etc/skyport/config.json"
}

install_skyport_daemon() {
    require_root
    detect_os
    check_debian_like

    install_docker
    install_node22

    if [[ -d /etc/skyportd/.git ]]; then
        git -C /etc/skyportd pull --ff-only || true
    else
        rm -rf /etc/skyportd
        git clone https://github.com/skyport-team/skyportd /etc/skyportd
    fi

    cd /etc/skyportd
    npm install

    if [[ ! -f config.json && -f example_config.json ]]; then
        cp example_config.json config.json
    fi

    npm install -g pm2
    pm2 delete skyportd >/dev/null 2>&1 || true
    pm2 start index.js --name skyportd
    pm2 save

    ok "Skyport Daemon installed."
    warn "Add this daemon to your Skyport Panel and use its generated configuration command."
}

# --------------------------- No-KVM VPS Manager -------------------------------
install_nokvm_manager() {
    require_root
    detect_os
    check_debian_like

    info "Installing QEMU No-KVM VPS dependencies..."
    apt_install qemu-system-x86 qemu-utils cloud-image-utils wget curl openssl

    mkdir -p /opt/nrb-vps /var/lib/nrb-vps
    chmod 755 /opt/nrb-vps

    cat >/usr/local/bin/nrb-vps <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

BASE="/var/lib/nrb-vps"
mkdir -p "$BASE"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing dependency: $1"
        exit 1
    }
}

list_vms() {
    echo "Available VMs:"
    find "$BASE" -mindepth 1 -maxdepth 1 -type d -printf ' - %f\n' | sort
}

vm_dir() { echo "$BASE/$1"; }

create_vm() {
    read -r -p "VM name: " NAME
    [[ "$NAME" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Invalid VM name."; return; }

    read -r -p "Disk size (example 20G): " SIZE
    SIZE="${SIZE:-20G}"

    D="$(vm_dir "$NAME")"
    [[ ! -e "$D" ]] || { echo "VM already exists."; return; }

    mkdir -p "$D"
    qemu-img create -f qcow2 "$D/disk.qcow2" "$SIZE"

    cat >"$D/run.sh" <<RUN
#!/usr/bin/env bash
exec qemu-system-x86_64 \
  -m 2048 \
  -smp 2 \
  -drive file="$D/disk.qcow2",format=qcow2,if=virtio \
  -netdev user,id=n1,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=n1 \
  -nographic \
  -enable-kvm
RUN
    chmod +x "$D/run.sh"

    # If KVM is unavailable, automatically remove -enable-kvm.
    if [[ ! -e /dev/kvm ]]; then
        sed -i 's/  -enable-kvm//' "$D/run.sh"
    fi

    echo "VM created: $NAME"
    echo "Put an OS installer/cloud image into:"
    echo "  $D/"
    echo "Then customize $D/run.sh before first boot."
}

start_vm() {
    read -r -p "VM name: " NAME
    D="$(vm_dir "$NAME")"
    [[ -x "$D/run.sh" ]] || { echo "VM not found."; return; }
    "$D/run.sh"
}

delete_vm() {
    read -r -p "VM name to DELETE: " NAME
    D="$(vm_dir "$NAME")"
    [[ -d "$D" ]] || { echo "VM not found."; return; }
    read -r -p "Type DELETE to confirm: " CONFIRM
    [[ "$CONFIRM" == "DELETE" ]] || { echo "Cancelled."; return; }
    rm -rf "$D"
    echo "Deleted."
}

while true; do
    clear || true
    echo "=============================================="
    echo " NRB NO-KVM VPS MANAGER"
    echo "=============================================="
    echo "1) List VMs"
    echo "2) Create VM"
    echo "3) Start VM"
    echo "4) Delete VM"
    echo "5) Exit"
    echo
    read -r -p "Select: " C
    case "$C" in
        1) list_vms; read -r -p "ENTER..." _ ;;
        2) create_vm; read -r -p "ENTER..." _ ;;
        3) start_vm ;;
        4) delete_vm; read -r -p "ENTER..." _ ;;
        5) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done
EOF

    chmod +x /usr/local/bin/nrb-vps
    ln -sf /usr/local/bin/nrb-vps /usr/local/bin/nrb-vm

    ok "No-KVM VPS manager installed."
    echo "Run: nrb-vps"
    warn "No-KVM mode is CPU-emulated QEMU. Performance is lower than KVM."
}

# ----------------------------- Diagnostics -----------------------------------
system_check() {
    echo
    echo "================ SYSTEM CHECK ================"
    echo "OS:       ${PRETTY_NAME:-unknown}"
    echo "Kernel:   $(uname -r)"
    echo "Arch:     $(uname -m)"
    echo "CPU:      $(nproc) cores"
    echo "RAM:      $(free -h | awk '/^Mem:/ {print $2}')"
    echo "Disk:     $(df -h / | awk 'NR==2 {print $2 " total, " $4 " free"}')"
    echo "KVM:      $( [[ -e /dev/kvm ]] && echo 'AVAILABLE' || echo 'NOT AVAILABLE' )"
    echo "Docker:   $(command -v docker >/dev/null 2>&1 && docker --version || echo 'not installed')"
    echo "PHP:      $(command -v php >/dev/null 2>&1 && php -v | head -1 || echo 'not installed')"
    echo "Node:     $(command -v node >/dev/null 2>&1 && node --version || echo 'not installed')"
    echo "=============================================="
}

# -------------------------------- Menu ----------------------------------------
main_menu() {
    require_root
    detect_os

    while true; do
        banner
        cat <<'EOF'
  1) Install base dependencies
  2) Install Docker
  3) Install Node.js 22
  4) Install Pterodactyl Panel
  5) Install Pterodactyl Wings
  6) Install Skyport Panel
  7) Install Skyport Daemon
  8) Install No-KVM VPS Manager
  9) System check
  0) Exit

EOF
        read -r -p "Select an option: " CHOICE
        echo

        case "$CHOICE" in
            1) install_base; pause ;;
            2) install_docker; pause ;;
            3) install_node22; pause ;;
            4) install_pterodactyl_panel; pause ;;
            5) install_wings; pause ;;
            6) install_skyport_panel; pause ;;
            7) install_skyport_daemon; pause ;;
            8) install_nokvm_manager; pause ;;
            9) system_check; pause ;;
            0) echo "Goodbye."; exit 0 ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

main_menu
