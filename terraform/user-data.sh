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

# [5/6] Create systemd service (no config = setup wizard on first visit)
echo "[5/6] Creating systemd service..."
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

# [6/6] Configure Nginx
echo "[6/6] Configuring Nginx..."
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
echo "Abre en el navegador para crear tu cuenta de administrador"
echo ""
echo "Para HTTPS (despues de configurar DNS):"
echo "  sudo certbot --nginx -d mayra-content.comuhack.com --non-interactive --agree-tos -m tu@email.com"
