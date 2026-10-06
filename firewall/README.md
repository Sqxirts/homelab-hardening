# Firewall and exposure model

Two different problems, often confused: what the **host** accepts, and what the **internet** can reach.

## Host firewall

Default deny inbound on every container, allowing only what that container serves. Applied by [`../scripts/harden-container.sh`](../scripts/harden-container.sh), checked by [`../scripts/verify-baseline.sh`](../scripts/verify-baseline.sh).

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 2222/tcp comment 'ssh'
ufw --force enable          # only ever AFTER the allow rule
```

Reversing those last two lines ends your session. On a container whose console requires the hypervisor's web UI, that is a genuinely annoying recovery.

## Per-host rule sets

The baseline above is the floor. Each role adds only what it serves, in [`hosts/`](hosts/):

| Script | Role | Inbound beyond SSH |
|---|---|---|
| [`game-server-docker.sh`](hosts/game-server-docker.sh) | game server, Docker bridge publishes | game + query UDP from anywhere; REST, RCON, metrics from the dashboard only |
| [`game-server-hostnet.sh`](hosts/game-server-hostnet.sh) | game server, `network_mode: host` | game TCP + voice UDP from anywhere; socket proxy, RCON, metrics from the dashboard only |
| [`dashboard.sh`](hosts/dashboard.sh) | LAN dashboard | the web UI port |
| [`nas.sh`](hosts/nas.sh) | storage + tailnet node | SMB, Tailscale direct UDP, everything on `tailscale0` |
| [`vpn-router.sh`](hosts/vpn-router.sh) | subnet router + exit node | **not applied yet**: needs `DEFAULT_FORWARD_POLICY="ACCEPT"` first |

Management-only ports (RCON, the Docker socket proxy, metrics) are scoped `from <dashboard-ip>`, never `Anywhere`. Run each with `DASHBOARD_IP=<ip> SSH_PORT=<port> sudo -E ./hosts/<role>.sh`.

**Baseline before you enable, re-test after.** Enabling ufw on the Docker game server silently cut the dashboard off from REST and RCON. Reading the rules did not catch it; polling the endpoints from the dashboard host before and after did. Arm a dead-man's switch first so a bad rule set undoes itself:

```bash
systemd-run --on-active=5min --unit=ufw-rollback ufw --force disable
# ...rules, enable, verify from a fresh session...
systemctl stop ufw-rollback.timer
```

## Internet exposure

Only the game servers are reachable from the internet, through per-service port forwards on the router plus dynamic DNS. Everything else is reachable over the VPN only.

**Per-service forwards, not a DMZ host and not a third-party tunnel.** A forward for one UDP port to one container exposes exactly that. A tunnel provider, by contrast, means trusting a third party with a path into the network and accepting their availability as your own.

The tradeoff being made deliberately: port forwarding publishes a home IP address that is discoverable by anyone who joins a game server. That is acceptable for a game server. It would not be acceptable for anything holding data.

## What to check periodically

```bash
# What is this host actually listening on, and is it bound to 0.0.0.0?
ss -tlnp

# What does the outside actually see? Run from OFF the network.
nmap -Pn -p- <public-ip>
```

`ss` output is the one that surprises people. A service bound to `0.0.0.0` on a host with a forward is exposed; the same service bound to `127.0.0.1` behind a reverse proxy is not. Check the bind address, not just the port number.

Scan from outside your own network. A scan from inside tests the host firewall and tells you nothing about the router.
