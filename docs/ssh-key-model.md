# SSH key model

## The problem

The fleet started with one key authorized on every host. Convenient, and it meant a single compromised private key reached all of them. The key was also misleadingly named after the first service it was created for, so its actual scope was not obvious from the filename.

Blast radius of one stolen laptop: everything.

## The model now

**One key per host.** Each container authorizes exactly one key, named for the container. A compromised key reaches one machine.

```
~/.ssh/
├── config                 # aliases, so you connect by name, not by IP
├── lab_dns                # one key ...
├── lab_vpn                # ... per ...
├── lab_nas                # ... host
└── retired-YYYY-MM-DD/    # rotated-out keys, kept until proven dead
```

Client config, so nobody types an address:

```sshconfig
Host lab-dns
    HostName 192.0.2.10
    Port 2222
    User svcadmin
    IdentityFile ~/.ssh/lab_dns
    IdentitiesOnly yes
```

`IdentitiesOnly yes` matters more than it looks. Without it, SSH offers every key it knows about, in order, and three rejected offers trip fail2ban before the correct key is ever tried.

Keys are ed25519 with no passphrase, because unattended jobs need them. That tradeoff is only acceptable because the client disk is encrypted at rest. On a machine without full-disk encryption, use a passphrase and an agent.

## Rotation is not done when the new key works

The new key working proves nothing about the old one. Both work, right up until you check.

Rotation is complete when the **retired key is refused** by every host:

```bash
for host in lab-dns lab-vpn lab-nas; do
    printf '%-12s ' "$host"
    ssh -i ~/.ssh/retired-2026-01-01/old_key \
        -o IdentitiesOnly=yes \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        "svcadmin@$host" true 2>&1 | tail -1
done
```

Expect `Permission denied (publickey)` from every host. Anything else is an incomplete rotation.

Do this slowly or from a host in `ignoreip`, because a loop of deliberately failing authentications is indistinguishable from an attack and fail2ban will treat it as one.

## Orphaned keys in root's authorized_keys

Rotating user keys does not touch `root`. Audit separately:

```bash
for host in lab-dns lab-vpn lab-nas; do
    echo "== $host"
    ssh "$host" 'sudo cat /root/.ssh/authorized_keys 2>/dev/null | grep -v "^#" | awk "{print \$3}"'
done
```

An entry here is only exploitable if that host also permits root login, so check both together. A key listed under `PermitRootLogin no` is inert, which explains the otherwise confusing result of a key that is clearly present and still refused. Remove them anyway. Inert today is a configuration change away from live.

`verify-baseline.sh` reports this pairing rather than flagging the key alone.
