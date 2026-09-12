# Homelab Hardening Baseline

A reproducible security baseline for a small Proxmox VE + LXC fleet, plus the tooling to prove it is still in effect.

## What it is

Six guests on one hypervisor, running DNS filtering, a VPN, network storage, a dashboard, and two internet-facing game servers. This repo is the access-control and hardening standard applied across all of them, written as config and scripts rather than as a wiki page nobody rereads.

The part I care about most is `scripts/verify-baseline.sh`. Applying a baseline is easy. Knowing it is still applied three months later is the actual problem.

## Why I built it

I hardened these hosts once, wrote it down, and later found the configuration had reverted on at least one of them without anything failing loudly. Nothing broke. SSH still worked. The documentation still said "hardened." The only thing that had changed was that it wasn't true anymore.

That is the failure mode this repo exists for. A security control that silently stops applying is worse than one you never had, because you stop checking.

So the baseline ships in two halves:

- **`harden-container.sh`** applies it, idempotently, refusing to reload a broken SSH config.
- **`verify-baseline.sh`** reads the *effective* state back and exits non-zero when reality and intent disagree.

## What it demonstrates

- **Blast radius reduction.** One shared SSH key across the fleet meant one compromised key reached every host. Replaced with one key per container, then verified the retired key was actually refused everywhere rather than assuming the rotation took. See [`docs/ssh-key-model.md`](docs/ssh-key-model.md).
- **Least privilege over convenience.** The VPN ran an allow-all policy, which was fine while every device belonged to me and stopped being fine the moment one didn't. Rewritten as explicit grants. See [`docs/access-control.md`](docs/access-control.md).
- **Verification as a first-class step.** Every control here has a check that reads effective state, not file contents. `sshd -T` over `grep sshd_config`, because a drop-in file that is never included looks perfect and does nothing.
- **Recovery you have tested.** Scheduled backups across separate physical disks, plus a written restore procedure that has actually been run. An untested backup is a hypothesis. See [`docs/backups.md`](docs/backups.md).
- **Documented failure modes.** The traps that cost me real time, written down so they cost me less next time. See [`docs/failure-modes.md`](docs/failure-modes.md).

## Incident write-ups

Two things that went wrong, what the symptoms looked like, and what I changed afterwards.

- [**A VPN exit node eating 40% of my download**](writeups/exit-node-bandwidth.md) - 491 Mbps on an 800/40 line. The cause was two layers above the NIC I spent two hours tuning, and `tracert` found it in four seconds.
- [**Access review: my VPN was allow-all**](writeups/vpn-access-review.md) - what a default policy granted a guest account, and why tightening it broke DNS everywhere the moment I saved it.

## Layout

```
ssh/          sshd drop-in config, plus why a drop-in and not an edit
fail2ban/     sshd jail
firewall/     default-deny ufw baseline
tailscale/    VPN access policy, allow-all rewritten as explicit grants
backup/       restore verification procedure
scripts/      harden-container.sh (apply), verify-baseline.sh (check)
docs/         the reasoning behind each decision
```

## Usage

Both scripts are safe to read before you run them, and neither changes anything unless you ask.

```bash
# Check a host against the baseline. Read-only. Exit 0 = compliant, 1 = drift.
sudo ./scripts/verify-baseline.sh

# Show what applying the baseline would change, without changing it.
sudo ./scripts/harden-container.sh --user svcadmin --key ~/.ssh/id_ed25519.pub

# Actually apply it.
sudo ./scripts/harden-container.sh --user svcadmin --key ~/.ssh/id_ed25519.pub --apply
```

`harden-container.sh` is dry-run by default on purpose. A hardening script that locks you out of a machine on first run because you typed the wrong username is not a hardening script.

**Keep a second root session open the first time you apply this to a host.** The script validates the SSH config with `sshd -t` before reloading and aborts if validation fails, but that protects against a malformed config, not against you excluding your own account from `AllowUsers`.

## Scope and honesty

This is a homelab standard, not an enterprise one. Specifically missing, and known to be missing:

- No centralized logging or alerting. Every host bans intruders locally and tells no one. This is the next thing I am building, and it is the real gap.
- No host-based intrusion detection or file integrity monitoring.
- No secrets manager. Keys live on disk, protected by full-disk encryption on the client.
- Backups are cross-disk on one machine, not off-site. A fire or a controller failure takes both copies.

Addresses, hostnames, usernames, and ports in this repo are placeholders. Nothing here is a live configuration.

## License

MIT. See [LICENSE](LICENSE).
