#!/usr/bin/env bash
# Dashboard host. LAN-facing web UI, no TLS and no auth, so it must never get
# a router forward. It reaches out to the other hosts; nothing reaches in
# except the UI itself.
set -euo pipefail
SSH_PORT="${SSH_PORT:-2222}"   # match harden-container.sh --port

ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment 'ssh'
ufw allow 3000/tcp comment 'dashboard'
ufw --force enable
