#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#                    NRB WINGS INSTALLER
# ============================================================
# Pterodactyl Wings Installer
# NRB Hosting
#
# Installs:
#   - Required packages
#   - Docker
#   - Latest Wings binary
#   - Wings systemd service
#
# Does NOT create a fake config.yml.
# The config.yml must come from your Pterodactyl Panel.
# ============================================================

WINGS_BIN="/usr/local/bin/wings"
WINGS_DIR="/etc/pterodactyl"
WINGS_SERVICE="/etc/systemd/system/wings.service"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

pause_screen() {
    echo
    read -rp "Press Enter to continue..."
}

# ------------------------------------------------------------
# Root verification
# ------------------------------------------------------------

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "This installer must be run as root."
        echo
        echo "Run:"
        echo "  sudo -i"
        echo
        echo "Then run the installer again."
        exit 1
    fi
}

# ------------------------------------------------------------
# OS detection
# ------------------------------------------------------------

check_os() {

    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect operating system."
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    echo
    info "Operating System: ${PRETTY_NAME}"
    echo

    case "${ID}" in
        ubuntu|debian|rocky|almalinux|rhel)
            success "Operating system detected."
            ;;
        *)
            warning "This operating system is not in the supported list."
            echo
            read -rp "Continue anyway? [y/N]: " answer

            if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
                error "Installation cancelled."
                exit 1
            fi
            ;;
    esac
}

# ------------------------------------------------------------
# Architecture detection
# ------------------------------------------------------------

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
            error "Unsupported architecture: ${SYSTEM_ARCH}"
            echo
            echo "Supported:"
            echo "  x86_64 / amd64"
            echo "  aarch64 / arm64"
            exit 1
            ;;
    esac

    success "Architecture: ${SYSTEM_ARCH}"
    info "Wings architecture: ${WINGS_ARCH}"
}

# ------------------------------------------------------------
# Virtualization check
# ------------------------------------------------------------

check_virtualization() {

    if command -v systemd-detect-virt >/dev/null 2>&1; then

        VIRT="$(systemd-detect-virt 2>/dev/null || true)"

        echo
        info "Virtualization: ${VIRT:-unknown}"

        case "${VIRT}" in

            lxc|openvz|container)

                warning "This server appears to be running inside a container."
                echo
                echo "Docker/Wings may require nested-container support."
                echo

                read -rp "Continue? [y/N]: " answer

                if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
                    error "Installation cancelled."
                    exit 1
                fi

                ;;

            "")
                info "Virtualization type could not be detected."
                ;;

            *)
                success "Virtualization check passed."
                ;;
        esac
    fi
}

# ------------------------------------------------------------
# Install packages
# ------------------------------------------------------------

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
        error "No supported package manager found."
        exit 1
    fi

    success "Required packages installed."
}

# ------------------------------------------------------------
# Docker installation
# ------------------------------------------------------------

install_docker() {

    echo
    echo "============================================================"
    echo "                     DOCKER CHECK"
    echo "============================================================"
    echo

    if command -v docker >/dev/null 2>&1; then

        success "Docker is already installed."

    else

        info "Docker was not found."
        info "Installing Docker..."

        if ! curl -fsSL https://get.docker.com | sh; then
            error "Docker installation failed."
            exit 1
        fi

        success "Docker installed."
    fi

    echo
    info "Enabling Docker service..."

    systemctl enable docker >/dev/null 2>&1 || true

    if ! systemctl restart docker; then
        error "Unable to start Docker."
        systemctl status docker --no-pager || true
        exit 1
    fi

    sleep 2

    if ! systemctl is-active --quiet docker; then
        error "Docker is not running."
        systemctl status docker --no-pager || true
        exit 1
    fi

    success "Docker is running."

    echo
    info "Docker version:"
    docker --version || true
}

# ------------------------------------------------------------
# Pterodactyl directory
# ------------------------------------------------------------

prepare_wings_directory() {

    echo
    echo "============================================================"
    echo "                PREPARING WINGS DIRECTORY"
    echo "============================================================"
    echo

    mkdir -p "${WINGS_DIR}"

    chmod 755 "${WINGS_DIR}"

    if [[ ! -d "${WINGS_DIR}" ]]; then
        error "Failed to create ${WINGS_DIR}"
        exit 1
    fi

    success "Directory ready: ${WINGS_DIR}"
}

# ------------------------------------------------------------
# Download Wings
# ------------------------------------------------------------

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

        rm -f "${temp_file}"

        error "Wings download failed."
        exit 1
    fi

    if [[ ! -s "${temp_file}" ]]; then

        rm -f "${temp_file}"

        error "Downloaded Wings file is empty."
        exit 1
    fi

    install -m 755 "${temp_file}" "${WINGS_BIN}"

    rm -f "${temp_file}"

    if [[ ! -x "${WINGS_BIN}" ]]; then
        error "Wings binary was not installed correctly."
        exit 1
    fi

    success "Wings binary installed."

    echo
    info "Wings version:"
    "${WINGS_BIN}" version || true
}

# ------------------------------------------------------------
# Create systemd service
# ------------------------------------------------------------

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

    if [[ ! -f "${WINGS_SERVICE}" ]]; then
        error "Failed to create Wings systemd service."
        exit 1
    fi

    success "Wings systemd service created."

    systemctl enable wings >/dev/null 2>&1

    success "Wings service enabled."
}

# ------------------------------------------------------------
# Configuration verification
# ------------------------------------------------------------

verify_configuration() {

    echo
    echo "============================================================"
    echo "                  WINGS CONFIGURATION"
    echo "============================================================"
    echo

    if [[ -f "${WINGS_DIR}/config.yml" ]]; then

        success "Wings configuration found:"
        echo
        echo "  ${WINGS_DIR}/config.yml"
        echo

        info "Testing Wings configuration..."

        if "${WINGS_BIN}" --help >/dev/null 2>&1; then
            success "Wings binary verification passed."
        else
            warning "Wings binary verification returned an unexpected result."
        fi

        return 0
    fi

    warning "No config.yml was found."
    echo
    echo "This is expected for a newly installed node."
    echo
    echo "Create the node in your Pterodactyl Panel and copy"
    echo "the generated configuration to:"
    echo
    echo "  ${WINGS_DIR}/config.yml"
    echo

    return 1
}

# ------------------------------------------------------------
# Start Wings
# ------------------------------------------------------------

start_wings() {

    if [[ ! -f "${WINGS_DIR}/config.yml" ]]; then

        warning "Wings cannot be started yet."
        echo
        echo "Missing:"
        echo "  ${WINGS_DIR}/config.yml"
        echo

        return 0
    fi

    echo
    info "Starting Wings..."

    if ! systemctl restart wings; then
        error "Wings failed to start."
        echo
        echo "Recent logs:"
        journalctl -u wings -n 50 --no-pager || true
        return 1
    fi

    sleep 3

    if systemctl is-active --quiet wings; then

        success "Wings is running."

    else

        error "Wings is not running."
        echo
        echo "Recent logs:"
        journalctl -u wings -n 50 --no-pager || true

        return 1
    fi
}

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

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
        warning "Node configuration is still required."
    fi

    echo

    if [[ "${failed}" -eq 0 ]]; then
        success "Core Wings installation verification passed."
    else
        error "One or more core installation checks failed."
        return 1
    fi
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

main() {

    clear || true

    echo
    echo "============================================================"
    echo "                    NRB HOSTING"
    echo "                 PTERODACTYL WINGS"
    echo "                    INSTALLER"
    echo "============================================================"
    echo

    check_root
    check_os
    detect_architecture
    check_virtualization

    install_dependencies
    install_docker
    prepare_wings_directory
    install_wings_binary
    create_wings_service

    verify_configuration || true

    start_wings || true

    final_verification || true

    echo
    echo "============================================================"
    echo "              NRB WINGS INSTALLATION FINISHED"
    echo "============================================================"
    echo
    echo "Useful commands:"
    echo
    echo "  systemctl status wings"
    echo "  systemctl restart wings"
    echo "  systemctl stop wings"
    echo "  journalctl -u wings -f"
    echo
    echo "Configuration:"
    echo
    echo "  /etc/pterodactyl/config.yml"
    echo
}

main "$@"
