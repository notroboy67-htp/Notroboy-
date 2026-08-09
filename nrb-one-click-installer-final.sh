#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#                     NRB HOSTING INSTALLER
# ============================================================
# One-click menu for:
# 1) Pterodactyl
# 2) PufferPanel
# 3) Skyport Panel
# 4) No-KVM / QEMU VM Installer
# 5) Service Start / Stop / Status
# 6) Uninstall / Repair
# 7) Exit
#
# ============================================================
# NRB INSTALLATION COMMANDS — EDIT THESE ONLY
# ============================================================

PTERODACTYL_COMMAND='bash <(curl -s https://ptero.jishnu.site)'

PUFFERPANEL_COMMAND='
curl -fsSL https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh?any=true | bash
apt-get update
apt-get install -y pufferpanel
systemctl enable --now pufferpanel
'

mcpanel_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/panel/refs/heads/main/install-1.sh)'

NOKVM_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/VMS/refs/heads/main/nokvm.sh)'

# ============================================================
#                        UI / HELPERS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

SCRIPT_NAME="NOTROBOY Installer"
SKYPORT_DIR="/opt/skyport"
SKYPORT_LOG="/var/log/nrb-skyport.log"
SKYPORT_PID="/var/run/nrb-skyport.pid"

banner() {
    clear 2>/dev/null || true
    printf '%b\n' "${CYAN}"
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
    printf '%b\n' "${NC}"
}

info()    { printf '%b\n' "${CYAN}[INFO]${NC} $*"; }
success() { printf '%b\n' "${GREEN}[ OK ]${NC} $*"; }
warn()    { printf '%b\n' "${YELLOW}[WARN]${NC} $*"; }
error()   { printf '%b\n' "${RED}[ERROR]${NC} $*"; }

pause() {
    echo
    read -rp "Press Enter to continue..." _
}

die() {
    error "$*"
    exit 1
}

require_root() {
    [[ "$EUID" -eq 0 ]] || die "Please run this installer as root."
}

check_network() {
    curl -fsSI --max-time 10 https://github.com >/dev/null 2>&1 || {
        error "Internet connectivity check failed."
        return 1
    }
}

apt_base() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl wget git ca-certificates gnupg
}

run_command() {
    local command_text="$1"
    bash -c "$command_text"
}

# ============================================================
#                     INSTALL: PTERODACTYL
# ============================================================

install_pterodactyl() {
    banner
    echo
    printf '%b\n' "${WHITE}PTERODACTYL${NC}"
    echo
    info "Running the Pterodactyl command you supplied:"
    echo "  $PTERODACTYL_COMMAND"
    echo

    check_network || { pause; return; }

    if run_command "$PTERODACTYL_COMMAND"; then
        success "Pterodactyl installer finished."
    else
        error "Pterodactyl installer returned an error."
    fi
    pause
}

# ============================================================
#                     INSTALL: PUFFERPANEL
# ============================================================

install_pufferpanel() {
    banner
    echo
    printf '%b\n' "${WHITE}PUFFERPANEL${NC}"
    echo

    check_network || { pause; return; }

    info "Installing PufferPanel using the package installation method."
    echo

    if run_command "$PUFFERPANEL_COMMAND"; then
        success "PufferPanel package installation completed."
        echo
        info "Create the first administrator with:"
        echo "  pufferpanel user add"
        echo
        info "The panel service is:"
        echo "  systemctl status pufferpanel"
        echo
        info "Default web port: 8080"
        info "Default SFTP port: 5657"
    else
        error "PufferPanel installation failed."
    fi
    pause
}

# ============================================================
#                      INSTALL: MCPANEL
# ============================================================

install_skyport() {
    banner
    echo
    printf '%b\n' "${WHITE}SKYPORT PANEL${NC}"
    echo

    check_network || { pause; return; }
    apt_base || {
        error "Base package installation failed."
        pause
        return
    }

    # Node/npm are required by the supplied Skyport procedure.
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        info "Node.js/npm not found. Installing Node.js 20..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || {
            error "NodeSource setup failed."
            pause
            return
        }
        apt-get install -y nodejs || {
            error "Node.js installation failed."
            pause
            return
        }
    fi

    info "Node.js: $(node -v)"
    info "npm: $(npm -v)"
    echo

    # Use a fixed directory so the installer can manage start/stop/status.
    if [[ -d "$SKYPORT_DIR/.git" ]]; then
        info "Existing Skyport repository found at $SKYPORT_DIR."
        read -rp "Pull latest changes? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            git -C "$SKYPORT_DIR" pull --ff-only || {
                error "Skyport git pull failed."
                pause
                return
            }
        fi
    elif [[ -e "$SKYPORT_DIR" ]]; then
        error "$SKYPORT_DIR exists and is not a Git repository."
        pause
        return
    else
        info "Cloning $SKYPORT_REPO ..."
        git clone "$SKYPORT_REPO" "$SKYPORT_DIR" || {
            error "Skyport clone failed."
            pause
            return
        }
    fi

    [[ -f "$SKYPORT_DIR/package.json" ]] || {
        error "Skyport package.json was not found."
        pause
        return
    }

    info "Installing project dependencies..."
    (cd "$SKYPORT_DIR" && npm install) || {
        error "npm install failed."
        pause
        return
    }

    info "Seeding database/images..."
    (cd "$SKYPORT_DIR" && npm run seed) || {
        error "npm run seed failed."
        pause
        return
    }

    echo
    info "Creating the Skyport administrator."
    info "Answer the prompts from npm run createUser."
    (cd "$SKYPORT_DIR" && npm run createUser) || {
        error "npm run createUser failed or was cancelled."
        pause
        return
    }

    # The requested "node ." command is started in the background so the
    # NRB menu remains usable. Output is preserved in a log.
    info "Starting Skyport with node . ..."
    rm -f "$SKYPORT_PID"
    touch "$SKYPORT_LOG"
    chmod 600 "$SKYPORT_LOG"

    (
        cd "$SKYPORT_DIR"
        nohup node . >>"$SKYPORT_LOG" 2>&1 &
        echo $! >"$SKYPORT_PID"
    )

    sleep 3

    local pid=""
    pid="$(cat "$SKYPORT_PID" 2>/dev/null || true)"

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        success "Skyport is running. PID: $pid"
    else
        error "Skyport did not remain running."
        echo
        warn "Last Skyport log output:"
        tail -n 50 "$SKYPORT_LOG" 2>/dev/null || true
        pause
        return
    fi

    echo
    info "Skyport installation sequence:"
    printf '%s\n' "$SKYPORT_COMMAND"
    echo
    info "Skyport directory: $SKYPORT_DIR"
    info "Skyport log:       $SKYPORT_LOG"
    pause
}

# ============================================================
#                    INSTALL: NO-KVM
# ============================================================

install_nokvm() {
    banner
    echo
    printf '%b\n' "${WHITE}NRB NO-KVM / QEMU VM INSTALLER${NC}"
    echo
    info "Running the NRB No-KVM installer:"
    echo "  $NOKVM_COMMAND"
    echo

    check_network || { pause; return; }

    if run_command "$NOKVM_COMMAND"; then
        success "NRB No-KVM installer finished."
    else
        error "NRB No-KVM installer returned an error."
    fi
    pause
}

# ============================================================
#                   SERVICE MANAGEMENT
# ============================================================

skyport_status() {
    local pid=""
    pid="$(cat "$SKYPORT_PID" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        success "Skyport: RUNNING (PID $pid)"
    else
        warn "Skyport: STOPPED"
    fi
}

skyport_start() {
    if [[ ! -d "$SKYPORT_DIR" ]]; then
        error "Skyport is not installed at $SKYPORT_DIR."
        return 1
    fi

    if [[ -f "$SKYPORT_PID" ]]; then
        local old_pid=""
        old_pid="$(cat "$SKYPORT_PID" 2>/dev/null || true)"
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            warn "Skyport is already running (PID $old_pid)."
            return 0
        fi
    fi

    touch "$SKYPORT_LOG"
    (
        cd "$SKYPORT_DIR"
        nohup node . >>"$SKYPORT_LOG" 2>&1 &
        echo $! >"$SKYPORT_PID"
    )
    sleep 2
    skyport_status
}

skyport_stop() {
    if [[ ! -f "$SKYPORT_PID" ]]; then
        warn "Skyport PID file not found."
        return 0
    fi

    local pid=""
    pid="$(cat "$SKYPORT_PID" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 2
        kill -9 "$pid" 2>/dev/null || true
        success "Skyport stopped."
    else
        warn "Skyport is not running."
    fi
    rm -f "$SKYPORT_PID"
}

service_menu() {
    while true; do
        banner
        echo
        printf '%b\n' "${WHITE}SERVICE START / STOP / STATUS${NC}"
        echo
        echo "1) Skyport Start"
        echo "2) Skyport Stop"
        echo "3) Skyport Status"
        echo "4) PufferPanel Start"
        echo "5) PufferPanel Stop"
        echo "6) PufferPanel Status"
        echo "7) Docker Start"
        echo "8) Docker Stop"
        echo "9) Docker Status"
        echo "10) Return"
        echo
        read -rp "Select an option: " choice

        case "$choice" in
            1) skyport_start; pause ;;
            2) skyport_stop; pause ;;
            3) skyport_status; pause ;;
            4) systemctl start pufferpanel 2>/dev/null && success "PufferPanel started." || error "Could not start PufferPanel."; pause ;;
            5) systemctl stop pufferpanel 2>/dev/null && success "PufferPanel stopped." || error "Could not stop PufferPanel."; pause ;;
            6) systemctl --no-pager status pufferpanel 2>/dev/null || true; pause ;;
            7) systemctl start docker 2>/dev/null && success "Docker started." || error "Could not start Docker."; pause ;;
            8) systemctl stop docker 2>/dev/null && success "Docker stopped." || error "Could not stop Docker."; pause ;;
            9) systemctl --no-pager status docker 2>/dev/null || true; pause ;;
            10) return ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

# ============================================================
#                     REPAIR / UNINSTALL
# ============================================================

repair_menu() {
    while true; do
        banner
        echo
        printf '%b\n' "${WHITE}UNINSTALL / REPAIR${NC}"
        echo
        echo "1) Repair PufferPanel"
        echo "2) Repair Skyport"
        echo "3) Restart all selected services"
        echo "4) Uninstall PufferPanel"
        echo "5) Uninstall Skyport"
        echo "6) Return"
        echo
        read -rp "Select an option: " choice

        case "$choice" in
            1)
                apt-get update
                apt-get install --reinstall -y pufferpanel || true
                systemctl enable --now pufferpanel || true
                success "PufferPanel repair attempt completed."
                pause
                ;;
            2)
                if [[ -d "$SKYPORT_DIR/.git" ]]; then
                    git -C "$SKYPORT_DIR" pull --ff-only || true
                    (cd "$SKYPORT_DIR" && npm install) || true
                    skyport_stop || true
                    skyport_start || true
                    success "Skyport repair attempt completed."
                else
                    error "Skyport installation not found."
                fi
                pause
                ;;
            3)
                systemctl restart pufferpanel 2>/dev/null || true
                skyport_stop || true
                skyport_start || true
                success "Restart attempt completed."
                pause
                ;;
            4)
                read -rp "Uninstall PufferPanel? [y/N]: " answer
                if [[ "$answer" =~ ^[Yy]$ ]]; then
                    systemctl disable --now pufferpanel 2>/dev/null || true
                    apt-get remove -y pufferpanel 2>/dev/null || true
                    success "PufferPanel package removed."
                else
                    info "Cancelled."
                fi
                pause
                ;;
            5)
                read -rp "Delete Skyport from $SKYPORT_DIR and its logs? [y/N]: " answer
                if [[ "$answer" =~ ^[Yy]$ ]]; then
                    skyport_stop || true
                    rm -rf "$SKYPORT_DIR"
                    rm -f "$SKYPORT_LOG" "$SKYPORT_PID"
                    success "Skyport files removed."
                else
                    info "Cancelled."
                fi
                pause
                ;;
            6) return ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

# ============================================================
#                           MAIN MENU
# ============================================================

main_menu() {
    while true; do
        banner
        echo
        printf '%b\n' "${WHITE}Choose an option:${NC}"
        echo
        echo "1) Pterodactyl"
        echo "2) PufferPanel"
        echo "3) Skyport Panel"
        echo "4) NRB No-KVM / QEMU VM Installer"
        echo "5) Service Start / Stop / Status"
        echo "6) Uninstall / Repair"
        echo "7) Exit"
        echo
        read -rp "Enter your choice [1-7]: " choice

        case "$choice" in
            1) install_pterodactyl ;;
            2) install_pufferpanel ;;
            3) install_skyport ;;
            4) install_nokvm ;;
            5) service_menu ;;
            6) repair_menu ;;
            7)
                echo
                success "Thank you for using NOTROBOY Installer."
                exit 0
                ;;
            *) warn "Invalid option. Please choose 1-7."; sleep 1 ;;
        esac
    done
}

require_root
main_menu
