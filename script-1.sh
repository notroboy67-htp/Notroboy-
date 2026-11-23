#!/bin/bash
# ============================================
# Discord LXC/LXD VPS Bot - Complete Setup
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║     DISCORD LXC/LXD VPS BOT SETUP       ║"
echo "║     Container Management & Monitoring    ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] This script must be run as root${NC}"
   exit 1
fi

# Install LXD if not present
install_lxd() {
    if command -v lxd &>/dev/null; then
        echo -e "${GREEN}[+] LXD already installed${NC}"
        return
    fi
    
    echo -e "${YELLOW}[*] Installing LXD/LXC...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq lxd lxc lxc-template debootstrap bridge-utils dnsmasq-base iptables
    
    # Initialize LXD
    lxd init --auto 2>/dev/null || true
    
    # Create default bridge
    lxc network create lxdbr0 ipv4.address=10.0.0.1/24 ipv4.nat=true ipv6.address=none 2>/dev/null || true
    
    systemctl enable lxd 2>/dev/null || true
    systemctl start lxd 2>/dev/null || true
    
    echo -e "${GREEN}[+] LXD installed and initialized${NC}"
}

install_lxd

# Install Python dependencies
install_python_deps() {
    echo -e "${YELLOW}[*] Installing Python dependencies...${NC}"
    pip3 install --break-system-packages discord.py pyyaml requests 2>/dev/null || \
    pip3 install discord.py pyyaml requests --break-system-packages
    
    echo -e "${GREEN}[+] Python dependencies installed${NC}"
}

install_python_deps

# Create bot directory
mkdir -p /opt/discord_lxc_bot/{cogs,utils,config}
mkdir -p /var/log/discord_lxc_bot
mkdir -p /etc/discord_lxc_bot

# ============================================
# LXD MANAGER CLASS
# ============================================

cat > /opt/discord_lxc_bot/utils/lxd_manager.py << 'LXDMANAGER'
#!/usr/bin/env python3
"""LXD Manager - Core container operations for Discord Bot"""
import subprocess
import json
import os
import time
import yaml
from datetime import datetime

class LXDManager:
    def __init__(self):
        self.ensure_lxd_ready()
    
    def ensure_lxd_ready(self):
        """Ensure LXD daemon is running"""
        try:
            result = subprocess.run(['lxc', 'list', '--mode', 'json'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                subprocess.run(['lxd', 'start'], capture_output=True, timeout=5)
                time.sleep(2)
        except Exception:
            pass
    
    def list_containers(self):
        """List all LXD containers"""
        try:
            result = subprocess.run(['lxc', 'list', '--mode', 'json'], 
                                  capture_output=True, text=True, timeout=15)
            if result.returncode == 0 and result.stdout.strip():
                return json.loads(result.stdout)
        except Exception as e:
            print(f"Error listing containers: {e}")
        return []
    
    def get_container_info(self, name):
        """Get detailed container information"""
        try:
            result = subprocess.run(['lxc', 'info', name, '--format', 'json'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                return json.loads(result.stdout)
        except Exception as e:
            print(f"Error getting container info: {e}")
        return None
    
    def start_container(self, name):
        """Start a container"""
        try:
            result = subprocess.run(['lxc', 'start', name], 
                                  capture_output=True, text=True, timeout=30)
            return result.returncode == 0, result.stdout, result.stderr
        except Exception as e:
            return False, "", str(e)
    
    def stop_container(self, name, timeout=30):
        """Stop a container"""
        try:
            result = subprocess.run(['lxc', 'stop', name, '--timeout', str(timeout)], 
                                  capture_output=True, text=True, timeout=35)
            return result.returncode == 0, result.stdout, result.stderr
        except Exception as e:
            return False, "", str(e)
    
    def restart_container(self, name):
        """Restart a container"""
        success_stop, _, _ = self.stop_container(name, timeout=10)
        if success_stop:
            success_start, _, _ = self.start_container(name)
            return success_start
        return False
    
    def delete_container(self, name, remove_storage=False):
        """Delete a container"""
        flag = '--remove-storage' if remove_storage else ''
        try:
            result = subprocess.run(['lxc', 'delete', name, flag], 
                                  capture_output=True, text=True, timeout=30)
            return result.returncode == 0
        except Exception:
            return False
    
    def execute_in_container(self, name, command, timeout=30):
        """Execute command inside container"""
        try:
            result = subprocess.run(['lxc', 'exec', name, '--'] + command.split(), 
                                  capture_output=True, text=True, timeout=timeout)
            return result.returncode, result.stdout, result.stderr
        except Exception as e:
            return -1, "", str(e)
    
    def create_container(self, name, image='ubuntu', release='22.04', 
                         architecture='amd64', profile='default', 
                         resources=None):
        """Create a new container"""
        try:
            # Check if container already exists
            containers = self.list_containers()
            container_names = [c.get('name') for c in containers if c.get('status')]
            
            if name in container_names:
                return False, f"Container {name} already exists", ""
            
            # Create container command
            if image.startswith('~') or '/' in image:
                cmd = ['lxc', 'launch', image, name]
            else:
                cmd = ['lxc', 'launch', f'{image}:{release}/{architecture}', name]
            
            # Add profile if specified
            if profile and profile != 'default':
                cmd.extend(['--profile', profile])
            
            # Add resources if specified
            if resources:
                for res_key, res_val in resources.items():
                    cmd.extend(['--', f'{res_key}={res_val}'])
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                time.sleep(3)
                return True, f"Container {name} created successfully", ""
            else:
                return False, "", result.stderr
                
        except Exception as e:
            return False, "", str(e)
    
    def get_container_status(self, name):
        """Get container status"""
        try:
            result = subprocess.run(['lxc', 'list', '--columns', 'name,status', '--filter', name], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                lines = result.stdout.strip().split('\n')
                if len(lines) > 1:
                    parts = lines[1].split()
                    if len(parts) >= 2:
                        return parts[1]
        except Exception:
            pass
        return "unknown"
    
    def get_system_resources(self):
        """Get system resource usage"""
        resources = {}
        
        # CPU usage
        try:
            cpu_result = subprocess.run(['top', '-bn1'], capture_output=True, text=True, timeout=5)
            cpu_line = cpu_result.stdout.split('\n')[1] if cpu_result.stdout else ""
            if cpu_line:
                cpu_parts = cpu_line.split()
                if len(cpu_parts) > 4:
                    resources['cpu_usage'] = cpu_parts[4]
                else:
                    resources['cpu_usage'] = "0%"
            else:
                resources['cpu_usage'] = "0%"
        except:
            resources['cpu_usage'] = "0%"
        
        # Memory usage
        try:
            mem_result = subprocess.run(['free', '-m'], capture_output=True, text=True, timeout=5)
            mem_parts = mem_result.stdout.split('\n')[1].split() if mem_result.stdout else []
            if len(mem_parts) >= 2:
                mem_total = mem_parts[1]
                mem_used = mem_parts[2]
                mem_percent = round(int(mem_used) * 100 / int(mem_total)) if mem_total.isdigit() else "0"
                resources['memory_usage'] = f"{mem_percent}%"
                resources['memory_total'] = f"{int(mem_total) // 1024}GB"
                resources['memory_used'] = f"{int(mem_used) // 1024}GB"
            else:
                resources['memory_usage'] = "0%"
        except:
            resources['memory_usage'] = "0%"
        
        # Disk usage
        try:
            disk_result = subprocess.run(['df', '/'], capture_output=True, text=True, timeout=5)
            disk_parts = disk_result.stdout.split('\n')[1].split() if disk_result.stdout else []
            if len(disk_parts) >= 5:
                resources['disk_usage'] = disk_parts[4]
            else:
                resources['disk_usage'] = "0%"
        except:
            resources['disk_usage'] = "0%"
        
        return resources
    
    def list_images(self):
        """List available LXD images"""
        try:
            result = subprocess.run(['lxc', 'image', 'list', '--format', 'json'], 
                                  capture_output=True, text=True, timeout=15)
            if result.returncode == 0:
                return json.loads(result.stdout)
        except:
            pass
        return []
    
    def create_snapshot(self, name, snapshot_name=None):
        """Create container snapshot"""
        if not snapshot_name:
            snapshot_name = f"auto-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        
        try:
            result = subprocess.run(['lxc', 'snapshot', 'create', name, snapshot_name], 
                                  capture_output=True, text=True, timeout=30)
            return result.returncode == 0, snapshot_name
        except Exception:
            return False, snapshot_name
    
    def restore_snapshot(self, name, snapshot_name):
        """Restore container snapshot"""
        try:
            result = subprocess.run(['lxc', 'restore', name, snapshot_name], 
                                  capture_output=True, text=True, timeout=30)
            return result.returncode == 0
        except Exception:
            return False
    
    def list_snapshots(self, name):
        """List container snapshots"""
        try:
            result = subprocess.run(['lxc', 'snapshot', 'list', name], 
                                  capture_output=True, text=True, timeout=15)
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                snapshots = []
                for line in lines[2:]:  # Skip header lines
                    if line.strip():
                        parts = line.split()
                        if len(parts) >= 1:
                            snapshots.append(parts[0])
                return snapshots
        except:
            pass
        return []
    
    def copy_container(self, source, destination):
        """Copy container to new name"""
        try:
            result = subprocess.run(['lxc', 'copy', source, destination], 
                                  capture_output=True, text=True, timeout=60)
            return result.returncode == 0
        except Exception:
            return False
    
    def migrate_container(self, name, target_host):
        """Migrate container to another host"""
        try:
            result = subprocess.run(['lxc', 'move', name, f"{target_host}:{name}"], 
                                  capture_output=True, text=True, timeout=120)
            return result.returncode == 0
        except Exception:
            return False

LXDMANAGER
chmod +x /opt/discord_lxc_bot/utils/lxd_manager.py
echo -e "${GREEN}[+] LXD Manager created${NC}"

# ============================================
# DISCORD BOT MAIN FILE
# ============================================

cat > /opt/discord_lxc_bot/bot.py << 'DISCORDBOT'
#!/usr/bin/env python3
"""Discord LXC/LXD VPS Bot - Main Bot File"""
import discord
from discord.ext import commands
import os
import json
import time
from datetime import datetime
import sys
sys.path.insert(0, '/opt/discord_lxc_bot/utils')
from lxd_manager import LXDManager

# Bot configuration
intents = discord.Intents.default()
intents.message_content = True
intents.reactions = True
intents.members = True

bot = commands.Bot(command_prefix='!', intents=intents)
manager = LXDManager()

# Bot configuration
BOT_CONFIG = {
    'admin_roles': ['LXD Admin', 'Admin', 'Administrator'],
    'bot_color': 0x00ff00,
    'max_output_length': 2000
}

def has_admin_role(ctx):
    """Check if user has admin role"""
    if not ctx.author.roles:
        return False
    user_roles = [role.name for role in ctx.author.roles]
    return any(role in user_roles for role in BOT_CONFIG['admin_roles'])

def format_container_info(container):
    """Format container information for Discord embed"""
    name = container.get('name', 'unknown')
    status = container.get('status', 'unknown')
    state = container.get('state', 'stopped')
    
    # Get IP addresses
    ips = []
    devices = container.get('devices', {})
    if 'eth0' in devices:
        addresses = devices['eth0'].get('addresses', [])
        for addr in addresses:
            if addr.get('type') == 'physical':
                ips.append(addr.get('address', ''))
    
    ip_str = ', '.join(ips[:2]) if ips else 'No IP'
    
    # Get resources
    cpu_usage = container.get('cpu', {}).get('usage', {}).get('total', 0) / 1e9
    memory_usage = container.get('memory', {}).get('usage', {}).get('total', 0) / 1024 / 1024
    
    # Status emoji
    status_emoji = "🟢" if state == "Running" else "🔴" if state == "Stopped" else "🟡"
    
    embed = discord.Embed(
        title=f"{status_emoji} {name}",
        color=0x00ff00 if state == "Running" else 0xff0000
    )
    embed.add_field(name="Status", value=f"`{status}`", inline=True)
    embed.add_field(name="State", value=f"`{state}`", inline=True)
    embed.add_field(name="IP Address", value=f"`{ip_str}`", inline=True)
    embed.add_field(name="CPU Usage", value=f"`{cpu_usage:.2f}s`", inline=True)
    embed.add_field(name="Memory Usage", value=f"`{memory_usage:.2f}MB`", inline=True)
    
    return embed

@bot.event
async def on_ready():
    print(f'🤖 Logged in as {bot.user.name} (ID: {bot.user.id})')
    print(f'📊 Connected to {len(bot.guilds)} guild(s)')
    await bot.change_presence(
        activity=discord.Game(name="!help for LXD commands"),
        status=discord.Status.online
    )

@bot.slash_command(name="lxd-status", description="Show LXD system status")
async def lxd_status(ctx):
    """Show system and container status"""
    if not has_admin_role(ctx):
        embed = discord.Embed(
            title="❌ Access Denied",
            description="You need the Admin role to use this command.",
            color=discord.Color.red()
        )
        await ctx.respond(embed=embed)
        return
    
    containers = manager.list_containers()
    resources = manager.get_system_resources()
    
    running = sum(1 for c in containers if c.get('state') == 'Running')
    total = len(containers)
    
    embed = discord.Embed(
        title="📊 LXD System Status",
        color=discord.Color.blue()
    )
    embed.add_field(name="🔥 CPU Usage", value=f"`{resources['cpu_usage']}`", inline=True)
    embed.add_field(name="💾 Memory Usage", value=f"`{resources['memory_usage']}`", inline=True)
    embed.add_field(name="💿 Disk Usage", value=f"`{resources['disk_usage']}`", inline=True)
    embed.add_field(name="🖥️ Containers", value=f"`{running}/{total}` running", inline=True)
    embed.set_footer(text=f"LXD Bot • {datetime.now().strftime('%H:%M:%S')}")
    
    await ctx.respond(embed=embed)

@bot.slash_command(name="lxd-list", description="List all LXD containers")
async def lxd_list(ctx):
    """List all containers"""
    if not has_admin_role(ctx):
        embed = discord.Embed(
            title="❌ Access Denied",
            description="You need the Admin role to use this command.",
            color=discord.Color.red()
        )
        await ctx.respond(embed=embed)
        return
    
    containers = manager.list_containers()
    
    if not containers:
        embed = discord.Embed(
            title="📦 Container List",
            description="📭 No LXD containers found.",
            color=discord.Color.blue()
        )
        await ctx.respond(embed=embed)
        return
    
    embed = discord.Embed(
        title=f"📦 Container List ({len(containers)} total)",
        color=discord.Color.blue()
    )
    
    for i, container in enumerate(containers, 1):
        name = container.get('name', 'unknown')
        status = container.get('status', 'unknown')
        state = container.get('state', 'stopped')
        
        emoji = "🟢" if state == "Running" else "🔴" if state == "Stopped" else "🟡"
        
        embed.add_field(
            name=f"{emoji} {name}",
            value=f"Status: `{status}`",
            inline=False
        )
    
    embed.set_footer(text=f"Total: {len(containers)} containers")
    await ctx.respond(embed=embed)

@bot.slash_command(name="lxd-start", description="Start an LXD container")
async def lxd_start(ctx, container_name: str):
    """Start a container"""
    if not has_admin_role(ctx):
        embed = discord.Embed(
            title="❌ Access Denied",
            description="You need the Admin role to use this command.",
            color=discord.Color.red()
        )
        await ctx.respond(embed=embed)
        return
    
    # Check if container exists
    containers = manager.list_containers()
    container_names = [c.get('name') for c in containers]
    
    if container_name not in container_names:
        embed = discord.Embed(
            title="❌ Container Not Found",
            description=f"Container `{container_name}` not found!",
            color=discord.Color.red()
        )
        await ctx.respond(embed=embed)
        return
    
    success, stdout, stderr = manager.start_container(container_name)
    
    if success:
        embed = discord.Embed(
            title="▶️ Container Started",
            description=f"Container `{container_name}` started successfully!",
            color=discord.Color.green()
        )
        await ctx.respond(embed=embed)
    else:
        embed = discord.Embed(
            title="❌ Failed to Start",
            description=f"Error starting container:\n