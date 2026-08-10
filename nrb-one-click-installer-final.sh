#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# NRB HOSTING ONE-COMMAND INSTALLER
# ===========================================================
# 1) Pterodactyl
# 2) PufferPanel
# 3) Panel V1
# 4) NRB No-KVM / QEMU VM Installer
# 5) LXC + LXD Installation
# 6) Cloudflare Installation
# 7) IP Maker 
# 8) Service Start / Stop / Status
# 9) Uninstall / Repair
# 10) Exit
# ============================================================

PTERODACTYL_COMMAND='bash <(curl -fsSL https://ptero.jishnu.site)'
PUFFERPANEL_COMMAND='curl -fsSL "https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh?any=true" | bash; apt-get update; apt-get install -y pufferpanel; systemctl enable --now pufferpanel'
PANEL_V1_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/panel/refs/heads/main/install-1.sh)'
NOKVM_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/VMS/refs/heads/main/nokvm.sh)'
LXC_LXD_COMMAND='bash <(curl -fsSL https://raw.githubusercontent.com/notroboy67-htp/Notroboy-/refs/heads/main/lxd-installer.sh)'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

banner() {
    clear 2>/dev/null || true
    printf '%b\n' "$CYAN"
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
    printf '%b\n' "$NC"
}

info() { printf '%b\n' "${CYAN}[INFO]${NC} $*"; }
success() { printf '%b\n' "${GREEN}[ OK ]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[WARN]${NC} $*"; }
error() { printf '%b\n' "${RED}[ERROR]${NC} $*"; }
pause() { echo; read -rp "Press Enter to continue..." _; }
die() { error "$*"; exit 1; }

require_root() {
    [[ "$EUID" -eq 0 ]] || die "Please run this installer as root."
}

check_network() {
    command -v curl >/dev/null 2>&1 || { error "curl is not installed."; return 1; }
    curl -fsSI --max-time 10 https://github.com >/dev/null 2>&1 || {
        error "Internet connectivity check failed."
        return 1
    }
}

run_command() { bash -c "$1"; }

install_pterodactyl() {
    banner
    printf '%b\n' "${WHITE}PTERODACTYL INSTALLATION${NC}"
    check_network || { pause; return; }
    if run_command "$PTERODACTYL_COMMAND"; then
        success "Pterodactyl installer finished."
    else
        error "Pterodactyl installer returned an error."
    fi
    pause
}

install_pufferpanel() {
    banner
    printf '%b\n' "${WHITE}PUFFERPANEL INSTALLATION${NC}"
    check_network || { pause; return; }
    if run_command "$PUFFERPANEL_COMMAND"; then
        success "PufferPanel installation completed."
        echo "Create administrator: pufferpanel user add"
        echo "Web port: 8080"
        echo "SFTP port: 5657"
    else
        error "PufferPanel installation failed."
    fi
    pause
}

install_panel_v1() {
    banner
    printf '%b\n' "${WHITE}PANEL V1 INSTALLATION${NC}"
    check_network || { pause; return; }
    if run_command "$PANEL_V1_COMMAND"; then
        success "Panel V1 installation completed."
    else
        error "Panel V1 installer returned an error."
    fi
    pause
}

install_nokvm() {
    banner
    printf '%b\n' "${WHITE}NRB NO-KVM / QEMU VM INSTALLER${NC}"
    check_network || { pause; return; }
    if run_command "$NOKVM_COMMAND"; then
        success "NRB No-KVM installer finished."
    else
        error "NRB No-KVM installer returned an error."
    fi
    pause
}

install_lxc_lxd() {
    banner
    printf '%b\n' "${WHITE}LXC + LXD INSTALLATION${NC}"
    check_network || { pause; return; }
    if run_command "$LXC_LXD_COMMAND"; then
        success "LXC + LXD installation completed."
        echo "Verify: lxc version"
        echo "Initialize: lxd init"
    else
        error "LXC + LXD installer returned an error."
    fi
    pause
}

install_cloudflare() {
    banner
    printf '%b\n' "${WHITE}CLOUDFLARE TUNNEL INSTALLATION${NC}"
    check_network || { pause; return; }

    command -v apt-get >/dev/null 2>&1 || {
        error "Cloudflare installer requires an APT-based system."
        pause
        return
    }

    apt-get update -y
    apt-get install -y curl ca-certificates

    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg         | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main"         | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

    apt-get update -y
    apt-get install -y cloudflared

    command -v cloudflared >/dev/null 2>&1 || {
        error "Cloudflared installation failed."
        pause
        return
    }

    success "Cloudflared installed successfully."
    cloudflared --version

    echo
    read -rsp "Enter Cloudflare Tunnel token: " CLOUDFLARE_TOKEN
    echo

    [[ -n "$CLOUDFLARE_TOKEN" ]] || {
        error "No Cloudflare Tunnel token entered."
        pause
        return
    }

    if cloudflared service install "$CLOUDFLARE_TOKEN"; then
        systemctl enable cloudflared
        systemctl restart cloudflared
        success "Cloudflare Tunnel started."
    else
        error "Cloudflare Tunnel service installation failed."
    fi

    systemctl --no-pager --full status cloudflared || true
    pause
}

# ============================================================
# IP MAKER - TAILSCALE
# ============================================================

install_ip_maker() {
    banner
    printf '%b\n' "${WHITE}IP MAKER - TAILSCALE${NC}"
    echo

    check_network || { pause; return; }

    info "Installing Tailscale..."

    if command -v tailscale >/dev/null 2>&1; then
        success "Tailscale is already installed."
    else
        if curl -fsSL https://tailscale.com/install.sh | sh; then
            success "Tailscale installed successfully."
        else
            error "Tailscale installation failed."
            pause
            return
        fi
    fi

    systemctl enable --now tailscaled

    if ! systemctl is-active --quiet tailscaled; then
        error "tailscaled is not running."
        pause
        return
    fi

    success "Tailscale service is running."

    echo
    info "Running tailscale up..."

    if ! tailscale status >/dev/null 2>&1; then
        if tailscale up --accept-dns=true; then
            success "Tailscale authentication completed."
        else
            warn "Tailscale authentication was not completed."
            echo "Run this later: tailscale up"
            pause
            return
        fi
    else
        success "Tailscale is already connected."
    fi

    echo
    echo "============================================================"
    printf '%b\n' "${GREEN}IP MAKER RESULT${NC}"
    echo "============================================================"

    TAILSCALE_IPV4="$(tailscale ip -4 2>/dev/null || true)"
    TAILSCALE_IPV6="$(tailscale ip -6 2>/dev/null || true)"

    [[ -n "$TAILSCALE_IPV4" ]]         && echo "Tailscale IPv4: $TAILSCALE_IPV4"         || warn "Tailscale IPv4 unavailable."

    [[ -n "$TAILSCALE_IPV6" ]]         && echo "Tailscale IPv6: $TAILSCALE_IPV6"         || true

    echo
    tailscale status || true

    echo
    echo "Useful commands:"
    echo "  tailscale up"
    echo "  tailscale down"
    echo "  tailscale status"
    echo "  tailscale ip"
    echo "  tailscale logout"

    success "IP Maker setup completed."
    pause
}

service_menu() {
    while true; do
        banner
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
        echo "10) Tailscale Start"
        echo "11) Tailscale Stop"
        echo "12) Tailscale Status"
        echo "13) Return"
        echo
        read -rp "Select an option: " choice

        case "$choice" in
            1) systemctl start pufferpanel 2>/dev/null && success "PufferPanel started." || error "Could not start PufferPanel."; pause ;;
            2) systemctl stop pufferpanel 2>/dev/null && success "PufferPanel stopped." || error "Could not stop PufferPanel."; pause ;;
            3) systemctl --no-pager status pufferpanel 2>/dev/null || true; pause ;;
            4) systemctl start docker 2>/dev/null && success "Docker started." || error "Could not start Docker."; pause ;;
            5) systemctl stop docker 2>/dev/null && success "Docker stopped." || error "Could not stop Docker."; pause ;;
            6) systemctl --no-pager status docker 2>/dev/null || true; pause ;;
            7) systemctl start cloudflared 2>/dev/null && success "Cloudflare Tunnel started." || error "Could not start Cloudflare Tunnel."; pause ;;
            8) systemctl stop cloudflared 2>/dev/null && success "Cloudflare Tunnel stopped." || error "Could not stop Cloudflare Tunnel."; pause ;;
            9) systemctl --no-pager status cloudflared 2>/dev/null || true; pause ;;
            10) systemctl start tailscaled 2>/dev/null && success "Tailscale started." || error "Could not start Tailscale."; pause ;;
            11) systemctl stop tailscaled 2>/dev/null && success "Tailscale stopped." || error "Could not stop Tailscale."; pause ;;
            12)
                if command -v tailscale >/dev/null 2>&1; then
                    tailscale status || true
                    echo
                    tailscale ip || true
                else
                    error "Tailscale is not installed."
                fi
                pause
                ;;
            13) return ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

repair_menu() {
    while true; do
        banner
        printf '%b\n' "${WHITE}UNINSTALL / REPAIR${NC}"
        echo
        echo "1) Repair PufferPanel"
        echo "2) Restart PufferPanel"
        echo "3) Uninstall PufferPanel"
        echo "4) Restart Cloudflare Tunnel"
        echo "5) Repair Cloudflare Tunnel"
        echo "6) Uninstall Cloudflare Tunnel"
        echo "7) Repair Tailscale"
        echo "8) Restart Tailscale"
        echo "9) Uninstall Tailscale"
        echo "10) Return"
        echo
        read -rp "Select an option: " choice

        case "$choice" in
            1)
                apt-get update
                apt-get install --reinstall -y pufferpanel || true
                systemctl enable --now pufferpanel || true
                success "PufferPanel repair attempted."
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
                    success "PufferPanel removed."
                fi
                pause
                ;;
            4)
                systemctl restart cloudflared 2>/dev/null && success "Cloudflare restarted." || error "Could not restart Cloudflare."
                pause
                ;;
            5)
                systemctl restart cloudflared 2>/dev/null && success "Cloudflare repair attempted." || warn "Cloudflare service unavailable."
                pause
                ;;
            6)
                read -rp "Uninstall Cloudflare Tunnel? [y/N]: " answer
                if [[ "$answer" =~ ^[Yy]$ ]]; then
                    systemctl disable --now cloudflared 2>/dev/null || true
                    cloudflared service uninstall 2>/dev/null || true
                    apt-get remove -y cloudflared 2>/dev/null || true
                    rm -f /etc/apt/sources.list.d/cloudflared.list
                    rm -f /usr/share/keyrings/cloudflare-main.gpg
                    success "Cloudflare removed."
                fi
                pause
                ;;
            7)
                if command -v tailscale >/dev/null 2>&1; then
                    systemctl restart tailscaled
                    success "Tailscale repair completed."
                else
                    warn "Tailscale is not installed."
                fi
                pause
                ;;
            8)
                systemctl restart tailscaled 2>/dev/null && success "Tailscale restarted." || error "Could not restart Tailscale."
                pause
                ;;
            9)
                read -rp "Uninstall Tailscale? [y/N]: " answer
                if [[ "$answer" =~ ^[Yy]$ ]]; then
                    tailscale logout 2>/dev/null || true
                    systemctl disable --now tailscaled 2>/dev/null || true
                    apt-get remove -y tailscale 2>/dev/null || true
                    success "Tailscale removed."
                fi
                pause
                ;;
            10) return ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

main_menu() {
    while true; do
        banner
        printf '%b\n' "${WHITE}Choose an option:${NC}"
        echo
        echo "1) Pterodactyl"
        echo "2) PufferPanel"
        echo "3) Panel V1"
        echo "4) NRB No-KVM / QEMU VM Installer"
        echo "5) LXC + LXD Installation"
        echo "6) Cloudflare Installation"
        echo "7) IP Maker"
        echo "8) Service Start / Stop / Status"
        echo "9) Uninstall / Repair"
        echo "10) Exit"
        echo
        read -rp "Enter your choice [1-10]: " choice

        case "$choice" in
            1) install_pterodactyl ;;
            2) install_pufferpanel ;;
            3) install_panel_v1 ;;
            4) install_nokvm ;;
            5) install_lxc_lxd ;;
            6) install_cloudflare ;;
            7) install_ip_maker ;;
            8) service_menu ;;
            9) repair_menu ;;
            10)
                success "Thank you for using NOTROBOY Installer."
                exit 0
                ;;
            *) warn "Invalid option. Please choose 1-10."; sleep 1 ;;
        esac
    done
}

require_root
main_menu
