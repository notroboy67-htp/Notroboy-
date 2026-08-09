#!/bin/bash

set -e

# ============================================================
#        NRB RDP PANEL - ONE CLICK INSTALLER
# ============================================================

REPO="https://github.com/notroboy67-htp/RDP.git"
INSTALL_DIR="/opt/RDP"
PANEL_DIR="$INSTALL_DIR/panel"
PORT="3000"

echo "============================================================"
echo "              NRB RDP PANEL INSTALLER"
echo "============================================================"
echo

# ------------------------------------------------------------
# ROOT CHECK
# ------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run this installer as root."
    echo
    echo "Example:"
    echo "sudo bash install.sh"
    exit 1
fi

# ------------------------------------------------------------
# UPDATE SYSTEM
# ------------------------------------------------------------

echo "[1/7] Updating system..."
apt update -y

# ------------------------------------------------------------
# INSTALL BASIC PACKAGES
# ------------------------------------------------------------

echo "[2/7] Installing required packages..."

apt install -y \
    git \
    curl \
    ca-certificates \
    build-essential

# ------------------------------------------------------------
# INSTALL NODE.JS 20
# ------------------------------------------------------------

echo "[3/7] Installing Node.js..."

if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node -p "process.versions.node.split('.')[0]")

    if [ "$NODE_VERSION" -lt 18 ]; then
        echo "[INFO] Existing Node.js is too old."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt install -y nodejs
    else
        echo "[OK] Node.js $(node --version) already installed."
    fi
else
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
fi

echo "Node.js: $(node --version)"
echo "NPM:     $(npm --version)"

# ------------------------------------------------------------
# REMOVE OLD INSTALLATION
# ------------------------------------------------------------

echo "[4/7] Preparing installation directory..."

if [ -d "$INSTALL_DIR" ]; then
    echo "[INFO] Removing previous installation..."
    rm -rf "$INSTALL_DIR"
fi

# ------------------------------------------------------------
# CLONE PROJECT
# ------------------------------------------------------------

echo "[5/7] Downloading RDP Panel..."

git clone "$REPO" "$INSTALL_DIR"

if [ ! -d "$PANEL_DIR" ]; then
    echo "[ERROR] Panel directory was not found:"
    echo "$PANEL_DIR"
    exit 1
fi

cd "$PANEL_DIR"

# ------------------------------------------------------------
# INSTALL NPM DEPENDENCIES
# ------------------------------------------------------------

echo "[6/7] Installing Node.js dependencies..."

npm install --omit=dev

# Required application directories
mkdir -p servers
mkdir -p public/uploads

# ------------------------------------------------------------
# CREATE SYSTEMD SERVICE
# ------------------------------------------------------------

echo "[7/7] Creating systemd service..."

cat > /etc/systemd/system/nrb-rdp-panel.service <<EOF
[Unit]
Description=NRB RDP Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
Environment=NODE_ENV=production
Environment=PORT=$PORT
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# START SERVICE
# ------------------------------------------------------------

systemctl daemon-reload
systemctl enable nrb-rdp-panel
systemctl restart nrb-rdp-panel

sleep 3

# ------------------------------------------------------------
# CHECK SERVICE
# ------------------------------------------------------------

if systemctl is-active --quiet nrb-rdp-panel; then

    SERVER_IP=$(hostname -I | awk '{print $1}')

    echo
    echo "============================================================"
    echo "             NRB RDP PANEL INSTALLED"
    echo "============================================================"
    echo
    echo "Panel URL:"
    echo "http://$SERVER_IP:$PORT"
    echo
    echo "Installation:"
    echo "$PANEL_DIR"
    echo
    echo "Service:"
    echo "nrb-rdp-panel"
    echo
    echo "Login:"
    echo "Username: admin"
    echo "Password: admin123"
    echo
    echo "============================================================"
    echo "Useful commands:"
    echo
    echo "Start:"
    echo "systemctl start nrb-rdp-panel"
    echo
    echo "Stop:"
    echo "systemctl stop nrb-rdp-panel"
    echo
    echo "Restart:"
    echo "systemctl restart nrb-rdp-panel"
    echo
    echo "Status:"
    echo "systemctl status nrb-rdp-panel"
    echo
    echo "Logs:"
    echo "journalctl -u nrb-rdp-panel -f"
    echo
    echo "============================================================"

else

    echo
    echo "[ERROR] RDP Panel failed to start."
    echo
    echo "Check logs with:"
    echo "journalctl -u nrb-rdp-panel -n 100 --no-pager"
    exit 1

fi
