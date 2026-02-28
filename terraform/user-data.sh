#!/bin/bash
set -euo pipefail

LOG="/var/log/setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Server Setup - $(date) ==="

# System updates
apt-get update && apt-get upgrade -y
apt-get install -y curl git nginx

# Swap 4GB
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

echo "=== Setup Complete - $(date) ==="
echo "Node: $(node --version)"
echo ""
echo "Conectate con: ssh -i key.pem ubuntu@<IP>"
echo "Luego instala OpenClaw manualmente:"
echo "  sudo npm install -g openclaw@latest @anthropic-ai/claude-code"
echo "  claude login"
echo "  openclaw gateway install --port 18789"
