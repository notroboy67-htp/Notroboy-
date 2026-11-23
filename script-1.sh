#!/bin/bash
# ==========================================
# DISCORD VPS HOSTING BOT - ONE CMD INSTALLER
# ==========================================

set -Eeuo pipefail

APP="/opt/discord-vps-bot"
DATA="/var/lib/discord-vps-bot"
ENV="/etc/discord-vps-bot.env"
USER="discordvps"

if [[ $EUID -ne 0 ]]; then
    echo "Run: sudo bash install.sh"
    exit 1
fi

clear
echo "=========================================="
echo "       DISCORD VPS HOSTING BOT"
echo "=========================================="
echo

ask() {
    local answer
    read -r -p "$1 [$2]: " answer
    echo "${answer:-$2}"
}

read -r -s -p "Discord Bot Token: " TOKEN
echo
[[ -n "$TOKEN" ]] || exit 1

GUILD=$(ask "Discord Server ID (0 = global)" "0")
ADMINS=$(ask "Admin User IDs (comma separated)" "")
ROLES=$(ask "Admin Role IDs (comma separated)" "")
MAX=$(ask "Maximum VPS per customer" "2")
CPU=$(ask "Default CPU cores" "1")
RAM=$(ask "Default RAM in MB" "1024")
DISK=$(ask "Default Disk in GB" "10")
IMAGE=$(ask "Ubuntu image" "images:ubuntu/22.04")

for n in "$GUILD" "$MAX" "$CPU" "$RAM" "$DISK"; do
    [[ "$n" =~ ^[0-9]+$ ]] || {
        echo "Invalid numeric value"
        exit 1
    }
done

(( MAX >= 1 && CPU >= 1 && RAM >= 256 && DISK >= 1 )) || exit 1

echo
echo "[1/7] Installing dependencies..."

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y python3 python3-venv python3-pip snapd

echo "[2/7] Installing LXD..."

if ! command -v lxc >/dev/null 2>&1; then
    snap install lxd
fi

if ! getent group lxd >/dev/null 2>&1; then
    groupadd lxd
fi

if ! lxc info >/dev/null 2>&1; then
    lxd init --auto
fi

echo "[3/7] Creating directories..."

id "$USER" >/dev/null 2>&1 || \
useradd --system --create-home --home-dir "$DATA" \
--shell /usr/sbin/nologin "$USER"

usermod -aG lxd "$USER"

mkdir -p "$APP/bot" "$DATA"
chown "$USER:$USER" "$DATA"

echo "[4/7] Configuring bot..."

cat > "$ENV" <<EOF
DISCORD_TOKEN=$TOKEN
GUILD_ID=$GUILD
ADMIN_USER_IDS=$ADMINS
ADMIN_ROLE_IDS=$ROLES
DB_PATH=$DATA/bot.sqlite3
LXC_BIN=/snap/bin/lxc
DEFAULT_IMAGE=$IMAGE
MAX_VPS_PER_USER=$MAX
DEFAULT_VCPU=$CPU
DEFAULT_MEMORY_MB=$RAM
DEFAULT_DISK_GB=$DISK
MAX_VCPU=$CPU
MAX_MEMORY_MB=$RAM
MAX_DISK_GB=$DISK
EOF

chmod 600 "$ENV"

cat > "$APP/bot/__init__.py" <<'EOF'
EOF

cat > "$APP/bot/config.py" <<'EOF'
import os

def csv_ints(name):
    return {
        int(x.strip())
        for x in os.getenv(name, "").split(",")
        if x.strip()
    }

DISCORD_TOKEN = os.environ["DISCORD_TOKEN"]
GUILD_ID = int(os.getenv("GUILD_ID", "0"))
ADMIN_USER_IDS = csv_ints("ADMIN_USER_IDS")
ADMIN_ROLE_IDS = csv_ints("ADMIN_ROLE_IDS")

DB_PATH = os.getenv("DB_PATH")
LXC_BIN = os.getenv("LXC_BIN", "lxc")
DEFAULT_IMAGE = os.getenv("DEFAULT_IMAGE", "images:ubuntu/22.04")

MAX_VPS_PER_USER = int(os.getenv("MAX_VPS_PER_USER", "2"))
DEFAULT_VCPU = int(os.getenv("DEFAULT_VCPU", "1"))
DEFAULT_MEMORY_MB = int(os.getenv("DEFAULT_MEMORY_MB", "1024"))
DEFAULT_DISK_GB = int(os.getenv("DEFAULT_DISK_GB", "10"))
EOF

cat > "$APP/bot/db.py" <<'EOF'
import sqlite3
from pathlib import Path
from . import config

def connect():
    Path(config.DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(config.DB_PATH)
    db.row_factory = sqlite3.Row
    return db

def init_db():
    with connect() as db:
        db.execute("""
        CREATE TABLE IF NOT EXISTS vps (
            name TEXT PRIMARY KEY,
            owner_id INTEGER NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """)

def add_vps(name, owner):
    with connect() as db:
        db.execute(
            "INSERT INTO vps(name, owner_id) VALUES(?, ?)",
            (name, owner)
        )

def remove_vps(name):
    with connect() as db:
        db.execute("DELETE FROM vps WHERE name=?", (name,))

def owner_of(name):
    with connect() as db:
        row = db.execute(
            "SELECT owner_id FROM vps WHERE name=?", (name,)
        ).fetchone()
        return int(row["owner_id"]) if row else None

def count_for_user(owner):
    with connect() as db:
        return db.execute(
            "SELECT COUNT(*) FROM vps WHERE owner_id=?", (owner,)
        ).fetchone()[0]

def list_for_user(owner):
    with connect() as db:
        return db.execute(
            "SELECT name FROM vps WHERE owner_id=?", (owner,)
        ).fetchall()
EOF

cat > "$APP/bot/lxd.py" <<'EOF'
import subprocess
import json
import re
from . import config

class LXD:

    def run(self, *args, timeout=90):
        p = subprocess.run(
            [config.LXC_BIN, *map(str, args)],
            capture_output=True,
            text=True,
            timeout=timeout
        )

        if p.returncode:
            raise RuntimeError((p.stderr or p.stdout)[-1000:])

        return p.stdout

    def validate(self, name):
        if not re.fullmatch(r"[a-z][a-z0-9-]{2,29}", name):
            raise ValueError("Invalid VPS name")

    def list(self):
        return json.loads(
            self.run("list", "--format", "json")
        )

    def launch(self, name):
        self.validate(name)

        if any(x["name"] == name for x in self.list()):
            raise ValueError("VPS already exists")

        self.run(
            "launch", config.DEFAULT_IMAGE, name,
            timeout=180
        )

        try:
            self.run("config", "set", name,
                     "limits.cpu", config.DEFAULT_VCPU)

            self.run("config", "set", name,
                     "limits.memory",
                     f"{config.DEFAULT_MEMORY_MB}MB")

            self.run("config", "device", "override",
                     name, "root",
                     f"size={config.DEFAULT_DISK_GB}GB")

        except Exception:
            try:
                self.run("delete", name, "--force")
            except Exception:
                pass
            raise

    def action(self, action, name):
        self.validate(name)

        if action == "delete":
            return self.run("delete", name, "--force")

        if action == "restart":
            return self.run("restart", name)

        if action == "start":
            return self.run("start", name)

        if action == "stop":
            return self.run("stop", name)

        raise ValueError("Invalid action")

    def details(self, name):
        self.validate(name)

        data = json.loads(
            self.run("info", name, "--format", "json")
        )

        return data.get("state", {})
EOF

cat > "$APP/bot/main.py" <<'EOF'
import asyncio
import logging
import discord

from discord import app_commands
from discord.ext import commands

from . import config, db
from .lxd import LXD

logging.basicConfig(level=logging.INFO)

bot = commands.Bot(
    command_prefix="!",
    intents=discord.Intents.default()
)

lxd = LXD()

def admin(interaction):
    if interaction.user.id in config.ADMIN_USER_IDS:
        return True

    return any(
        role.id in config.ADMIN_ROLE_IDS
        for role in getattr(interaction.user, "roles", [])
    )

def permitted(interaction, name):
    return admin(interaction) or db.owner_of(name) == interaction.user.id

async def run(fn, *args):
    return await asyncio.to_thread(fn, *args)

async def reply(interaction, message):
    if interaction.response.is_done():
        await interaction.followup.send(
            message, ephemeral=True
        )
    else:
        await interaction.response.send_message(
            message, ephemeral=True
        )

@bot.event
async def on_ready():
    print(f"Bot online: {bot.user}")

    try:
        if config.GUILD_ID:
            guild = discord.Object(id=config.GUILD_ID)
            bot.tree.copy_global_to(guild=guild)
            await bot.tree.sync(guild=guild)
        else:
            await bot.tree.sync()
    except Exception:
        logging.exception("Command sync failed")

@bot.tree.command(
    name="vps-create",
    description="Create your own VPS"
)
async def create(interaction: discord.Interaction, name: str):
    name = name.lower().strip()

    try:
        lxd.validate(name)

        if (
            db.count_for_user(interaction.user.id)
            >= config.MAX_VPS_PER_USER
            and not admin(interaction)
        ):
            return await reply(interaction, "VPS limit reached.")

        await interaction.response.defer(ephemeral=True)

        await run(lxd.launch, name)

        try:
            db.add_vps(name, interaction.user.id)
        except Exception:
            await run(lxd.action, "delete", name)
            raise

        await interaction.followup.send(
            f"✅ VPS `{name}` created!\n"
            f"CPU: {config.DEFAULT_VCPU}\n"
            f"RAM: {config.DEFAULT_MEMORY_MB} MB\n"
            f"Disk: {config.DEFAULT_DISK_GB} GB\n"
            "Note: container IP is not automatically public.",
            ephemeral=True
        )

    except Exception as e:
        await reply(interaction, f"❌ {str(e)[:700]}")

@bot.tree.command(name="vps-list", description="List your VPS")
async def listing(interaction: discord.Interaction):

    rows = db.list_for_user(interaction.user.id)

    if admin(interaction):
        rows = await run(lxd.list)
        names = [x["name"] for x in rows]
    else:
        names = [x["name"] for x in rows]

    await reply(
        interaction,
        "\n".join(names) if names else "No VPS found."
    )

async def manage(interaction, action, name):
    name = name.lower().strip()

    try:
        lxd.validate(name)

        if not permitted(interaction, name):
            return await reply(interaction, "Access denied.")

        if db.owner_of(name) is None and not admin(interaction):
            return await reply(interaction, "VPS ownership not found.")

        await interaction.response.defer(ephemeral=True)

        await run(lxd.action, action, name)

        if action == "delete":
            db.remove_vps(name)

        await interaction.followup.send(
            f"✅ VPS {name}: {action} successful.",
            ephemeral=True
        )

    except Exception as e:
        await reply(interaction, f"❌ {str(e)[:700]}")

def make_callback(action):
    async def callback(interaction: discord.Interaction, name: str):
        await manage(interaction, action, name)
    return callback

for action in ("start", "stop", "restart", "delete"):
    bot.tree.add_command(
        app_commands.Command(
            name=f"vps-{action}",
            description=f"{action.capitalize()} your VPS",
            callback=make_callback(action)
        )
    )

@bot.tree.command(name="vps-info", description="Show VPS information")
async def info(interaction: discord.Interaction, name: str):

    if not permitted(interaction, name):
        return await reply(interaction, "Access denied.")

    try:
        data = await run(lxd.details, name)

        await reply(
            interaction,
            f"VPS: {name}\n"
            f"Status: {data.get('status', 'Unknown')}"
        )

    except Exception as e:
        await reply(interaction, f"❌ {str(e)[:700]}")

@bot.tree.command(
    name="vps-admin-list",
    description="Administrator: list all VPS"
)
async def admin_list(interaction: discord.Interaction):

    if not admin(interaction):
        return await reply(interaction, "Admin only.")

    containers = await run(lxd.list)

    names = [
        f"{x['name']} - {x.get('status', 'Unknown')}"
        for x in containers
    ]

    await reply(
        interaction,
        "\n".join(names) if names else "No containers."
    )

def main():
    db.init_db()
    bot.run(config.DISCORD_TOKEN)

if __name__ == "__main__":
    main()
EOF

echo "[5/7] Installing Python packages..."

python3 -m venv "$APP/venv"

"$APP/venv/bin/pip" install --upgrade pip
"$APP/venv/bin/pip" install "discord.py>=2.4,<3"

chown -R root:root "$APP"
chmod -R go-w "$APP"
chown -R "$USER:$USER" "$DATA"

echo "[6/7] Creating systemd service..."

cat > /etc/systemd/system/discord-vps-bot.service <<EOF
[Unit]
Description=Discord VPS Hosting Bot
After=network-online.target snap.lxd.daemon.service
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=$USER
SupplementaryGroups=lxd
WorkingDirectory=$APP
EnvironmentFile=$ENV
ExecStart=$APP/venv/bin/python -m bot.main
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=$DATA

[Install]
WantedBy=multi-user.target
EOF

echo "[7/7] Starting Discord bot..."

systemctl daemon-reload
systemctl enable --now discord-vps-bot

echo
echo "=========================================="
echo "       INSTALLATION COMPLETE!"
echo "=========================================="
echo
echo "Discord commands:"
echo "/vps-create"
echo "/vps-list"
echo "/vps-info"
echo "/vps-start"
echo "/vps-stop"
echo "/vps-restart"
echo "/vps-delete"
echo "/vps-admin-list"
echo
echo "Check status:"
echo "systemctl status discord-vps-bot"
echo
echo "View logs:"
echo "journalctl -u discord-vps-bot -f"
echo
echo "IMPORTANT: Public IP and SSH networking"
echo "must be configured separately."
