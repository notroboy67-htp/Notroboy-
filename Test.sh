
#!/usr/bin/env bash
set -Eeuo pipefail

REPO="https://github.com/notroboy67-htp/NRB.git"
DIR="/opt/NRB"
PORT="5000"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=================================="
echo "       NRB PANEL INSTALLER"
echo "=================================="

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run this installer as root."
    exit 1
fi

# Wait for automatic package updates
echo "[1/8] Checking package manager..."
for i in $(seq 1 60); do
    if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        break
    fi
    echo "APT is busy. Waiting..."
    sleep 5
done

if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    echo "ERROR: APT is still locked. Try again later."
    exit 1
fi

# Install system packages
echo "[2/8] Installing Python and dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    git curl wget ca-certificates gnupg \
    python3 python3-pip python3-venv \
    build-essential psmisc

# Clone or update NRB
echo "[3/8] Downloading NRB..."
if [ -d "$DIR/.git" ]; then
    git -C "$DIR" pull --ff-only
else
    mkdir -p "$(dirname "$DIR")"
    git clone "$REPO" "$DIR"
fi

cd "$DIR"

# Python virtual environment
echo "[4/8] Creating Python environment..."
python3 -m venv venv
source venv/bin/activate

python -m pip install --upgrade pip setuptools wheel
python -m pip install -r requirements.txt

# Verify Python files
echo "[5/8] Checking NRB files..."
python -m py_compile nrb.py

chmod +x start.sh nrb-tool.sh 2>/dev/null || true

# Install Cloudflare
echo "[6/8] Installing Cloudflare Tunnel..."
mkdir -p /usr/share/keyrings

curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    -o /usr/share/keyrings/cloudflare-main.gpg

echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
    > /etc/apt/sources.list.d/cloudflared.list

apt-get update
apt-get install -y cloudflared

# Require systemd for persistent service
echo "[7/8] Configuring Cloudflare..."
if ! command -v systemctl >/dev/null 2>&1 || \
   [ "$(ps -p 1 -o comm= | tr -d ' ')" != "systemd" ]; then
    echo "ERROR: systemd is unavailable."
    echo "Cloudflared is installed, but cannot be registered as a system service."
    echo "Use a systemd-enabled Ubuntu/Debian VM."
    exit 1
fi

read -rsp "Paste your Cloudflare Tunnel token: " CF_TOKEN
echo

if [ -z "$CF_TOKEN" ]; then
    echo "ERROR: Empty Cloudflare token."
    exit 1
fi

cloudflared service install "$CF_TOKEN"
unset CF_TOKEN

systemctl enable cloudflared
systemctl restart cloudflared

# Start NRB
echo "[8/8] Starting NRB Panel..."
cd "$DIR"

if [ -f nrb.pid ] && kill -0 "$(cat nrb.pid)" 2>/dev/null; then
    echo "NRB is already running."
else
    nohup ./start.sh > nrb.log 2>&1 &
    echo $! > nrb.pid
fi

sleep 5

echo
echo "=================================="
echo "       NRB INSTALLATION DONE"
echo "=================================="
echo "Panel directory: $DIR"
echo "Panel port: $PORT"
echo "Cloudflare: $(systemctl is-active cloudflared)"
echo "Panel log: $DIR/nrb.log"
echo
echo "Check panel:"
echo "tail -f $DIR/nrb.log"
echo
echo "Configure Cloudflare Public Hostname:"
echo "Type: HTTP"
echo "Service: http://localhost:$PORT"
echo "=================================="
