#!/usr/bin/env bash
# Game server whose container publishes ports through Docker's bridge.
# Mixed publish styles on purpose, see ../../docs/failure-modes.md:
#   game + query UDP are published to 0.0.0.0, so Docker's DNAT rules bypass ufw
#   entirely; the allow rules below only document intent.
#   REST and RCON are published to the host's own IP, so they DO traverse ufw
#   and need an explicit allow, scoped to the one host that polls them.
set -euo pipefail
SSH_PORT="${SSH_PORT:-2222}"   # match harden-container.sh --port
DASHBOARD_IP="${DASHBOARD_IP:?set DASHBOARD_IP}"

ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment 'ssh'
ufw allow 15120/udp comment 'game'
ufw allow 27015/udp comment 'steam query'
ufw allow from "$DASHBOARD_IP" to any port 8212 proto tcp comment 'REST: dashboard only'
ufw allow from "$DASHBOARD_IP" to any port 25575 proto tcp comment 'rcon: dashboard only'
ufw allow from "$DASHBOARD_IP" to any port 61208 proto tcp comment 'glances: dashboard only'
ufw --force enable
