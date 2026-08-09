#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#                     NRB HOSTING INSTALLER
# ============================================================
# One-click menu:
# 1) Pterodactyl
# 2) PufferPanel
# 3) Panel V1
# 4) NRB No-KVM / QEMU VM Installer
# 5) LXC + LXD Installation
# 6) Service Start / Stop / Status
# 7) Uninstall / Repair
# 8) Exit
# ============================================================

# ============================================================
# NRB INSTALLATION COMMANDS — EDIT THESE ONLY
# ============================================================

PTERODACTYL_COMMAND='bash <(curl -fsSL https://ptero.jishnu.site)'

PUFFERPANEL_COMMAND='
curl -fsSL https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh?any=true | bash
apt-get update
apt-get install -y pufferpanel
systemctl enable --now pufferpanel
'

PANEL_V1_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/panel/refs/heads/main/install-1.sh)'

NOKVM_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/VMS/refs/heads/main/nokvm.sh)'

LXC_LXD_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/Notroboy-/refs/heads/main/lxd-installer.sh)'

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

info() {
    printf '%b\n' "${CYAN}[INFO]${NC} $*"
}

success() {
    printf '%b\n' "${GREEN}[ OK ]${NC} $*"
}

warn() {
    printf '%b\n' "${YELLOW}[WARN]${NC} $*"
}

error() {
    printf '%b\n' "${RED}[ERROR]${NC} $*"
}

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
    if ! command -v curl >/dev/null 2>&1; then
        error "curl is not installed."
        return 1
    fi

    if ! curl -fsSI --max-time 10 https://github.com >/dev/null 2>&1; then
        error "Internet connectivity check failed."
        return 1
    fi

    return 0
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

    info "Running the Pterodactyl command:"
    echo "  $PTERODACTYL_COMMAND"
    echo

    check_network || {
        pause
        return
    }

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

    check_network || {
        pause
        return
    }

    info "Installing PufferPanel."
    echo

    if run_command "$PUFFERPANEL_COMMAND"; then
        success "PufferPanel installation completed."

        echo
        info "Create the first administrator with:"
        echo "  pufferpanel user add"

        echo
        info "Service:"
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
#                       INSTALL: PANEL V1
# ============================================================

install_panel_v1() {
    banner

    echo
    printf '%b\n' "${WHITE}PANEL V1${NC}"
    echo

    check_network || {
        pause
        return
    }

    info "Starting Panel V1 installation..."
    echo

    info "Running:"
    echo "  $PANEL_V1_COMMAND"
    echo

    if run_command "$PANEL_V1_COMMAND"; then
        success "Panel V1 installation completed."
    else
        error "Panel V1 installer returned an error."
    fi

    pause
}

# ============================================================
#                    INSTALL: NO-KVM / QEMU
# ============================================================

install_nokvm() {
    banner

    echo
    printf '%b\n' "${WHITE}NRB NO-KVM / QEMU VM INSTALLER${NC}"
    echo

    info "Running:"
    echo "  $NOKVM_COMMAND"
    echo

    check_network || {
        pause
        return
    }

    if run_command "$NOKVM_COMMAND"; then
        success "NRB No-KVM installer finished."
    else
        error "NRB No-KVM installer returned an error."
    fi

    pause
}

# ============================================================
#                    INSTALL: LXC + LXD
# ============================================================

install_lxc_lxd() {
    banner

    echo
    printf '%b\n' "${WHITE}LXC + LXD INSTALLATION${NC}"
    echo

    info "Starting LXC + LXD installation..."
    echo

    info "Running:"
    echo "  $LXC_LXD_COMMAND"
    echo

    check_network || {
        pause
        return
    }

    if run_command "$LXC_LXD_COMMAND"; then
        success "LXC + LXD installation completed."
        echo
        info "You can verify the installation with:"
        echo "  lxc version"
        echo
        info "Then initialize LXD with:"
        echo "  lxd init"
    else
        error "LXC + LXD installer returned an error."
    fi

    pause
}

# ============================================================
#                   SERVICE MANAGEMENT
# ============================================================

service_menu() {
    while true; do

        banner

        echo
        printf '%b\n' "${WHITE}SERVICE START / STOP / STATUS${NC}"
        echo

        echo "1) PufferPanel Start"
        echo "2) PufferPanel Stop"
        echo "3) PufferPanel Status"
        echo "4) Docker Start"
        echo "5) Docker Stop"
        echo "6) Docker Status"
        echo "7) Return"

        echo

        read -rp "Select an option: " choice

        case "$choice" in

            1)
                if systemctl start pufferpanel 2>/dev/null; then
                    success "PufferPanel started."
                else
                    error "Could not start PufferPanel."
                fi

                pause
                ;;

            2)
                if systemctl stop pufferpanel 2>/dev/null; then
                    success "PufferPanel stopped."
                else
                    error "Could not stop PufferPanel."
                fi

                pause
                ;;

            3)
                systemctl --no-pager status pufferpanel 2>/dev/null || true
                pause
                ;;

            4)
                if systemctl start docker 2>/dev/null; then
                    success "Docker started."
                else
                    error "Could not start Docker."
                fi

                pause
                ;;

            5)
                if systemctl stop docker 2>/dev/null; then
                    success "Docker stopped."
                else
                    error "Could not stop Docker."
                fi

                pause
                ;;

            6)
                systemctl --no-pager status docker 2>/dev/null || true
                pause
                ;;

            7)
                return
                ;;

            *)
                warn "Invalid option."
                sleep 1
                ;;

        esac
    done
}

# ============================================================
#                    UNINSTALL / REPAIR
# ============================================================

repair_menu() {
    while true; do

        banner

        echo
        printf '%b\n' "${WHITE}UNINSTALL / REPAIR${NC}"
        echo

        echo "1) Repair PufferPanel"
        echo "2) Restart PufferPanel"
        echo "3) Uninstall PufferPanel"
        echo "4) Return"

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
                systemctl restart pufferpanel 2>/dev/null || true

                success "PufferPanel restart attempted."

                pause
                ;;

            3)
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

            4)
                return
                ;;

            *)
                warn "Invalid option."
                sleep 1
                ;;

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
        echo "3) Panel V1"
        echo "4) NRB No-KVM / QEMU VM Installer"
        echo "5) LXC + LXD Installation"
        echo "6) Service Start / Stop / Status"
        echo "7) Uninstall / Repair"
        echo "8) Exit"

        echo

        read -rp "Enter your choice [1-8]: " choice

        case "$choice" in

            1)
                install_pterodactyl
                ;;

            2)
                install_pufferpanel
                ;;

            3)
                install_panel_v1
                ;;

            4)
                install_nokvm
                ;;

            5)
                install_lxc_lxd
                ;;

            6)
                service_menu
                ;;

            7)
                repair_menu
                ;;

            8)
                echo
                success "Thank you for using NOTROBOY Installer."
                exit 0
                ;;

            *)
                warn "Invalid option. Please choose 1-8."
                sleep 1
                ;;

        esac

    done
}

# ============================================================
#                           START
# ============================================================

require_root
main_menu
