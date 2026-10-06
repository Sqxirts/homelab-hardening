#!/usr/bin/env bash
# Network storage that is also a tailnet node, so remote devices reach SMB
# over the tunnel instead of through a router forward.
set -euo pipefail
SSH_PORT="${SSH_PORT:-2222}"   # match harden-container.sh --port

ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment 'ssh'
ufw allow 445/tcp comment 'smb'
ufw allow 41641/udp comment 'tailscale direct connections'
ufw allow in on tailscale0 comment 'tailnet'
ufw --force enable
