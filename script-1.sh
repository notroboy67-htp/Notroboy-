
#!/bin/bash
set -e

mkdir -p /opt/nrb-vps-bot/data
cd /opt/nrb-vps-bot

echo "Installing Docker dependencies..."

if ! command -v docker >/dev/null 2>&1; then
    apt-get update
    apt-get install -y docker.io docker-compose-v2
fi

systemctl enable --now docker

cat > requirements.txt <<'EOF'
discord.py
docker
python-dotenv
EOF

cat > Dockerfile <<'EOF'
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y curl openssh-client && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY bot.py .
CMD ["python", "-u", "bot.py"]
EOF

cat > docker-compose.yml <<'EOF'
services:
  bot:
    build: .
    container_name: nrb-discord-bot
    restart: unless-stopped
    env_file: .env
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
EOF

cat > .env <<'EOF'
DISCORD_TOKEN=YOUR_DISCORD_BOT_TOKEN
EOF

cat > bot.py <<'EOF'
import discord, docker, os, json, secrets, string, subprocess
from discord import app_commands

TOKEN = os.getenv("DISCORD_TOKEN")
d = docker.from_env()
os.makedirs("data", exist_ok=True)
DB = "data/vps.json"

def load():
    try:
        with open(DB) as f: return json.load(f)
    except: return {}

def save(x):
    with open(DB, "w") as f: json.dump(x, f, indent=2)

def get_ip():
    try:
        return subprocess.check_output(
            ["curl", "-4", "-s", "--max-time", "5", "https://api.ipify.org"],
            text=True
        ).strip()
    except:
        return "Unavailable"

def key(uid, name):
    return f"{uid}:{name.lower()}"

def password():
    return ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20))

intents = discord.Intents.default()
bot = discord.Client(intents=intents)
tree = app_commands.CommandTree(bot)

@bot.event
async def on_ready():
    await tree.sync()
    print(f"NRB VPS BOT ONLINE: {bot.user}")

@tree.command(name="create-vps", description="Create Docker VPS")
async def create(interaction: discord.Interaction, name: str, ram: int = 1024, cpu: int = 1):
    await interaction.response.defer(ephemeral=True)

    if not name.replace("-", "").replace("_", "").isalnum():
        return await interaction.followup.send("Invalid VPS name.")

    if not 512 <= ram <= 8192 or not 1 <= cpu <= 4:
        return await interaction.followup.send("RAM: 512-8192 MB, CPU: 1-4.")

    data = load()
    k = key(interaction.user.id, name)
    if k in data:
        return await interaction.followup.send("Name already exists.")

    passwd = password()
    port = 22000 + secrets.randbelow(20000)
    cname = f"nrb-{interaction.user.id}-{name.lower()}"

    try:
        c = d.containers.run(
            "linuxserver/openssh-server:latest",
            name=cname,
            detach=True,
            restart_policy={"Name": "unless-stopped"},
            mem_limit=f"{ram}m",
            nano_cpus=cpu * 1000000000,
            ports={"2222/tcp": port},
            environment={
                "USER_NAME": "nrbuser",
                "USER_PASSWORD": passwd,
                "PASSWORD_ACCESS": "true",
                "SUDO_ACCESS": "false",
                "TZ": "Asia/Kolkata"
            },
            labels={"nrb.owner": str(interaction.user.id)}
        )

        ip = get_ip()
        data[k] = {
            "container": cname,
            "port": port,
            "ip": ip,
            "password": passwd,
            "ram": ram,
            "cpu": cpu
        }
        save(data)

        e = discord.Embed(title="NRB VPS Created", color=0x00ff88)
        e.add_field(name="IPv4", value=ip)
        e.add_field(name="SSH Port", value=str(port))
        e.add_field(name="Username", value="nrbuser")
        e.add_field(name="Password", value=f"||{passwd}||")
        e.add_field(name="SSH command", value=f"`ssh -p {port} nrbuser@{ip}`", inline=False)
        e.set_footer(text="NRB VPS Docker Edition")
        await interaction.followup.send(embed=e, ephemeral=True)

    except Exception as ex:
        await interaction.followup.send(f"Error: {str(ex)[:500]}")

@tree.command(name="start-vps", description="Start VPS")
async def start(interaction: discord.Interaction, name: str):
    await interaction.response.defer(ephemeral=True)
    v = load().get(key(interaction.user.id, name))
    if not v: return await interaction.followup.send("VPS not found.")
    d.containers.get(v["container"]).start()
    await interaction.followup.send("VPS started.")

@tree.command(name="stop-vps", description="Stop VPS")
async def stop(interaction: discord.Interaction, name: str):
    await interaction.response.defer(ephemeral=True)
    v = load().get(key(interaction.user.id, name))
    if not v: return await interaction.followup.send("VPS not found.")
    d.containers.get(v["container"]).stop()
    await interaction.followup.send("VPS stopped.")

@tree.command(name="restart-vps", description="Restart VPS")
async def restart(interaction: discord.Interaction, name: str):
    await interaction.response.defer(ephemeral=True)
    v = load().get(key(interaction.user.id, name))
    if not v: return await interaction.followup.send("VPS not found.")
    d.containers.get(v["container"]).restart()
    await interaction.followup.send("VPS restarted.")

@tree.command(name="delete-vps", description="Delete VPS")
async def delete(interaction: discord.Interaction, name: str):
    await interaction.response.defer(ephemeral=True)
    data = load()
    k = key(interaction.user.id, name)
    v = data.get(k)
    if not v: return await interaction.followup.send("VPS not found.")
    d.containers.get(v["container"]).remove(force=True)
    del data[k]
    save(data)
    await interaction.followup.send("VPS deleted.")

@tree.command(name="list-vps", description="List your VPS")
async def listing(interaction: discord.Interaction):
    data = load()
    items = [f"**{k.split(':',1)[1]}** - {v['ip']}:{v['port']}" for k,v in data.items() if k.startswith(f"{interaction.user.id}:")]
    await interaction.response.send_message("\n".join(items) or "No VPS found.", ephemeral=True)

@tree.command(name="vps-info", description="VPS connection information")
async def info(interaction: discord.Interaction, name: str):
    v = load().get(key(interaction.user.id, name))
    if not v: return await interaction.response.send_message("VPS not found.", ephemeral=True)
    e = discord.Embed(title="NRB VPS Information")
    e.add_field(name="IPv4", value=v["ip"])
    e.add_field(name="Port", value=str(v["port"]))
    e.add_field(name="Username", value="nrbuser")
    e.add_field(name="Password", value=f"||{v['password']}||")
    await interaction.response.send_message(embed=e, ephemeral=True)

if not TOKEN or TOKEN == "YOUR_DISCORD_BOT_TOKEN":
    raise RuntimeError("Set DISCORD_TOKEN in .env first")

bot.run(TOKEN)
EOF

echo
echo "===================================="
echo " NRB VPS BOT CREATED"
echo "===================================="
echo "Enter your Discord bot token:"
read -r -s TOKEN
echo
sed -i "s|^DISCORD_TOKEN=.*|DISCORD_TOKEN=$TOKEN|" .env

docker compose up -d --build

echo
echo "NRB VPS BOT STARTED!"
echo "Check logs: cd /opt/nrb-vps-bot && docker compose logs -f"
