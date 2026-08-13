#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# NRB HOSTING - PTERODACTYL DOCKER INSTALLER V2
# ============================================================
# Docker-based Panel + MariaDB + Redis
# HTTPS-ready
# Secure generated credentials
# Health checks and diagnostic output
#
# Supported:
#   Ubuntu 22.04 / 24.04
#   Debian 12
#
# Run as root.
# ============================================================

NRB_DIR="/srv/pterodactyl"
COMPOSE_FILE="${NRB_DIR}/docker-compose.yml"
ENV_FILE="${NRB_DIR}/.env"
CREDENTIAL_FILE="/root/nrb-pterodactyl-credentials.txt"

PANEL_CONTAINER="nrb-pterodactyl-panel"
DB_CONTAINER="nrb-pterodactyl-db"
REDIS_CONTAINER="nrb-pterodactyl-cache"

log()  { echo -e "\033[1;32m[NRB]\033[0m $*"; }
info() { echo -e "\033[1;36m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

trap 'die "Installer stopped unexpectedly at line ${LINENO}."' ERR

require_root() {
    [[ "$EUID" -eq 0 ]] || die "Run this installer as root."
}

detect_os() {
    [[ -f /etc/os-release ]] || die "Cannot detect operating system."
    . /etc/os-release

    case "${ID}:${VERSION_ID}" in
        ubuntu:22.04|ubuntu:24.04|debian:12)
            log "Supported OS detected: ${PRETTY_NAME}"
            ;;
        *)
            die "Unsupported OS: ${PRETTY_NAME}. Use Ubuntu 22.04/24.04 or Debian 12."
            ;;
    esac
}

check_virtualization() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT="$(systemd-detect-virt || true)"

        case "${VIRT}" in
            openvz|lxc)
                warn "Detected virtualization: ${VIRT}"
                warn "Docker/Wings may require additional host support."

                read -r -p "Continue? [y/N]: " answer
                [[ "${answer}" =~ ^[Yy]$ ]] || exit 0
                ;;
        esac
    fi
}

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log "Docker is already installed."
    else
        log "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
    fi

    systemctl enable --now docker

    docker info >/dev/null 2>&1 || die "Docker is not working."

    log "Docker: OK"

    if docker compose version >/dev/null 2>&1; then
        log "Docker Compose plugin: OK"
    else
        die "Docker Compose plugin is not available."
    fi
}

ask_configuration() {
    echo

    read -r -p "Panel domain (example: panel.example.com): " PANEL_DOMAIN
    [[ -n "${PANEL_DOMAIN}" ]] || die "Panel domain cannot be empty."

    read -r -p "Administrator email: " ADMIN_EMAIL
    [[ "${ADMIN_EMAIL}" == *@*.* ]] || die "Enter a valid email address."

    echo

    read -r -p "Enable HTTPS/Let's Encrypt setup instructions? [Y/n]: " HTTPS_ANSWER
    HTTPS_ANSWER="${HTTPS_ANSWER:-Y}"

    if [[ "${HTTPS_ANSWER}" =~ ^[Yy]$ ]]; then
        USE_HTTPS="true"
        APP_URL="https://${PANEL_DOMAIN}"
    else
        USE_HTTPS="false"
        APP_URL="http://${PANEL_DOMAIN}"

        warn "HTTP selected. Do not use this for sensitive production traffic."
    fi

    DB_NAME="panel"
    DB_USER="pterodactyl"

    DB_PASSWORD="$(openssl rand -hex 24)"
    DB_ROOT_PASSWORD="$(openssl rand -hex 24)"

    APP_TIMEZONE="UTC"

    log "Configuration collected."
}

prepare_directories() {
    log "Preparing NRB directories..."

    mkdir -p \
        "${NRB_DIR}/database" \
        "${NRB_DIR}/var" \
        "${NRB_DIR}/nginx" \
        "${NRB_DIR}/certs" \
        "${NRB_DIR}/logs" \
        "${NRB_DIR}/redis"

    chmod 700 "${NRB_DIR}"
}

write_env() {
    log "Writing secure environment file..."

    umask 077

    cat > "${ENV_FILE}" <<EOF
PANEL_DOMAIN=${PANEL_DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
APP_URL=${APP_URL}
APP_TIMEZONE=${APP_TIMEZONE}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
USE_HTTPS=${USE_HTTPS}
EOF

    chmod 600 "${ENV_FILE}"

    cat > "${CREDENTIAL_FILE}" <<EOF
NRB PTERODACTYL CREDENTIALS
===========================

Panel URL: ${APP_URL}
Administrator Email: ${ADMIN_EMAIL}

Database Host (inside Docker): database
Database Port: 3306
Database Name: ${DB_NAME}
Database User: ${DB_USER}
Database Password: ${DB_PASSWORD}
MariaDB Root Password: ${DB_ROOT_PASSWORD}

Environment file:
${ENV_FILE}

KEEP THIS FILE PRIVATE.
DO NOT UPLOAD IT TO GITHUB.
EOF

    chmod 600 "${CREDENTIAL_FILE}"
}

write_compose() {
    log "Generating Docker Compose configuration..."

    cat > "${COMPOSE_FILE}" <<'EOF'
services:

  database:
    image: mariadb:10.5
    container_name: nrb-pterodactyl-db
    restart: unless-stopped

    command:
      --default-authentication-plugin=mysql_native_password

    environment:
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}

    volumes:
      - /srv/pterodactyl/database:/var/lib/mysql

    networks:
      - nrb


  cache:
    image: redis:alpine
    container_name: nrb-pterodactyl-cache
    restart: unless-stopped

    volumes:
      - /srv/pterodactyl/redis:/data

    networks:
      - nrb


  panel:
    image: ghcr.io/pterodactyl/panel:latest
    container_name: nrb-pterodactyl-panel
    restart: unless-stopped

    depends_on:
      - database
      - cache

    ports:
      - "80:80"
      - "443:443"

    environment:

      APP_URL: ${APP_URL}
      APP_ENV: production
      APP_TIMEZONE: ${APP_TIMEZONE}
      APP_SERVICE_AUTHOR: ${ADMIN_EMAIL}

      TRUSTED_PROXIES: ""

      DB_CONNECTION: mysql
      DB_HOST: database
      DB_PORT: 3306
      DB_DATABASE: ${DB_NAME}
      DB_USERNAME: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}

      CACHE_DRIVER: redis
      SESSION_DRIVER: redis
      QUEUE_DRIVER: redis

      REDIS_HOST: cache
      REDIS_PORT: 6379

      MAIL_FROM: ${ADMIN_EMAIL}
      MAIL_DRIVER: smtp
      MAIL_HOST: ""
      MAIL_PORT: 587
      MAIL_USERNAME: ""
      MAIL_PASSWORD: ""
      MAIL_ENCRYPTION: tls

    volumes:
      - /srv/pterodactyl/var:/app/var
      - /srv/pterodactyl/nginx:/etc/nginx/http.d
      - /srv/pterodactyl/certs:/etc/letsencrypt
      - /srv/pterodactyl/logs:/app/storage/logs

    networks:
      - nrb


networks:

  nrb:
    driver: bridge
EOF

    chmod 600 "${COMPOSE_FILE}"
}

start_stack() {
    log "Pulling container images..."

    cd "${NRB_DIR}"

    docker compose \
        --env-file "${ENV_FILE}" \
        -f "${COMPOSE_FILE}" \
        pull

    log "Starting MariaDB and Redis first..."

    docker compose \
        --env-file "${ENV_FILE}" \
        -f "${COMPOSE_FILE}" \
        up -d database cache

    wait_for_database
    wait_for_redis

    log "Starting Pterodactyl Panel..."

    docker compose \
        --env-file "${ENV_FILE}" \
        -f "${COMPOSE_FILE}" \
        up -d panel

    sleep 10
}

wait_for_database() {
    log "Waiting for MariaDB..."

    for _ in $(seq 1 60); do

        if docker exec "${DB_CONTAINER}" \
            mariadb-admin ping \
            -uroot \
            -p"${DB_ROOT_PASSWORD}" \
            --silent >/dev/null 2>&1; then

            log "MariaDB: READY"
            return
        fi

        sleep 2
    done

    docker logs --tail 80 "${DB_CONTAINER}" || true

    die "MariaDB did not become ready."
}

wait_for_redis() {
    log "Checking Redis..."

    for _ in $(seq 1 30); do

        if docker exec "${REDIS_CONTAINER}" \
            redis-cli ping 2>/dev/null | grep -q PONG; then

            log "Redis: READY"
            return
        fi

        sleep 2
    done

    docker logs --tail 80 "${REDIS_CONTAINER}" || true

    die "Redis did not become ready."
}

database_test() {
    log "Testing Panel database credentials..."

    docker exec "${DB_CONTAINER}" \
        mariadb \
        -u"${DB_USER}" \
        -p"${DB_PASSWORD}" \
        -D "${DB_NAME}" \
        -e "SELECT 1;" >/dev/null 2>&1 \
        || die "Panel database login test failed."

    log "Database credentials: OK"
}

panel_health() {
    log "Checking Panel container..."

    docker ps --format '{{.Names}}' |
        grep -qx "${PANEL_CONTAINER}" \
        || die "Pterodactyl Panel container is not running."

    log "Panel container: RUNNING"

    info "Recent Panel logs:"

    docker logs --tail 30 "${PANEL_CONTAINER}" || true
}

create_admin() {
    echo

    read -r -p \
        "Create Pterodactyl administrator now? [Y/n]: " \
        CREATE_ADMIN

    CREATE_ADMIN="${CREATE_ADMIN:-Y}"

    [[ "${CREATE_ADMIN}" =~ ^[Yy]$ ]] || {
        warn "Skipping administrator creation."
        return
    }

    log "Starting Pterodactyl administrator creation..."

    docker exec -it \
        "${PANEL_CONTAINER}" \
        php artisan p:user:make
}

show_wings_instructions() {
    echo

    echo "============================================================"
    echo " WINGS / NODE NEXT STEP"
    echo "============================================================"
    echo

    echo "The Panel is installed, but Wings is NOT automatically"
    echo "connected to a Node yet."

    echo

    echo "1. Open:"
    echo "   ${APP_URL}"

    echo

    echo "2. Log into the administrator account."

    echo

    echo "3. Create a Node in:"
    echo "   Admin Panel -> Nodes"

    echo

    echo "4. Copy the generated Wings configuration."

    echo

    echo "5. Put it on the Wings server at:"
    echo "   /etc/pterodactyl/config.yml"

    echo

    echo "6. Start Wings:"
    echo "   systemctl enable --now wings"

    echo

    echo "Do NOT invent the config.yml manually."

    echo "============================================================"
}

final_diagnostics() {
    echo

    log "Running NRB final diagnostics..."

    echo

    docker compose \
        --env-file "${ENV_FILE}" \
        -f "${COMPOSE_FILE}" \
        ps

    echo

    log "Container checks:"

    for container in \
        "${DB_CONTAINER}" \
        "${REDIS_CONTAINER}" \
        "${PANEL_CONTAINER}"
    do

        if docker inspect \
            -f '{{.State.Running}}' \
            "${container}" 2>/dev/null |
            grep -q true; then

            echo "  [OK] ${container}"

        else

            echo "  [FAIL] ${container}"

        fi
    done

    echo

    echo "============================================================"
    echo " NRB PTERODACTYL INSTALLATION FINISHED"
    echo "============================================================"

    echo " Panel URL:       ${APP_URL}"
    echo " Compose file:    ${COMPOSE_FILE}"
    echo " Environment:     ${ENV_FILE}"
    echo " Credentials:     ${CREDENTIAL_FILE}"

    echo

    echo " Useful commands:"
    echo "   cd ${NRB_DIR}"
    echo "   docker compose --env-file ${ENV_FILE} ps"
    echo "   docker compose --env-file ${ENV_FILE} logs -f panel"
    echo "   docker compose --env-file ${ENV_FILE} restart panel"

    echo

    echo " IMPORTANT:"
    echo "   HTTPS requires valid DNS and certificate configuration."
    echo "   Wings must be configured separately from the Panel."

    echo "============================================================"
}

main() {

    clear || true

    echo "============================================================"
    echo "       NRB HOSTING - PTERODACTYL DOCKER INSTALLER V2"
    echo "============================================================"

    echo

    require_root
    detect_os
    check_virtualization
    install_docker
    ask_configuration
    prepare_directories
    write_env
    write_compose
    start_stack
    database_test
    panel_health
    create_admin
    show_wings_instructions
    final_diagnostics
}

main "$@"
