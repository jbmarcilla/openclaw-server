#!/bin/bash
set -euo pipefail

LOG="/var/log/admin-panel-setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Admin Panel Setup (Terraform) - $(date) ==="

# Run the main installer
curl -fsSL https://raw.githubusercontent.com/jbmarcilla/openclaw-server/master/install.sh | bash

echo ""
echo "=== Setup Complete - $(date) ==="
