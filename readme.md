# OpenClaw Server - EC2 Deployment

Infraestructura automatizada para desplegar [OpenClaw](https://openclaw.ai) en AWS EC2 con Terraform y GitHub Actions.

## Arquitectura

```
           Internet
              │
    http://<ELASTIC_IP>
              │
    ┌─────────┴──────────┐
    │   Nginx (port 80)  │  ← Basic Auth (admin/password)
    │   Reverse Proxy     │
    └─────────┬──────────┘
              │ proxy_pass
    ┌─────────┴──────────┐
    │  OpenClaw Gateway   │  ← localhost:18789 (user service)
    │  AI Agent Platform  │
    └─────────┬──────────┘
              │ API calls
    ┌─────────┴──────────┐
    │ Claude Max Proxy    │  ← localhost:3456 (system service)
    │ LLM API Provider    │
    └────────────────────┘

    AWS EC2 (t2.small, 2GB RAM)
    Ubuntu 22.04 LTS + Elastic IP
```

## Estructura del Proyecto

```
openclaw-server/
├── terraform/
│   ├── main.tf                   # EC2 + Elastic IP + Security Group + SSH Keys
│   ├── variables.tf              # Variables: region, tipo instancia
│   ├── outputs.tf                # IP, SSH command, URL del gateway
│   └── user-data.sh              # Script de instalacion automatica (todo incluido)
├── .github/workflows/
│   └── deploy.yml                # CI/CD: deploy automatico al push a main
├── scripts/
│   ├── quick-deploy.sh           # Deploy completo via SSH (sin Terraform)
│   └── entrypoint.sh             # Entrypoint Docker (opcional)
├── Dockerfile                    # Imagen Docker (opcional)
├── .env.example                  # Variables de entorno requeridas
└── readme.md
```

## Requisitos Previos

- **Cuenta AWS** con usuario IAM con permisos de administrador
- **Terraform** >= 1.0 ([descargar](https://developer.hashicorp.com/terraform/downloads))
- **Suscripcion Claude Max** (para Claude Max API Proxy)

## Despliegue (2 opciones)

### Opcion 1: Terraform (recomendado)

Crea toda la infraestructura desde cero con un solo comando.

```bash
# 1. Clonar
git clone https://github.com/tu-usuario/openclaw-server.git
cd openclaw-server

# 2. Configurar credenciales
cp .env.example .env
# Editar .env con tus credenciales AWS:
#   AWS_ACCESS_KEY_ID=tu-key
#   AWS_SECRET_ACCESS_KEY=tu-secret
#   AWS_REGION=us-west-2

# 3. Crear infraestructura
export $(grep -v '^#' .env | xargs)
cd terraform
terraform init
terraform apply -var="aws_region=$AWS_REGION"
# Escribir "yes" cuando pida confirmacion

# 4. Guardar clave SSH
terraform output -raw private_key > ../openclaw-server-key.pem
chmod 400 ../openclaw-server-key.pem

# 5. Ver IP asignada
terraform output elastic_ip
```

Terraform crea automaticamente:

| Recurso | Detalle |
|---------|---------|
| EC2 (t2.small) | Ubuntu 22.04, 2GB RAM, 20GB disco |
| Elastic IP | IP publica fija |
| Security Group | Puertos 22 (SSH), 80 (HTTP), 18789-18793 |
| SSH Key Pair | RSA 4096-bit, auto-generado |
| Software | Node.js 22, OpenClaw, Claude Max Proxy, Claude CLI, Nginx |
| Servicios | claude-max-proxy (systemd), openclaw-gateway (user service) |
| Nginx | Reverse proxy puerto 80 → 18789 con autenticacion |

### Opcion 2: Quick Deploy (sin Terraform)

Si ya tienes una instancia EC2 corriendo (creada manualmente):

```bash
chmod +x scripts/quick-deploy.sh
./scripts/quick-deploy.sh <EC2_IP> <SSH_KEY_PATH>
```

Ejemplo:

```bash
./scripts/quick-deploy.sh 44.252.138.103 ./openclaw-server-key.pem
```

Este script instala todo via SSH: Node.js, OpenClaw, Claude CLI, Nginx con auth.

## Post-Deploy (una sola vez)

Despues de que Terraform o quick-deploy terminen (~5 min), necesitas autenticar Claude:

```bash
# 1. Conectar al servidor
ssh -i openclaw-server-key.pem ubuntu@<ELASTIC_IP>

# 2. Autenticar Claude Code CLI
claude login
# Sigue las instrucciones (abre el link en tu navegador)

# 3. Iniciar servicios
sudo systemctl start claude-max-proxy
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user start openclaw-gateway

# 4. Verificar
sudo systemctl status claude-max-proxy    # debe estar "active (running)"
systemctl --user status openclaw-gateway  # debe estar "active (running)"

# 5. Abrir en el navegador
# http://<ELASTIC_IP>
# Usuario: admin
# Password: OpenClaw2026!
```

## Acceso al Dashboard

Una vez desplegado, abre en tu navegador:

```
http://<ELASTIC_IP>
```

| Credencial | Valor |
|------------|-------|
| **Usuario** | `admin` |
| **Password** | `OpenClaw2026!` |

Para cambiar la password:

```bash
ssh -i openclaw-server-key.pem ubuntu@<ELASTIC_IP>
sudo htpasswd -b /etc/nginx/.htpasswd admin TuNuevaPassword
sudo systemctl reload nginx
```

## Deploy Automatico con GitHub Actions

Cada push a `main` actualiza el servidor automaticamente.

### Configurar GitHub Secrets

Ve a tu repo en GitHub: **Settings > Secrets and variables > Actions > New repository secret**

| Secret | Descripcion | Como obtenerlo |
|--------|-------------|----------------|
| `EC2_HOST` | IP del servidor | `terraform output elastic_ip` |
| `EC2_SSH_KEY` | Clave privada SSH completa | `terraform output -raw private_key` |

> Copia el contenido **completo** del `.pem`, incluyendo `-----BEGIN RSA PRIVATE KEY-----` y `-----END RSA PRIVATE KEY-----`.

### Flujo CI/CD

```
git push origin main
       │
       ▼
GitHub Actions (deploy.yml)
       │
       ▼
SSH al servidor EC2
       │
       ▼
npm install -g openclaw@latest ...
       │
       ▼
Restart claude-max-proxy + openclaw-gateway
       │
       ▼
Verificacion automatica (HTTP 200)
```

## Comandos Utiles

### Gestion de servicios

```bash
# Estado
sudo systemctl status claude-max-proxy
systemctl --user status openclaw-gateway

# Reiniciar
sudo systemctl restart claude-max-proxy
systemctl --user restart openclaw-gateway

# Logs
sudo journalctl -u claude-max-proxy -f
journalctl --user -u openclaw-gateway -f

# IMPORTANTE: para comandos --user necesitas estas variables
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
export XDG_RUNTIME_DIR=/run/user/$(id -u)
```

### Terraform

```bash
cd terraform

terraform output              # Ver IP, SSH command, URL
terraform output elastic_ip   # Solo la IP
terraform output -raw private_key > key.pem  # Exportar clave SSH
terraform show                # Estado completo
terraform destroy             # Destruir toda la infraestructura
```

## Puertos

| Puerto | Servicio | Acceso | Protegido |
|--------|----------|--------|-----------|
| 22 | SSH | Publico | Clave SSH |
| 80 | Nginx (reverse proxy) | Publico | Basic Auth |
| 3456 | Claude Max API Proxy | Solo localhost | - |
| 18789 | OpenClaw Gateway | Solo localhost | Via Nginx |

## Problemas Comunes

### "Gateway service disabled"
El gateway necesita instalarse como user service:
```bash
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
export XDG_RUNTIME_DIR=/run/user/$(id -u)
openclaw gateway install --port 18789
```

### "origin not allowed"
La IP publica no esta en allowedOrigins. Editar `~/.openclaw/openclaw.json`:
```json
{
  "gateway": {
    "controlUi": {
      "allowedOrigins": ["http://TU_IP"]
    }
  }
}
```
Y reiniciar: `systemctl --user restart openclaw-gateway`

### OOM / Out of Memory
OpenClaw necesita minimo 2GB de RAM. Usar `t2.small` o superior.
Verificar swap: `free -h` (debe tener 4GB de swap).

### Claude Max Proxy falla
Verificar que Claude Code CLI esta instalado y autenticado:
```bash
claude --version    # debe mostrar version
claude login        # si no esta autenticado
```

## Costos Estimados (AWS)

| Recurso | Costo |
|---------|-------|
| EC2 t2.small (2GB RAM) | ~$17/mes |
| Elastic IP (en uso) | Gratis |
| EBS 20GB gp3 | ~$1.60/mes |
| **Total** | **~$19/mes** |
