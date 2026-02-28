#!/bin/bash
set -e

echo "=== OpenClaw Server Starting ==="

# Apply config from environment if provided
if [ -n "${OPENCLAW_CONFIG_JSON:-}" ]; then
    echo "$OPENCLAW_CONFIG_JSON" > ~/.openclaw/openclaw.json
    chmod 600 ~/.openclaw/openclaw.json
    echo "[+] Config applied from OPENCLAW_CONFIG_JSON"
fi

# Write .env with API keys if provided
{
    [ -n "${ANTHROPIC_API_KEY:-}" ]  && echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
    [ -n "${OPENAI_API_KEY:-}" ]     && echo "OPENAI_API_KEY=$OPENAI_API_KEY"
    [ -n "${OPENROUTER_API_KEY:-}" ] && echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY"
    [ -n "${GEMINI_API_KEY:-}" ]     && echo "GEMINI_API_KEY=$GEMINI_API_KEY"
} > ~/.openclaw/.env 2>/dev/null || true

# Run non-interactive onboard if no config exists yet
if [ ! -f ~/.openclaw/openclaw.json ]; then
    echo "[+] Running first-time onboard..."
    openclaw onboard \
        --non-interactive \
        --accept-risk \
        --gateway-bind lan \
        --gateway-auth token \
        --skip-channels \
        --skip-skills \
        --install-daemon || echo "[!] Onboard completed with warnings"
fi

# Set gateway token if provided
if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    echo "[+] Gateway token configured"
fi

# Start the gateway
echo "[+] Starting OpenClaw gateway on port ${OPENCLAW_GATEWAY_PORT:-18789}..."
exec openclaw gateway start --port "${OPENCLAW_GATEWAY_PORT:-18789}"
