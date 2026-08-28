install_wings() {
    clear

    echo "=============================================="
    echo "        NRB - WINGS INSTALLER"
    echo "        Latest Stable Wings Release"
    echo "=============================================="
    echo

    # Must be root
    if [ "$(id -u)" -ne 0 ]; then
        echo "[ERROR] Please run this installer as root."
        return 1
    fi

    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
    else
        echo "[ERROR] Cannot detect operating system."
        return 1
    fi

    echo "[1/8] Checking virtualization..."
    VIRT=$(systemd-detect-virt 2>/dev/null || true)

    if [[ "$VIRT" == "lxc" || "$VIRT" == "openvz" ]]; then
        echo
        echo "[WARNING] This system appears to be running inside:"
        echo "          $VIRT"
        echo
        echo "Wings normally requires Docker-capable virtualization."
        echo "KVM/dedicated VPS is recommended."
        echo
        read -rp "Continue anyway? [y/N]: " CONTINUE

        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            return 1
        fi
    fi

    echo
    echo "[2/8] Installing required packages..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y

    apt-get install -y \
        curl \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common

    echo
    echo "[3/8] Installing Docker CE..."

    # Remove conflicting Docker packages if present
    apt-get remove -y \
        docker.io \
        docker-doc \
        docker-compose \
        docker-compose-v2 \
        podman-docker \
        containerd \
        runc 2>/dev/null || true

    # Docker official repository
    install -m 0755 -d /etc/apt/keyrings

    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
        curl -fsSL https://download.docker.com/linux/$ID/gpg \
            -o /etc/apt/keyrings/docker.asc

        chmod a+r /etc/apt/keyrings/docker.asc
    fi

    if [ "$ID" = "ubuntu" ]; then
        DOCKER_CODENAME="${VERSION_CODENAME}"
    elif [ "$ID" = "debian" ]; then
        DOCKER_CODENAME="${VERSION_CODENAME}"
    else
        echo "[ERROR] Unsupported OS: $ID"
        echo "Supported by this installer: Debian/Ubuntu."
        return 1
    fi

    cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $DOCKER_CODENAME stable
EOF

    apt-get update -y

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    echo
    echo "[4/8] Starting Docker..."

    systemctl enable --now docker

    if ! systemctl is-active --quiet docker; then
        echo "[ERROR] Docker failed to start."
        systemctl status docker --no-pager
        return 1
    fi

    echo "[OK] Docker is running."

    echo
    echo "[5/8] Creating Pterodactyl directories..."

    mkdir -p /etc/pterodactyl

    # Common Wings data directory
    mkdir -p /var/lib/pterodactyl

    # Ensure permissions
    chmod 755 /etc/pterodactyl
    chmod 755 /var/lib/pterodactyl

    echo
    echo "[6/8] Installing latest Wings..."

    ARCH="$(uname -m)"

    case "$ARCH" in
        x86_64)
            WINGS_ARCH="amd64"
            ;;
        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;
        *)
            echo "[ERROR] Unsupported architecture: $ARCH"
            return 1
            ;;
    esac

    WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"

    # Download to temporary location first
    curl -fL "$WINGS_URL" \
        -o /tmp/wings

    if [ ! -s /tmp/wings ]; then
        echo "[ERROR] Failed to download Wings."
        return 1
    fi

    install -m 0755 /tmp/wings /usr/local/bin/wings

    rm -f /tmp/wings

    echo
    echo "[OK] Wings installed:"
    /usr/local/bin/wings version || true

    echo
    echo "[7/8] Creating systemd service..."

    mkdir -p /var/run/wings

    cat > /etc/systemd/system/wings.service <<'EOF'
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

    systemctl daemon-reload

    echo
    echo "[8/8] Preparing Wings configuration..."

    if [ ! -f /etc/pterodactyl/config.yml ]; then
        touch /etc/pterodactyl/config.yml
        chmod 600 /etc/pterodactyl/config.yml
    fi

    echo
    echo "=============================================="
    echo "        WINGS INSTALLATION COMPLETE"
    echo "=============================================="
    echo
    echo "Wings binary:"
    echo "  /usr/local/bin/wings"
    echo
    echo "Configuration:"
    echo "  /etc/pterodactyl/config.yml"
    echo
    echo "Systemd service:"
    echo "  /etc/systemd/system/wings.service"
    echo
    echo "Docker:"
    docker --version
    echo
    echo "Wings:"
    wings version || true
    echo
    echo "=============================================="
    echo " NEXT STEP: CONFIGURE THE NODE"
    echo "=============================================="
    echo
    echo "1. Open your Pterodactyl Panel."
    echo "2. Go to Administration -> Nodes."
    echo "3. Create/select your node."
    echo "4. Open the Configuration tab."
    echo "5. Copy the generated configuration."
    echo "6. Put it in:"
    echo
    echo "   /etc/pterodactyl/config.yml"
    echo
    echo "Then run:"
    echo
    echo "   wings --debug"
    echo
    echo "If there are no errors, press CTRL+C and run:"
    echo
    echo "   systemctl enable --now wings"
    echo
    echo "=============================================="
}
