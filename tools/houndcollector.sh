#!/bin/sh
# HoundCollector.sh  -  RootHound's own collector
#
# Runs on the TARGET as your low-priv user. Gathers exactly the raw signals
# RootHound's rulebook reasons about, and prints them as clean JSON.
# No LinPEAS needed. Portable /bin/sh, no dependencies beyond coreutils.
#
#   ./HoundCollector.sh > loot.json      # on the target
#   # copy loot.json back, then on YOUR box:
#   python3 RootHound.py loot.json -o report.html
#
# Why this exists: when we parse LinPEAS we only see what LinPEAS collects,
# and we fight its text format. Collecting ourselves means new misconfigs are
# just "one more line here + one rulebook entry" - and parsing is trivial JSON.

# ---- tiny JSON helpers (POSIX sh, no jq) ----
esc() { sed 's/\\/\\\\/g; s/"/\\"/g'; }          # escape \ and "
arr() {                                           # stdin lines -> ["a","b"]
  printf '['
  first=1
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    e=$(printf '%s' "$l" | esc)
    if [ "$first" = 1 ]; then printf '"%s"' "$e"; first=0
    else printf ',"%s"' "$e"; fi
  done
  printf ']'
}

# ---- basics ----
USER_=$(id -un 2>/dev/null)
GROUPS_=$(id -Gn 2>/dev/null | tr ' ' '\n' | arr)
KERNEL_=$(uname -r 2>/dev/null)
SUDOVER_=$(sudo --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[p0-9]*' | head -1)

# ---- sudo -l (non-interactive: never prompts / locks the account) ----
SUDO_OUT=$(sudo -n -l 2>/dev/null)
if printf '%s' "$SUDO_OUT" | grep -qE '\(ALL( *: *ALL)?\) *ALL'; then SUDO_ALL=true; else SUDO_ALL=false; fi
if printf '%s' "$SUDO_OUT" | grep -qiE 'env_keep.*(ld_preload|ld_library_path)'; then LDP=true; else LDP=false; fi
SUDO_BINS=$(printf '%s' "$SUDO_OUT" \
  | grep -vE 'Defaults|secure_path|Matching|may run|env_' \
  | grep -oE '/[^ ,]+' | arr)

# ---- SUID / SGID ----
SUID_=$(find / -perm -4000 -type f 2>/dev/null | arr)
SGID_=$(find / -perm -2000 -type f 2>/dev/null | arr)

# ---- capabilities ----  (getcap output: "/path cap_x+ep" or "/path = cap_x+ep")
CAPS_=$(
  printf '['
  first=1
  getcap -r / 2>/dev/null | while IFS= read -r line; do
    p=$(printf '%s' "$line" | awk '{print $1}')
    c=$(printf '%s' "$line" | grep -oE 'cap_[a-z_]+' | head -1)
    [ -z "$c" ] && continue
    pe=$(printf '%s' "$p" | esc)
    if [ "$first" = 1 ]; then printf '["%s","%s"]' "$pe" "$c"; first=0
    else printf ',["%s","%s"]' "$pe" "$c"; fi
  done
  printf ']'
)

# ---- writable sensitive files & dirs ----
WR=""
for t in /etc/passwd /etc/shadow /etc/sudoers /etc/ld.so.preload /etc/crontab /etc/profile /root; do
  [ -w "$t" ] && WR="$WR$t\n"
done
for d in /etc/sudoers.d /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/systemd/system; do
  [ -w "$d" ] && WR="$WR$d\n"
done
WRITABLE_=$(printf "$WR" | arr)

# ---- writable systemd units ----
SVC_=$(find /etc/systemd/system /lib/systemd/system /run/systemd/system -name '*.service' -writable 2>/dev/null | arr)

# ---- root cron jobs (crontab + cron.d) ----
CRON_=$(
  { cat /etc/crontab 2>/dev/null; cat /etc/cron.d/* 2>/dev/null; } \
  | grep -E '^\s*([0-9*/,-]+\s+){5}root\s+/|^\s*@\w+\s+root\s+/' \
  | grep -oE '/[^ ]+$' | arr
)

# ---- NFS no_root_squash ----
NFS_=$(grep -v '^#' /etc/exports 2>/dev/null | grep 'no_root_squash' | awk '{print $1}' | arr)

# ---- writable dirs in PATH (PATH hijack) ----
PATHHJ=""
old_ifs=$IFS; IFS=:
for d in $PATH; do
  [ -n "$d" ] && [ -w "$d" ] && PATHHJ="$PATHHJ$d\n"
done
IFS=$old_ifs
PATH_HIJACK_=$(printf "$PATHHJ" | arr)

# ---- writable docker socket (same power as docker group) ----
DOCK=""
[ -S /var/run/docker.sock ] && [ -w /var/run/docker.sock ] && DOCK="docker.sock"

# ---- emit JSON ----
cat <<JSON
{
  "_collector": "HoundCollector",
  "user": "$(printf '%s' "$USER_" | esc)",
  "groups": $GROUPS_,
  "kernel": "$(printf '%s' "$KERNEL_" | esc)",
  "sudo_version": "$(printf '%s' "$SUDOVER_" | esc)",
  "sudo_all": $SUDO_ALL,
  "ld_preload": $LDP,
  "docker_sock": "$DOCK",
  "sudo": $SUDO_BINS,
  "suid": $SUID_,
  "sgid": $SGID_,
  "caps": $CAPS_,
  "cron": $CRON_,
  "writable": $WRITABLE_,
  "writable_systemd": $SVC_,
  "nfs": $NFS_,
  "path_hijack": $PATH_HIJACK_
}
JSON
