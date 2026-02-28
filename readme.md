# OpenClaw Server - Admin Panel

Panel web de administracion para desplegar y gestionar [OpenClaw](https://openclaw.ai) en AWS EC2. Incluye login, terminal web integrado y dashboard de OpenClaw.

## Arquitectura

```
         Internet
            |
  https://mayra-content.comuhack.com
            |
  +---------+----------+
  |  Nginx (80/443)    |  <- SSL via Let's Encrypt
  |  Reverse Proxy     |
  +---------+----------+
            | proxy_pass
  +---------+----------+
  |  Express.js Admin  |  <- systemd: openclaw-admin
  |  Panel (:3000)     |
  |                    |
  |  /login    -> Login page
  |  /         -> Dashboard (Terminal + OpenClaw tabs)
  |  /ws/terminal -> WebSocket terminal (bash)
  |  /openclaw/*  -> Proxy a OpenClaw Gateway
  +---------+----------+
            |
  +---------+----------+
  |  OpenClaw Gateway  |  <- localhost:18789
  |  (instalado via    |     (se instala desde el terminal web)
  |   terminal web)    |
  +--------------------+

  EC2 t2.small (Ubuntu 22.04, 2GB RAM)
```

## Estructura del Proyecto

```
openclaw-server/
├── admin-panel/                     # Panel web de administracion
│   ├── package.json                 # Dependencias Node.js
│   ├── config.js                    # Configuracion (credenciales, puertos)
│   ├── server.js                    # Express + WebSocket + auth + proxy
│   └── public/
│       ├── login.html               # Pagina de login
│       ├── dashboard.html           # Dashboard (terminal + OpenClaw)
│       ├── css/style.css            # Estilos (dark theme)
│       └── js/terminal.js           # Cliente xterm.js
├── terraform/
│   ├── main.tf                      # EC2 + Elastic IP + Security Group
│   ├── variables.tf                 # Variables (region, instancia, dominio)
│   ├── outputs.tf                   # IP, URL, instrucciones post-deploy
│   └── user-data.sh                 # Script de instalacion automatica
├── .github/workflows/
│   └── deploy.yml                   # CI/CD: deploy al push a main
├── .env.example                     # Variables de entorno requeridas
└── readme.md
```

## Requisitos

- **Node.js** >= 18 ([descargar](https://nodejs.org/))
- **Cuenta AWS** con usuario IAM (permisos EC2, EIP, Security Groups) — solo para deploy en produccion
- **Terraform** >= 1.0 ([descargar](https://developer.hashicorp.com/terraform/downloads)) — solo para deploy en produccion
- **Dominio** con acceso a DNS (para HTTPS con Let's Encrypt) — opcional

## Desarrollo Local

Puedes correr el admin panel localmente para desarrollo o pruebas:

```bash
# 1. Clonar el repo
git clone https://github.com/jbmarcilla/openclaw-server.git
cd openclaw-server

# 2. Instalar dependencias
cd admin-panel
npm install

# 3. Ejecutar
npm start
```

Abre http://localhost:3000 en tu navegador.

| Credencial | Valor |
|------------|-------|
| **Usuario** | `admin` |
| **Password** | `OpenClaw2026!` |

El terminal web abrira una sesion bash en tu maquina local. La pestana de OpenClaw mostrara "no esta corriendo" a menos que tengas OpenClaw Gateway en el puerto 18789.

### Variables de entorno opcionales

| Variable | Default | Descripcion |
|----------|---------|-------------|
| `ADMIN_PORT` | `3000` | Puerto del servidor |
| `SESSION_SECRET` | auto-generado | Secreto para sesiones |
| `OPENCLAW_PORT` | `18789` | Puerto del gateway OpenClaw |
| `ADMIN_DOMAIN` | `mayra-content.comuhack.com` | Dominio para SSL |

Ejemplo:

```bash
ADMIN_PORT=4000 npm start
```

## Despliegue en AWS (Produccion)

```bash
# 1. Clonar
git clone https://github.com/jbmarcilla/openclaw-server.git
cd openclaw-server

# 2. Configurar credenciales AWS
cp .env.example .env
# Editar .env con tus credenciales:
#   AWS_ACCESS_KEY_ID=tu-key
#   AWS_SECRET_ACCESS_KEY=tu-secret
#   AWS_REGION=us-west-2

# 3. Crear infraestructura
export $(grep -v '^#' .env | xargs)
cd terraform
terraform init
terraform apply -var="aws_region=$AWS_REGION"

# 4. Guardar clave SSH
terraform output -raw private_key > ../openclaw-server-key.pem
chmod 400 ../openclaw-server-key.pem

# 5. Ver IP y pasos siguientes
terraform output elastic_ip
terraform output post_deploy
```

Terraform crea automaticamente:

| Recurso | Detalle |
|---------|---------|
| EC2 (t2.small) | Ubuntu 22.04, 2GB RAM, 20GB disco |
| Elastic IP | IP publica fija |
| Security Group | Puertos 22 (SSH), 80 (HTTP), 443 (HTTPS) |
| SSH Key Pair | RSA 4096-bit, auto-generado |
| Admin Panel | Express.js + xterm.js en puerto 3000 |
| Nginx | Reverse proxy 80/443 -> 3000 |

## Post-Deploy

### 1. Acceder al Admin Panel

Esperar 3-5 minutos despues de `terraform apply`, luego abrir:

```
http://<ELASTIC_IP>
```

| Credencial | Valor |
|------------|-------|
| **Usuario** | `admin` |
| **Password** | `OpenClaw2026!` |

### 2. Instalar OpenClaw (desde el terminal web)

Una vez logueado, en la pestana **Terminal** ejecutar:

```bash
sudo npm install -g openclaw@latest @anthropic-ai/claude-code
claude login          # Seguir instrucciones (abrir link en navegador)
openclaw gateway install --port 18789
```

### 3. Verificar OpenClaw

Cambiar a la pestana **OpenClaw Dashboard** y hacer clic en **Actualizar Estado**. Deberia mostrar el dashboard de OpenClaw.

### 4. Habilitar HTTPS (opcional)

Agregar un registro DNS A apuntando al Elastic IP:

```
mayra-content.comuhack.com -> <ELASTIC_IP>
```

Luego, en el terminal web:

```bash
sudo certbot --nginx -d mayra-content.comuhack.com --non-interactive --agree-tos -m tu@email.com
```

Ahora acceder via `https://mayra-content.comuhack.com`.

## CI/CD con GitHub Actions

Cada push a `main` actualiza el servidor automaticamente.

### Configurar GitHub Secrets

En GitHub: **Settings > Secrets and variables > Actions > New repository secret**

| Secret | Descripcion | Como obtenerlo |
|--------|-------------|----------------|
| `EC2_HOST` | IP del servidor | `terraform output elastic_ip` |
| `EC2_SSH_KEY` | Clave privada SSH completa | `terraform output -raw private_key` |

## Comandos Utiles

```bash
# Estado del admin panel
sudo systemctl status openclaw-admin
sudo journalctl -u openclaw-admin -f

# Log de instalacion inicial
cat /var/log/admin-panel-setup.log

# SSH al servidor
ssh -i openclaw-server-key.pem ubuntu@<ELASTIC_IP>

# Terraform
cd terraform
terraform output              # Ver outputs
terraform output elastic_ip   # Solo la IP
terraform destroy             # Destruir todo
```

## Puertos

| Puerto | Servicio | Acceso |
|--------|----------|--------|
| 22 | SSH | Publico (clave SSH) |
| 80 | Nginx -> Admin Panel | Publico (redirige a 443 con HTTPS) |
| 443 | Nginx -> Admin Panel | Publico (SSL) |
| 3000 | Admin Panel (Express) | Solo localhost |
| 18789 | OpenClaw Gateway | Solo localhost (via proxy /openclaw/) |

## Costos Estimados (AWS)

| Recurso | Costo |
|---------|-------|
| EC2 t2.small (2GB RAM) | ~$17/mes |
| Elastic IP (en uso) | Gratis |
| EBS 20GB gp3 | ~$1.60/mes |
| **Total** | **~$19/mes** |
