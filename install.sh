#!/bin/bash
# OpenClaw Admin Panel - Instalador
# Uso: curl -fsSL https://raw.githubusercontent.com/jbmarcilla/openclaw-server/master/install.sh | bash
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "  ${CYAN}[*]${NC} $1"; }
ok()    { echo -e "  ${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "  ${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo -e "  ${CYAN}OpenClaw Admin - Instalador${NC}"
echo ""

# --- Detect OS ---
OS=""
DISTRO=""

detect_os() {
  case "$(uname -s)" in
    Linux)
      OS="linux"
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$ID"
      fi
      ;;
    Darwin)
      OS="macos"
      DISTRO="macos"
      ;;
    *)
      fail "Sistema operativo no soportado: $(uname -s). Usa Ubuntu/Debian o macOS."
      ;;
  esac

  case "$DISTRO" in
    ubuntu|debian) ok "Sistema operativo: $DISTRO $(uname -m)" ;;
    macos) ok "Sistema operativo: macOS $(sw_vers -productVersion) $(uname -m)" ;;
    *)
      if [ "$OS" = "linux" ]; then
        warn "Distribucion '$DISTRO' no probada. Se intentara instalar como Debian/Ubuntu."
      fi
      ;;
  esac
}

# --- Check/Install Node.js ---
install_node() {
  if command -v node &>/dev/null; then
    local node_version
    node_version=$(node --version)
    ok "Node.js ya instalado ($node_version)"
    return
  fi

  info "Instalando Node.js 22..."
  if [ "$OS" = "linux" ]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash - >/dev/null 2>&1
    sudo apt-get install -y nodejs >/dev/null 2>&1
  elif [ "$OS" = "macos" ]; then
    if ! command -v brew &>/dev/null; then
      fail "Homebrew no encontrado. Instala Homebrew primero: https://brew.sh"
    fi
    brew install node@22 >/dev/null 2>&1
    brew link --overwrite node@22 >/dev/null 2>&1 || true
  fi
  ok "Node.js instalado ($(node --version))"
}

# --- Check/Install Nginx ---
install_nginx() {
  if command -v nginx &>/dev/null; then
    ok "Nginx ya instalado"
    return
  fi

  info "Instalando Nginx..."
  if [ "$OS" = "linux" ]; then
    sudo apt-get install -y nginx >/dev/null 2>&1
  elif [ "$OS" = "macos" ]; then
    brew install nginx >/dev/null 2>&1
  fi
  ok "Nginx instalado"
}

# --- Create swap (Linux only) ---
create_swap() {
  if [ "$OS" != "linux" ]; then return; fi
  if [ -f /swapfile ]; then return; fi

  local mem_mb
  mem_mb=$(free -m | awk '/Mem:/ {print $2}')
  if [ "$mem_mb" -lt 3000 ]; then
    info "Creando swap de 4GB (RAM: ${mem_mb}MB)..."
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile >/dev/null 2>&1
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
    ok "Swap creado"
  fi
}

# --- Install system dependencies (Linux) ---
install_system_deps() {
  if [ "$OS" = "linux" ]; then
    info "Instalando dependencias del sistema..."
    sudo apt-get update >/dev/null 2>&1
    sudo apt-get install -y curl git build-essential >/dev/null 2>&1
    ok "Dependencias instaladas"
  fi
}

# --- Clone/update repo ---
install_app() {
  local APP_DIR

  if [ "$OS" = "linux" ]; then
    APP_DIR="/opt/openclaw-admin"
  else
    APP_DIR="$HOME/openclaw-admin"
  fi

  if [ -d "$APP_DIR" ]; then
    info "Actualizando OpenClaw Admin..."
    if [ "$OS" = "linux" ]; then
      sudo git -C "$APP_DIR" pull --quiet
    else
      git -C "$APP_DIR" pull --quiet
    fi
    ok "Admin Panel actualizado"
  else
    info "Descargando OpenClaw Admin..."
    if [ "$OS" = "linux" ]; then
      sudo git clone --quiet https://github.com/jbmarcilla/openclaw-server.git "$APP_DIR"
    else
      git clone --quiet https://github.com/jbmarcilla/openclaw-server.git "$APP_DIR"
    fi
    ok "Admin Panel descargado"
  fi

  info "Instalando dependencias de Node.js..."
  if [ "$OS" = "linux" ]; then
    cd "$APP_DIR/admin-panel" && sudo npm install --production --silent 2>/dev/null
  else
    cd "$APP_DIR/admin-panel" && npm install --production --silent 2>/dev/null
  fi
  ok "Admin Panel instalado"

  echo "$APP_DIR"
}

# --- Configure Nginx ---
configure_nginx() {
  local APP_DIR="$1"

  info "Configurando Nginx..."

  local NGINX_CONF='map $http_upgrade $connection_upgrade {
    default upgrade;
    '"''"' close;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}'

  if [ "$OS" = "linux" ]; then
    echo "$NGINX_CONF" | sudo tee /etc/nginx/sites-available/openclaw-admin >/dev/null
    sudo ln -sf /etc/nginx/sites-available/openclaw-admin /etc/nginx/sites-enabled/openclaw-admin
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx -t >/dev/null 2>&1
    sudo systemctl restart nginx
    sudo systemctl enable nginx >/dev/null 2>&1
  elif [ "$OS" = "macos" ]; then
    local nginx_conf_dir
    nginx_conf_dir="$(brew --prefix)/etc/nginx"
    # Backup original config
    if [ ! -f "$nginx_conf_dir/nginx.conf.backup" ]; then
      cp "$nginx_conf_dir/nginx.conf" "$nginx_conf_dir/nginx.conf.backup" 2>/dev/null || true
    fi
    mkdir -p "$nginx_conf_dir/servers"
    echo "$NGINX_CONF" > "$nginx_conf_dir/servers/openclaw-admin.conf"
    # Ensure nginx.conf includes servers/ directory
    if ! grep -q "include servers" "$nginx_conf_dir/nginx.conf" 2>/dev/null; then
      # Add include directive before closing brace
      sed -i '' '$i\
    include servers/*.conf;
' "$nginx_conf_dir/nginx.conf"
    fi
    brew services restart nginx >/dev/null 2>&1
  fi

  ok "Nginx configurado"
}

# --- Create service ---
create_service() {
  local APP_DIR="$1"

  info "Creando servicio..."

  if [ "$OS" = "linux" ]; then
    local CURRENT_USER
    CURRENT_USER=$(logname 2>/dev/null || whoami)

    sudo tee /etc/systemd/system/openclaw-admin.service >/dev/null << SYSTEMD
[Unit]
Description=OpenClaw Admin Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$APP_DIR/admin-panel
ExecStart=$(which node) server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-admin

[Install]
WantedBy=multi-user.target
SYSTEMD

    sudo systemctl daemon-reload
    sudo systemctl enable openclaw-admin >/dev/null 2>&1
    sudo systemctl restart openclaw-admin

    # Enable user lingering for OpenClaw user services later
    loginctl enable-linger "$CURRENT_USER" 2>/dev/null || true

  elif [ "$OS" = "macos" ]; then
    local PLIST="$HOME/Library/LaunchAgents/com.openclaw.admin.plist"
    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.admin</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which node)</string>
        <string>$APP_DIR/admin-panel/server.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$APP_DIR/admin-panel</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/openclaw-admin.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/openclaw-admin.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>NODE_ENV</key>
        <string>production</string>
    </dict>
</dict>
</plist>
PLIST

    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
  fi

  ok "Servicio creado y corriendo"
}

# --- Pre-configure OpenClaw gateway settings ---
preconfigure_openclaw() {
  local user_home
  if [ "$OS" = "linux" ]; then
    user_home=$(eval echo "~$(logname 2>/dev/null || whoami)")
  else
    user_home="$HOME"
  fi

  local oc_dir="$user_home/.openclaw"
  local oc_config="$oc_dir/openclaw.json"

  if [ ! -f "$oc_config" ]; then
    if [ "$OS" = "linux" ]; then
      local CURRENT_USER
      CURRENT_USER=$(logname 2>/dev/null || whoami)
      sudo -u "$CURRENT_USER" mkdir -p "$oc_dir"
      sudo -u "$CURRENT_USER" tee "$oc_config" >/dev/null << 'OCCONFIG'
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "loopback"
  }
}
OCCONFIG
    else
      mkdir -p "$oc_dir"
      cat > "$oc_config" << 'OCCONFIG'
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "loopback"
  }
}
OCCONFIG
    fi
  fi
}

# --- Detect public IP ---
get_public_ip() {
  local ip=""
  ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) \
    || ip=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null) \
    || ip=""
  echo "$ip"
}

# ===== Main =====

detect_os

if [ "$OS" = "linux" ]; then
  install_system_deps
  create_swap
fi

install_node
install_nginx

APP_DIR=$(install_app)
configure_nginx "$APP_DIR"
create_service "$APP_DIR"
preconfigure_openclaw

PUBLIC_IP=$(get_public_ip)

echo ""
echo -e "  ${GREEN}==========================================${NC}"
echo -e "  ${GREEN}  LISTO!${NC}"
echo ""
if [ -n "$PUBLIC_IP" ]; then
echo -e "  Tu IP publica: ${CYAN}${PUBLIC_IP}${NC}"
echo ""
echo -e "  Abre en tu navegador:"
echo -e "  ${CYAN}http://${PUBLIC_IP}${NC}"
else
echo -e "  Abre en tu navegador:"
echo -e "  ${CYAN}http://localhost${NC}"
fi
echo ""
echo -e "  Crea tu cuenta de admin y sigue"
echo -e "  la guia para configurar HTTPS y OpenClaw."
echo -e "  ${GREEN}==========================================${NC}"
echo ""
