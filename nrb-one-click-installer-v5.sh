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
PUFFERPANEL_APT_REPO="https://packagecloud.io/pufferpanel/pufferpanel/any/"
SKYPORT_REPO="https://github.com/skyport-team/panel.git"
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
            2) install_pufferpanel ;;
            3) install_skyport ;;
            4) install_nokvm ;;
            5) service_menu ;;
            6) uninstall_repair_menu ;;
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

    info "The supplied Pterodactyl installer requires administrator details."
    echo
    read -rp "Panel hostname/IP (FQDN): " FQDN
    read -rp "Installer author email: " email
    read -rp "Admin email: " user_email
    read -rp "Admin username: " user_username
    read -rp "Admin first name: " user_firstname
    read -rp "Admin last name: " user_lastname
    read -rsp "Admin password: " user_password
    echo

    if [[ -z "$FQDN" || -z "$email" || -z "$user_email" || -z "$user_username" ||
          -z "$user_firstname" || -z "$user_lastname" || -z "$user_password" ]]; then
        error "All Pterodactyl Panel fields are required."
        pause
        return
    fi

    export FQDN email user_email user_username user_firstname user_lastname user_password
    export ASSUME_SSL=false CONFIGURE_LETSENCRYPT=false CONFIGURE_FIREWALL=false

    info "The supplied Pterodactyl installer will now run."
    printf '\n'

    if download_and_run_script "$PTERODACTYL_PANEL_URL" "pterodactyl-panel"; then
        success "Pterodactyl Panel installer completed."
    else
        error "Pterodactyl Panel installer failed."
    fi

    pause
}

# --------------------------- Pterodactyl Wings ------------------------------

install_pufferpanel() {
    banner
    printf '%b\n\n' "${WHITE}PUFFERPANEL INSTALLATION${NC}"

    require_supported_linux || { pause; return; }
    check_network || { pause; return; }

    if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
        error "Current PufferPanel 3.x package instructions target Debian/Ubuntu."
        info "Official documentation: ${PUFFERPANEL_DOCS}"
        pause
        return
    fi

    install_base_dependencies || {
        error "Base dependency installation failed."
        pause
        return
    }

    info "Installing PufferPanel from the official Packagecloud repository."
    info "Official documentation: ${PUFFERPANEL_DOCS}"

    local keyring="/etc/apt/keyrings/pufferpanel.gpg"
    local source_file="/etc/apt/sources.list.d/pufferpanel.sources"

    run_as_root mkdir -p /etc/apt/keyrings

    if ! curl -fsSL "https://packagecloud.io/pufferpanel/pufferpanel/gpgkey" \
        | gpg --dearmor \
        | run_as_root tee "$keyring" >/dev/null; then
        error "Could not install PufferPanel repository signing key."
        pause
        return
    fi

    run_as_root chmod 0644 "$keyring"

    cat <<EOF | run_as_root tee "$source_file" >/dev/null
Types: deb
URIs: https://packagecloud.io/pufferpanel/pufferpanel/any/
Suites: any
Components: main
Signed-By: ${keyring}
EOF

    if ! run_as_root apt-get update; then
        error "PufferPanel repository update failed."
        pause
        return
    fi

    if ! run_as_root apt-get install -y pufferpanel; then
        error "PufferPanel package installation failed."
        pause
        return
    fi

    success "PufferPanel package installed."

    run_as_root systemctl enable --now pufferpanel.service || {
        error "PufferPanel service failed to start."
        run_as_root journalctl -u pufferpanel.service -n 50 --no-pager 2>/dev/null || true
        pause
        return
    }

    printf '\n'
    info "Create the first administrator account."
    info "Answer YES when PufferPanel asks whether the account is an admin."
    if ! run_as_root pufferpanel user add; then
        error "PufferPanel admin creation failed."
        pause
        return
    fi

    local ip
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"

    success "PufferPanel installation completed."
    echo
    echo "  Web URL : http://${ip:-SERVER-IP}:8080"
    echo "  SFTP    : ${ip:-SERVER-IP}:5657"
    echo "  Service : pufferpanel"
    echo "  Logs    : /var/log/pufferpanel"
    echo
    warn "For production, configure Docker isolation and TLS/reverse proxy."
    pause
}

# -------------------------------- Skyport -----------------------------------
install_skyport() {
    banner
    printf '%b\n\n' "${WHITE}SKYPORT PANEL INSTALLATION${NC}"

    require_supported_linux || { pause; return; }
    check_network || { pause; return; }
    install_base_dependencies || {
        error "Base dependency installation failed."
        pause
        return
    }

    local install_dir="/opt/skyport-panel"

    # Install Node.js when it is missing or too old.
    local node_major=""
    if command_exists node; then
        node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
    fi

    if [[ -z "$node_major" || "$node_major" -lt 18 ]]; then
        info "Installing Node.js 20 LTS..."
        if ! curl -fsSL https://deb.nodesource.com/setup_20.x | run_as_root bash -; then
            error "Node.js repository setup failed."
            pause
            return
        fi
        run_as_root apt-get install -y nodejs || {
            error "Node.js installation failed."
            pause
            return
        }
    fi

    if ! command_exists node || ! command_exists npm; then
        error "Node.js/npm is unavailable."
        pause
        return
    fi

    info "Node.js: $(node --version)"
    info "npm: $(npm --version)"

    # Clone the exact repository supplied by the user.
    if [[ -d "$install_dir/.git" ]]; then
        info "Existing Skyport repository found."
        read -rp "Update the existing repository? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            git -C "$install_dir" pull --ff-only || {
                error "Skyport repository update failed."
                pause
                return
            }
        fi
    elif [[ -e "$install_dir" ]]; then
        error "$install_dir exists but is not a Git repository."
        pause
        return
    else
        info "Cloning Skyport Labs Panel..."
        run_as_root git clone https://github.com/skyportlabs/panel "$install_dir" || {
            error "Skyport clone failed."
            pause
            return
        }
    fi

    [[ -f "$install_dir/package.json" ]] || {
        error "Skyport package.json was not found."
        pause
        return
    }

    info "Installing project dependencies..."
    (cd "$install_dir" && npm install) || {
        error "npm install failed."
        pause
        return
    }

    info "Seeding database/images..."
    (cd "$install_dir" && npm run seed) || {
        error "npm run seed failed."
        pause
        return
    }

    echo
    info "Creating the Skyport administrator."
    info "Complete the prompts from npm run createUser."
    (cd "$install_dir" && npm run createUser) || {
        error "npm run createUser failed or was cancelled."
        pause
        return
    }

    # Start exactly as requested: node .
    # Run in the background so control returns to the NRB menu.
    info "Starting Skyport with node . ..."
    local pid_file="$install_dir/skyport.pid"
    local log_file="$install_dir/skyport.log"

    (cd "$install_dir" && nohup node . > "$log_file" 2>&1 & echo $! > "$pid_file")

    sleep 3

    local pid=""
    pid="$(cat "$pid_file" 2>/dev/null || true)"

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        success "Skyport is running. PID: $pid"
    else
        error "Skyport did not remain running."
        echo
        warn "Last Skyport log output:"
        tail -n 50 "$log_file" 2>/dev/null || true
        pause
        return
    fi

    local ip=""
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"

    echo
    success "Skyport installation completed."
    echo "Repository : https://github.com/skyportlabs/panel"
    echo "Directory  : $install_dir"
    echo "Start      : cd $install_dir && node ."
    echo "PID        : $pid"
    echo "Log        : $log_file"
    echo "Server IP  : ${ip:-SERVER-IP}"
    echo
    info "Use the port configured by the Skyport project."
    pause
}

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

    if [[ "$service" == pm2:* ]]; then
        local proc="${service#pm2:}"
        case "$action" in
            start) pm2 start "$proc" ;;
            stop) pm2 stop "$proc" ;;
            restart) pm2 restart "$proc" ;;
            status) pm2 describe "$proc" 2>/dev/null || true ;;
        esac
        return
    fi

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
    banner
    printf '%b\n\n' "${WHITE}PTERODACTYL INSTALLATION${NC}"

    require_supported_linux || { pause; return; }
    check_network || { pause; return; }

    info "Running your Pterodactyl installer:"
    echo "bash <(curl -s https://ptero.jishnu.site)"
    echo

    if ! curl -fsSL https://ptero.jishnu.site | bash; then
        error "Pterodactyl installation failed."
        pause
        return
    fi

    success "Pterodactyl installer finished."
    pause
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
    if confirm "Stop PM2 Skyport processes and permanently delete /etc/skyport and /etc/skyportd?"; then
        pm2 delete skyport 2>/dev/null || true
        pm2 delete skyportd 2>/dev/null || true
        pm2 save 2>/dev/null || true
        run_as_root rm -rf -- /etc/skyport /etc/skyportd
        success "Skyport Panel and Daemon directories removed."
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
