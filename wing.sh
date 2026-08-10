#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#                    NRB WINGS INSTALLER
# ============================================================
# Pterodactyl Wings installer
# NRB Hosting
#
# Features:
#   - Root verification
#   - OS / architecture detection
#   - Interrupted dpkg repair
#   - Broken dependency repair
#   - Docker installation and verification
#   - Latest Wings binary installation
#   - Wings systemd service creation
#   - config.yml detection
#   - Wings service verification
# ============================================================

WINGS_BIN="/usr/local/bin/wings"
WINGS_DIR="/etc/pterodactyl"
WINGS_SERVICE="/etc/systemd/system/wings.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

fail() {
    error "$*"
    exit 1
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        fail "Run this installer as root."
    fi
}

check_os() {
    [[ -f /etc/os-release ]] || fail "Cannot detect the operating system."

    # shellcheck disable=SC1091
    source /etc/os-release

    echo
    info "Operating System: ${PRETTY_NAME:-unknown}"

    case "${ID:-}" in
        ubuntu|debian|rocky|almalinux|rhel)
            success "Operating system detected."
            ;;
        *)
            warning "This OS is not in the expected supported list."
            read -rp "Continue anyway? [y/N]: " answer
            [[ "${answer}" =~ ^[Yy]$ ]] || fail "Installation cancelled."
            ;;
    esac
}

detect_architecture() {
    SYSTEM_ARCH="$(uname -m)"

    case "${SYSTEM_ARCH}" in
        x86_64|amd64)
            WINGS_ARCH="amd64"
            ;;
        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;
        *)
            fail "Unsupported architecture: ${SYSTEM_ARCH}"
            ;;
    esac

    success "System architecture: ${SYSTEM_ARCH}"
    info "Wings architecture: ${WINGS_ARCH}"
}

check_virtualization() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT="$(systemd-detect-virt 2>/dev/null || true)"
        info "Virtualization: ${VIRT:-unknown}"

        case "${VIRT}" in
            lxc|openvz|container)
                warning "This server appears to be running inside a container."
                warning "Docker/Wings may require nested-container support."
                read -rp "Continue? [y/N]: " answer
                [[ "${answer}" =~ ^[Yy]$ ]] || fail "Installation cancelled."
                ;;
        esac
    fi
}

repair_package_system() {
    echo
    echo "============================================================"
    echo "                 PACKAGE SYSTEM CHECK"
    echo "============================================================"
    echo

    export DEBIAN_FRONTEND=noninteractive

    # The screenshot showed:
    # E: dpkg was interrupted...
    # Always attempt to finish pending package configuration
    # before using apt.
    if command -v dpkg >/dev/null 2>&1; then
        info "Checking for interrupted dpkg configuration..."
        if ! dpkg --configure -a; then
            error "dpkg configuration could not be completed."
            echo
            echo "Try manually:"
            echo "  dpkg --configure -a"
            echo "  apt-get install -f -y"
            exit 1
        fi
        success "dpkg check completed."
    fi

    info "Repairing broken dependencies..."

    if ! apt-get install -f -y; then
        error "Could not repair package dependencies."
        echo
        echo "Try manually:"
        echo "  dpkg --configure -a"
        echo "  apt-get install -f -y"
        exit 1
    fi

    success "Package system is ready."
}

install_dependencies() {
    echo
    echo "============================================================"
    echo "                 INSTALLING DEPENDENCIES"
    echo "============================================================"
    echo

    export DEBIAN_FRONTEND=noninteractive

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y

        apt-get install -y \
            curl \
            ca-certificates \
            gnupg \
            lsb-release \
            apt-transport-https

    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y \
            curl \
            ca-certificates \
            gnupg2

    elif command -v yum >/dev/null 2>&1; then
        yum install -y \
            curl \
            ca-certificates \
            gnupg2

    else
        fail "No supported package manager was found."
    fi

    success "Required packages installed."
}

install_docker() {
    echo
    echo "============================================================"
    echo "                     DOCKER CHECK"
    echo "============================================================"
    echo

    if command -v docker >/dev/null 2>&1; then
        success "Docker is already installed."
    else
        info "Docker not found."
        info "Installing Docker..."

        if ! curl -fsSL https://get.docker.com | sh; then
            fail "Docker installation failed."
        fi

        success "Docker installed."
    fi

    info "Enabling Docker..."
    systemctl enable docker >/dev/null 2>&1 || true

    info "Starting Docker..."

    if ! systemctl restart docker; then
        systemctl status docker --no-pager || true
        fail "Docker failed to start."
    fi

    sleep 2

    if ! systemctl is-active --quiet docker; then
        systemctl status docker --no-pager || true
        fail "Docker is not running."
    fi

    success "Docker is running."

    echo
    docker --version || true
}

prepare_wings_directory() {
    echo
    echo "============================================================"
    echo "                PREPARING WINGS DIRECTORY"
    echo "============================================================"
    echo

    mkdir -p "${WINGS_DIR}"
    chmod 755 "${WINGS_DIR}"

    [[ -d "${WINGS_DIR}" ]] || fail "Could not create ${WINGS_DIR}"

    success "Directory ready: ${WINGS_DIR}"
}

install_wings_binary() {
    echo
    echo "============================================================"
    echo "                  WINGS INSTALLATION"
    echo "============================================================"
    echo

    local wings_url
    local temp_file

    wings_url="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"
    temp_file="$(mktemp)"

    trap 'rm -f "${temp_file}"' RETURN

    info "Downloading latest Wings..."
    echo
    echo "${wings_url}"
    echo

    if ! curl \
        --fail \
        --location \
        --retry 3 \
        --connect-timeout 15 \
        --output "${temp_file}" \
        "${wings_url}"; then
        fail "Wings download failed."
    fi

    [[ -s "${temp_file}" ]] || fail "Downloaded Wings file is empty."

    install -m 755 "${temp_file}" "${WINGS_BIN}"

    [[ -x "${WINGS_BIN}" ]] || fail "Wings binary installation failed."

    success "Wings installed at ${WINGS_BIN}."

    echo
    info "Wings version:"
    "${WINGS_BIN}" version || true
}

create_wings_service() {
    echo
    echo "============================================================"
    echo "                 WINGS SYSTEMD SERVICE"
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

    [[ -f "${WINGS_SERVICE}" ]] || fail "Could not create Wings service."

    systemctl enable wings >/dev/null 2>&1 || \
        fail "Could not enable Wings service."

    success "Wings systemd service created and enabled."
}

check_config() {
    echo
    echo "============================================================"
    echo "                 WINGS CONFIGURATION"
    echo "============================================================"
    echo

    if [[ -f "${WINGS_DIR}/config.yml" ]]; then
        success "Found ${WINGS_DIR}/config.yml"
        return 0
    fi

    warning "No config.yml found."
    echo
    echo "Create your node in the Pterodactyl Panel, then place"
    echo "the generated node configuration at:"
    echo
    echo "  ${WINGS_DIR}/config.yml"
    echo

    return 1
}

start_wings() {
    if [[ ! -f "${WINGS_DIR}/config.yml" ]]; then
        warning "Wings cannot start until config.yml is present."
        return 0
    fi

    info "Starting Wings..."

    if ! systemctl restart wings; then
        error "Wings failed to start."
        journalctl -u wings -n 50 --no-pager || true
        return 1
    fi

    sleep 3

    if systemctl is-active --quiet wings; then
        success "Wings is running."
        return 0
    fi

    error "Wings is not running."
    echo
    echo "Recent Wings logs:"
    journalctl -u wings -n 50 --no-pager || true
    return 1
}

final_verification() {
    echo
    echo "============================================================"
    echo "                 FINAL VERIFICATION"
    echo "============================================================"
    echo

    local failed=0

    if command -v docker >/dev/null 2>&1; then
        success "Docker binary: OK"
    else
        error "Docker binary: FAILED"
        failed=1
    fi

    if systemctl is-active --quiet docker; then
        success "Docker service: RUNNING"
    else
        error "Docker service: NOT RUNNING"
        failed=1
    fi

    if [[ -x "${WINGS_BIN}" ]]; then
        success "Wings binary: OK"
    else
        error "Wings binary: FAILED"
        failed=1
    fi

    if [[ -f "${WINGS_SERVICE}" ]]; then
        success "Wings systemd service: OK"
    else
        error "Wings systemd service: FAILED"
        failed=1
    fi

    if [[ -f "${WINGS_DIR}/config.yml" ]]; then
        success "Wings config.yml: FOUND"

        if systemctl is-active --quiet wings; then
            success "Wings service: RUNNING"
        else
            warning "Wings service: NOT RUNNING"
        fi
    else
        warning "Wings config.yml: NOT FOUND"
    fi

    echo

    if [[ "${failed}" -eq 0 ]]; then
        success "Core installation verification passed."
        return 0
    fi

    error "One or more core checks failed."
    return 1
}

main() {
    clear 2>/dev/null || true

    echo
    echo "============================================================"
    echo "                    NRB HOSTING"
    echo "               PTERODACTYL WINGS"
    echo "                    INSTALLER"
    echo "============================================================"
    echo

    check_root
    check_os
    detect_architecture
    check_virtualization

    # Fix the exact dpkg interruption shown in the screenshot
    repair_package_system

    install_dependencies
    install_docker
    prepare_wings_directory
    install_wings_binary
    create_wings_service

    check_config || true
    start_wings || true
    final_verification || true

    echo
    echo "============================================================"
    echo "           NRB WINGS INSTALLATION FINISHED"
    echo "============================================================"
    echo
    echo "Configuration:"
    echo "  ${WINGS_DIR}/config.yml"
    echo
    echo "Useful commands:"
    echo "  systemctl status wings"
    echo "  systemctl restart wings"
    echo "  systemctl stop wings"
    echo "  journalctl -u wings -f"
    echo
}

main "$@"
