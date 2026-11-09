#!/usr/bin/env bash
set -Eeuo pipefail

# NRB Pterodactyl Panel installer for Ubuntu/Debian inside Termux PRoot.
# Panel only: Wings/Docker are intentionally not installed.
# No systemd/systemctl is used. Services are started manually.

PANEL_DIR="${PANEL_DIR:-$HOME/pterodactyl}"
STATE_DIR="${STATE_DIR:-$HOME/.pterodactyl-proot}"
RUN_DIR="${RUN_DIR:-$STATE_DIR/run}"
LOG_DIR="${LOG_DIR:-$STATE_DIR/log}"
PORT="${PORT:-8080}"
DB_NAME="panel"
DB_USER="pterodactyl"
DB_PASS_FILE="$STATE_DIR/db-password"
PHP_FPM_BIN=""
PHP_BIN="php"
PHP_FPM_SOCKET="$RUN_DIR/php-fpm.sock"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info(){ printf "${YELLOW}[NRB]${NC} %s\n" "$*"; }
ok(){ printf "${GREEN}[OK]${NC} %s\n" "$*"; }
die(){ printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; exit 1; }
trap 'die "Installer stopped at line $LINENO. Check the message above."' ERR

[[ "$(id -u)" -eq 0 ]] || die "Enter your Ubuntu/Debian PRoot as root, then run this installer."
[[ -r /etc/os-release ]] || die "Cannot identify this Linux environment."
. /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) die "Supported inside PRoot: Ubuntu or Debian. Detected: ${PRETTY_NAME:-unknown}";; esac
[[ -n "${PREFIX:-}" || -n "${PROOT_VERSION:-}" || "${NRB_ALLOW_NON_PROOT:-0}" == "1" ]] || {
  info "PRoot could not be positively detected. Continuing only if this is an Ubuntu/Debian PRoot."
}

mkdir -p "$RUN_DIR" "$LOG_DIR" "$(dirname "$PANEL_DIR")"
chmod 700 "$STATE_DIR"

if [[ -f "$PANEL_DIR/artisan" ]]; then
  die "A Panel installation already exists at $PANEL_DIR. Back it up/remove it before reinstalling."
fi

echo
echo "============================================================"
echo " NRB PTERODACTYL PANEL - PROOT EDITION"
echo " Panel only | no systemd | no Docker | no Wings"
echo "============================================================"
echo

export DEBIAN_FRONTEND=noninteractive
info "[1/8] Installing packages..."
apt-get update
apt-get install -y ca-certificates curl wget unzip tar gzip git openssl \
  nginx mariadb-server redis-server composer \
  php-cli php-fpm php-mysql php-gd php-mbstring php-bcmath php-xml \
  php-curl php-zip php-intl php-redis php-tokenizer php-fileinfo

command -v php >/dev/null || die "PHP CLI package did not install."
command -v composer >/dev/null || die "Composer package did not install."
PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
PHP_FPM_BIN="$(command -v "php-fpm${PHP_VERSION}" || command -v php-fpm || true)"
[[ -n "$PHP_FPM_BIN" ]] || die "PHP-FPM executable not found."
ok "PHP $PHP_VERSION and Composer are installed."

info "[2/8] Preparing PRoot service configuration..."
# MariaDB's normal system service is not used. Disable io_uring/native AIO,
# which commonly fails under Android/PRoot.
DB_DATA_DIR="/var/lib/mysql"
[[ -d "$DB_DATA_DIR" ]] || mkdir -p "$DB_DATA_DIR"
if [[ ! -d "$DB_DATA_DIR/mysql" ]]; then
  command -v mariadb-install-db >/dev/null || command -v mysql_install_db >/dev/null || die "MariaDB initialization tool missing."
  if command -v mariadb-install-db >/dev/null; then
    mariadb-install-db --user=root --datadir="$DB_DATA_DIR" --auth-root-authentication-method=normal
  else
    mysql_install_db --user=root --datadir="$DB_DATA_DIR"
  fi
fi

start_mariadb() {
  if mariadb-admin --protocol=tcp -h127.0.0.1 ping >/dev/null 2>&1; then return; fi
  info "Starting MariaDB without systemd..."
  (mariadbd --user=root --datadir="$DB_DATA_DIR" \
    --socket="$RUN_DIR/mysql.sock" --pid-file="$RUN_DIR/mariadb.pid" \
    --bind-address=127.0.0.1 --port=3306 \
    --innodb-use-native-aio=0 --skip-log-error \
    >>"$LOG_DIR/mariadb.log" 2>&1 &) || true
  for _ in $(seq 1 40); do
    mariadb-admin --protocol=tcp -h127.0.0.1 ping >/dev/null 2>&1 && return
    sleep 1
  done
  tail -n 60 "$LOG_DIR/mariadb.log" || true
  die "MariaDB did not start. See $LOG_DIR/mariadb.log"
}

start_redis() {
  if redis-cli -h 127.0.0.1 ping 2>/dev/null | grep -q PONG; then return; fi
  info "Starting Redis without systemd..."
  redis-server --bind 127.0.0.1 --port 6379 --daemonize yes \
    --pidfile "$RUN_DIR/redis.pid" --logfile "$LOG_DIR/redis.log"
  for _ in $(seq 1 15); do
    redis-cli -h 127.0.0.1 ping 2>/dev/null | grep -q PONG && return
    sleep 1
  done
  tail -n 40 "$LOG_DIR/redis.log" || true
  die "Redis did not start."
}

start_mariadb
start_redis

info "[3/8] Creating Panel database..."
if [[ ! -s "$DB_PASS_FILE" ]]; then
  openssl rand -hex 24 > "$DB_PASS_FILE"
  chmod 600 "$DB_PASS_FILE"
fi
DB_PASSWORD="$(cat "$DB_PASS_FILE")"
mariadb --protocol=tcp -h127.0.0.1 -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
ok "Database created."

info "[4/8] Downloading the latest Pterodactyl Panel..."
mkdir -p "$PANEL_DIR"
ARCHIVE="$STATE_DIR/panel.tar.gz"
curl -fL --retry 3 https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz -o "$ARCHIVE"
tar -xzf "$ARCHIVE" -C "$PANEL_DIR" --strip-components=1
rm -f "$ARCHIVE"
cd "$PANEL_DIR"
cp -n .env.example .env
composer install --no-dev --optimize-autoloader --no-interaction
php artisan key:generate --force
ok "Panel files and Composer dependencies installed."

info "[5/8] Configuring Panel..."
read -r -p "Panel URL (for local testing, use http://127.0.0.1:${PORT}): " PANEL_URL
read -r -p "Admin email: " ADMIN_EMAIL
[[ -n "$PANEL_URL" && -n "$ADMIN_EMAIL" ]] || die "Panel URL and admin email are required."

php artisan p:environment:database \
  --host=127.0.0.1 --port=3306 --database="$DB_NAME" \
  --username="$DB_USER" --password="$DB_PASSWORD"
php artisan p:environment:setup \
  --author="$ADMIN_EMAIL" --url="$PANEL_URL" --timezone="Asia/Kolkata" \
  --cache=redis --session=redis --queue=redis \
  --redis-host=127.0.0.1 --redis-port=6379 --redis-password=""
php artisan migrate --seed --force

info "[6/8] Configuring PHP-FPM and Nginx..."
# Use a private Unix socket in the user's PRoot home; avoid /run/systemd paths.
FPM_CONF="$(find /etc/php -type f -path '*/fpm/pool.d/www.conf' 2>/dev/null | sort -V | tail -n1)"
[[ -n "$FPM_CONF" ]] || die "Could not locate PHP-FPM www.conf."
cp "$FPM_CONF" "$FPM_CONF.nrb-backup"
sed -i \
  -e "s|^[;[:space:]]*listen = .*|listen = $PHP_FPM_SOCKET|" \
  -e 's|^[;[:space:]]*listen.owner = .*|;listen.owner = www-data|' \
  -e 's|^[;[:space:]]*listen.group = .*|;listen.group = www-data|' \
  -e 's|^[;[:space:]]*listen.mode = .*|listen.mode = 0660|' \
  "$FPM_CONF"
# Panel writable directories: avoid chown, which is unreliable in PRoot.
chmod -R u+rwX,go+rX "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

NGINX_CONF="/etc/nginx/sites-available/pterodactyl-proot"
cat > "$NGINX_CONF" <<EOF
server {
    listen ${PORT};
    server_name _;
    root ${PANEL_DIR}/public;
    index index.php;
    client_max_body_size 100m;

    location / {
        try_files \\$uri \\$uri/ /index.php?\\$query_string;
    }
    location ~ \\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_FPM_SOCKET};
    }
    location ~ /\\.ht {
        deny all;
    }
}
EOF
mkdir -p /etc/nginx/sites-enabled
rm -f /etc/nginx/sites-enabled/default
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/pterodactyl-proot
nginx -t

info "[7/8] Creating manual start/stop helpers..."
cat > "$STATE_DIR/start.sh" <<'START'
#!/usr/bin/env bash
set -e
STATE_DIR="${HOME}/.pterodactyl-proot"
RUN_DIR="$STATE_DIR/run"
LOG_DIR="$STATE_DIR/log"
mkdir -p "$RUN_DIR" "$LOG_DIR"
DB_DATA_DIR="/var/lib/mysql"
if ! mariadb-admin --protocol=tcp -h127.0.0.1 ping >/dev/null 2>&1; then
  (mariadbd --user=root --datadir="$DB_DATA_DIR" --socket="$RUN_DIR/mysql.sock" \
    --pid-file="$RUN_DIR/mariadb.pid" --bind-address=127.0.0.1 --port=3306 \
    --innodb-use-native-aio=0 --skip-log-error >>"$LOG_DIR/mariadb.log" 2>&1 &)
fi
for i in $(seq 1 40); do mariadb-admin --protocol=tcp -h127.0.0.1 ping >/dev/null 2>&1 && break; sleep 1; done
redis-cli ping >/dev/null 2>&1 || redis-server --bind 127.0.0.1 --port 6379 --daemonize yes --pidfile "$RUN_DIR/redis.pid" --logfile "$LOG_DIR/redis.log"
PHP_FPM_BIN="$(find /usr/sbin /usr/bin -maxdepth 1 -type f -name 'php-fpm*' 2>/dev/null | sort -V | tail -n1)"
[[ -n "$PHP_FPM_BIN" ]] && "$PHP_FPM_BIN" -D
nginx
cd "$HOME/pterodactyl" 2>/dev/null || cd /var/www/pterodactyl
php artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 >>"$LOG_DIR/queue.log" 2>&1 &
echo "Pterodactyl services started. Open http://127.0.0.1:8080"
START
# Replace the helper's default panel directory/port with actual install values.
sed -i "s|\\$HOME/pterodactyl|$PANEL_DIR|g; s|8080|$PORT|g" "$STATE_DIR/start.sh"
cat > "$STATE_DIR/stop.sh" <<'STOP'
#!/usr/bin/env bash
STATE_DIR="${HOME}/.pterodactyl-proot"
nginx -s quit 2>/dev/null || true
pkill -f 'artisan queue:work' 2>/dev/null || true
pkill -f 'php-fpm: master process' 2>/dev/null || true
redis-cli shutdown 2>/dev/null || true
if [[ -f "$STATE_DIR/run/mariadb.pid" ]]; then kill "$(cat "$STATE_DIR/run/mariadb.pid")" 2>/dev/null || true; fi
echo "Pterodactyl services stopped where possible."
STOP
chmod +x "$STATE_DIR/start.sh" "$STATE_DIR/stop.sh"

# Start PHP-FPM, Nginx and queue worker for this session.
"$PHP_FPM_BIN" -D
nginx
php artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 >>"$LOG_DIR/queue.log" 2>&1 &
QUEUE_PID=$!
echo "$QUEUE_PID" > "$RUN_DIR/queue.pid"

info "[8/8] Creating administrator..."
php artisan p:user:make
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan config:cache
php artisan route:cache || true
php artisan view:cache

echo
echo "============================================================"
echo " NRB PTERODACTYL PROOT INSTALLATION FINISHED"
echo "============================================================"
echo "Panel URL:       http://127.0.0.1:${PORT}"
echo "Configured URL:  ${PANEL_URL}"
echo "Panel directory: ${PANEL_DIR}"
echo "PHP:             ${PHP_VERSION}"
echo "DB name/user:    ${DB_NAME} / ${DB_USER}"
echo "DB password:     ${DB_PASSWORD}"
echo "Start services:  bash ${STATE_DIR}/start.sh"
echo "Stop services:   bash ${STATE_DIR}/stop.sh"
echo "Logs:            ${LOG_DIR}"
echo "Wings:           NOT INSTALLED (requires a Docker-capable host)"
echo "============================================================"
