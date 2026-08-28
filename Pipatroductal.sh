#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# NRB - PTERODACTYL PANEL ONLY INSTALLER
# Stage 1
#
# Installation path:
#   /var/www/pterodactyl
#
# Wings:
#   NOT INSTALLED
# ============================================================

PANEL_DIR="/var/www/pterodactyl"
PANEL_ARCHIVE="/tmp/pterodactyl-panel.tar.gz"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${YELLOW}[NRB]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

trap 'error "Installation failed at line $LINENO."' ERR

# ============================================================
# ROOT CHECK
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    error "Run this installer as root."
    echo
    echo "Example:"
    echo "sudo bash $0"
    exit 1
fi

# ============================================================
# OS CHECK
# ============================================================

if [ ! -f /etc/os-release ]; then
    error "Cannot detect operating system."
    exit 1
fi

source /etc/os-release

case "$ID" in
    ubuntu|debian)
        ;;
    *)
        error "Unsupported operating system: $ID"
        echo "Supported: Ubuntu and Debian"
        exit 1
        ;;
esac

info "Detected OS: $PRETTY_NAME"

# ============================================================
# EXISTING INSTALLATION CHECK
# ============================================================

if [ -f "$PANEL_DIR/artisan" ]; then
    error "Pterodactyl Panel already exists at:"
    echo "$PANEL_DIR"
    echo
    echo "This installer is for a fresh installation."
    exit 1
fi

# ============================================================
# STAGE 1 - SYSTEM UPDATE
# ============================================================

echo
echo "=============================================="
echo " [1/8] SYSTEM UPDATE"
echo "=============================================="

apt-get update -y
apt-get upgrade -y

success "System updated."

# ============================================================
# STAGE 2 - BASIC DEPENDENCIES
# ============================================================

echo
echo "=============================================="
echo " [2/8] INSTALLING BASIC DEPENDENCIES"
echo "=============================================="

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
    openssl

success "Basic dependencies installed."

# ============================================================
# STAGE 3 - DOCKER
# ============================================================

echo
echo "=============================================="
echo " [3/8] INSTALLING DOCKER"
echo "=============================================="

install -m 0755 -d /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    curl -fsSL \
        "https://download.docker.com/linux/${ID}/gpg" \
        -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc
fi

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable
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
    error "Docker is not running."
    exit 1
fi

success "Docker installed and running."

# ============================================================
# STAGE 4 - PHP / NGINX / DATABASE / REDIS
# ============================================================

echo
echo "=============================================="
echo " [4/8] INSTALLING PANEL DEPENDENCIES"
echo "=============================================="

apt-get install -y \
    nginx \
    mariadb-server \
    redis-server \
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

systemctl enable --now mariadb
systemctl enable --now redis-server

PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"

info "Detected PHP version: $PHP_VERSION"

success "Panel dependencies installed."

# ============================================================
# COMPOSER
# ============================================================

info "Installing Composer..."

if ! command -v composer
