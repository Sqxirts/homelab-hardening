# Access review: my VPN was allow-all, and I had put someone else on it

**Finding:** a second person's laptop on my VPN could reach every container, the NAS on every port, and route their traffic out of my home IP.
**Cause:** the default access policy, never changed, plus an invite I made for a good reason and never re-read the policy after.
**Fix:** allow-all replaced with explicit grants. They now get internet and DNS filtering. Nothing else.

## How I found it

I was auditing the VPN after fixing an unrelated bandwidth problem. The node list had one more entry than I expected: a macOS device under a different user ID from mine, an Apple Private Relay address rather than my own account.

Not an intrusion. It was my mother's laptop, and I had added it on purpose so she could use my ad and malware filtering while away from home. Her actual requirement was narrow: VPN plus DNS filtering.

What she had was the default policy:

```json
{ "src": ["*"], "dst": ["*"], "ip": ["*"] }
```

Every node reachable from every node, on every port. In practice that meant her laptop could reach the NAS on any port, every container in the lab, and the exit node, which put her traffic on my home IP address attributed to this household.

Nobody did anything wrong. The policy simply granted about fifty times what the use case needed, and I had not looked at it since the day I set the VPN up.

## The lesson I actually care about

**A default that is fine for one identity is rarely fine for two.**

Allow-all was a completely reasonable setting while every device on that VPN was mine. The risk did not change gradually. It changed the moment a second account joined, and nothing in the system prompted me to re-read the policy at that moment. The invite and the access review are two separate actions, and only one of them is obvious.

Access policy should be re-read when the set of *people* changes, not on a calendar.

## What I replaced it with

```hujson
{
  "groups": {
    "group:owner":  ["me@example.com"],
    "group:family": ["guest@example.com"],
  },
  "grants": [
    { "src": ["group:owner"],  "dst": ["autogroup:self"],     "ip": ["*"] },
    { "src": ["group:owner"],  "dst": ["autogroup:internet"], "ip": ["*"] },
    { "src": ["group:owner"],  "dst": ["192.0.2.53/32"],      "ip": ["53"] },

    { "src": ["group:family"], "dst": ["autogroup:internet"], "ip": ["*"] },
    { "src": ["group:family"], "dst": ["192.0.2.53/32"],      "ip": ["53"] },
  ],
  "ssh": [],
}
```

`autogroup:self` means "devices owned by the same user as the source." One line keeps all of my own devices reaching each other exactly as before. Her account owns none of them, so it matches nothing.

**There is no deny rule for her.** She is excluded by not being granted, which is the part I want to call out. A deny list has to be updated every time I add a host, and the day I forget is the day it fails open. This one fails closed by construction.

I also turned off the VPN's built-in SSH feature while I was in there. It had been enabled the whole time with no SSH block in the policy, so it was granting nothing. A live-looking feature doing nothing is still worth removing, because the next person to read the config has to work out that it is inert.

## The part that broke, and why

Saving the new policy immediately killed DNS for every off-LAN device.

**`autogroup:internet` deliberately excludes RFC1918 ranges.** That is correct behavior. Exit node users should not be able to reach the exit node's private LAN. But my VPN-wide DNS server *is* a private address, so tightening the policy cut every remote device off from name resolution while leaving raw connectivity perfectly intact.

The signature is distinctive and worth memorizing:

```
ping 1.1.1.1        # works
nslookup google.com # fails
```

Fixed with a `/32` grant to the resolver plus a subnet route advertising it from the VPN container.

Verification had a trap of its own. A `dig` from a machine on my home LAN passes whether or not the policy works, because it resolves over the LAN and never touches the tunnel. The test has to run from the tunnel side:

```
tailscale ping 192.0.2.53
# pong ... via <vpn-container>
```

## Two traps I caught before they fired

**Re-advertising routes silently removes the exit node.** The subnet router stores its exit-node role *as* part of its advertised route list. Running `--advertise-routes` without also passing `--advertise-exit-node` replaces the list and quietly drops the role. I read the current value before writing a new one.

**Tagging a node removes it from `autogroup:self`.** I was about to tag the NAS so I could write explicit rules for it. My draft grant allowed ports 22 and 445. Running `ss -tlnp` on the box first showed a database fronted by a TLS proxy on 443, which the grant did not include. Tagging it would have broken document sync on every device I own, and the failure would have shown up as "sync stopped working," not as an access denial I could trace.

Enumerate what a host actually listens on before you tag it. Not after.

## What I would tell someone setting this up

1. **The default policy is a starting point, not a configuration.** Read it on day one.
2. **Re-read access rules whenever a person is added**, not on a schedule.
3. **Prefer exclusion by omission over deny rules.** Ownership-based grants keep working as you add hosts. Deny lists rot.
4. **Verify from the constrained side.** A test run from the privileged network proves nothing about the restricted path.
5. **Least privilege will break something the day you turn it on.** Budget for that instead of being surprised, and know it is usually DNS.
