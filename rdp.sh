
#!/usr/bin/env bash
set -e

echo "================================"
echo "     FreeRoot RDP Installer"
echo "================================"

mkdir -p "$HOME/workspace"
cd "$HOME/workspace"

# Install wget
if ! command -v wget >/dev/null 2>&1; then
    nix-env -iA nixpkgs.wget
    export PATH="$HOME/.nix-profile/bin:$PATH"
fi

# Download FreeRoot
rm -rf freeroot
git clone https://github.com/foxytouxxx/freeroot.git
cd freeroot

# Install FreeRoot
chmod +x root.sh
echo "yes" | bash root.sh

PROOT="./usr/local/bin/proot"

if [ ! -x "$PROOT" ]; then
    echo "ERROR: PRoot was not installed."
    exit 1
fi

# Install desktop and VNC packages
"$PROOT" --rootfs="." -0 -w /root \
-b /dev -b /sys -b /proc -b /etc/resolv.conf \
/bin/bash -c '
apt-get update
apt-get install -y fluxbox xterm dbus-x11 \
websockify tigervnc-standalone-server novnc

mkdir -p /root/.vnc

cat > /root/.vnc/xstartup <<EOF
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
dbus-launch --exit-with-session &
fluxbox &
EOF

chmod +x /root/.vnc/xstartup
'

# Ask for VNC password
read -rsp "Enter VNC password: " VNC_PASSWORD
echo

if [ "${#VNC_PASSWORD}" -lt 6 ]; then
    echo "VNC password must be at least 6 characters."
    exit 1
fi

# Start VNC and noVNC
"$PROOT" --rootfs="." -0 -w /root \
-b /dev -b /sys -b /proc -b /etc/resolv.conf \
/bin/bash -c "
mkdir -p /root/.vnc
vncserver -kill :1 2>/dev/null || true
printf '%s\n%s\nn\n' '$VNC_PASSWORD' '$VNC_PASSWORD' | \
vncserver :1 -geometry 1280x720 -depth 16

nohup websockify --web=/usr/share/novnc/ \
3000 127.0.0.1:5901 >/tmp/novnc.log 2>&1 &
"

echo "================================"
echo "       INSTALLATION DONE"
echo "================================"
echo "noVNC port: 3000"
echo "VNC port: 5901"
echo "Open your forwarded port 3000 in the browser."
