#!/bin/bash

set -e

echo "=========================================="
echo "       NRB LXC + LXD ONE-CLICK INSTALLER"
echo "=========================================="
echo

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Please run this installer as root."
    echo
    echo "Run:"
    echo "sudo bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/Notroboy-/refs/heads/main/lxd-installer.sh)"
    exit 1
fi

echo "[1/7] Updating system..."
apt update -y

echo "[2/7] Installing required packages..."
apt install -y lxc lxc-utils bridge-utils uidmap snapd curl

echo "[3/7] Starting snapd..."
systemctl enable --now snapd.socket

sleep 3

echo "[4/7] Preparing /snap..."
if [ ! -e /snap ]; then
    ln -s /var/lib/snapd/snap /snap
fi

echo "[5/7] Installing LXD..."

if snap list lxd >/dev/null 2>&1; then
    echo "[INFO] LXD is already installed."
else
    snap install lxd
fi

echo "[6/7] Configuring LXD group..."

if ! getent group lxd >/dev/null 2>&1; then
    groupadd lxd
fi

usermod -aG lxd root 2>/dev/null || true

echo "[7/7] Checking installation..."
if command -v lxc >/dev/null 2>&1; then
    echo
    echo "=========================================="
    echo "       LXC + LXD INSTALLATION COMPLETE"
    echo "=========================================="
    echo
    lxc version || true
    echo
    echo "Next step:"
    echo "  lxd init"
    echo
    echo "Then test:"
    echo "  lxc list"
    echo
else
    echo
    echo "[ERROR] LXC/LXD installation failed."
    exit 1
fi
