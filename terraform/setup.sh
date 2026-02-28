#!/bin/bash
set -e

# =========================================================================
#  OpenClaw Server (Claude Max) — Setup de infraestructura EC2
# =========================================================================
#
#  Requisitos:
#    - Terraform instalado (https://developer.hashicorp.com/terraform/install)
#    - AWS CLI configurado con credenciales (aws configure)
#    - Suscripcion Claude Max activa ($200/mes)
#
#  Ejecucion (desde la carpeta terraform/):
#    cd terraform
#
#    bash setup.sh setup     # Paso 1: Crea EC2 + Elastic IP
#    bash setup.sh ssh       # Paso 2: Guarda SSH key + muestra para GitHub
#    bash setup.sh destroy   # (Opcional) Destruye toda la infraestructura
#
#  Flujo completo:
#    1. bash setup.sh setup    → Crea la infra, te da la Elastic IP
#    2. bash setup.sh ssh      → Te muestra la SSH key y la guarda en key.pem
#    3. SSH al servidor        → ssh -i key.pem ubuntu@<IP>
#    4. Autenticar Claude      → claude login
#    5. Iniciar servicios      → sudo systemctl start claude-max-proxy openclaw
#    6. Copia IP + SSH key     → GitHub Secrets: EC2_HOST, EC2_SSH_KEY
#    7. git push origin main   → GitHub Actions despliega automaticamente
#
#  Recursos creados:
#    - EC2 t2.micro (Ubuntu 22.04) con Node.js + OpenClaw + Claude Max Proxy
#    - Elastic IP (IP fija)
#    - Security Group (puertos 22, 80, 18789-18793)
#    - SSH Key Pair (generada automaticamente)
#
#  Arquitectura:
#    Claude Max Sub → claude-max-api-proxy (:3456) → OpenClaw (:18789)
#    $200/mes flat, sin pago por token
#
# =========================================================================

# ── Funcion: crear infraestructura ───────────────────────────────
setup() {
  echo "=== Inicializando Terraform ==="
  terraform init

  echo ""
  echo "=== Creando infraestructura ==="
  terraform apply

  echo ""
  echo "=========================================="
  echo "  EC2 creado exitosamente!"
  echo "=========================================="
  echo ""
  echo "Elastic IP:"
  terraform output elastic_ip
  echo ""
  echo "OpenClaw Gateway:"
  terraform output openclaw_url
  echo ""
  echo "SSH:"
  terraform output ssh_command
  echo ""
  echo "Siguiente paso: bash setup.sh ssh"
}

# ── Funcion: obtener SSH key ─────────────────────────────────────
ssh_key() {
  echo "=== SSH Private Key ==="
  echo "Copia TODO el bloque de abajo (incluyendo BEGIN y END)"
  echo "y pegalo en GitHub Secrets como EC2_SSH_KEY"
  echo ""
  echo "------- COPIAR DESDE AQUI -------"
  terraform output -raw private_key
  echo ""
  echo "------- HASTA AQUI -------"
  echo ""
  echo "Tambien se guardo en key.pem para uso local:"
  terraform output -raw private_key > key.pem
  chmod 600 key.pem
  echo "  ssh -i key.pem ubuntu@$(terraform output -raw elastic_ip)"
  echo ""
  echo "=== PASOS EN EL SERVIDOR ==="
  echo "  1. ssh -i key.pem ubuntu@$(terraform output -raw elastic_ip)"
  echo "  2. claude login          # Autenticar tu suscripcion Claude Max"
  echo "  3. sudo systemctl start claude-max-proxy openclaw"
  echo "  4. curl localhost:3456/v1/models   # Verificar proxy"
}

# ── Funcion: destruir infraestructura ────────────────────────────
destroy() {
  echo "=== Destruyendo infraestructura ==="
  terraform destroy
}

# ── Menu ─────────────────────────────────────────────────────────
case "${1:-}" in
  setup)   setup ;;
  ssh)     ssh_key ;;
  destroy) destroy ;;
  *)
    echo "Uso: bash setup.sh <comando>"
    echo ""
    echo "Comandos:"
    echo "  setup    Inicializa Terraform y crea EC2 + Elastic IP"
    echo "  ssh      Muestra la SSH private key y la guarda en key.pem"
    echo "  destroy  Destruye toda la infraestructura"
    ;;
esac
