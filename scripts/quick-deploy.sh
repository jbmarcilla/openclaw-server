#!/bin/bash
# =============================================================================
# Quick Deploy: Install/update OpenClaw on an EC2 instance via SSH
# =============================================================================
# Installs everything from scratch or updates an existing installation.
# After running, only "claude login" is needed on first setup.
#
# Usage:
#   ./scripts/quick-deploy.sh <EC2_IP> <SSH_KEY_PATH>
#
# Example:
#   ./scripts/quick-deploy.sh 44.252.138.103 ./openclaw-server-key.pem
# =============================================================================
set -euo pipefail

EC2_IP="${1:?Usage: $0 <EC2_IP> <SSH_KEY_PATH>}"
SSH_KEY="${2:?Usage: $0 <EC2_IP> <SSH_KEY_PATH>}"

echo "=== Quick Deploy OpenClaw to $EC2_IP ==="

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "ubuntu@$EC2_IP" << REMOTE
set -euo pipefail

echo "[1/8] Updating system..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

echo "[2/8] Installing dependencies..."
sudo apt-get install -y -qq curl git nginx apache2-utils python3

echo "[3/8] Creating swap (4GB)..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

echo "[4/8] Installing Node.js 22..."
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
    sudo apt-get install -y nodejs
fi
echo "  Node: \$(node --version)"

echo "[5/8] Installing OpenClaw + Claude Max Proxy + Claude Code CLI..."
sudo OPENCLAW_NO_PROMPT=1 npm install -g openclaw@latest claude-max-api-proxy @anthropic-ai/claude-code
echo "  OpenClaw: installed"
echo "  Claude CLI: \$(claude --version 2>/dev/null || echo 'installed')"

echo "[6/8] Configuring services..."
CLAUDE_MAX_BIN=\$(which claude-max-api)

# Claude Max Proxy service
sudo tee /etc/systemd/system/claude-max-proxy.service > /dev/null << SYSTEMD
[Unit]
Description=Claude Max API Proxy (localhost:3456)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=\${CLAUDE_MAX_BIN}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=claude-max-proxy

[Install]
WantedBy=multi-user.target
SYSTEMD

sudo systemctl daemon-reload
sudo systemctl enable claude-max-proxy.service

# Enable user lingering
sudo loginctl enable-linger ubuntu

echo "[7/8] Configuring OpenClaw..."
mkdir -p ~/.openclaw
chmod 700 ~/.openclaw

ELASTIC_IP="${EC2_IP}"
cat > ~/.openclaw/openclaw.json << CONFIG
{
  "gateway": {
    "port": 18789,
    "bind": "loopback",
    "mode": "local",
    "controlUi": {
      "allowedOrigins": ["http://\${ELASTIC_IP}", "http://\${ELASTIC_IP}:18789"]
    }
  },
  "models": {
    "providers": {
      "claude-max": {
        "baseUrl": "http://localhost:3456/v1",
        "apiKey": "claude-max-local",
        "api": "openai-completions",
        "models": [
          {"id": "claude-opus-4", "name": "Claude Opus 4 (Max Sub)", "contextWindow": 200000},
          {"id": "claude-sonnet-4", "name": "Claude Sonnet 4 (Max Sub)", "contextWindow": 200000}
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {"primary": "claude-max/claude-sonnet-4"}
    }
  }
}
CONFIG
chmod 600 ~/.openclaw/openclaw.json

# Install gateway as user service
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus
export XDG_RUNTIME_DIR=/run/user/\$(id -u)
openclaw gateway install --port 18789 2>&1 || echo "[!] Gateway install may need claude login first"

echo "[8/8] Configuring nginx (port 80 → admin panel)..."
sudo tee /etc/nginx/sites-available/openclaw > /dev/null << 'NGINX'
map \\\$http_upgrade \\\$connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection \\\$connection_upgrade;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
NGINX

sudo ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/openclaw
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx
sudo systemctl enable nginx

echo ""
echo "============================================"
echo "  Installation Complete!"
echo "============================================"
echo ""
echo "  Open: http://${EC2_IP}"
echo "  Create your account on first visit (setup wizard)"
echo ""
echo "  NEXT STEPS (from the web terminal):"
echo "    1. claude login"
echo "    2. Follow the guide in the admin panel"
echo "============================================"
REMOTE

echo ""
echo "=== Deploy Complete! ==="
echo "SSH: ssh -i $SSH_KEY ubuntu@$EC2_IP"
echo "URL: http://$EC2_IP (create account on first visit)"
