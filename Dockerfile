FROM ubuntu:24.04

LABEL maintainer="jbmarcilla"
LABEL description="OpenClaw AI Agent Server"

ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_VERSION=22
ENV OPENCLAW_NO_PROMPT=1
ENV OPENCLAW_GATEWAY_BIND=lan

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
    gnupg \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create dedicated user
RUN useradd -m -s /bin/bash openclaw \
    && mkdir -p /home/openclaw/.openclaw \
    && chown -R openclaw:openclaw /home/openclaw

USER openclaw
WORKDIR /home/openclaw

# Install OpenClaw globally for this user
RUN npm install -g openclaw@latest

# Expose gateway port
EXPOSE 18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:18789/health || exit 1

# Copy entrypoint script
COPY --chown=openclaw:openclaw scripts/entrypoint.sh /home/openclaw/entrypoint.sh
RUN chmod +x /home/openclaw/entrypoint.sh

ENTRYPOINT ["/home/openclaw/entrypoint.sh"]
