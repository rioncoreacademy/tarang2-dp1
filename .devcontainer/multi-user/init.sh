#!/bin/bash
set -e

if [[ -n "${GITHUB_CLIENT_ID:-}" ]]; then
    cat > "$(dirname "$0")/../../.env" <<EOF
GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID}
GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET:-}
CHIPCRAFT_KEY=${CHIPCRAFT_KEY:-}
VNC_PASSWORD=${VNC_PASSWORD:-novnc}
TEMPLATE_REPO=${TEMPLATE_REPO:-}
PORT_START=6081
PORT_END=6085
SESSION_TTL=14400
SHARED_PATH=/data/workspace/project
EOF
    echo "✓ .env written from Codespaces secrets"
else
    cp .env.example .env
    echo "⚠ No secrets found — .env copied from .env.example. Edit it manually before starting."
fi

docker compose build
