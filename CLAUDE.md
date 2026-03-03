# OpenClaw Server

Web admin panel for deploying and managing OpenClaw (AI gateway) on cloud servers. Designed for non-technical users.

## Architecture

```
Browser → Cloudflare (HTTPS) → Nginx (port 80) → Admin Panel (port 3000) → OpenClaw Gateway (port 18789)
```

- **Admin Panel**: Express.js app with session auth, WebSocket terminal, reverse proxy to OpenClaw
- **OpenClaw Gateway**: Runs as a user systemd service on port 18789
- **Nginx**: Reverse proxy from port 80 to admin panel port 3000
- **Cloudflare**: Free SSL/HTTPS termination (configured by user via guide in dashboard)

## Project Structure

```
admin-panel/
  server.js          # Express server: auth, API endpoints, WS terminal, OpenClaw proxy
  config.js          # Config management (~/.openclaw-admin/config.json)
  public/
    dashboard.html   # Main dashboard (3 tabs: Terminal, Guia, OpenClaw Dashboard)
    login.html       # Login page
    setup.html       # First-time setup wizard
    css/style.css    # All styles (Catppuccin Mocha dark theme)
    js/terminal.js   # Terminal WS, tab switching, guide progress, HTTPS detection, reset modal
terraform/           # AWS EC2 infrastructure (Terraform)
scripts/
  quick-deploy.sh    # SSH-based deploy to EC2 (alternative to Terraform)
```

## Key Conventions

- **Language**: UI text is in Spanish (es). Code comments in English.
- **Theme**: Catppuccin Mocha. Key colors: green #a6e3a1, blue #89b4fa, yellow #f9e2af, red #f38ba8, peach #fab387
- **No frameworks**: Vanilla JS (ES5-compatible IIFE in terminal.js), plain CSS, no build step
- **Config storage**: `~/.openclaw-admin/config.json` (admin credentials, settings), `~/.openclaw/` (OpenClaw config)
- **Auth**: bcryptjs password hashing, express-session with 24h cookie
- **WebSocket**: Two WS paths — `/ws/terminal` (node-pty shell) and everything else proxied to OpenClaw gateway with Origin header rewrite

## Deploy to EC2

```bash
# From local machine
ssh -i openclaw-server-key.pem ubuntu@<EC2_IP>

# On EC2: pull and restart
cd /opt/openclaw-admin && sudo git pull origin master && sudo systemctl restart openclaw-admin
```

## Git Workflow

- **Branch**: `master` (main working branch), `main` (base branch for PRs)
- **Versioning**: Semantic versioning with git tags (v0.1.0, v0.2.0, etc.)
- **Commits**: Conventional-style messages in English (feat:, fix:, docs:, etc.)
- Never commit: `.env`, `*.pem`, `*.key`, credentials, `node_modules/`, terraform state

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/setup | No | First-time account creation |
| POST | /api/login | No | Login |
| POST | /api/logout | Yes | Logout |
| POST | /api/reset-server | Yes | Reset everything to initial state |
| GET | /api/guide-status | Yes | Check installed tools (openclaw, claude, gateway) |
| GET | /api/server-info | Yes | Public IP + HTTPS detection |
| GET | /api/openclaw-status | Yes | Check if OpenClaw gateway is running |
| ALL | /openclaw/* | Yes | Reverse proxy to OpenClaw gateway |
