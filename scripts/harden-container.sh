#!/usr/bin/env bash
#
# harden-container.sh - apply the SSH / fail2ban / firewall baseline to a
# fresh Debian or Ubuntu LXC container.
#
# Dry-run by default. Nothing changes without --apply.
#
# Usage:
#   sudo ./harden-container.sh --user svcadmin --key ~/.ssh/id_ed25519.pub
#   sudo ./harden-container.sh --user svcadmin --key ~/.ssh/id_ed25519.pub --apply
#   sudo ./harden-container.sh --user svcadmin --key key.pub --port 2222 --apply
#
# Keep a second root session open the first time you run this against a host.
# The script refuses to reload a config that `sshd -t` rejects, but that does
# not protect you from locking yourself out with a correct-but-wrong AllowUsers.

set -euo pipefail

USER_NAME=""
PUBKEY_FILE=""
SSH_PORT="2222"
APPLY=0

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --user)  USER_NAME="${2:?--user needs a value}"; shift 2 ;;
        --key)   PUBKEY_FILE="${2:?--key needs a value}"; shift 2 ;;
        --port)  SSH_PORT="${2:?--port needs a value}"; shift 2 ;;
        --apply) APPLY=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "unknown argument: $1" >&2; usage 2 ;;
    esac
done

# Validate arguments before checking for root, so a typo reports a useful
# error instead of "run as root".
[ -n "$USER_NAME" ]  || { echo "--user is required" >&2; exit 2; }
[ -n "$PUBKEY_FILE" ] || { echo "--key is required" >&2; exit 2; }
[ -r "$PUBKEY_FILE" ] || { echo "cannot read key file: $PUBKEY_FILE" >&2; exit 2; }

# Reject anything that is not a public key before it reaches authorized_keys.
if ! grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+) ' "$PUBKEY_FILE"; then
    echo "$PUBKEY_FILE does not look like an SSH public key" >&2
    exit 2
fi
if grep -q 'PRIVATE KEY' "$PUBKEY_FILE"; then
    echo "$PUBKEY_FILE is a PRIVATE key. Pass the .pub file." >&2
    exit 2
fi

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 2; }

run() {
    if [ "$APPLY" -eq 1 ]; then
        "$@"
    else
        printf '  would run: %s\n' "$*"
    fi
}

say() { printf '\n== %s\n' "$1"; }

[ "$APPLY" -eq 1 ] || printf 'DRY RUN - nothing will change. Re-run with --apply.\n'

# ---------------------------------------------------------------------------
say "Admin user: $USER_NAME"

if id "$USER_NAME" >/dev/null 2>&1; then
    printf '  %s already exists\n' "$USER_NAME"
else
    run useradd --create-home --shell /bin/bash "$USER_NAME"
fi

# sudo group name differs: Debian/Ubuntu use sudo, RHEL-likes use wheel.
admin_group=sudo
getent group sudo >/dev/null 2>&1 || admin_group=wheel
run usermod -aG "$admin_group" "$USER_NAME"

home_dir="$(getent passwd "$USER_NAME" | cut -d: -f6)"
home_dir="${home_dir:-/home/$USER_NAME}"
run install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$home_dir/.ssh"

pubkey="$(cat "$PUBKEY_FILE")"
auth_keys="$home_dir/.ssh/authorized_keys"
if [ -f "$auth_keys" ] && grep -qF "$pubkey" "$auth_keys" 2>/dev/null; then
    printf '  key already authorized for %s\n' "$USER_NAME"
elif [ "$APPLY" -eq 1 ]; then
    printf '%s\n' "$pubkey" >> "$auth_keys"
    chown "$USER_NAME:$USER_NAME" "$auth_keys"
    chmod 600 "$auth_keys"
    printf '  key added to %s\n' "$auth_keys"
else
    printf '  would append key to %s\n' "$auth_keys"
fi

# ---------------------------------------------------------------------------
say "SSH daemon"

# A drop-in rather than an edit to sshd_config, so a package upgrade that
# replaces the main file does not silently take the hardening with it.
# That only works if the main config actually includes the directory -
# check, do not assume.
dropin=/etc/ssh/sshd_config.d/10-hardening.conf

if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
    printf '  sshd_config has no Include for sshd_config.d - a drop-in would be ignored\n'
    if [ "$APPLY" -eq 1 ]; then
        cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
        printf '  added Include directive (original backed up)\n'
    else
        printf '  would add the Include directive and back up the original\n'
    fi
fi

if [ "$APPLY" -eq 1 ]; then
    install -d -m 755 /etc/ssh/sshd_config.d
    cat > "$dropin" <<EOF
# Managed by harden-container.sh. Edit the repo, not this file.
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers $USER_NAME
MaxAuthTries 3
LoginGraceTime 20
X11Forwarding no
AllowAgentForwarding no
PermitEmptyPasswords no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    chmod 644 "$dropin"
    printf '  wrote %s\n' "$dropin"
else
    printf '  would write %s (port %s, root login off, key-only, AllowUsers %s)\n' \
        "$dropin" "$SSH_PORT" "$USER_NAME"
fi

# Validate before reload. A bad config plus a reload is how you lose a host
# that has no console.
if [ "$APPLY" -eq 1 ]; then
    if sshd -t; then
        printf '  sshd -t OK\n'
        systemctl reload ssh 2>/dev/null || systemctl reload sshd
        printf '  sshd reloaded\n'
    else
        printf '  sshd -t FAILED - removing the drop-in and leaving sshd untouched\n' >&2
        rm -f "$dropin"
        exit 1
    fi
else
    printf '  would validate with sshd -t, then reload only if it passes\n'
fi

# ---------------------------------------------------------------------------
say "fail2ban"

if ! command -v fail2ban-client >/dev/null 2>&1; then
    run apt-get update -qq
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban
fi

if [ "$APPLY" -eq 1 ]; then
    install -d -m 755 /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled  = true
port     = $SSH_PORT
backend  = systemd
maxretry = 3
findtime = 10m
bantime  = 1h
# Escalating bans: a repeat offender earns a longer one.
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 1w
EOF
    systemctl enable --now fail2ban
    systemctl restart fail2ban
    printf '  sshd jail installed on port %s\n' "$SSH_PORT"
else
    printf '  would install the sshd jail on port %s with escalating bantime\n' "$SSH_PORT"
fi

# ---------------------------------------------------------------------------
say "Firewall"

if ! command -v ufw >/dev/null 2>&1; then
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw
fi

# Order matters. Allow SSH before enabling, or enabling ends the session.
run ufw default deny incoming
run ufw default allow outgoing
run ufw allow "$SSH_PORT/tcp" comment 'ssh'
if [ "$APPLY" -eq 1 ]; then
    ufw --force enable
else
    printf '  would enable ufw (after the allow rule above, not before)\n'
fi

# ---------------------------------------------------------------------------
say "Unattended security updates"

if [ "$APPLY" -eq 1 ]; then
    env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    printf '  unattended-upgrades enabled\n'
else
    printf '  would install and enable unattended-upgrades\n'
fi

# ---------------------------------------------------------------------------
if [ "$APPLY" -eq 1 ]; then
    printf '\nDone. Verify from a NEW session before closing this one:\n'
    printf '  ssh -p %s %s@<host>\n' "$SSH_PORT" "$USER_NAME"
    printf '  sudo ./verify-baseline.sh\n'
else
    printf '\nDry run complete. Re-run with --apply to make these changes.\n'
fi
