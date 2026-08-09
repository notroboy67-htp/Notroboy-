#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#                     NRB HOSTING INSTALLER
# ============================================================
# 1) Pterodactyl
# 2) PufferPanel
# 3) Panel V1
# 4) NRB No-KVM / QEMU VM Installer
# 5) LXC + LXD Installation
# 6) Cloudflare Installation
# 7) Service Start / Stop / Status
# 8) Uninstall / Repair
# 9) Exit
# ============================================================

# ============================================================
# NRB INSTALLATION COMMANDS
# ============================================================

PTERODACTYL_COMMAND='bash <(curl -fsSL https://ptero.jishnu.site)'

PUFFERPANEL_COMMAND='
curl -fsSL "https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh?any=true" | bash
apt-get update
apt-get install -y pufferpanel
systemctl enable --now pufferpanel
'

PANEL_V1_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/panel/refs/heads/main/install-1.sh)'

NOKVM_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/VMS/refs/heads/main/nokvm.sh)'

LXC_LXD_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/Notroboy-/refs/heads/main/lxd-installer.sh)'

# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

SCRIPT_NAME="NOTROBOY Installer"

# ============================================================
# UI / HELPERS
# ============================================================

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
    if [[ "$EUID" -ne 0 ]]; then
        die "Please run this installer as root."
    fi
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
# PTERODACTYL
# ============================================================

install_pterodactyl() {
    banner

    echo
    printf '%b\n' "${WHITE}PTERODACTYL INSTALLATION${NC}"
    echo

    check_network || {
        pause
        return
    }

    info "Running Pterodactyl installer..."
    echo

    if run_command "$PTERODACTYL_COMMAND"; then
        success "Pterodactyl installer finished."
    else
        error "Pterodactyl installer returned an error."
    fi

    pause
}

# ============================================================
# PUFFERPANEL
# ============================================================

install_pufferpanel() {
    banner

    echo
    printf '%b\n' "${WHITE}PUFFERPANEL INSTALLATION${NC}"
    echo

    check_network || {
        pause
        return
    }

    info "Installing PufferPanel..."
    echo

    if run_command "$PUFFERPANEL_COMMAND"; then

        success "PufferPanel installation completed."

        echo
        info "Create administrator:"
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
# PANEL V1
# ============================================================

install_panel_v1() {
    banner

    echo
    printf '%b\n' "${WHITE}PANEL V1 INSTALLATION${NC}"
    echo

    check_network || {
        pause
        return
    }

    info "Starting Panel V1 installation..."
    echo

    if run_command "$PANEL_V1_COMMAND"; then
        success "Panel V1 installation completed."
    else
        error "Panel V1 installer returned an error."
    fi

    pause
}

# ============================================================
# NO-KVM / QEMU
# ============================================================

install_nokvm() {
    banner

    echo
    printf '%b\n' "${WHITE}NRB NO-KVM / QEMU VM INSTALLER${NC}"
    echo

    check_network || {
        pause
        return
    }

    info "Starting NRB No-KVM / QEMU installer..."
    echo

    if run_command "$NOKVM_COMMAND"; then
        success "NRB No-KVM installer finished."
    else
        error "NRB No-KVM installer returned an error."
    fi

    pause
}

# ============================================================
# LXC + LXD
# ============================================================

install_lxc_lxd() {
    banner

    echo
    printf '%b\n' "${WHITE}LXC + LXD INSTALLATION${NC}"
    echo

    check_network || {
        pause
        return
    }

    info "Starting LXC + LXD installation..."
    echo

    if run_command "$LXC_LXD_COMMAND"; then

        success "LXC + LXD installation completed."

        echo
        info "Verify installation:"
        echo "  lxc version"

        echo
        info "Initialize LXD:"
        echo "  lxd init"

    else
        error "LXC + LXD installer returned an error."
    fi

    pause
}

# ============================================================
# CLOUDFLARE TUNNEL
# ============================================================

install_cloudflare() {
    banner

    echo
    printf '%b\n' "${WHITE}CLOUDFLARE TUNNEL INSTALLATION${NC}"
    echo

    check_network || {
        pause
        return
    }

    if ! command -v apt-get >/dev/null 2>&1; then
        error "This Cloudflare installer requires an APT-based system."
        pause
        return
    fi

    info "Installing required packages..."
    apt-get update -y
    apt-get install -y curl ca-certificates

    echo
    info "Adding Cloudflare repository..."

    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
        | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

    echo
    info "Updating package lists..."
    apt-get update -y

    echo
    info "Installing cloudflared..."
    apt-get install -y cloudflared

    if ! command -v cloudflared >/dev/null 2>&1; then
        error "Cloudflared installation failed."
        pause
        return
    fi

    success "Cloudflared installed successfully."

    echo
    info "Cloudflared version:"
    cloudflared --version

    echo
    echo "============================================================"
    printf '%b\n' "${CYAN}CLOUDFLARE TUNNEL TOKEN${NC}"
    echo "============================================================"
    echo
    echo "Paste your Cloudflare Tunnel token below."
    echo
    echo "The token is obtained from your Cloudflare Zero Trust"
    echo "Tunnel configuration."
    echo

    read -rsp "Enter Cloudflare Tunnel token: " CLOUDFLARE_TOKEN
    echo

    if [[ -z "$CLOUDFLARE_TOKEN" ]]; then
        error "No Cloudflare Tunnel token entered."
        pause
        return
    fi

    echo
    info "Installing Cloudflare Tunnel service..."

    if cloudflared service install "$CLOUDFLARE_TOKEN"; then
        success "Cloudflare Tunnel service installed."
    else
        error "Cloudflare Tunnel service installation failed."
        pause
        return
    fi

    echo
    info "Enabling Cloudflare Tunnel service..."

    systemctl enable cloudflared

    echo
    info "Starting Cloudflare Tunnel..."

    if systemctl restart cloudflared; then
        success "Cloudflare Tunnel started."
    else
        error "Cloudflare Tunnel could not be started."
    fi

    echo
    info "Cloudflare Tunnel status:"
    systemctl --no-pager --full status cloudflared || true

    echo
    echo "============================================================"
    printf '%b\n' "${GREEN}CLOUDFLARE INSTALLATION COMPLETE${NC}"
    echo "============================================================"
    echo

    echo "Service commands:"
    echo "  systemctl start cloudflared"
    echo "  systemctl stop cloudflared"
    echo "  systemctl restart cloudflared"
    echo "  systemctl status cloudflared"

    echo

    pause
}

# ============================================================
# SERVICE MANAGEMENT
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
        echo "7) Cloudflare Start"
        echo "8) Cloudflare Stop"
        echo "9) Cloudflare Status"
        echo "10) Return"

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
                if systemctl start cloudflared 2>/dev/null; then
                    success "Cloudflare Tunnel started."
                else
                    error "Could not start Cloudflare Tunnel."
                fi
                pause
                ;;

            8)
                if systemctl stop cloudflared 2>/dev/null; then
                    success "Cloudflare Tunnel stopped."
                else
                    error "Could not stop Cloudflare Tunnel."
                fi
                pause
                ;;

            9)
                systemctl --no-pager status cloudflared 2>/dev/null || true
                pause
                ;;

            10)
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
# UNINSTALL / REPAIR
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
        echo "4) Restart Cloudflare Tunnel"
        echo "5) Repair Cloudflare Tunnel"
        echo "6) Uninstall Cloudflare Tunnel"
        echo "7) Return"

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
                if systemctl restart cloudflared 2>/dev/null; then
                    success "Cloudflare Tunnel restarted."
                else
                    error "Could not restart Cloudflare Tunnel."
                fi

                pause
                ;;

            5)
                if command -v cloudflared >/dev/null 2>&1; then

                    systemctl stop cloudflared 2>/dev/null || true

                    cloudflared service uninstall 2>/dev/null || true

                    success "Cloudflare service removed."

                    echo
                    info "Run option 6 from the main menu again to configure a new tunnel."

                else
                    warn "cloudflared is not installed."
                fi

                pause
                ;;

            6)
                read -rp "Uninstall Cloudflare Tunnel? [y/N]: " answer

                if [[ "$answer" =~ ^[Yy]$ ]]; then

                    systemctl stop cloudflared 2>/dev/null || true
                    systemctl disable cloudflared 2>/dev/null || true
                    cloudflared service uninstall 2>/dev/null || true

                    apt-get remove -y cloudflared 2>/dev/null || true

                    rm -f /etc/apt/sources.list.d/cloudflared.list
                    rm -f /usr/share/keyrings/cloudflare-main.gpg

                    success "Cloudflare Tunnel removed."

                else
                    info "Cancelled."
                fi

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
# MAIN MENU
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
        echo "6) Cloudflare Installation"
        echo "7) Service Start / Stop / Status"
        echo "8) Uninstall / Repair"
        echo "9) Exit"

        echo

        read -rp "Enter your choice [1-9]: " choice

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
                install_cloudflare
                ;;

            7)
                service_menu
                ;;

            8)
                repair_menu
                ;;

            9)
                echo
                success "Thank you for using NOTROBOY Installer."
                exit 0
                ;;

            *)
                warn "Invalid option. Please choose 1-9."
                sleep 1
                ;;

        esac

    done
}

# ============================================================
# START
# ============================================================

require_root
main_menu
