#!/bin/bash
# deploy.sh — Build and deploy vtunnel to a VPS
#
# Usage:
#   ./deploy/deploy.sh user@your-vps.example.com
#
# Prerequisites:
#   - V compiler installed locally
#   - SSH access to the VPS
#   - VPS running Ubuntu/Debian with systemd
#   - Caddy already installed (see deploy/setup-vps.sh)

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <user@host>"
    echo "Example: $0 root@vps.example.com"
    exit 1
fi

TARGET="$1"
BINARY="vtunnel"
REMOTE_BIN="/usr/local/bin/${BINARY}"
REMOTE_SERVICE="/etc/systemd/system/vtunnel.service"
REMOTE_CADDYFILE="/etc/caddy/Caddyfile"

echo "==> Building vtunnel (linux/amd64)..."
v -prod -os linux cmd/vtunnel/ -o "${BINARY}"

echo "==> Uploading binary to ${TARGET}..."
scp "${BINARY}" "${TARGET}:${REMOTE_BIN}"

echo "==> Uploading systemd service..."
scp deploy/vtunnel.service "${TARGET}:${REMOTE_SERVICE}"

echo "==> Uploading Caddyfile..."
scp deploy/Caddyfile "${TARGET}:${REMOTE_CADDYFILE}"

echo "==> Setting up on remote..."
ssh "${TARGET}" bash <<'EOF'
    # Create vtunnel user if it doesn't exist
    id -u vtunnel &>/dev/null || useradd --system --no-create-home vtunnel

    # Create data directories
    mkdir -p /var/lib/vtunnel /etc/vtunnel
    chown vtunnel:vtunnel /var/lib/vtunnel

    # Make binary executable
    chmod +x /usr/local/bin/vtunnel

    # Reload and restart vtunnel
    systemctl daemon-reload
    systemctl enable vtunnel
    systemctl restart vtunnel

    # Reload Caddy config
    systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null || true

    echo ""
    echo "==> vtunnel service status:"
    systemctl status vtunnel --no-pager || true
    echo ""
    echo "==> caddy service status:"
    systemctl status caddy --no-pager || true
EOF

echo ""
echo "==> Deployed successfully!"
echo ""
echo "Post-deploy checklist:"
echo "  1. Generate API key:  openssl rand -hex 16"
echo "  2. Update --api-key in /etc/systemd/system/vtunnel.service"
echo "  3. Set CF_API_TOKEN in /etc/systemd/system/caddy.service.d/override.conf"
echo "  4. Verify DNS: dig tunnel.vtunnel.io / dig *.tunnel.vtunnel.io"
echo "  5. systemctl restart vtunnel && systemctl restart caddy"
echo "  6. Test: vtunnel http 3000 --server tunnel.vtunnel.io:8080"

# Cleanup local binary
rm -f "${BINARY}"
