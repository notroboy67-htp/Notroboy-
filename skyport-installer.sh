#!/bin/bash

set -e

echo "======================================"
echo "       NRB RDP PANEL INSTALLER"
echo "======================================"

apt update -y
apt install -y git unzip curl nodejs npm

echo "[1/4] Cloning RDP repository..."
rm -rf /root/RDP
git clone https://github.com/notroboy67-htp/RDP.git /root/RDP

cd /root/RDP

echo "[2/4] Checking panel directory..."
if [ -d "panel" ]; then
    cd panel
else
    echo "ERROR: panel directory not found."
    echo "Repository contents:"
    ls -la
    exit 1
fi

echo "[3/4] Installing Node.js dependencies..."
npm install

echo "[4/4] Starting panel..."
node .
