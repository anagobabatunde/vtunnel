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

echo "==> Building vtunnel (linux/amd64)..."
v -prod -os linux cmd/vtunnel/ -o "${BINARY}"

echo "==> Uploading binary to ${TARGET}..."
scp "${BINARY}" "${TARGET}:${REMOTE_BIN}"

echo "==> Uploading systemd service..."
scp deploy/vtunnel.service "${TARGET}:${REMOTE_SERVICE}"

echo "==> Setting up on remote..."
ssh "${TARGET}" bash <<'EOF'
    # Create vtunnel user if it doesn't exist
    id -u vtunnel &>/dev/null || useradd --system --no-create-home vtunnel

    # Create data directories
    mkdir -p /var/lib/vtunnel /etc/vtunnel
    chown vtunnel:vtunnel /var/lib/vtunnel

    # Make binary executable
    chmod +x /usr/local/bin/vtunnel

    # Reload and restart service
    systemctl daemon-reload
    systemctl enable vtunnel
    systemctl restart vtunnel

    echo "==> vtunnel service status:"
    systemctl status vtunnel --no-pager || true
EOF

echo "==> Deployed successfully!"
echo ""
echo "Next steps:"
echo "  1. Edit /etc/systemd/system/vtunnel.service on the VPS"
echo "     - Set --domain to your real domain"
echo "     - Set --api-key to a random secret"
echo "  2. Set up DNS: A record for *.tunnel.yourdomain.com -> VPS IP"
echo "  3. Install and configure Caddy for TLS (see deploy/Caddyfile)"
echo "  4. systemctl restart vtunnel"

# Cleanup local binary
rm -f "${BINARY}"
