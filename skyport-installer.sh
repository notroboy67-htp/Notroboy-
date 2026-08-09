#!/bin/bash

set -Eeuo pipefail

# ============================================================
#              NRB SKYPORT PANEL INSTALLER
# ===========================================================

SKYPORT_DIR="/opt/skyport"
SKYPORT_USER="skyport"
SERVICE_NAME="skyport"
SKYPORT_REPO="https://github.com/skyport-team/panel.git"

NODE_VERSION="22.20.0"
NODE_ARCH="linux-x64"
NODE_DIR="/opt/nodejs"

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

trap 'error "Installer failed at line $LINENO."' ERR

# ============================================================
# BANNER
# ============================================================

clear 2>/dev/null || true

echo
echo "============================================================"
echo "              NRB SKYPORT PANEL INSTALLER"
echo "============================================================"
echo
echo " Repository : $SKYPORT_REPO"
echo " Directory  : $SKYPORT_DIR"
echo " Node.js    : $NODE_VERSION"
echo
echo "============================================================"
echo

# ============================================================
# ROOT
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

success "Running as root."

# ============================================================
# CHECK REQUIRED COMMANDS
# ============================================================

echo
info "Checking required commands..."

MISSING=()

for CMD in git curl tar; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        MISSING+=("$CMD")
    else
        success "$CMD is already installed."
    fi
done

# ============================================================
# ONLY USE APT IF SOMETHING IS ACTUALLY MISSING
# ============================================================

if [ "${#MISSING[@]}" -gt 0 ]; then

    warning "Missing commands: ${MISSING[*]}"

    echo
    info "Installing only missing packages..."

    # IMPORTANT:
    # Do not blindly reinstall git.
    # This avoids the cross-device dpkg error seen in Codespaces.

    apt-get update -y

    for PACKAGE in "${MISSING[@]}"; do
        case "$PACKAGE" in
            git)
                apt-get install -y git
                ;;
            curl)
                apt-get install -y curl
                ;;
            tar)
                apt-get install -y tar
                ;;
        esac
    done

fi

# ============================================================
# VERIFY GIT
# ============================================================

command -v git >/dev/null 2>&1 || die "Git is required."

echo
info "Git version:"
git --version

# ============================================================
# NODE.JS
# ============================================================

echo
echo "============================================================"
echo "                 NODE.JS SETUP"
echo "============================================================"
echo

NODE_OK=false

if command -v node >/dev/null 2>&1; then

    CURRENT_NODE="$(node -v | sed 's/^v//' | cut -d. -f1)"

    if [ "$CURRENT_NODE" = "22" ]; then
        NODE_OK=true
        success "Node.js 22 is already installed."
    else
        warning "Existing Node.js version is not 22."
    fi

fi

if [ "$NODE_OK" = false ]; then

    info "Installing Node.js $NODE_VERSION..."

    TMP_DIR="$(mktemp -d)"
    NODE_TAR="$TMP_DIR/node.tar.xz"

    NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${NODE_ARCH}.tar.xz"

    curl -fL "$NODE_URL" -o "$NODE_TAR"

    rm -rf "$NODE_DIR"

    mkdir -p "$NODE_DIR"

    tar -xJf "$NODE_TAR" \
        --strip-components=1 \
        -C "$NODE_DIR"

    ln -sf "$NODE_DIR/bin/node" /usr/local/bin/node
    ln -sf "$NODE_DIR/bin/npm" /usr/local/bin/npm
    ln -sf "$NODE_DIR/bin/npx" /usr/local/bin/npx
    ln -sf "$NODE_DIR/bin/corepack" /usr/local/bin/corepack 2>/dev/null || true

    rm -rf "$TMP_DIR"

    success "Node.js installed."

fi

export PATH="/usr/local/bin:$NODE_DIR/bin:$PATH"

echo
info "Node.js: $(node --version)"
info "NPM:     $(npm --version)"

# ============================================================
# SKYPORT DIRECTORY
# ============================================================

echo
echo "============================================================"
echo "                 SKYPORT INSTALLATION"
echo "============================================================"
echo

if [ -d "$SKYPORT_DIR/.git" ]; then

    info "Existing Skyport installation detected."

    cd "$SKYPORT_DIR"

    git fetch --all

    success "Skyport repository found."

else

    if [ -d "$SKYPORT_DIR" ]; then
        warning "$SKYPORT_DIR exists but is not a Git repository."

        BACKUP="${SKYPORT_DIR}.backup.$(date +%s)"

        mv "$SKYPORT_DIR" "$BACKUP"

        info "Old directory moved to:"
        echo "$BACKUP"
    fi

    info "Cloning Skyport..."

    mkdir -p "$(dirname "$SKYPORT_DIR")"

    git clone "$SKYPORT_REPO" "$SKYPORT_DIR"

    cd "$SKYPORT_DIR"

    success "Skyport cloned successfully."

fi

# ============================================================
# PACKAGE.JSON
# ============================================================

if [ ! -f "$SKYPORT_DIR/package.json" ]; then
    die "package.json was not found in the Skyport repository."
fi

success "Skyport package.json detected."

# ============================================================
# NPM INSTALL
# ============================================================

echo
info "Installing Skyport npm dependencies..."

cd "$SKYPORT_DIR"

npm install

success "NPM dependencies installed."

# ============================================================
# CREATE USER
# ============================================================

echo
echo "============================================================"
echo "                 SKYPORT USER"
echo "============================================================"
echo

if id "$SKYPORT_USER" >/dev/null 2>&1; then

    success "User '$SKYPORT_USER' already exists."

else

    useradd \
        --system \
        --home "$SKYPORT_DIR" \
        --shell /usr/sbin/nologin \
        "$SKYPORT_USER"

    success "Created user '$SKYPORT_USER'."

fi

chown -R "$SKYPORT_USER:$SKYPORT_USER" "$SKYPORT_DIR"

# ============================================================
# CREATE SYSTEMD SERVICE
# ============================================================

echo
echo "============================================================"
echo "                 SYSTEMD SETUP"
echo "============================================================"
echo

if command -v systemctl >/dev/null 2>&1 && \
   [ -d /run/systemd/system ]; then

    info "systemd detected."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Skyport Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

User=${SKYPORT_USER}
Group=${SKYPORT_USER}

WorkingDirectory=${SKYPORT_DIR}

Environment=NODE_ENV=production
Environment=PATH=/usr/local/bin:/opt/nodejs/bin:/usr/bin:/bin

ExecStart=/usr/local/bin/node .

Restart=always
RestartSec=5

LimitNOFILE=65535

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    systemctl enable "$SERVICE_NAME"

    systemctl restart "$SERVICE_NAME"

    sleep 5

    if systemctl is-active --quiet "$SERVICE_NAME"; then

        success "Skyport systemd service is running."

        SYSTEMD_OK=true

    else

        SYSTEMD_OK=false

        warning "Skyport service did not start."

        echo
        journalctl \
            -u "$SERVICE_NAME" \
            -n 80 \
            --no-pager || true
        echo

    fi

else

    SYSTEMD_OK=false

    warning "systemd is not available in this environment."

    warning "This looks like a container/Codespace environment."

fi

# ============================================================
# FINAL
# ============================================================

echo
echo "============================================================"
echo "             SKYPORT INSTALLATION COMPLETE"
echo "============================================================"
echo

echo "Skyport directory:"
echo "  $SKYPORT_DIR"
echo

echo "Node.js:"
node --version

echo
echo "NPM:"
npm --version

echo

if [ "${SYSTEMD_OK:-false}" = true ]; then

    echo "Service:"
    echo "  skyport"
    echo
    echo "Status:"
    echo "  RUNNING"
    echo
    echo "Commands:"
    echo
    echo "  systemctl status skyport"
    echo "  systemctl restart skyport"
    echo "  systemctl stop skyport"
    echo "  systemctl start skyport"
    echo
    echo "Logs:"
    echo
    echo "  journalctl -u skyport -f"

else

    echo "Systemd:"
    echo "  NOT AVAILABLE"
    echo
    echo "Run Skyport manually with:"
    echo
    echo "  cd $SKYPORT_DIR"
    echo "  node ."

fi

echo
echo "============================================================"
echo
success "Installation finished."
