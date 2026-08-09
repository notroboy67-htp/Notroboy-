#!/bin/bash

set -e

# ============================================================
# SKYPORT PANEL ONE-COMMAND INSTALLER
# ============================================================

PANEL_DIR="/opt/skyport"
SERVICE_NAME="skyport"
REPO_URL="https://github.com/skyport-team/panel.git"

echo "=============================================="
echo "        SKYPORT PANEL INSTALLER"
echo "=============================================="

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run this installer as root."
    echo "Example:"
    echo "bash <(curl -fsSL YOUR_INSTALLER_URL)"
    exit 1
fi

# ------------------------------------------------------------
# OS check
# ------------------------------------------------------------

if [ ! -f /etc/os-release ]; then
    echo "[ERROR] Cannot detect operating system."
    exit 1
fi

. /etc/os-release

echo "[INFO] Operating System: $PRETTY_NAME"

# ------------------------------------------------------------
# Update system
# ------------------------------------------------------------

echo "[1/8] Updating system..."

apt-get update -y

# ------------------------------------------------------------
# Install basic dependencies
# ------------------------------------------------------------

echo "[2/8] Installing dependencies..."

apt-get install -y \
    curl \
    git \
    ca-certificates \
    build-essential \
    gnupg

# ------------------------------------------------------------
# Install Node.js LTS
# ------------------------------------------------------------

echo "[3/8] Installing Node.js LTS..."

curl -fsSL https://deb.nodesource.com/setup_22.x | bash -

apt-get install -y nodejs

echo ""
echo "Node.js version:"
node --version

echo "NPM version:"
npm --version
echo ""

# ------------------------------------------------------------
# Remove old installation if present
# ------------------------------------------------------------

echo "[4/8] Preparing Skyport directory..."

if [ -d "$PANEL_DIR" ]; then
    echo "[INFO] Existing Skyport installation detected."

    if [ -d "$PANEL_DIR/.git" ]; then
        echo "[INFO] Updating existing repository..."
        cd "$PANEL_DIR"
        git pull
    else
        echo "[INFO] Removing incomplete installation..."
        rm -rf "$PANEL_DIR"

        git clone "$REPO_URL" "$PANEL_DIR"
    fi
else
    git clone "$REPO_URL" "$PANEL_DIR"
fi

cd "$PANEL_DIR"

# ------------------------------------------------------------
# Install npm dependencies
# ------------------------------------------------------------

echo "[5/8] Installing Skyport dependencies..."

npm install

# ------------------------------------------------------------
# Create Skyport user
# ------------------------------------------------------------

echo "[6/8] Skyport user setup..."

if id "skyport" >/dev/null 2>&1; then
    echo "[INFO] User 'skyport' already exists."
else
    useradd \
        --system \
        --home "$PANEL_DIR" \
        --shell /usr/sbin/nologin \
        skyport
fi

chown -R skyport:skyport "$PANEL_DIR"

# ------------------------------------------------------------
# Create systemd service
# ------------------------------------------------------------

echo "[7/8] Creating systemd service..."

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Skyport Panel
Documentation=https://github.com/skyport-team/panel
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple

User=skyport
Group=skyport

WorkingDirectory=$PANEL_DIR

ExecStart=/usr/bin/node .

Restart=always
RestartSec=5

Environment=NODE_ENV=production

StandardOutput=journal
StandardError=journal

LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# Enable and start service
# ------------------------------------------------------------

echo "[8/8] Starting Skyport Panel..."

systemctl daemon-reload

systemctl enable "$SERVICE_NAME"

systemctl restart "$SERVICE_NAME"

sleep 3

# ------------------------------------------------------------
# Check service
# ------------------------------------------------------------

if systemctl is-active --quiet "$SERVICE_NAME"; then

    echo ""
    echo "=============================================="
    echo "       SKYPORT INSTALLATION COMPLETE"
    echo "=============================================="
    echo ""
    echo "Panel Directory : $PANEL_DIR"
    echo "Service         : $SERVICE_NAME"
    echo "Status          : RUNNING"
    echo ""
    echo "Useful commands:"
    echo ""
    echo "  systemctl status skyport"
    echo "  systemctl restart skyport"
    echo "  systemctl stop skyport"
    echo "  systemctl start skyport"
    echo ""
    echo "View live logs:"
    echo ""
    echo "  journalctl -u skyport -f"
    echo ""
    echo "=============================================="

else

    echo ""
    echo "=============================================="
    echo "       SKYPORT FAILED TO START"
    echo "=============================================="
    echo ""
    echo "Check the logs with:"
    echo ""
    echo "journalctl -u skyport -n 100 --no-pager"
    echo ""

    exit 1
fi
