mkdir -p assets && cat > assets/lxd-installer.sh <<'EOF'
#!/bin/bash

set -e

echo "======================================"
echo "     NRB LXC + LXD INSTALLER"
echo "======================================"

if command -v apt >/dev/null 2>&1; then
    echo "[1/6] Updating system..."
    sudo apt update
    sudo apt upgrade -y

    echo "[2/6] Installing LXC dependencies..."
    sudo apt install -y lxc lxc-utils bridge-utils uidmap snapd

    echo "[3/6] Starting snapd..."
    sudo systemctl enable --now snapd.socket

    if [ ! -e /snap ]; then
        sudo ln -s /var/lib/snapd/snap /snap || true
    fi

    echo "[4/6] Installing LXD..."
    sudo snap install lxd

    echo "[5/6] Adding current user to LXD group..."
    sudo usermod -aG lxd "$USER"

    echo "[6/6] Initializing LXD..."
    echo "Run 'newgrp lxd' and then 'sudo lxd init' if required."

    echo
    echo "======================================"
    echo " LXC + LXD installation completed!"
    echo "======================================"
    echo
    echo "Run:"
    echo "    newgrp lxd"
    echo "    sudo lxd init"
else
    echo "ERROR: apt package manager not found."
    exit 1
fi
EOF

chmod +x assets/lxd-installer.sh
