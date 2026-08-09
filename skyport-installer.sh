#!/bin/bash

set -e

echo "======================================"
echo "       SKYPORT PANEL INSTALLER"
echo "======================================"

sudo -i

apt update -y
apt install -y git curl nodejs npm

cd /root

git clone https://github.com/skyport-team/panel.git

cd panel

npm install
npm i

npm run createUser

node .
