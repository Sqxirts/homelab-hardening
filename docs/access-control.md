# VPN access control

## What changed and why

The tailnet ran the default policy:

```json
{ "src": ["*"], "dst": ["*"], "ip": ["*"] }
```

Every node reachable from every node, on every port. That was an acceptable risk while every device on it was mine. It stopped being acceptable when I invited a family member's laptop onto the VPN so they could use ad filtering off-network.

Their requirement was narrow: internet egress plus DNS filtering. Under allow-all they got file shares, every container, and the ability to route traffic out of my public IP. Nobody did anything wrong. The policy simply granted far more than the use case needed, and I had not looked at it since setup.

**The trigger worth generalizing: a default that is fine for one identity is rarely fine for two.** Re-read access policy whenever the set of people changes, not on a schedule.

## The policy

See [`../tailscale/policy.hujson`](../tailscale/policy.hujson). Three ideas do the work.

### `autogroup:self` carries the whole thing

`autogroup:self` means "devices owned by the same user as the source." One rule keeps every one of my own devices reaching every other, exactly as before. The guest account owns none of those devices, so it matches nothing.

**There is no deny rule for the guest.** They are excluded by not being granted, which is the difference between a default-deny policy and a default-allow policy with holes punched in it. Deny lists rot as you add hosts; this does not.

### Tagging removes a node from `autogroup:self`

A tagged node is owned by the tag, not by you, so it leaves `autogroup:self` and becomes reachable **only** through grants naming that tag.

This is the trap. Tagging a file server whose `tag:infra` grant lists ports 22 and 445 will cut off anything else it serves. A database fronted by a TLS reverse proxy on 443 disappears, and the failure shows up as a sync client that stopped working, not as an access denial you can trace.

**Enumerate what a node actually listens on before tagging it:**

```bash
ss -tlnp
```

Then widen the grant, then tag. In that order.

### `autogroup:internet` excludes private ranges

Deliberate: exit-node users must not reach the exit node's LAN. It also means a tailnet DNS server on a private address becomes unreachable the moment you tighten the policy, and **name resolution dies for every off-LAN device while raw connectivity stays perfect**.

Signature is distinctive: `ping 1.1.1.1` works, `nslookup anything` fails.

Fix is a `/32` grant to the resolver plus a subnet route advertising it. Verify from the tunnel, not the LAN:

```bash
tailscale ping 192.0.2.53          # expect: via <subnet-router>
tailscale dns status               # read resolver preference order here
```

A `dig` from inside the LAN passes whether or not the policy works, so it proves nothing.

## Operational notes

- **Add a fallback resolver.** A single nameserver with "override DNS" enabled means a dead resolver equals no DNS anywhere, and it also breaks any device that joins a foreign network. A public fallback listed second degrades to unfiltered DNS instead of none, at the cost of one timeout per lookup while the primary is down.
- **A subnet router stores its exit-node role as part of its route list.** Re-advertising routes without re-advertising the exit node silently removes it.
- **Check the CLI you have, not the CLI in the docs.** Published guidance referenced flags this client version does not implement. `--help` beats a blog post.
- **Device approval and key expiry** are still off here. Named because it is a real remaining gap, not an oversight.
