#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVE_DIR="${SERVE_DIR:-${ROOT}/tools}"
SERVER_IP="${SERVER_IP:-0.0.0.0}"
HTTP_PORT="${HTTP_PORT:-8080}"
SMB_PORT="${SMB_PORT:-445}"
SMB_SHARE="${SMB_SHARE:-tools}"
SMB_USER="${SMB_USER:-guest}"
SMB_PASS="${SMB_PASS:-guest}"

log() { echo "[deliver_tools] $*" >&2; }
die() { echo "[deliver_tools] ERROR: $*" >&2; exit 1; }

[[ -d "$SERVE_DIR" ]] || die "serve directory not found: $SERVE_DIR"

cleanup() {
  local pid
  for pid in "${HTTP_PID:-}" "${SMB_PID:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

start_http() {
  if command -v python3 >/dev/null 2>&1; then
    log "HTTP  http://${SERVER_IP}:${HTTP_PORT}/  (root: ${SERVE_DIR})"
    (cd "$SERVE_DIR" && python3 -m http.server "$HTTP_PORT" --bind "$SERVER_IP") &
    HTTP_PID=$!
    return 0
  fi
  die "python3 required for HTTP server"
}

start_smb() {
  local smb_cmd=()

  if command -v impacket-smbserver >/dev/null 2>&1; then
    smb_cmd=(impacket-smbserver "$SMB_SHARE" "$SERVE_DIR" -smb2support -username "$SMB_USER" -password "$SMB_PASS" -ip "$SERVER_IP")
  elif command -v smbserver.py >/dev/null 2>&1; then
    smb_cmd=(smbserver.py "$SMB_SHARE" "$SERVE_DIR" -smb2support -username "$SMB_USER" -password "$SMB_PASS" -ip "$SERVER_IP")
  elif python3 -c "import impacket.examples.smbserver" 2>/dev/null; then
    smb_cmd=(python3 -m impacket.examples.smbserver "$SMB_SHARE" "$SERVE_DIR" -smb2support -username "$SMB_USER" -password "$SMB_PASS" -ip "$SERVER_IP")
  else
    log "WARN: impacket smbserver not found — HTTP only (install: pip install impacket)"
    return 0
  fi

  log "SMB   \\\\$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)\\${SMB_SHARE}  (bind: ${SERVER_IP}, user: ${SMB_USER}, pass: ${SMB_PASS})"
  "${smb_cmd[@]}" &
  SMB_PID=$!
}

log "starting staging server..."
start_http
start_smb
log "press Ctrl+C to stop"
wait
