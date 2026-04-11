#!/usr/bin/env bash
# ============================================================
# SOC Platform Phase 1 - EC2 User Data Bootstrap Script
# Installs Docker and Docker Compose, then clones & starts
# the SOC platform automatically on first boot.
# ============================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# System update
apt-get update -y
apt-get upgrade -y

# Install dependencies
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    netcat-openbsd \
    unzip

# ── Docker install ────────────────────────────────────────────────────────────
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

usermod -aG docker ubuntu
systemctl enable --now docker

# ── Elasticsearch system requirements ─────────────────────────────────────────
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# ── Clone SOC platform ────────────────────────────────────────────────────────
INSTALL_DIR="/opt/${project_name}"
mkdir -p "$INSTALL_DIR"
git clone https://github.com/SriHarsha379/soc-platform-phase1.git "$INSTALL_DIR"
chown -R ubuntu:ubuntu "$INSTALL_DIR"

# ── Bootstrap environment ──────────────────────────────────────────────────────
cd "$INSTALL_DIR"
if [[ ! -f .env ]]; then
    cp .env.example .env
fi

# ── Start services ─────────────────────────────────────────────────────────────
chmod +x scripts/*.sh tests/*.sh
sudo -u ubuntu docker compose pull
sudo -u ubuntu docker compose up -d

echo "SOC Platform Phase 1 bootstrapped successfully." >> /var/log/soc-bootstrap.log
