# OpenClaw Server

Panel web para desplegar y administrar [OpenClaw](https://openclaw.ai) en la nube. Disenado para que cualquier persona pueda tener su propio servidor de IA, sin necesidad de conocimientos tecnicos avanzados.

## Que incluye

- **Panel de administracion web** con login seguro
- **Terminal integrada** en el navegador (no necesitas SSH)
- **Guia paso a paso** para configurar HTTPS y OpenClaw
- **Dashboard de OpenClaw** embebido para gestionar agentes, canales y modelos
- **Deploy automatico** con Terraform en AWS (un solo comando)

## Como funciona

```
Tu navegador (HTTPS)
     |
  https://tudominio.com
     |
  ┌─────────────────────┐
  │  Cloudflare (gratis) │  ← SSL/HTTPS, WAF, DDoS protection
  └──────────┬──────────┘
             |
  ┌──────────▼──────────┐
  │   Firewall (ufw)    │  ← Solo permite trafico de Cloudflare
  └──────────┬──────────┘
             |
  ┌──────────▼──────────┐
  │  Nginx (port 80)    │  ← Reverse proxy + rate limiting
  └──────────┬──────────┘
             |
  ┌──────────▼──────────┐
  │  Admin Panel :3000  │  ← Login seguro, rate limit, helmet
  │  ┌────────────────┐ │
  │  │ Terminal web   │ │     Solo escucha en localhost
  │  │ Guia de config │ │     (127.0.0.1, no accesible desde
  │  │ Dashboard      │ │      internet directamente)
  │  └────────┬───────┘ │
  └───────────┼─────────┘
              |
  ┌───────────▼─────────┐
  │ OpenClaw GW :18789  │  ← Se instala desde la guia del panel
  │ (agentes de IA)     │     Solo localhost
  └─────────────────────┘
```

## Seguridad

El panel administra un servidor con terminal web — la seguridad es critica. Estas son las capas de proteccion:

### Capas de defensa

| Capa | Proteccion | Detalle |
|------|-----------|---------|
| **Cloudflare** | HTTPS, WAF, DDoS | Cifra todo el trafico, bloquea ataques comunes |
| **Firewall (ufw)** | Bloqueo por IP | Solo permite trafico de IPs de Cloudflare en puerto 80 |
| **Nginx** | Rate limiting | Limita peticiones por IP a nivel de proxy |
| **Admin Panel** | Rate limit en login | 10 intentos cada 15 minutos, luego bloquea |
| **Admin Panel** | Helmet (headers) | CSP, X-Frame-Options, HSTS, nosniff |
| **Admin Panel** | Cookie segura | SameSite=Strict, HttpOnly, Secure (con HTTPS) |
| **Admin Panel** | Setup token | Solo quien hizo deploy puede crear la primera cuenta |
| **Admin Panel** | Password 12+ chars | Minimo 12 caracteres para la cuenta admin |
| **Terminal** | Env vars filtradas | Solo pasa PATH, HOME, TERM al shell |

### Recomendaciones post-deploy

1. **Configurar Cloudflare HTTPS** lo antes posible (Fase 1 de la guia)
2. **Activar firewall** para bloquear acceso directo por IP:
   ```bash
   # En el servidor (via terminal web o SSH):
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow ssh
   # Permitir solo IPs de Cloudflare en puerto 80
   for ip in 173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22; do
     sudo ufw allow from $ip to any port 80
   done
   sudo ufw enable
   ```
3. **Usar una contrasena fuerte** (12+ caracteres, mezcla de letras, numeros y simbolos)

---

## Opcion 1: Deploy en AWS (Recomendado)

La forma mas facil. Un comando crea todo automaticamente.

### Requisitos

1. **Cuenta de AWS** — [Crear cuenta gratis](https://aws.amazon.com/free/)
2. **Terraform** instalado — [Descargar](https://developer.hashicorp.com/terraform/downloads)
3. **Git** instalado — [Descargar](https://git-scm.com/downloads)

### Pasos

```bash
# 1. Descargar el proyecto
git clone https://github.com/jbmarcilla/openclaw-server.git
cd openclaw-server

# 2. Configurar credenciales de AWS
cp .env.example .env
# Edita .env con tus credenciales AWS:
#   AWS_ACCESS_KEY_ID=tu-key
#   AWS_SECRET_ACCESS_KEY=tu-secret
#   AWS_REGION=us-west-2

# 3. Crear el servidor (toma ~3 minutos)
export $(grep -v '^#' .env | xargs)
cd terraform
terraform init
terraform apply

# 4. Guardar la clave SSH (por si necesitas acceso directo)
terraform output -raw private_key > ../openclaw-server-key.pem
chmod 400 ../openclaw-server-key.pem

# 5. Ver la IP de tu servidor
terraform output elastic_ip
```

**Listo.** Espera 3-5 minutos y abre `http://<TU_IP>` en el navegador.

### Que se crea automaticamente

| Recurso | Detalle |
|---------|---------|
| Servidor EC2 | Ubuntu 22.04, 2GB RAM, 20GB disco |
| IP fija | Elastic IP (no cambia al reiniciar) |
| Firewall | Puertos 22, 80, 443 abiertos |
| Admin Panel | Express.js + terminal web |
| Nginx | Reverse proxy |

### Costo estimado

| Recurso | Costo |
|---------|-------|
| EC2 t2.small | ~$17/mes |
| Disco 20GB | ~$1.60/mes |
| **Total** | **~$19/mes** |

> AWS tiene un [Free Tier](https://aws.amazon.com/free/) que incluye 12 meses de t2.micro gratis (1GB RAM). Funciona para pruebas pero puede ser lento.

---

## Opcion 2: Instalar en cualquier VPS

Si ya tienes un servidor Ubuntu (DigitalOcean, Linode, Hetzner, Azure, etc.):

```bash
# Desde tu computadora, reemplaza con tu IP y clave SSH:
./scripts/quick-deploy.sh <IP_DEL_SERVIDOR> <RUTA_CLAVE_SSH>
```

Esto instala todo automaticamente en tu servidor existente.

### Requisitos del servidor

- Ubuntu 20.04 o 22.04
- Minimo 2GB RAM
- Puerto 80 abierto

---

## Despues del deploy

### 1. Crear tu cuenta

Abre `http://<TU_IP>` en el navegador. La primera vez veras un wizard para crear tu usuario y contrasena.

### 2. Seguir la guia

Una vez logueado, ve al tab **"Guia"**. Ahi encontraras todos los pasos:

**Fase 1 — Configurar HTTPS (desde el navegador)**
1. Tener un dominio o subdominio
2. Crear cuenta gratis en Cloudflare
3. Agregar dominio a Cloudflare
4. Crear registro DNS apuntando a tu servidor
5. Verificar que HTTPS funciona

**Fase 2 — Instalar OpenClaw (desde el terminal web)**
6. Instalar OpenClaw CLI
7. Instalar Claude Code
8. Login en Claude
9. Configurar OpenClaw (wizard interactivo)
10. Verificar gateway
11. Abrir el dashboard de OpenClaw

Cada paso tiene instrucciones detalladas, botones para copiar comandos, y deteccion automatica de progreso.

### 3. Conectar canales

Desde el dashboard de OpenClaw puedes conectar:
- WhatsApp
- Telegram
- Discord
- Slack
- Y mas

### 4. Elegir modelos de IA

El panel soporta multiples proveedores:

| Provider | Modelos | Tipo |
|----------|---------|------|
| Anthropic (Claude) | Opus, Sonnet, Haiku | Incluido con Claude login |
| OpenAI | GPT-4o, GPT-5, o1 | API Key |
| Google | Gemini 2.0 Flash, Pro | API Key |
| Ollama | Llama 3, Mistral, DeepSeek | Gratis / Local |
| OpenRouter | 100+ modelos | API Key |

---

## Desarrollo local

Para contribuir o probar cambios:

```bash
git clone https://github.com/jbmarcilla/openclaw-server.git
cd openclaw-server/admin-panel
npm install
npm start
```

Abre http://localhost:3000. La primera vez crearas tu cuenta en el wizard.

---

## Estructura del proyecto

```
openclaw-server/
├── admin-panel/              # Panel web
│   ├── server.js             # Servidor Express + WebSocket + proxy
│   ├── config.js             # Configuracion
│   ├── package.json
│   └── public/
│       ├── setup.html        # Wizard primera vez
│       ├── login.html        # Login
│       ├── dashboard.html    # Dashboard (terminal + guia + OpenClaw)
│       ├── css/style.css     # Estilos (dark theme)
│       └── js/terminal.js    # Terminal + guia + logica
├── terraform/                # Infraestructura AWS
│   ├── main.tf               # EC2 + IP + Security Group
│   ├── variables.tf          # Variables configurables
│   ├── outputs.tf            # Outputs post-deploy
│   └── user-data.sh          # Script de instalacion automatica
├── scripts/
│   └── quick-deploy.sh       # Deploy rapido a cualquier VPS
├── CLAUDE.md                 # Contexto para Claude Code
├── LICENSE                   # MIT License
└── readme.md
```

---

## Comandos utiles

```bash
# Ver estado del admin panel (en el servidor)
sudo systemctl status openclaw-admin
sudo journalctl -u openclaw-admin -f

# SSH directo al servidor
ssh -i openclaw-server-key.pem ubuntu@<TU_IP>

# Destruir infraestructura AWS
cd terraform && terraform destroy
```

---

## Contribuir

Las contribuciones son bienvenidas. Puedes:

1. Hacer fork del proyecto
2. Crear una rama (`git checkout -b mi-mejora`)
3. Hacer commit de tus cambios
4. Abrir un Pull Request

---

## Licencia

[MIT License](LICENSE) — Libre de usar, copiar, modificar y distribuir. Solo se requiere mantener la atribucion al autor original.

Creado por [Joseph Marcilla Flores](https://github.com/jbmarcilla).
