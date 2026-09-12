#!/usr/bin/env bash
#
# verify-baseline.sh - read the EFFECTIVE security state of a host and compare
# it to the baseline. Read-only. Changes nothing.
#
# Exit 0 = compliant, 1 = drift found, 2 = could not run the checks.
#
# The point of this script is that it reads effective state, not files.
# `grep PermitRootLogin /etc/ssh/sshd_config` tells you what someone wrote.
# `sshd -T` tells you what sshd is actually doing. Those differ more often
# than you would like, and every time they have differed on my fleet, the
# file looked correct and the daemon did not.
#
# Usage:
#   sudo ./verify-baseline.sh
#   SSH_PORT=2222 ADMIN_USER=svcadmin sudo -E ./verify-baseline.sh
#   sudo ./verify-baseline.sh --quiet     # only failures and the summary

set -u

SSH_PORT="${SSH_PORT:-2222}"
ADMIN_USER="${ADMIN_USER:-svcadmin}"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

pass=0; fail=0; warn=0

ok()   { pass=$((pass+1)); [ "$QUIET" -eq 1 ] || printf '  PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note() { warn=$((warn+1)); [ "$QUIET" -eq 1 ] || printf '  WARN  %s\n' "$1"; }
head_() { [ "$QUIET" -eq 1 ] || printf '\n%s\n' "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sshd -T and /etc/shadow both need it." >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# SSH daemon - effective config, not the file
# ---------------------------------------------------------------------------
head_ "SSH daemon"

if ! sshd_effective="$(sshd -T 2>/dev/null)"; then
    bad "sshd -T failed: the running config is invalid or sshd is not installed"
    sshd_effective=""
fi

sshd_opt() { printf '%s\n' "$sshd_effective" | awk -v k="$1" '$1==k {print $2; exit}'; }

if [ -n "$sshd_effective" ]; then
    for check in \
        "permitrootlogin:no:root can log in over SSH" \
        "passwordauthentication:no:password auth is enabled" \
        "kbdinteractiveauthentication:no:keyboard-interactive auth is enabled (a second password path)" \
        "pubkeyauthentication:yes:public key auth is disabled"
    do
        key="${check%%:*}"; rest="${check#*:}"
        want="${rest%%:*}"; msg="${rest#*:}"
        got="$(sshd_opt "$key")"
        if [ "$got" = "$want" ]; then
            ok "$key = $want"
        else
            bad "$key = ${got:-unset} (expected $want) - $msg"
        fi
    done

    port_now="$(sshd_opt port)"
    if [ "$port_now" = "$SSH_PORT" ]; then
        ok "port = $SSH_PORT"
    elif [ "$port_now" = "22" ]; then
        note "port = 22 (baseline expects $SSH_PORT; harmless if this host is deliberately on the default)"
    else
        note "port = ${port_now:-unset}, baseline expects $SSH_PORT"
    fi

    allow_users="$(printf '%s\n' "$sshd_effective" | awk '$1=="allowusers" {$1=""; print substr($0,2); exit}')"
    if [ -n "$allow_users" ]; then
        ok "allowusers = $allow_users"
        case " $allow_users " in
            *" $ADMIN_USER "*) : ;;
            *) note "$ADMIN_USER is not in allowusers - confirm that is intended" ;;
        esac
    else
        note "allowusers unset: any account with a key and a shell can authenticate"
    fi
fi

# A drop-in that is never included is the quietest way to be wrong. The file
# looks right, the daemon ignores it, and nothing reports an error.
if [ -d /etc/ssh/sshd_config.d ] && ls /etc/ssh/sshd_config.d/*.conf >/dev/null 2>&1; then
    if grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
        ok "sshd_config.d drop-ins are included by the main config"
    else
        bad "drop-ins exist in /etc/ssh/sshd_config.d but sshd_config has no Include directive - they are being ignored"
    fi
fi

# ---------------------------------------------------------------------------
# Accounts and keys
# ---------------------------------------------------------------------------
head_ "Accounts and keys"

empty_pw="$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null)"
if [ -z "$empty_pw" ]; then
    ok "no accounts with an empty password"
else
    bad "accounts with an empty password: $(echo "$empty_pw" | tr '\n' ' ')"
fi

root_keys=0
[ -s /root/.ssh/authorized_keys ] &&     root_keys="$(grep -cvE '^[[:space:]]*(#|$)' /root/.ssh/authorized_keys 2>/dev/null || echo 0)"
if [ "$root_keys" -gt 0 ]; then
    count="$root_keys"
    if [ "$(sshd_opt permitrootlogin)" = "no" ]; then
        note "root has $count authorized key(s), inert while PermitRootLogin=no - stale entries worth removing"
    else
        bad "root has $count authorized key(s) and root login is not disabled"
    fi
else
    ok "root has no authorized_keys"
fi

for home in /home/*; do
    [ -d "$home" ] || continue
    user="$(basename "$home")"
    ak="$home/.ssh/authorized_keys"
    [ -f "$ak" ] || continue
    perms="$(stat -c '%a' "$ak")"
    case "$perms" in
        600|644) ok "$user authorized_keys perms $perms" ;;
        *)       bad "$user authorized_keys perms $perms (expected 600)" ;;
    esac
done

# Informational: passwordless sudo is a deliberate tradeoff for unattended
# work, not automatically a finding. Report it so the decision stays visible.
if ls /etc/sudoers.d/* >/dev/null 2>&1 && grep -rqs 'NOPASSWD' /etc/sudoers.d/; then
    note "passwordless sudo rules present in /etc/sudoers.d - intended for unattended automation, review scope"
else
    ok "no passwordless sudo rules"
fi

# ---------------------------------------------------------------------------
# fail2ban
# ---------------------------------------------------------------------------
head_ "fail2ban"

if ! command -v fail2ban-client >/dev/null 2>&1; then
    bad "fail2ban is not installed"
elif ! systemctl is-active --quiet fail2ban 2>/dev/null; then
    bad "fail2ban is installed but not running"
else
    ok "fail2ban is running"
    if fail2ban-client status 2>/dev/null | grep -q 'sshd'; then
        banned="$(fail2ban-client status sshd 2>/dev/null | awk -F: '/Currently banned/ {gsub(/[[:space:]]/,"",$2); print $2}')"
        total="$(fail2ban-client status sshd 2>/dev/null | awk -F: '/Total banned/ {gsub(/[[:space:]]/,"",$2); print $2}')"
        ok "sshd jail active (currently banned: ${banned:-0}, total: ${total:-0})"
    else
        bad "fail2ban is running but the sshd jail is not active"
    fi
fi

# ---------------------------------------------------------------------------
# Host firewall
# ---------------------------------------------------------------------------
head_ "Firewall"

if command -v ufw >/dev/null 2>&1; then
    if ufw status verbose 2>/dev/null | grep -q 'Status: active'; then
        ok "ufw is active"
        if ufw status verbose 2>/dev/null | grep -q 'deny (incoming)'; then
            ok "default incoming policy is deny"
        else
            bad "ufw default incoming policy is not deny"
        fi
    else
        bad "ufw is installed but inactive"
    fi
elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q 'hook input'; then
    note "no ufw, but nftables has input rules - verify the policy by hand"
else
    bad "no host firewall found (ufw or nftables)"
fi

# ---------------------------------------------------------------------------
# Patching
# ---------------------------------------------------------------------------
head_ "Updates"

if [ -f /etc/apt/apt.conf.d/20auto-upgrades ] \
   && grep -q '"1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null; then
    ok "unattended-upgrades is configured"
else
    note "unattended-upgrades is not configured - security updates need a human"
fi

# ---------------------------------------------------------------------------
printf '\n%s\n' "-------------------------------------------"
printf 'pass %d   fail %d   warn %d\n' "$pass" "$fail" "$warn"

if [ "$fail" -gt 0 ]; then
    printf 'BASELINE DRIFT on %s\n' "$(hostname)"
    exit 1
fi
printf 'baseline holds on %s\n' "$(hostname)"
exit 0
