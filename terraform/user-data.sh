#!/bin/bash
set -euo pipefail

LOG="/var/log/admin-panel-setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Admin Panel Setup - $(date) ==="

# [1/7] System updates + packages
echo "[1/7] Installing system packages..."
apt-get update && apt-get upgrade -y
apt-get install -y curl git nginx certbot python3-certbot-nginx \
  build-essential python3

# [2/7] Swap 4GB
echo "[2/7] Creating swap..."
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# [3/7] Node.js 22
echo "[3/7] Installing Node.js 22..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# [4/7] Clone repo and install admin panel
echo "[4/7] Cloning repo and installing admin panel..."
APP_DIR="/opt/openclaw-admin"

if [ -d "$APP_DIR" ]; then
  cd "$APP_DIR" && git pull
else
  git clone https://github.com/jbmarcilla/openclaw-server.git "$APP_DIR"
fi

cd "$APP_DIR/admin-panel"
npm install --production

# [5/7] Create config with default credentials
echo "[5/7] Creating config..."
sudo -u ubuntu mkdir -p /home/ubuntu/.openclaw-admin

RANDOM_SECRET=$(openssl rand -hex 32)
BCRYPT_HASH=$(cd "$APP_DIR/admin-panel" && node -e "
  var bcrypt = require('bcryptjs');
  console.log(bcrypt.hashSync('OpenClaw2026!', 10));
")

cat > /home/ubuntu/.openclaw-admin/config.json << EOF
{
  "port": 3000,
  "sessionSecret": "${RANDOM_SECRET}",
  "credentials": {
    "username": "admin",
    "passwordHash": "${BCRYPT_HASH}"
  },
  "openclawPort": 18789,
  "domain": "mayra-content.comuhack.com"
}
EOF
chown ubuntu:ubuntu /home/ubuntu/.openclaw-admin/config.json
chmod 600 /home/ubuntu/.openclaw-admin/config.json

# [6/7] Create systemd service
echo "[6/7] Creating systemd service..."
cat > /etc/systemd/system/openclaw-admin.service << 'SYSTEMD'
[Unit]
Description=OpenClaw Admin Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/openclaw-admin/admin-panel
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-admin

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable openclaw-admin
systemctl start openclaw-admin

# [7/7] Configure Nginx
echo "[7/7] Configuring Nginx..."
cat > /etc/nginx/sites-available/openclaw-admin << 'NGINX'
server {
    listen 80;
    server_name mayra-content.comuhack.com _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/openclaw-admin /etc/nginx/sites-enabled/openclaw-admin
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx
systemctl enable nginx

# Enable user lingering for ubuntu (needed for openclaw user services)
loginctl enable-linger ubuntu

echo ""
echo "=== Setup Complete - $(date) ==="
echo "Node: $(node --version)"
echo ""
echo "Admin panel: http://<ELASTIC_IP>"
echo "Login: admin / OpenClaw2026!"
echo ""
echo "Para HTTPS (despues de configurar DNS):"
echo "  sudo certbot --nginx -d mayra-content.comuhack.com --non-interactive --agree-tos -m tu@email.com"
