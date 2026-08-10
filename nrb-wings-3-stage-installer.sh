#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#             NRB WINGS INSTALLER - 3 STAGE
# ============================================================
# Stage 1: Install official Pterodactyl Wings
# Stage 2: Connect Wings to a Panel node
# Stage 3: Validate and start Wings
#
# Official Wings docs:
# https://pterodactyl.io/wings/1.0/installing
#
# Node credentials MUST come from:
# Panel -> Admin -> Nodes -> Your Node -> Configuration
# ============================================================

WINGS_BIN="/usr/local/bin/wings"
WINGS_DIR="/etc/pterodactyl"
WINGS_CONFIG="${WINGS_DIR}/config.yml"
WINGS_SERVICE="/etc/systemd/system/wings.service"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info(){ echo -e "${CYAN}[INFO]${NC} $*"; }
ok(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARNING]${NC} $*"; }
die(){ echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

TMP_WINGS=""
TMP_CONFIG=""

cleanup() {
    [[ -n "$TMP_WINGS" && -f "$TMP_WINGS" ]] && rm -f "$TMP_WINGS"
    [[ -n "$TMP_CONFIG" && -f "$TMP_CONFIG" ]] && rm -f "$TMP_CONFIG"
}
trap cleanup EXIT

# ============================================================
# BASIC CHECKS
# ============================================================

[[ "$EUID" -eq 0 ]] || die "Run this installer as root."

[[ -f /etc/os-release ]] || die "Cannot detect operating system."
# shellcheck disable=SC1091
source /etc/os-release

case "${ID:-}" in
    ubuntu|debian|rocky|almalinux|rhel) ;;
    *) die "Unsupported operating system: ${ID:-unknown}" ;;
esac

case "$(uname -m)" in
    x86_64) WINGS_ARCH="amd64" ;;
    aarch64|arm64) WINGS_ARCH="arm64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
esac

if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT="$(systemd-detect-virt 2>/dev/null || true)"
    case "$VIRT" in
        lxc|openvz)
            die "LXC/OpenVZ may not provide the Docker features required by Wings."
            ;;
    esac
fi

clear 2>/dev/null || true

echo
echo "============================================================"
echo "              NRB WINGS INSTALLER"
echo "============================================================"
echo
echo "This installer has 3 stages:"
echo
echo "  [1] Install official Wings"
echo "  [2] Connect Wings to Panel Node"
echo "  [3] Verify and start Wings"
echo

# ============================================================
# STAGE 1 - WINGS INSTALLATION
# ============================================================

echo
echo "============================================================"
echo "             [1/3] WINGS INSTALLATION"
echo "============================================================"
echo

# Repair interrupted dpkg first.
if command -v dpkg >/dev/null 2>&1; then
    info "Checking dpkg..."
    dpkg --configure -a || die "dpkg repair failed."
    ok "dpkg is ready."
fi

# Dependencies.
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive

    info "Updating package lists..."
    apt-get update -y

    info "Installing required packages..."
    apt-get install -y curl ca-certificates
else
    command -v curl >/dev/null || die "curl is required."
fi

# Docker.
if command -v docker >/dev/null 2>&1; then
    ok "Docker already installed."
else
    info "Installing Docker..."
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    command -v docker >/dev/null || die "Docker installation failed."
fi

systemctl enable --now docker
systemctl is-active --quiet docker || die "Docker is not running."
ok "Docker is running."

# Wings directory.
mkdir -p "$WINGS_DIR"
chmod 755 "$WINGS_DIR"

# Stop an existing Wings service before replacing the binary.
systemctl stop wings.service 2>/dev/null || true

# Download to temporary file to prevent curl error 23 / Text file busy.
TMP_WINGS="$(mktemp /tmp/nrb-wings.XXXXXX)"

WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"

info "Downloading official Pterodactyl Wings..."
echo "  $WINGS_URL"

curl -fL --retry 3 --connect-timeout 20 \
    -o "$TMP_WINGS" "$WINGS_URL" \
    || die "Wings download failed."

[[ -s "$TMP_WINGS" ]] || die "Downloaded Wings file is empty."

# ELF check.
if command -v od >/dev/null 2>&1; then
    head -c 4 "$TMP_WINGS" | od -An -tx1 | grep -qi '7f 45 4c 46' \
        || die "Downloaded Wings file is not a valid Linux executable."
fi

# Install only after successful download.
install -m 755 "$TMP_WINGS" "$WINGS_BIN"
[[ -x "$WINGS_BIN" ]] || die "Wings installation failed."

ok "Wings binary installed."

info "Installed Wings version:"
"$WINGS_BIN" version || true

echo
ok "STAGE 1 COMPLETE - Wings is installed."
echo

# ============================================================
# STAGE 2 - PANEL NODE CONNECTION
# ============================================================

echo
echo "============================================================"
echo "          [2/3] CONNECT WINGS TO PANEL NODE"
echo "============================================================"
echo
echo "Get these values from:"
echo
echo "  Pterodactyl Panel"
echo "    -> Admin"
echo "    -> Nodes"
echo "    -> Your Node"
echo "    -> Configuration"
echo
echo "The four values must belong to the SAME node."
echo

read -r -p "Panel URL: " PANEL_URL
PANEL_URL="${PANEL_URL%/}"
PANEL_URL="$(printf '%s' "$PANEL_URL" | xargs)"

[[ "$PANEL_URL" =~ ^https?:// ]] \
    || die "Panel URL must start with http:// or https://"

read -r -p "Node UUID: " NODE_UUID
NODE_UUID="$(printf '%s' "$NODE_UUID" | xargs)"

[[ "$NODE_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] \
    || die "Invalid Node UUID."

read -r -p "Token ID: " TOKEN_ID
TOKEN_ID="$(printf '%s' "$TOKEN_ID" | xargs)"

[[ -n "$TOKEN_ID" ]] || die "Token ID cannot be empty."

read -r -s -p "Token: " TOKEN
echo

[[ -n "$TOKEN" ]] || die "Token cannot be empty."

echo
info "Node information received."
ok "UUID format verified."
ok "Token ID received."
ok "Panel URL verified."

# ------------------------------------------------------------
# Create configuration.
#
# IMPORTANT:
# The Panel's complete Configuration tab is authoritative.
# This baseline contains the four requested connection values
# and standard Wings defaults. If your node has custom SSL,
# SFTP, allocations, mounts, or Docker settings, use the exact
# Configuration generated by the Panel.
# ------------------------------------------------------------

TMP_CONFIG="$(mktemp /tmp/nrb-wings-config.XXXXXX)"
chmod 600 "$TMP_CONFIG"

cat > "$TMP_CONFIG" <<EOF
debug: false
app_name: Pterodactyl
uuid: '${NODE_UUID}'
token_id: '${TOKEN_ID}'
token: '${TOKEN}'
remote: '${PANEL_URL}'

api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: false
  upload_limit: 100
  trusted_proxies: []

system:
  root_directory: /var/lib/pterodactyl
  log_directory: /var/log/pterodactyl
  data: /var/lib/pterodactyl/volumes
  archive_directory: /var/lib/pterodactyl/archives
  tmp_directory: /tmp/pterodactyl
  username: pterodactyl
  timezone: UTC
  disk_check_interval: 150
  activity_send_interval: 60
  activity_send_count: 100
  check_permissions_on_boot: true
  enable_log_rotate: true
  websocket_log_count: 150
  sftp:
    bind_address: 0.0.0.0
    bind_port: 2022

docker:
  network:
    interface: 172.18.0.1
    dns:
      - 1.1.1.1
      - 8.8.8.8
    name: pterodactyl_nw
    network_mode: pterodactyl_nw
    driver: bridge
  tmpfs_size: 100
  container_pid_limit: 512
  timeout: 30

remote_query:
  timeout: 30

allowed_mounts: []
allowed_origins: []
EOF

# Backup old configuration if present.
if [[ -f "$WINGS_CONFIG" ]]; then
    BACKUP="${WINGS_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a "$WINGS_CONFIG" "$BACKUP"
    chmod 600 "$BACKUP"
    ok "Previous config backed up: $BACKUP"
fi

install -m 600 "$TMP_CONFIG" "$WINGS_CONFIG"
chown root:root "$WINGS_CONFIG"

# Verify values were written.
grep -Fq "uuid: '${NODE_UUID}'" "$WINGS_CONFIG" \
    || die "UUID verification failed."

grep -Fq "token_id: '${TOKEN_ID}'" "$WINGS_CONFIG" \
    || die "Token ID verification failed."

grep -Fq "remote: '${PANEL_URL}'" "$WINGS_CONFIG" \
    || die "Panel URL verification failed."

ok "Panel node configuration written."
ok "Node UUID verified."

# Remove credentials from shell variables.
unset TOKEN TOKEN_ID NODE_UUID PANEL_URL

echo
ok "STAGE 2 COMPLETE - Wings is configured for the Panel node."
echo

# ============================================================
# STAGE 3 - SERVICE + VERIFICATION
# ============================================================

echo
echo "============================================================"
echo "             [3/3] VERIFY AND START WINGS"
echo "============================================================"
echo

cat > "$WINGS_SERVICE" <<'EOF'
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

chmod 644 "$WINGS_SERVICE"
systemctl daemon-reload
systemctl enable wings.service

ok "Wings service installed."

# Basic executable check.
"$WINGS_BIN" --help >/dev/null 2>&1 \
    || die "Wings executable cannot run."

ok "Wings executable verification passed."

# Start Wings.
info "Starting Wings..."

if ! systemctl start wings.service; then
    error "Wings failed to start."
    systemctl status wings.service --no-pager || true
    echo
    journalctl -u wings.service -n 80 --no-pager || true
    die "Wings startup failed."
fi

sleep 3

if systemctl is-active --quiet wings.service; then
    ok "Wings service is RUNNING."
else
    error "Wings service is not running."
    systemctl status wings.service --no-pager || true
    echo
    journalctl -u wings.service -n 80 --no-pager || true
    die "Wings did not remain running."
fi

# ============================================================
# FINAL RESULT
# ============================================================

echo
echo "============================================================"
echo "             NRB WINGS INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "  [OK] Docker installed/running"
echo "  [OK] Official Wings installed"
echo "  [OK] Panel node configuration created"
echo "  [OK] Node UUID verified"
echo "  [OK] Wings service running"
echo
echo "Configuration:"
echo "  $WINGS_CONFIG"
echo
echo "Service:"
echo "  systemctl status wings"
echo
echo "Live logs:"
echo "  journalctl -u wings -f"
echo
echo "IMPORTANT:"
echo "If the node is offline in Panel, compare the complete"
echo "Panel -> Node -> Configuration output with:"
echo "  $WINGS_CONFIG"
echo
