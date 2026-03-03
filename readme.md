# OpenClaw Server

Panel web para desplegar y administrar [OpenClaw](https://openclaw.ai) en tu propio servidor. Disenado para que cualquier persona pueda tener su servidor de IA, sin necesidad de conocimientos tecnicos.

## Que incluye

- **Panel de administracion web** con login seguro
- **Terminal integrada** en el navegador (no necesitas SSH)
- **Guia paso a paso** para configurar HTTPS y OpenClaw
- **Dashboard de OpenClaw** embebido para gestionar agentes, canales y modelos

## Instalacion

### Opcion 1: Un solo comando (cualquier servidor Linux o Mac)

Si ya tienes un servidor (VPS, Mac Mini, etc.), ejecuta esto en el servidor:

```bash
curl -fsSL https://raw.githubusercontent.com/jbmarcilla/openclaw-server/master/install.sh | bash
```

Cuando termine, abre la IP que aparece en tu navegador. Crea tu cuenta y sigue la guia.

**Requisitos:**
- Ubuntu 20.04+ o macOS 12+
- 2GB RAM minimo
- Puerto 80 abierto

### Opcion 2: AWS con Terraform (crea el servidor automaticamente)

Si no tienes servidor, esta opcion crea uno en AWS:

```bash
git clone https://github.com/jbmarcilla/openclaw-server.git
cd openclaw-server

# Configurar credenciales AWS
cp .env.example .env
# Edita .env con tus credenciales AWS

# Crear servidor (~3 minutos)
export $(grep -v '^#' .env | xargs)
cd terraform && terraform init && terraform apply
```

Requiere: [cuenta AWS](https://aws.amazon.com/free/), [Terraform](https://developer.hashicorp.com/terraform/downloads), [Git](https://git-scm.com/downloads)

**Costo estimado:** ~$19/mes (EC2 t2.small + disco). AWS tiene Free Tier con 12 meses de t2.micro gratis.

---

## Despues de instalar

### 1. Crear tu cuenta

Abre `http://<TU_IP>` en el navegador. La primera vez crearas tu usuario y contrasena.

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
9. Configurar OpenClaw
10. Verificar gateway
11. Abrir el dashboard

### 3. Conectar canales

Desde el dashboard de OpenClaw puedes conectar WhatsApp, Telegram, Discord, Slack y mas.

### 4. Elegir modelos de IA

| Provider | Modelos | Tipo |
|----------|---------|------|
| Anthropic (Claude) | Opus, Sonnet, Haiku | Incluido con Claude login |
| OpenAI | GPT-4o, GPT-5, o1 | API Key |
| Google | Gemini 2.0 Flash, Pro | API Key |
| Ollama | Llama 3, Mistral, DeepSeek | Gratis / Local |
| OpenRouter | 100+ modelos | API Key |

---

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
  │  Nginx (port 80)    │  ← Reverse proxy
  └──────────┬──────────┘
             |
  ┌──────────▼──────────┐
  │  Admin Panel :3000  │  ← Login seguro, rate limit, helmet
  │  ┌────────────────┐ │
  │  │ Terminal web   │ │     Solo escucha en localhost
  │  │ Guia de config │ │     (127.0.0.1)
  │  │ Dashboard      │ │
  │  └────────┬───────┘ │
  └───────────┼─────────┘
              |
  ┌───────────▼─────────┐
  │ OpenClaw GW :18789  │  ← Se instala desde la guia del panel
  │ (agentes de IA)     │     Solo localhost
  └─────────────────────┘
```

## Seguridad

| Capa | Proteccion |
|------|-----------|
| Cloudflare | HTTPS, WAF, DDoS |
| Firewall (ufw) | Solo trafico de Cloudflare |
| Nginx | Reverse proxy |
| Admin Panel | Rate limit (10 intentos/15min), Helmet, SameSite=Strict, setup token |
| Terminal | Variables de entorno filtradas |

---

## Desarrollo local

```bash
git clone https://github.com/jbmarcilla/openclaw-server.git
cd openclaw-server/admin-panel
npm install
npm start
```

Abre http://localhost:3000

---

## Estructura

```
openclaw-server/
├── install.sh                   # Instalador (curl | bash)
├── admin-panel/                 # Panel web
│   ├── server.js                # Express + WebSocket + proxy
│   ├── config.js
│   └── public/                  # Frontend
├── terraform/                   # Infraestructura AWS
│   ├── main.tf
│   └── user-data.sh
├── scripts/
│   └── quick-deploy.sh          # Deploy via SSH
├── CLAUDE.md
├── LICENSE
└── readme.md
```

---

## Contribuir

1. Fork del proyecto
2. Crear rama (`git checkout -b mi-mejora`)
3. Commit y Pull Request

Reportar bugs o pedir mejoras: [GitHub Issues](https://github.com/jbmarcilla/openclaw-server/issues)

---

## Licencia

[MIT License](LICENSE) — Libre de usar, copiar, modificar y distribuir.

Creado por [Joseph Marcilla Flores](https://github.com/jbmarcilla).
