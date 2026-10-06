# Failure modes

Things that cost me real time. Most of them share a shape: **the control looks applied and isn't**, and nothing reports an error.

## A drop-in that is never included

`/etc/ssh/sshd_config.d/10-hardening.conf` is only read if `sshd_config` contains `Include /etc/ssh/sshd_config.d/*.conf`. Without that line the file sits there looking correct and changes nothing. No warning, no log line, no failed service.

**This is why every check in this repo reads effective state.** `sshd -T` prints what the daemon resolved. `grep` on a config file prints what someone typed. Those are different questions, and only one of them matters.

```bash
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|port)'
```

## fail2ban banning you off your own host

Testing several SSH keys against one host in quick succession looks exactly like a brute-force attempt, because it is one. Three failures inside the find window and your management workstation is banned for an hour. The symptom is a port that was open a minute ago now timing out, which reads like a firewall or network fault.

Two defenses, use both:

- Put your management ranges in `ignoreip`.
- Know the unban command before you need it, because you will be locked out when you need it:

```bash
fail2ban-client set sshd unbanip <your-ip>
```

## Enabling the firewall before allowing SSH

`ufw default deny incoming` followed by `ufw enable` ends your session, on a container whose console may need the hypervisor's web UI to reach. Always allow the SSH port first. `harden-container.sh` orders it that way deliberately.

## A green firewall that does not cover your containers

"Docker bypasses ufw" is half true, and the wrong half bites. It depends on how each port is published:

| Publish style | ufw filters it? |
|---|---|
| `-p 0.0.0.0:27015:27015/udp` (or no address) | **No.** Docker's DNAT in `PREROUTING` sends it to the container before ufw's `INPUT` rules ever see it. |
| `-p 192.0.2.53:8212:8212` (a specific host IP) | **Yes.** It traverses `INPUT` and needs an allow rule. |
| `network_mode: host` | **Yes.** Every port is an ordinary host socket. |

Two failures from one fact. A port published to `0.0.0.0` is open to everything no matter what `ufw status` says. And a port published to the host's own IP goes dark the moment ufw is enabled, which is how REST and RCON vanished from the dashboard here. Both look fine in `ufw status`.

```bash
docker ps --format '{{.Names}}  {{.Ports}}'   # 0.0.0.0: bypasses ufw; a specific IP is filtered
```

## Patching a file the package manager owns

Any fix that edits a file belonging to a package is reverted by that package's next upgrade. This is not the patch failing, it is the patch working exactly as long as it can.

If you must modify a vendor file, pair it with an `apt` post-invoke hook that reapplies the change, make the hook idempotent, and have it **warn instead of editing** when the anchor text it expects is missing, so a restructured upstream file fails loudly rather than being silently mangled.

Anchor on the most specific string you can find. Broad substitutions match in more places than you checked, and the second match is usually the one that matters.

## A sudoers file that does nothing

`/etc/sudoers.d/` entries are ignored without complaint when the filename contains a dot, or when permissions are not `0440`. A typo in the filename produces no error at all, so a rule you believe is active can be inert for months. Validate with `visudo -c` and confirm the effective result with `sudo -l` rather than by reading the file.

## A backup that excludes the data

An excluded mount point produces a backup job that runs green forever and archives none of the data you actually care about. The job reports success because it did what it was told.

Worse, restoring that guest **recreates the excluded volume empty and at full declared size**. You get a booting machine with the right services and no data, and on thin-provisioned storage the empty volume can overcommit the pool. Check whether overrun protection is enabled before you find out.

**Read what the job includes, not whether it succeeded.** Then restore it somewhere harmless and look at the filesystem.

## Conditional DNS forwarding the router will not answer

Reverse lookups for LAN hostnames failing is often blamed on the DNS server. It can equally be the router refusing to answer reverse queries at all, which no amount of DNS-side configuration fixes. Test the upstream directly before rebuilding your resolver:

```bash
dig -x 192.0.2.10 @<router-ip>
```

If that times out while forward lookups work, the limitation is upstream. Add static records for the few hosts that matter and move on.

## Private ranges excluded from internet egress

A VPN grant covering "the internet" typically excludes RFC1918 by design, so exit-node users cannot reach the exit node's LAN. If your tailnet DNS resolver is a private address, tightening the policy silently kills name resolution for every off-LAN device while raw connectivity keeps working.

**Signature: `ping 1.1.1.1` succeeds, `nslookup` fails.** Give the resolver its own `/32` grant, and verify from the tunnel side rather than from the LAN, where the test passes regardless and proves nothing.

## The general lesson

Every item above was found by checking, not by being alerted. That is the argument for the missing piece named in the README: none of these hosts tell anyone anything. Local enforcement with no central visibility means the only detection method is a human deciding to look.
