#!/bin/bash

set -Eeuo pipefail

# ============================================================
#              NRB SKYPORT PANEL INSTALLER
# ============================================================

PANEL_NAME="Skyport Panel"
PANEL_DIR="/opt/skyport"
PANEL_USER="skyport"
SERVICE_NAME="skyport"
REPO_URL="https://github.com/skyport-team/panel.git"
NODE_MAJOR="22"

# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

die() {
    error "$1"
    exit 1
}

# ============================================================
# ERROR HANDLER
# ============================================================

trap 'error "Installation failed at line $LINENO."; error "Check the output above for the actual error."' ERR

# ============================================================
# BANNER
# ============================================================

clear || true

echo
echo "============================================================"
echo "              NRB SKYPORT PANEL INSTALLER"
echo "============================================================"
echo
echo " Panel       : Skyport"
echo " Repository  : $REPO_URL"
echo " Directory   : $PANEL_DIR"
echo " Service     : $SERVICE_NAME"
echo " Node.js     : $NODE_MAJOR LTS"
echo
echo "============================================================"
echo

# ============================================================
# ROOT CHECK
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    die "Run this installer as root."
fi

success "Running as root."

# ============================================================
# OS CHECK
# ============================================================

if [ ! -f /etc/os-release ]; then
    die "Cannot detect operating system."
fi

source /etc/os-release

info "Operating system: ${PRETTY_NAME:-Unknown}"

case "${ID:-}" in
    debian|ubuntu)
        success "Supported Debian-based operating system detected."
        ;;
    *)
        warning "This installer is designed for Debian/Ubuntu."
        read -r -p "Continue anyway? [y/N]: " ANSWER

        if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
            exit 1
        fi
        ;;
esac

# ============================================================
# STOP OLD SKYPORT SERVICE
# ============================================================

if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
    info "Stopping existing Skyport service..."

    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
fi

# ============================================================
# REPAIR APT / DPKG
# ============================================================

echo
echo "============================================================"
echo "             REPAIRING APT / DPKG"
echo "============================================================"
echo

info "Checking dpkg status..."

dpkg --configure -a || true

info "Repairing broken dependencies..."

apt-get -f install -y || true

info "Cleaning package cache..."

apt-get clean || true

info "Updating package lists..."

apt-get update -y

success "APT/Dpkg preparation complete."

# ============================================================
# INSTALL BASIC PACKAGES
# ============================================================

echo
echo "============================================================"
echo "             INSTALLING SYSTEM PACKAGES"
echo "============================================================"
echo

info "Installing required packages..."

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    apt-transport-https \
    build-essential \
    git \
    unzip \
    tar

success "System packages installed."

# ============================================================
# VERIFY GIT
# ============================================================

if ! command -v git >/dev/null 2>&1; then
    die "Git installation failed."
fi

info "Git version:"
git --version

# ============================================================
# INSTALL NODE.JS
# ============================================================

echo
echo "============================================================"
echo "              INSTALLING NODE.JS"
echo "============================================================"
echo

CURRENT_NODE=""

if command -v node >/dev/null 2>&1; then
    CURRENT_NODE="$(node -v | sed 's/^v//' | cut -d. -f1)"
fi

if [ -n "$CURRENT_NODE" ] && [ "$CURRENT_NODE" = "$NODE_MAJOR" ]; then

    success "Node.js $NODE_MAJOR is already installed."

else

    info "Installing Node.js $NODE_MAJOR LTS..."

    # Remove conflicting old NodeSource configuration
    rm -f /etc/apt/sources.list.d/nodesource.list
    rm -f /etc/apt/keyrings/nodesource.gpg

    # Install NodeSource setup
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -

    apt-get update -y

    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

fi

# ============================================================
# VERIFY NODE
# ============================================================

if ! command -v node >/dev/null 2>&1; then
    die "Node.js installation failed."
fi

if ! command -v npm >/dev/null 2>&1; then
    die "NPM installation failed."
fi

NODE_VERSION="$(node -v)"
NPM_VERSION="$(npm -v)"

echo
info "Node.js : $NODE_VERSION"
info "NPM     : $NPM_VERSION"
echo

# ============================================================
# CREATE SKYPORT USER
# ============================================================

echo
echo "============================================================"
echo "             CREATING SKYPORT USER"
echo "============================================================"
echo

if id "$PANEL_USER" >/dev/null 2>&1; then
    success "User '$PANEL_USER' already exists."
else
    useradd \
        --system \
        --home-dir "$PANEL_DIR" \
        --create-home \
        --shell /usr/sbin/nologin \
        "$PANEL_USER"

    success "Created user '$PANEL_USER'."
fi

# ============================================================
# PREPARE INSTALL DIRECTORY
# ============================================================

info "Preparing $PANEL_DIR..."

if [ -d "$PANEL_DIR" ]; then

    if [ -d "$PANEL_DIR/.git" ]; then

        info "Existing Skyport repository detected."

        cd "$PANEL_DIR"

        git fetch --all

        git reset --hard origin/HEAD || true

        git pull --ff-only || true

    else

        warning "Existing directory is not a Git repository."

        mv "$PANEL_DIR" "${PANEL_DIR}.backup.$(date +%s)"

        git clone "$REPO_URL" "$PANEL_DIR"
    fi

else

    git clone "$REPO_URL" "$PANEL_DIR"

fi

cd "$PANEL_DIR"

success "Skyport source downloaded."

# ============================================================
# SHOW PROJECT FILES
# ============================================================

if [ ! -f "$PANEL_DIR/package.json" ]; then
    die "Skyport package.json was not found."
fi

success "Skyport package.json found."

# ============================================================
# NPM INSTALL
# ============================================================

echo
echo "============================================================"
echo "             INSTALLING SKYPORT DEPENDENCIES"
echo "============================================================"
echo

info "Running npm install..."

npm install --production=false

success "Skyport dependencies installed."

# ============================================================
# OWNERSHIP
# ============================================================

info "Setting Skyport ownership..."

chown -R "$PANEL_USER:$PANEL_USER" "$PANEL_DIR"

success "Ownership configured."

# ============================================================
# CREATE SYSTEMD SERVICE
# ============================================================

echo
echo "============================================================"
echo "              CREATING SYSTEMD SERVICE"
echo "============================================================"
echo

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Skyport Panel
Documentation=https://github.com/skyport-team/panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

User=${PANEL_USER}
Group=${PANEL_USER}

WorkingDirectory=${PANEL_DIR}

ExecStart=/usr/bin/node .

Environment=NODE_ENV=production

Restart=always
RestartSec=5

TimeoutStartSec=60
TimeoutStopSec=30

LimitNOFILE=65535

StandardOutput=journal
StandardError=journal

NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

success "Systemd service created."

# ============================================================
# ENABLE SERVICE
# ============================================================

info "Reloading systemd..."

systemctl daemon-reload

info "Enabling Skyport at boot..."

systemctl enable "$SERVICE_NAME"

success "Skyport enabled at boot."

# ============================================================
# START SERVICE
# ============================================================

echo
echo "============================================================"
echo "              STARTING SKYPORT PANEL"
echo "============================================================"
echo

systemctl restart "$SERVICE_NAME"

sleep 5

# ============================================================
# SERVICE CHECK
# ============================================================

if systemctl is-active --quiet "$SERVICE_NAME"; then

    success "Skyport service is running."

else

    error "Skyport failed to start."

    echo
    echo "Last Skyport logs:"
    echo "------------------------------------------------------------"

    journalctl \
        -u "$SERVICE_NAME" \
        -n 80 \
        --no-pager || true

    echo "------------------------------------------------------------"
    echo

    die "Skyport installation completed but the service failed to start."
fi

# ============================================================
# DETECT SERVER IP
# ============================================================

SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

if [ -z "$SERVER_IP" ]; then
    SERVER_IP="YOUR_SERVER_IP"
fi

# ============================================================
# FINAL STATUS
# ============================================================

echo
echo "============================================================"
echo "             SKYPORT INSTALLATION COMPLETE"
echo "============================================================"
echo
echo " Panel Directory : $PANEL_DIR"
echo " Service         : $SERVICE_NAME"
echo " Node.js         : $NODE_VERSION"
echo " NPM             : $NPM_VERSION"
echo " Status          : RUNNING"
echo
echo " Server IP       : $SERVER_IP"
echo
echo "============================================================"
echo "                  MANAGEMENT COMMANDS"
echo "============================================================"
echo
echo " Status:"
echo "   systemctl status skyport"
echo
echo " Start:"
echo "   systemctl start skyport"
echo
echo " Stop:"
echo "   systemctl stop skyport"
echo
echo " Restart:"
echo "   systemctl restart skyport"
echo
echo " Logs:"
echo "   journalctl -u skyport -f"
echo
echo " Last 100 logs:"
echo "   journalctl -u skyport -n 100 --no-pager"
echo
echo "============================================================"
echo

success "Skyport Panel installation finished."
