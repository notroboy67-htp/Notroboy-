#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#                 NRB OFFICIAL WINGS INSTALLER
# ============================================================
# Follows the official Pterodactyl Wings installation flow.
#
# Official documentation:
# https://pterodactyl.io/wings/1.0/installing
#
# This script does NOT:
#   - use third-party Wings installers
#   - use .netrc credentials
#   - generate a fake config.yml
#   - modify the Panel configuration
#
# It performs the documented Wings installation steps and
# adds only basic safety checks / dpkg recovery for systems
# where apt reports an interrupted package transaction.
# ============================================================

WINGS_DIR="/etc/pterodactyl"
WINGS_BIN="/usr/local/bin/wings"
WINGS_SERVICE="/etc/systemd/system/wings.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

die() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

# ------------------------------------------------------------
# Root
# ------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    die "Run this installer as root."
fi

# ------------------------------------------------------------
# OS
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect the operating system."
fi

# shellcheck disable=SC1091
source /etc/os-release

echo
echo "============================================================"
echo "              NRB OFFICIAL WINGS INSTALLER"
echo "============================================================"
echo
info "Operating System: ${PRETTY_NAME:-unknown}"

case "${ID:-}" in
    ubuntu|debian|rocky|almalinux|rhel)
        ok "Supported Linux family detected."
        ;;
    *)
        warn "This operating system is not listed in the official"
        warn "Pterodactyl Wings supported-system documentation."
        die "Installation stopped."
        ;;
esac

# ------------------------------------------------------------
# Virtualization
# Official documentation recommends checking systemd-detect-virt
# and warns about OpenVZ/LXC. KVM is expected to work.
# ------------------------------------------------------------

if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT="$(systemd-detect-virt 2>/dev/null || true)"
    info "Virtualization: ${VIRT:-none/unknown}"

    case "${VIRT}" in
        openvz|lxc)
            warn "Official Pterodactyl documentation warns that"
            warn "OpenVZ/LXC systems may be unable to run Wings."
            die "Installation stopped on unsupported virtualization."
            ;;
    esac
fi

# ------------------------------------------------------------
# Architecture
# Official command selects amd64 for x86_64 and arm64 otherwise.
# We explicitly reject other architectures rather than downloading
# an incorrect binary.
# ------------------------------------------------------------

case "$(uname -m)" in
    x86_64)
        WINGS_ARCH="amd64"
        ;;
    aarch64|arm64)
        WINGS_ARCH="arm64"
        ;;
    *)
        die "Unsupported CPU architecture: $(uname -m)"
        ;;
esac

info "Wings architecture: ${WINGS_ARCH}"

# ------------------------------------------------------------
# Repair interrupted dpkg transaction
# ------------------------------------------------------------
# This is only a recovery step for the exact apt/dpkg error shown
# during the user's previous installation attempt.
# It does not replace the official Wings installation procedure.
# ------------------------------------------------------------

if command -v dpkg >/dev/null 2>&1; then
    echo
    info "Checking package manager state..."

    if ! dpkg --configure -a; then
        die "dpkg could not finish its pending configuration."
    fi

    ok "dpkg is ready."
fi

# ------------------------------------------------------------
# Dependencies
# Official Wings documentation lists curl and Docker.
# ------------------------------------------------------------

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y
    apt-get install -y curl ca-certificates
else
    command -v curl >/dev/null 2>&1 || die "curl is required."
fi

# ------------------------------------------------------------
# Docker
# Official Pterodactyl documentation:
#
# curl -sSL https://get.docker.com/ | CHANNEL=stable bash
#
# systemctl enable --now docker
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                    DOCKER INSTALLATION"
echo "============================================================"
echo

if command -v docker >/dev/null 2>&1; then
    ok "Docker is already installed."
else
    info "Installing Docker CE using the official documented command..."

    curl -sSL https://get.docker.com/ | CHANNEL=stable bash

    command -v docker >/dev/null 2>&1 || die "Docker installation failed."

    ok "Docker installed."
fi

info "Enabling Docker at boot..."

systemctl enable --now docker

if ! systemctl is-active --quiet docker; then
    die "Docker is not running."
fi

ok "Docker is running."

# ------------------------------------------------------------
# Kernel information
# Official documentation recommends checking the kernel.
# ------------------------------------------------------------

echo
info "Kernel: $(uname -r)"

# ------------------------------------------------------------
# Wings directory
# Official documented command:
# mkdir -p /etc/pterodactyl
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                    WINGS INSTALLATION"
echo "============================================================"
echo

info "Creating ${WINGS_DIR}..."

mkdir -p "${WINGS_DIR}"

[[ -d "${WINGS_DIR}" ]] || die "Could not create ${WINGS_DIR}."

ok "${WINGS_DIR} is ready."

# ------------------------------------------------------------
# Wings binary
# Official documented download:
# https://github.com/pterodactyl/wings/releases/latest/download/
# wings_linux_<architecture>
# ------------------------------------------------------------

WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"

info "Downloading Wings from the official Pterodactyl GitHub release..."
echo
echo "  ${WINGS_URL}"
echo

curl -L -o "${WINGS_BIN}" "${WINGS_URL}"

[[ -s "${WINGS_BIN}" ]] || die "Wings download failed or produced an empty file."

# Official documented permission command:
chmod u+x "${WINGS_BIN}"

ok "Wings binary installed."

# ------------------------------------------------------------
# Version verification
# ------------------------------------------------------------

echo
info "Wings binary:"
"${WINGS_BIN}" version || true

# ------------------------------------------------------------
# Configuration
# Official documentation says the node configuration must be
# generated in the Panel and saved to /etc/pterodactyl/config.yml.
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                     CONFIGURATION"
echo "============================================================"
echo

if [[ -f "${WINGS_DIR}/config.yml" ]]; then
    ok "Existing config.yml found."
else
    warn "No config.yml found."
    echo
    echo "Official next step:"
    echo
    echo "  1. Open your Pterodactyl Panel."
    echo "  2. Go to Admin -> Nodes."
    echo "  3. Create/select your node."
    echo "  4. Open the Configuration tab."
    echo "  5. Copy the generated configuration."
    echo "  6. Save it as:"
    echo
    echo "       ${WINGS_DIR}/config.yml"
    echo
    echo "You can also use the Generate Token command provided"
    echo "by the Panel, as described in the official documentation."
    echo
fi

# ------------------------------------------------------------
# Official Wings systemd service
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                   SYSTEMD SERVICE"
echo "============================================================"
echo

cat > "${WINGS_SERVICE}" <<'EOF'
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

chmod 644 "${WINGS_SERVICE}"

systemctl daemon-reload

ok "Official Wings systemd service created."

# ------------------------------------------------------------
# Official start command:
# systemctl enable --now wings
#
# Only start it automatically when config.yml exists. Otherwise
# the official configuration step has not been completed yet.
# ------------------------------------------------------------

if [[ -f "${WINGS_DIR}/config.yml" ]]; then

    echo
    info "Starting Wings..."

    if systemctl enable --now wings; then
        sleep 2

        if systemctl is-active --quiet wings; then
            ok "Wings is running."
        else
            warn "Wings service did not remain running."
            echo
            echo "Recent logs:"
            journalctl -u wings -n 50 --no-pager || true
        fi
    else
        warn "Wings could not be started."
        echo
        echo "Recent logs:"
        journalctl -u wings -n 50 --no-pager || true
    fi

else

    info "Wings was not started because config.yml is not present."
    info "This follows the official configuration sequence."

fi

# ------------------------------------------------------------
# Final
# ------------------------------------------------------------

echo
echo "============================================================"
echo "              NRB WINGS INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Installed:"
echo "  Wings:      ${WINGS_BIN}"
echo "  Directory:  ${WINGS_DIR}"
echo "  Service:    ${WINGS_SERVICE}"
echo
echo "Official configuration file:"
echo "  ${WINGS_DIR}/config.yml"
echo
echo "Useful official commands:"
echo "  wings --debug"
echo "  systemctl enable --now wings"
echo "  systemctl status wings"
echo
echo "Official documentation:"
echo "  https://pterodactyl.io/wings/1.0/installing"
echo
