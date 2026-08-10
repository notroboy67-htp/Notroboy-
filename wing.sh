#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#                 NRB PTERODACTYL WINGS
#                 INSTALLATION SCRIPT
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${CYAN}[NRB]${NC} $1"
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

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    error "Run this installer as root."
    echo "Example:"
    echo "  sudo -i"
    echo "  bash nrb-wings-installer.sh"
    exit 1
fi

# ------------------------------------------------------------
# OS check
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect the operating system."
    exit 1
fi

source /etc/os-release

case "$ID" in
    ubuntu|debian)
        ;;
    *)
        error "This installer currently supports Ubuntu and Debian."
        error "Detected: $PRETTY_NAME"
        exit 1
        ;;
esac

info "Detected operating system: $PRETTY_NAME"

# ------------------------------------------------------------
# Check virtualization
# ------------------------------------------------------------

if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT="$(systemd-detect-virt || true)"

    case "$VIRT" in
        openvz|lxc)
            warning "Detected virtualization: $VIRT"
            warning "Docker/Wings may not work in this environment."
            warning "KVM or bare metal is recommended."
            ;;
        *)
            info "Virtualization: ${VIRT:-unknown}"
            ;;
    esac
fi

# ------------------------------------------------------------
# Install basic dependencies
# ------------------------------------------------------------

info "Installing required dependencies..."

apt-get update -y

apt-get install -y \
    ca-certificates \
    curl \
    gnupg

success "Required dependencies installed."

# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------

if command -v docker >/dev/null 2>&1; then
    success "Docker is already installed."
else
    info "Installing Docker..."

    curl -fsSL https://get.docker.com/ | CHANNEL=stable bash

    success "Docker installed."
fi

# ------------------------------------------------------------
# Start Docker
# ------------------------------------------------------------

info "Enabling Docker..."

systemctl enable --now docker

if systemctl is-active --quiet docker; then
    success "Docker is running."
else
    error "Docker failed to start."
    systemctl status docker --no-pager || true
    exit 1
fi

# ------------------------------------------------------------
# Test Docker
# ------------------------------------------------------------

info "Testing Docker..."

if docker info >/dev/null 2>&1; then
    success "Docker is working."
else
    error "Docker is not responding."
    exit 1
fi

# ------------------------------------------------------------
# Create Pterodactyl directory
# ------------------------------------------------------------

info "Creating Pterodactyl directory..."

mkdir -p /etc/pterodactyl

success "Created /etc/pterodactyl"

# ------------------------------------------------------------
# Detect architecture
# ------------------------------------------------------------

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)
        WINGS_ARCH="amd64"
        ;;
    aarch64|arm64)
        WINGS_ARCH="arm64"
        ;;
    *)
        error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

info "System architecture: $ARCH"
info "Wings architecture: $WINGS_ARCH"

# ------------------------------------------------------------
# Download Wings
# ------------------------------------------------------------

WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"

info "Downloading Pterodactyl Wings..."

curl -fL "$WINGS_URL" \
    -o /usr/local/bin/wings

chmod u+x /usr/local/bin/wings

if [[ ! -x /usr/local/bin/wings ]]; then
    error "Wings binary installation failed."
    exit 1
fi

success "Wings downloaded successfully."

# ------------------------------------------------------------
# Verify Wings binary
# ------------------------------------------------------------

info "Checking Wings..."

if /usr/local/bin/wings --version; then
    success "Wings binary is working."
else
    warning "Wings version check returned an error."
fi

# ------------------------------------------------------------
# Install systemd service
# ------------------------------------------------------------

info "Creating Wings systemd service..."

cat > /etc/systemd/system/wings.service <<'EOF'
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

success "Wings systemd service installed."

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

echo
echo "============================================================"
echo -e "${GREEN}       NRB WINGS INSTALLATION COMPLETED${NC}"
echo "============================================================"
echo
echo "Wings binary:"
echo "  /usr/local/bin/wings"
echo
echo "Wings directory:"
echo "  /etc/pterodactyl"
echo
echo "Systemd service:"
echo "  /etc/systemd/system/wings.service"
echo
echo "Service enabled:"
systemctl is-enabled wings || true
echo
echo "============================================================"
echo
warning "Do NOT start Wings yet unless /etc/pterodactyl/config.yml exists."
echo
echo "After creating the Node in your Pterodactyl Panel,"
echo "copy its generated configuration into:"
echo
echo "  /etc/pterodactyl/config.yml"
echo
echo "Then start Wings with:"
echo
echo "  systemctl enable --now wings"
echo
echo "Check Wings with:"
echo
echo "  systemctl status wings"
echo
echo "============================================================"
