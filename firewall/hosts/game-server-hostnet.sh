#!/usr/bin/env bash
# Game server whose container runs with network_mode: host.
# Host networking means every port is a plain host socket, so ufw filters all
# of them. Nothing is bypassed, and nothing is reachable without a rule here.
set -euo pipefail
SSH_PORT="${SSH_PORT:-2222}"   # match harden-container.sh --port
DASHBOARD_IP="${DASHBOARD_IP:?set DASHBOARD_IP}"

ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment 'ssh'
ufw allow 25565/tcp comment 'game'
ufw allow 24454/udp comment 'voice chat'
ufw allow from "$DASHBOARD_IP" to any port 2375 proto tcp comment 'docker socket proxy: dashboard only'
ufw allow from "$DASHBOARD_IP" to any port 25575 proto tcp comment 'rcon: dashboard only'
ufw allow from "$DASHBOARD_IP" to any port 61208 proto tcp comment 'glances: dashboard only'
ufw --force enable
