#!/usr/bin/env bash
# =============================================================================
# NOTROBOY67 - NRB ONE-CLICK HOSTING INSTALLER V2
# =============================================================================
# Components:
#   1) Pterodactyl Panel
#   2) Pterodactyl Wings
#   3) PufferPanel
#   4) Skyport Panel
#   5) NRB No-KVM / QEMU VM Installer
#   6) Service Start / Stop / Status
#   7) Uninstall / Repair
#   8) Exit
#
# Run:
#   sudo bash nrb-installer.sh
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ------------------------------- Sources ------------------------------------
PTERODACTYL_PANEL_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/refs/heads/master/installers/panel.sh"
PTERODACTYL_WINGS_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/refs/heads/master/installers/wings.sh"
PUFFERPANEL_DOCS="https://docs.pufferpanel.com/en/3.x/installing.html"
PUFFERPANEL_APT_REPO="https://package.pufferpanel.com"
SKYPORT_REPO="https://github.com/skyportlabs/panel.git"
NOKVM_URL="https://raw.githubusercontent.com/notroboy67-htp/VMS/refs/heads/main/nokvm.sh"

INSTALL_LOG="/var/log/nrb-installer.log"
TMP_DIR="/tmp/nrb-installer"

# ------------------------------- Colors -------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    WHITE='\033[1;37m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' WHITE='' DIM='' NC=''
fi

mkdir -p "$TMP_DIR"
touch "$INSTALL_LOG" 2>/dev/null || true
exec > >(tee -a "$INSTALL_LOG") 2>&1

# ------------------------------- Helpers ------------------------------------
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() { printf '[%s] %s\n' "$(timestamp)" "$*"; }
info() { printf '%b\n' "${CYAN}[INFO]${NC} $*"; }
success() { printf '%b\n' "${GREEN}[OK]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[WARN]${NC} $*"; }
error() { printf '%b\n' "${RED}[ERROR]${NC} $*" >&2; }

pause() {
    printf '\n%b' "${DIM}Press Enter to continue...${NC}"
    read -r _
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

run_as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    elif command_exists sudo; then
        sudo "$@"
    else
        error "Root privileges are required and sudo is not installed."
        return 1
    fi
}

download_file() {
    local url="$1"
    local output="$2"

    if command_exists curl; then
        curl -fL --retry 3 --connect-timeout 15 "$url" -o "$output"
    elif command_exists wget; then
        wget -O "$output" "$url"
    else
        error "Neither curl nor wget is installed."
        return 1
    fi
}

download_and_run_script() {
    local url="$1"
    local name="$2"
    local file="${TMP_DIR}/${name}.sh"

    info "Downloading ${name} installer..."
    download_file "$url" "$file" || return 1

    if [[ ! -s "$file" ]]; then
        error "Downloaded installer is empty."
        return 1
    fi

    chmod 700 "$file"
    info "Running ${name} installer..."
    bash "$file"
}

detect_os() {
    OS_ID="unknown"
    OS_VERSION="unknown"
    OS_NAME="Unknown Linux"

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_NAME="${PRETTY_NAME:-$OS_ID $OS_VERSION}"
    fi

    ARCH="$(uname -m)"
    KERNEL="$(uname -r)"
}

show_system_info() {
    printf '\n'
    info "System: ${OS_NAME}"
    info "Architecture: ${ARCH}"
    info "Kernel: ${KERNEL}"
    info "Hostname: $(hostname 2>/dev/null || echo unknown)"
    info "Installer log: ${INSTALL_LOG}"
    printf '\n'
}

require_supported_linux() {
    if [[ ! -r /etc/os-release ]]; then
        error "Cannot detect Linux distribution."
        return 1
    fi

    case "$OS_ID" in
        ubuntu|debian)
            return 0
            ;;
        *)
            warn "This installer was designed primarily for Debian/Ubuntu."
            read -rp "Continue anyway? [y/N]: " answer
            [[ "$answer" =~ ^[Yy]$ ]]
            ;;
    esac
}

apt_update() {
    run_as_root apt-get update
}

install_base_dependencies() {
    info "Installing common dependencies..."
    apt_update
    run_as_root apt-get install -y \
        ca-certificates curl wget git unzip tar \
        lsb-release gnupg apt-transport-https \
        software-properties-common
}

check_network() {
    if ! curl -fsSI --max-time 10 https://github.com >/dev/null 2>&1; then
        error "Internet connectivity check failed."
        return 1
    fi
}

port_in_use() {
    local port="$1"
    if command_exists ss; then
        ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
    elif command_exists netstat; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
    else
        return 1
    fi
}

check_port() {
    local port="$1"
    local name="$2"
    if port_in_use "$port"; then
        warn "Port ${port} appears to be in use (${name})."
        return 1
    fi
    return 0
}

confirm() {
    local message="$1"
    printf '%b\n' "${YELLOW}${message}${NC}"
    read -rp "Type YES to continue: " answer
    [[ "$answer" == "YES" ]]
}

# ------------------------------- Banner -------------------------------------
banner() {
    clear 2>/dev/null || true
    cat <<'EOF'
========================================================================

███╗   ██╗ ██████╗ ████████╗██████╗  ██████╗ ██████╗  ██████╗ ██╗   ██╗
████╗  ██║██╔═══██╗╚══██╔══╝██╔══██╗██╔═══██╗██╔══██╗██╔═══██╗╚██╗ ██╔╝
██╔██╗ ██║██║   ██║   ██║   ██████╔╝██║   ██║██████╔╝██║   ██║ ╚████╔╝
██║╚██╗██║██║   ██║   ██║   ██╔══██╗██║   ██║██╔══██╗██║   ██║  ╚██╔╝
██║ ╚████║╚██████╔╝   ██║   ██║  ██║╚██████╔╝██████╔╝╚██████╔╝   ██║
╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝    ╚═╝

               ---------------- • POWERED BY NOTROBOY67 • ----------------

========================================================================
EOF
}

main_menu() {
    while true; do
        banner
        printf '%b\n' "${WHITE}                 NRB ONE-CLICK HOSTING INSTALLER V2${NC}"
        printf '%b\n\n' "${DIM}========================================================================${NC}"

        cat <<'EOF'
 [1] Pterodactyl Panel
 [2] Pterodactyl Wings
 [3] PufferPanel
 [4] Skyport Panel
 [5] NRB No-KVM / QEMU VM Installer

 [6] Service Start / Stop / Status
 [7] Uninstall / Repair
 [8] Exit

========================================================================
EOF
        read -rp " Select an option [1-8]: " choice
        printf '\n'

        case "$choice" in
            1) install_pterodactyl_panel ;;
            2) install_pterodactyl_wings ;;
            3) install_pufferpanel ;;
            4) install_skyport ;;
            5) install_nokvm ;;
            6) service_menu ;;
            7) repair_uninstall_menu ;;
            8)
                success "Thank you for using NRB One-Click Installer."
                exit 0
                ;;
            *)
                error "Invalid option."
                sleep 1
                ;;
        esac
    done
}

# -------------------------- Pterodactyl Panel -------------------------------
install_pterodactyl_panel() {
    banner
    printf '%b\n\n' "${WHITE}PTERODACTYL PANEL INSTALLATION${NC}"

    require_supported_linux || { pause; return; }
    check_network || { pause; return; }

    if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
        warn "The upstream installer may reject this operating system."
    fi

    install_base_dependencies || {
        error "Base dependency installation failed."
        pause
        return
    }

    info "The official community Pterodactyl Installer script will now run."
    info "You may be asked interactive installation questions."
    printf '\n'

    if download_and_run_script "$PTERODACTYL_PANEL_URL" "pterodactyl-panel"; then
        success "Pterodactyl Panel installer completed."
    else
        error "Pterodactyl Panel installer failed."
    fi

    pause
}

# --------------------------- Pterodactyl Wings ------------------------------
install_pterodactyl_wings() {
    banner
    printf '%b\n\n' "${WHITE}PTERODACTYL WINGS INSTALLATION${NC}"

    require_supported_linux || { pause; return; }
    check_network || { pause; return; }

    install_base_dependencies || {
        error "Base dependency installation failed."
        pause
        return
    }

    info "The Pterodactyl Wings installer will now run."
    info "Wings normally requires configuration from your Pterodactyl Panel."
    printf '\n'

    if download_and_run_script "$PTERODACTYL_WINGS_URL" "pterodactyl-wings"; then
        success "Pterodactyl Wings installer completed."
    else
        error "Pterodactyl Wings installer failed."
    fi

    pause
}

# ------------------------------ PufferPanel ---------------------------------
install_pufferpanel() {
    banner
    printf '%b\n\n' "${WHITE}PUFFERPANEL INSTALLATION${NC}"

    require_supported_linux || { pause; return; }
    check_network || { pause; return; }

    if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
        warn "PufferPanel's official packages may not support this distribution."
        pause
        return
    fi

    install_base_dependencies || {
        error "Base dependency installation failed."
        pause
        return
    }

    info "Installing PufferPanel from its official package repository."
    info "Official documentation: ${PUFFERPANEL_DOCS}"
    printf '\n'

    # Official PufferPanel repository setup. The package repository provides
    # the pufferpanel package; if the upstream repository format changes,
    # the script stops rather than silently installing an unrelated package.
    local repo_file="/etc/apt/sources.list.d/pufferpanel.list"
    local keyring="/usr/share/keyrings/pufferpanel.gpg"
    local key_url="https://package.pufferpanel.com/deb/pubkey.gpg"

    if command_exists gpg; then
        info "Installing PufferPanel repository signing key..."
        if curl -fsSL "$key_url" | gpg --dearmor | run_as_root tee "$keyring" >/dev/null; then
            :
        else
            warn "Could not retrieve the PufferPanel signing key."
        fi
    fi

    # Use the repository definition documented by the package service when
    # possible. If it cannot be established, do not install an arbitrary
    # package from an unknown source.
    if [[ -s "$keyring" ]]; then
        printf 'deb [signed-by=%s] %s stable main\n' "$keyring" "$PUFFERPANEL_APT_REPO" \
            | run_as_root tee "$repo_file" >/dev/null
    else
        error "PufferPanel repository key setup failed."
        error "See official documentation: ${PUFFERPANEL_DOCS}"
        pause
        return
    fi

    if run_as_root apt-get update && run_as_root apt-get install -y pufferpanel; then
        success "PufferPanel package installed."

        if command_exists pufferpanel; then
            run_as_root systemctl enable pufferpanel.service 2>/dev/null || true
            run_as_root systemctl start pufferpanel.service 2>/dev/null || true
            success "PufferPanel service enabled/started when available."
        fi

        info "PufferPanel documentation: ${PUFFERPANEL_DOCS}"
        info "Common web port: 8080 (verify your installed configuration)."
    else
        error "PufferPanel installation failed."
        warn "Consult the official installation guide: ${PUFFERPANEL_DOCS}"
    fi

    pause
}

# -------------------------------- Skyport -----------------------------------
install_skyport() {
    banner
    printf '%b\n\n' "${WHITE}SKYPORT PANEL INSTALLATION${NC}"
    require_supported_linux || { pause; return; }
    check_network || { pause; return; }
    install_base_dependencies || { error "Base dependency installation failed."; pause; return; }
    local install_dir="/opt/skyport-panel"
    local node_major=""
    if command_exists node; then node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"; fi
    if [[ -z "$node_major" || "$node_major" -lt 18 ]]; then
        info "Installing Node.js 20 LTS..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | run_as_root bash - || { error "Node.js setup failed."; pause; return; }
        run_as_root apt-get install -y nodejs || { error "Node.js installation failed."; pause; return; }
    fi
    if [[ -e "$install_dir" && ! -d "$install_dir/.git" ]]; then error "$install_dir exists but is not a Git repository."; pause; return; fi
    if [[ -d "$install_dir/.git" ]]; then
        read -rp "Skyport already exists. Update it first? [y/N]: " answer
        [[ "$answer" =~ ^[Yy]$ ]] && git -C "$install_dir" pull --ff-only || true
    else
        git clone "$SKYPORT_REPO" "$install_dir" || { error "Skyport clone failed."; pause; return; }
    fi
    [[ -f "$install_dir/package.json" ]] || { error "Skyport package.json not found."; pause; return; }
    info "Installing Skyport dependencies..."
    (cd "$install_dir" && npm install) || { error "npm install failed."; pause; return; }
    info "Seeding Skyport..."
    (cd "$install_dir" && npm run seed) || { error "npm run seed failed."; pause; return; }
    info "Creating Skyport administrator. Follow the prompts."
    (cd "$install_dir" && npm run createUser) || { error "npm run createUser failed."; pause; return; }
    if ! id skyport >/dev/null 2>&1; then run_as_root useradd --system --home "$install_dir" --shell /usr/sbin/nologin skyport 2>/dev/null || true; fi
    id skyport >/dev/null 2>&1 && run_as_root chown -R skyport:skyport "$install_dir" 2>/dev/null || true
    local node_bin="$(command -v node)"
    run_as_root tee /etc/systemd/system/skyport.service >/dev/null <<SERVICE
[Unit]
Description=Skyport Panel
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
WorkingDirectory=$install_dir
ExecStart=$node_bin .
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
User=skyport
Group=skyport

[Install]
WantedBy=multi-user.target
SERVICE
    run_as_root systemctl daemon-reload
    if run_as_root systemctl enable --now skyport.service; then success "Skyport service started and enabled."; else error "Skyport service failed to start."; run_as_root journalctl -u skyport.service -n 50 --no-pager 2>/dev/null || true; pause; return; fi
    sleep 2
    if run_as_root systemctl is-active --quiet skyport.service; then success "Skyport is running."; else error "Skyport is not active."; run_as_root systemctl status skyport.service --no-pager 2>/dev/null || true; fi
    local ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    printf '\n%b\n' "${GREEN}Skyport installation completed.${NC}"
    printf 'Repository : %s\nDirectory  : %s\nService    : skyport.service\nStart      : systemctl start skyport\nStop       : systemctl stop skyport\nStatus     : systemctl status skyport\nLogs       : journalctl -u skyport -f\nServer IP  : %s\n\n' "$SKYPORT_REPO" "$install_dir" "${ip:-<server-ip>}"
    info "Check the Skyport project configuration for its HTTP port."
    pause
}

# ------------------------------ No-KVM --------------------------------------
install_nokvm() {
    banner
    printf '%b\n\n' "${WHITE}NRB NO-KVM / QEMU VM INSTALLATION${NC}"

    require_supported_linux || { pause; return; }
    check_network || { pause; return; }

    install_base_dependencies || {
        error "Base dependency installation failed."
        pause
        return
    }

    info "Downloading your NRB No-KVM installer..."
    info "Source: ${NOKVM_URL}"
    printf '\n'

    if download_and_run_script "$NOKVM_URL" "nrb-nokvm"; then
        success "NRB No-KVM installer completed."
    else
        error "NRB No-KVM installer failed."
    fi

    pause
}

# --------------------------- Service Manager --------------------------------
service_candidates() {
    cat <<'EOF'
pteroq
pterodactyl
wings
pufferpanel
skyport
skyport-panel
docker
nginx
apache2
mysql
mariadb
redis-server
libvirtd
qemu-kvm
EOF
}

discover_services() {
    if command_exists systemctl; then
        systemctl list-unit-files --type=service --no-legend 2>/dev/null \
            | awk '{print $1}' \
            | grep -Ei 'pterodactyl|puffer|skyport|wings|qemu|kvm|libvirt|docker|nginx|apache|mysql|maria|redis' \
            | sort -u
    fi
}

service_status() {
    local service="$1"
    if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
        systemctl --no-pager --full status "$service" 2>/dev/null || true
    else
        warn "Service not found: $service"
    fi
}

service_action() {
    local action="$1"
    local service="$2"

    case "$action" in
        start|stop|restart)
            if run_as_root systemctl "$action" "$service"; then
                success "${action^}ed: ${service}"
            else
                error "Could not ${action} ${service}."
            fi
            ;;
        status)
            service_status "$service"
            ;;
    esac
}

service_menu() {
    while true; do
        banner
        printf '%b\n\n' "${WHITE}SERVICE START / STOP / STATUS${NC}"

        echo "Detected services:"
        local services
        services="$(discover_services || true)"

        if [[ -n "$services" ]]; then
            echo "$services" | sed 's/^/  - /'
        else
            echo "  No matching services detected."
        fi

        cat <<'EOF'

 [1] Start service
 [2] Stop service
 [3] Restart service
 [4] Service status
 [5] Refresh detected services
 [6] Back

========================================================================
EOF

        read -rp " Select an option [1-6]: " choice

        case "$choice" in
            1|2|3|4)
                read -rp " Enter exact service name: " svc
                [[ -n "$svc" ]] || { error "Service name cannot be empty."; sleep 1; continue; }
                case "$choice" in
                    1) service_action start "$svc" ;;
                    2) service_action stop "$svc" ;;
                    3) service_action restart "$svc" ;;
                    4) service_action status "$svc" ;;
                esac
                pause
                ;;
            5) continue ;;
            6) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

# -------------------------- Repair / Uninstall ------------------------------
repair_pterodactyl() {
    info "Running Pterodactyl Panel installer in repair/update mode is
upstream-dependent. The installer will be downloaded and launched."
    download_and_run_script "$PTERODACTYL_PANEL_URL" "pterodactyl-panel-repair"
}

repair_wings() {
    info "Running Pterodactyl Wings installer."
    download_and_run_script "$PTERODACTYL_WINGS_URL" "pterodactyl-wings-repair"
}

repair_pufferpanel() {
    if command_exists apt-get; then
        run_as_root apt-get update
        run_as_root apt-get install --reinstall -y pufferpanel
        run_as_root systemctl daemon-reload || true
        run_as_root systemctl restart pufferpanel.service || true
    else
        error "APT is required for this repair function."
        return 1
    fi
}

repair_skyport() {
    local dir="/opt/skyport-panel"
    [[ -d "$dir/.git" ]] || { error "Skyport repository not found at $dir."; return 1; }
    git -C "$dir" pull --ff-only || return 1
    (cd "$dir" && npm install) || return 1
    (cd "$dir" && npm run seed) || warn "Skyport seed failed during repair."
    run_as_root systemctl restart skyport.service || true
}

uninstall_pterodactyl() {
    error "Pterodactyl has multiple data components (Panel, database, web server,
storage, Wings). Automatic destructive removal is intentionally disabled."
    warn "Use the official Pterodactyl documentation to remove components safely."
    return 1
}

uninstall_wings() {
    if confirm "This can remove the Wings service/configuration. Continue?"; then
        run_as_root systemctl disable --now wings.service 2>/dev/null || true
        run_as_root rm -f /etc/systemd/system/wings.service
        run_as_root systemctl daemon-reload
        success "Wings service unit removed when present."
    else
        info "Cancelled."
    fi
}

uninstall_pufferpanel() {
    if confirm "Uninstall PufferPanel package and service?"; then
        run_as_root systemctl disable --now pufferpanel.service 2>/dev/null || true
        run_as_root apt-get remove -y pufferpanel
        success "PufferPanel package removed."
        warn "Configuration/data may remain and were not blindly deleted."
    else
        info "Cancelled."
    fi
}

uninstall_skyport() {
    local dir="/opt/skyport-panel"
    if [[ ! -d "$dir" ]]; then
        warn "Skyport directory does not exist."
        return 0
    fi
    if confirm "Permanently delete ${dir}?"; then
        run_as_root rm -rf -- "$dir"
        success "Skyport source directory removed."
    else
        info "Cancelled."
    fi
}

uninstall_nokvm() {
    error "Automatic No-KVM removal is disabled because nokvm.sh may create
custom VM/network/storage resources."
    warn "Use the No-KVM manager's own uninstall/delete functions instead."
    return 1
}

repair_uninstall_menu() {
    while true; do
        banner
        printf '%b\n\n' "${WHITE}REPAIR / UNINSTALL${NC}"

        cat <<'EOF'
 [1] Repair Pterodactyl Panel
 [2] Repair Pterodactyl Wings
 [3] Repair PufferPanel
 [4] Repair Skyport
 [5] Repair NRB No-KVM

 [6] Uninstall Pterodactyl Panel (guided/disabled by default)
 [7] Uninstall Pterodactyl Wings
 [8] Uninstall PufferPanel
 [9] Uninstall Skyport
 [10] Uninstall NRB No-KVM (guided/disabled by default)

 [11] Back

========================================================================
EOF

        read -rp " Select an option [1-11]: " choice

        case "$choice" in
            1) repair_pterodactyl; pause ;;
            2) repair_wings; pause ;;
            3) repair_pufferpanel; pause ;;
            4) repair_skyport; pause ;;
            5) repair_nokvm; pause ;;
            6) uninstall_pterodactyl; pause ;;
            7) uninstall_wings; pause ;;
            8) uninstall_pufferpanel; pause ;;
            9) uninstall_skyport; pause ;;
            10) uninstall_nokvm; pause ;;
            11) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

# ------------------------------- Cleanup ------------------------------------
cleanup() {
    rm -rf "${TMP_DIR:?}"/* 2>/dev/null || true
}
trap cleanup EXIT

on_error() {
    local code=$?
    error "Installer stopped with exit code ${code}."
    error "Check the log: ${INSTALL_LOG}"
    exit "$code"
}
trap on_error ERR

# -------------------------------- Main ---------------------------------------
main() {
    detect_os
    if [[ "$OS_ID" == "unknown" ]]; then
        warn "Could not identify a supported operating system."
    fi

    if [[ "${EUID}" -ne 0 ]] && ! command_exists sudo; then
        error "Run as root or install sudo."
        exit 1
    fi

    main_menu
}

main "$@"
