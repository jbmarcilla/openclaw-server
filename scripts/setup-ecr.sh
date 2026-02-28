#!/bin/bash
# Create ECR repository for OpenClaw Server
# Run this once before the first deployment.
#
# Usage: ./scripts/setup-ecr.sh [region]

set -euo pipefail

REGION="${1:-us-east-1}"
REPO_NAME="openclaw-server"

echo "Creating ECR repository: $REPO_NAME in $REGION"

aws ecr create-repository \
    --repository-name "$REPO_NAME" \
    --region "$REGION" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256

echo "ECR repository created successfully."
echo ""
echo "Add these GitHub secrets:"
echo "  AWS_ACCOUNT_ID = $(aws sts get-caller-identity --query Account --output text)"
echo "  AWS_ACCESS_KEY_ID = <your IAM access key>"
echo "  AWS_SECRET_ACCESS_KEY = <your IAM secret key>"
