#!/bin/bash
# setup-vps.sh — Install dependencies on a fresh VPS for vtunnel
#
# Usage:
#   ssh root@your-vps.example.com 'bash -s' < deploy/setup-vps.sh
#
# What it does:
#   1. Installs Go (for building Caddy with plugins)
#   2. Builds Caddy with the Cloudflare DNS plugin
#   3. Installs Caddy as a systemd service
#   4. Opens firewall ports (80, 443, 8080)
#   5. Creates vtunnel system user and directories
#
# After running this, you still need to:
#   - Set CF_API_TOKEN for Caddy (Cloudflare API token)
#   - Run deploy.sh to upload the vtunnel binary

set -euo pipefail

echo "==> Updating system packages..."
apt-get update -y
apt-get install -y curl wget git

# --- Install Go ---
GO_VERSION="1.22.2"
if ! command -v go &>/dev/null; then
    echo "==> Installing Go ${GO_VERSION}..."
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> /etc/profile.d/go.sh
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
else
    echo "==> Go already installed: $(go version)"
fi

# --- Install xcaddy and build Caddy with Cloudflare plugin ---
echo "==> Installing xcaddy..."
GOBIN=/usr/local/bin go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

echo "==> Building Caddy with Cloudflare DNS plugin..."
cd /tmp
xcaddy build --with github.com/caddy-dns/cloudflare --output /usr/local/bin/caddy

# --- Install Caddy as systemd service ---
echo "==> Setting up Caddy systemd service..."
groupadd --system caddy 2>/dev/null || true
useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy 2>/dev/null || true
mkdir -p /etc/caddy /var/lib/caddy/.config /var/lib/caddy/.data
chown -R caddy:caddy /var/lib/caddy

cat > /etc/systemd/system/caddy.service <<'CADDYSERVICE'
[Unit]
Description=Caddy Web Server
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
CADDYSERVICE

# Create override directory for environment variables
mkdir -p /etc/systemd/system/caddy.service.d
cat > /etc/systemd/system/caddy.service.d/override.conf <<'OVERRIDE'
[Service]
# Set your Cloudflare API token here
# Generate at: https://dash.cloudflare.com/profile/api-tokens
# Permissions: Zone > DNS > Edit, scoped to vtunnel.io
Environment=CF_API_TOKEN=CHANGE_ME
OVERRIDE

echo ""
echo "  IMPORTANT: Edit /etc/systemd/system/caddy.service.d/override.conf"
echo "  and set CF_API_TOKEN to your Cloudflare API token"
echo ""

# --- Create vtunnel user ---
echo "==> Creating vtunnel system user..."
useradd --system --no-create-home vtunnel 2>/dev/null || true
mkdir -p /var/lib/vtunnel /etc/vtunnel
chown vtunnel:vtunnel /var/lib/vtunnel

# --- Firewall ---
echo "==> Configuring firewall..."
if command -v ufw &>/dev/null; then
    ufw allow 80/tcp    # HTTP (Caddy / ACME)
    ufw allow 443/tcp   # HTTPS (Caddy)
    ufw allow 8080/tcp  # vtunnel control port (client connections)
    ufw --force enable
    echo "  UFW rules added for ports 80, 443, 8080"
else
    echo "  UFW not found — configure your firewall manually"
    echo "  Required ports: 80 (HTTP), 443 (HTTPS), 8080 (vtunnel control)"
fi

# --- Reload systemd ---
systemctl daemon-reload
systemctl enable caddy

echo ""
echo "=========================================="
echo "  VPS setup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Set CF_API_TOKEN in /etc/systemd/system/caddy.service.d/override.conf"
echo "  2. Run: ./deploy/deploy.sh root@$(hostname -I | awk '{print $1}')"
echo "  3. Generate API key: openssl rand -hex 16"
echo "  4. Update --api-key in /etc/systemd/system/vtunnel.service"
echo "  5. systemctl restart vtunnel && systemctl restart caddy"
echo ""
