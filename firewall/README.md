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
