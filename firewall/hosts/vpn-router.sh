#!/usr/bin/env bash
# VPN subnet router and exit node. NOT YET APPLIED on the live host; kept here
# as the plan, because getting it wrong takes off-LAN DNS down with it.
#
# ufw ships with DEFAULT_FORWARD_POLICY="DROP". On a host whose whole job is
# forwarding packets, enabling ufw with that default silently kills the subnet
# route and the exit node while SSH keeps working, so it looks fine from the LAN.
# Change the forward policy FIRST, then add rules, then enable.
set -euo pipefail
SSH_PORT="${SSH_PORT:-2222}"   # match harden-container.sh --port

sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment 'ssh'
ufw allow 41641/udp comment 'tailscale direct connections'
ufw allow in on tailscale0 comment 'tailnet'
ufw --force enable
# Verify from the TUNNEL side (an off-LAN device), not from the LAN.
