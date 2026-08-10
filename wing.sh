#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#             NRB OFFICIAL PTERODACTYL WINGS
#                     INSTALLER - FIXED
# ============================================================
# Follows the official Pterodactyl Wings installation flow.
#
# Official documentation:
# https://pterodactyl.io/wings/1.0/installing
#
# Important fix:
# "curl: (23) Failure writing output to destination"
# "Text file busy"
#
# Wings is downloaded to a temporary file first. If the existing
# Wings binary is currently being used, its systemd service is
# stopped before the new binary is installed.
#
# This script does NOT use:
#   - third-party Wings installers
#   - .netrc credentials
#   - hidden authentication
#   - fake config.yml
# ============================================================

WINGS_DIR="/etc/pterodactyl"
WINGS_BIN="/usr/local/bin/wings"
WINGS_SERVICE="/etc/systemd/system/wings.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARNING]${NC} $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

cleanup() {
    if [[ -n "${TMP_WINGS:-}" && -f "${TMP_WINGS}" ]]; then
        rm -f "${TMP_WINGS}"
    fi
}
trap cleanup EXIT

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || die "Run this installer as root."

# ------------------------------------------------------------
# OS check
# ------------------------------------------------------------

[[ -f /etc/os-release ]] || die "Cannot detect the operating system."

# shellcheck disable=SC1091
source /etc/os-release

echo
echo "============================================================"
echo "          NRB OFFICIAL PTERODACTYL WINGS INSTALLER"
echo "============================================================"
echo

info "Operating System: ${PRETTY_NAME:-unknown}"

case "${ID:-}" in
    ubuntu|debian|rocky|almalinux|rhel)
        ok "Supported Linux family detected."
        ;;
    *)
        warn "This OS is not listed in the current official"
        warn "Pterodactyl Wings supported-system documentation."
        die "Installation stopped."
        ;;
esac

# ------------------------------------------------------------
# Virtualization check
# ------------------------------------------------------------

if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT="$(systemd-detect-virt 2>/dev/null || true)"
    info "Virtualization: ${VIRT:-none/unknown}"

    case "${VIRT}" in
        openvz|lxc)
            warn "The official documentation warns that OpenVZ/LXC"
            warn "may be unable to run Wings because of Docker limits."
            die "Unsupported virtualization environment."
            ;;
    esac
fi

# ------------------------------------------------------------
# Architecture
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

info "CPU architecture: $(uname -m)"
info "Wings architecture: ${WINGS_ARCH}"

# ------------------------------------------------------------
# Repair interrupted dpkg
# ------------------------------------------------------------

if command -v dpkg >/dev/null 2>&1; then
    echo
    info "Checking dpkg package state..."

    if ! dpkg --configure -a; then
        die "dpkg could not finish its pending configuration."
    fi

    ok "dpkg is ready."
fi

# ------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive

    info "Updating package lists..."
    apt-get update -y

    info "Installing curl and CA certificates..."
    apt-get install -y curl ca-certificates
else
    command -v curl >/dev/null 2>&1 || die "curl is required."
fi

# ------------------------------------------------------------
# Docker
# Official documented quick install:
# curl -sSL https://get.docker.com/ | CHANNEL=stable bash
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                     DOCKER CHECK"
echo "============================================================"
echo

if command -v docker >/dev/null 2>&1; then
    ok "Docker is already installed."
else
    info "Installing Docker using the official Docker install command..."

    curl -sSL https://get.docker.com/ | CHANNEL=stable bash

    command -v docker >/dev/null 2>&1 || die "Docker installation failed."

    ok "Docker installed."
fi

info "Enabling Docker..."
systemctl enable --now docker

systemctl is-active --quiet docker || die "Docker is not running."

ok "Docker is running."

# ------------------------------------------------------------
# Kernel information
# ------------------------------------------------------------

echo
info "Kernel: $(uname -r)"

# ------------------------------------------------------------
# Create Wings directory
# Official:
# mkdir -p /etc/pterodactyl
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                  PREPARING WINGS"
echo "============================================================"
echo

mkdir -p "${WINGS_DIR}"

[[ -d "${WINGS_DIR}" ]] || die "Could not create ${WINGS_DIR}."

ok "${WINGS_DIR} is ready."

# ------------------------------------------------------------
# Wings download
#
# Official URL:
# https://github.com/pterodactyl/wings/releases/latest/download/
# wings_linux_<architecture>
#
# FIX:
# Do NOT curl directly into /usr/local/bin/wings.
# Download to a temporary file first.
# This avoids curl error 23 when the existing executable is busy.
# ------------------------------------------------------------

WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"
TMP_WINGS="$(mktemp /tmp/wings.XXXXXX)"

echo
echo "============================================================"
echo "                  DOWNLOADING WINGS"
echo "============================================================"
echo

info "Official Wings download URL:"
echo "  ${WINGS_URL}"
echo

# ------------------------------------------------------------
# If the existing Wings binary is being used, stop the systemd
# service before replacing it.
# ------------------------------------------------------------

if [[ -f "${WINGS_BIN}" ]] && command -v fuser >/dev/null 2>&1; then

    if fuser -s "${WINGS_BIN}"; then
        warn "The existing Wings binary is currently in use."

        if systemctl list-unit-files wings.service >/dev/null 2>&1; then
            info "Stopping wings.service..."
            systemctl stop wings.service || true
        fi

        # Wait for the executable to become free.
        for _ in {1..15}; do
            if ! fuser -s "${WINGS_BIN}"; then
                break
            fi
            sleep 1
        done

        if fuser -s "${WINGS_BIN}"; then
            echo
            warn "The Wings binary is still being used."
            echo
            echo "If you started Wings manually with:"
            echo "  wings --debug"
            echo
            echo "stop that process with CTRL+C, then run this installer again."
            die "Cannot safely replace a running Wings executable."
        fi

        ok "Existing Wings process is stopped."
    fi
fi

# ------------------------------------------------------------
# Download to temporary file
# ------------------------------------------------------------

info "Downloading Wings..."

if ! curl -fL --retry 3 --connect-timeout 20 \
    -o "${TMP_WINGS}" \
    "${WINGS_URL}"; then
    die "Wings download failed."
fi

[[ -s "${TMP_WINGS}" ]] || die "Downloaded Wings file is empty."

# Basic sanity check: an ELF executable should begin with 0x7f ELF.
if ! head -c 4 "${TMP_WINGS}" | od -An -tx1 | grep -qi '7f 45 4c 46'; then
    die "Downloaded file is not a valid Linux executable."
fi

ok "Wings download verified."

# ------------------------------------------------------------
# Install executable
# Official permission step:
# chmod u+x /usr/local/bin/wings
# ------------------------------------------------------------

info "Installing Wings to ${WINGS_BIN}..."

install -m 755 "${TMP_WINGS}" "${WINGS_BIN}"

[[ -x "${WINGS_BIN}" ]] || die "Wings executable installation failed."

ok "Wings executable installed."

# ------------------------------------------------------------
# Verify version
# ------------------------------------------------------------

echo
info "Installed Wings version:"
"${WINGS_BIN}" version || true

# ------------------------------------------------------------
# Existing configuration
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                    CONFIGURATION"
echo "============================================================"
echo

if [[ -f "${WINGS_DIR}/config.yml" ]]; then
    ok "Existing config.yml found."
else
    warn "No config.yml found."
    echo
    echo "The official Pterodactyl procedure requires the node"
    echo "configuration generated by your Panel."
    echo
    echo "Save it as:"
    echo
    echo "  ${WINGS_DIR}/config.yml"
    echo
    echo "Panel path:"
    echo "  Admin -> Nodes -> Your Node -> Configuration"
    echo
fi

# ------------------------------------------------------------
# Official systemd service
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                  SYSTEMD SERVICE"
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

ok "Wings systemd service installed."

# ------------------------------------------------------------
# Start only after config exists.
#
# Official debug step:
#   wings --debug
#
# We do not invent a config file. If config.yml exists, start
# the official systemd service.
# ------------------------------------------------------------

if [[ -f "${WINGS_DIR}/config.yml" ]]; then

    echo
    info "Starting Wings..."

    if systemctl enable --now wings.service; then
        sleep 3

        if systemctl is-active --quiet wings.service; then
            ok "Wings is running."
        else
            warn "Wings did not remain running."
            echo
            echo "Recent Wings logs:"
            journalctl -u wings.service -n 50 --no-pager || true
        fi
    else
        warn "Wings could not be started."
        echo
        echo "Recent Wings logs:"
        journalctl -u wings.service -n 50 --no-pager || true
    fi

else

    info "Wings service was not started because config.yml is missing."
    info "Complete the Panel node configuration first."

fi

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                  FINAL VERIFICATION"
echo "============================================================"
echo

command -v docker >/dev/null 2>&1 \
    && ok "Docker binary: OK" \
    || warn "Docker binary: NOT FOUND"

systemctl is-active --quiet docker \
    && ok "Docker service: RUNNING" \
    || warn "Docker service: NOT RUNNING"

[[ -x "${WINGS_BIN}" ]] \
    && ok "Wings binary: OK" \
    || warn "Wings binary: NOT FOUND"

[[ -f "${WINGS_SERVICE}" ]] \
    && ok "Wings systemd service: OK" \
    || warn "Wings systemd service: NOT FOUND"

if [[ -f "${WINGS_DIR}/config.yml" ]]; then
    ok "Wings config.yml: FOUND"

    if systemctl is-active --quiet wings.service; then
        ok "Wings service: RUNNING"
    else
        warn "Wings service: NOT RUNNING"
    fi
else
    warn "Wings config.yml: NOT FOUND"
fi

echo
echo "============================================================"
echo "              NRB WINGS INSTALLATION FINISHED"
echo "============================================================"
echo
echo "Wings binary:"
echo "  ${WINGS_BIN}"
echo
echo "Configuration:"
echo "  ${WINGS_DIR}/config.yml"
echo
echo "Service:"
echo "  systemctl status wings"
echo
echo "Logs:"
echo "  journalctl -u wings -f"
echo
echo "Official documentation:"
echo "  https://pterodactyl.io/wings/1.0/installing"
echo
