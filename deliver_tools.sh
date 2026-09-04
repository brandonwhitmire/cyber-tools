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

# --- IP detection -----------------------------------------------------------

is_wildcard_ip() {
  case "$1" in
    0.0.0.0|::|\*|all) return 0 ;;
    *) return 1 ;;
  esac
}

is_loopback_ip() {
  case "$1" in
    127.*|::1|1.0.0.*) return 0 ;;
    *) return 1 ;;
  esac
}

# GLOBAL_IPS: "ifname=addr" pairs, global-scope IPv4 only.
collect_global_ips() {
  GLOBAL_IPS=()
  local line iface cidr addr
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    iface="${line%% *}"
    cidr="${line#* }"
    addr="${cidr%%/*}"
    is_loopback_ip "$addr" && continue
    GLOBAL_IPS+=("${iface}=${addr}")
  done < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2,$4}')
}

default_route_ip() {
  local addr
  addr="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
  if [[ -n "$addr" ]] && ! is_loopback_ip "$addr"; then
    printf '%s' "$addr"
    return 0
  fi
  return 1
}

# CONNECT_IP: address clients dial (never 0.0.0.0).
resolve_connect_ip() {
  local addr pair

  if [[ -n "${CONNECT_IP:-}" ]]; then
    printf '%s' "$CONNECT_IP"
    return 0
  fi

  if ! is_wildcard_ip "$SERVER_IP"; then
    printf '%s' "$SERVER_IP"
    return 0
  fi

  if addr="$(default_route_ip)"; then
    printf '%s' "$addr"
    return 0
  fi

  if ((${#GLOBAL_IPS[@]} > 0)); then
    pair="${GLOBAL_IPS[0]}"
    printf '%s' "${pair#*=}"
    return 0
  fi

  addr="$(hostname -I 2>/dev/null | tr ' ' '\n' | awk 'NF && $1 !~ /^127\./ && $1 !~ /^1\.0\.0\./ { print $1; exit }')"
  if [[ -n "$addr" ]]; then
    printf '%s' "$addr"
    return 0
  fi

  printf '%s' "<IP>"
}

other_ips_line() {
  local pair iface addr out=""
  for pair in "${GLOBAL_IPS[@]+"${GLOBAL_IPS[@]}"}"; do
    iface="${pair%%=*}"
    addr="${pair#*=}"
    [[ "$addr" == "$1" ]] && continue
    out+="${iface}=${addr}  "
  done
  printf '%s' "$out"
}

banner_extra_line() {
  if [[ -n "$(other_ips_line "$1")" ]]; then
    return 0
  fi
  [[ "$1" == "<IP>" ]]
}

# --- terminal + table -------------------------------------------------------

term_size() {
  local size
  if [[ -n "${LINES:-}" && -n "${COLUMNS:-}" ]]; then
    TERM_LINES="$LINES"
    TERM_COLS="$COLUMNS"
  elif size="$(stty size < /dev/tty 2>/dev/null)"; then
    TERM_LINES="${size% *}"
    TERM_COLS="${size#* }"
  else
    TERM_LINES=24
    TERM_COLS=80
  fi
  if ! [[ "$TERM_LINES" =~ ^[0-9]+$ ]] || ((TERM_LINES < 12)); then
    TERM_LINES=24
  fi
  if ! [[ "$TERM_COLS" =~ ^[0-9]+$ ]] || ((TERM_COLS < 40)); then
    TERM_COLS=80
  fi
}

fit_cell() {
  local s=$1 w=$2
  if ((${#s} <= w)); then
    printf '%s' "$s"
    return
  fi
  if ((w <= 3)); then
    printf '%s' "${s:0:w}"
    return
  fi
  printf '%s' "${s:0:$((w - 3))}..."
}

# Column-major ASCII table. Prefer full names; add columns (and truncate)
# only to try to fit TERM_LINES. Never shrink cells below min_inner.
print_file_table() {
  local reserved=$1
  shift
  local items=("$@")
  local n=${#items[@]}

  if ((n == 0)); then
    echo "(no files in ${SERVE_DIR})"
    return 0
  fi

  local maxw=0 i
  for ((i = 0; i < n; i++)); do
    if ((${#items[i]} > maxw)); then
      maxw=${#items[i]}
    fi
  done

  local min_inner=20
  if ((min_inner > maxw)); then
    min_inner=$maxw
  fi

  local max_cols=$(((TERM_COLS - 1) / (min_inner + 3)))
  if ((max_cols < 1)); then
    max_cols=1
  fi
  local full_cols=$(((TERM_COLS - 1) / (maxw + 3)))
  if ((full_cols < 1)); then
    full_cols=1
  fi

  local budget=$((TERM_LINES - reserved - 2))
  if ((budget < 1)); then
    budget=1
  fi

  local n_cols=$full_cols
  local inner=$maxw
  local data_rows=$(((n + n_cols - 1) / n_cols))
  local c try_inner try_rows

  if ((data_rows > budget)); then
    for ((c = full_cols + 1; c <= max_cols; c++)); do
      try_inner=$(((TERM_COLS - 1) / c - 3))
      if ((try_inner > maxw)); then
        try_inner=$maxw
      fi
      if ((try_inner < min_inner)); then
        try_inner=$min_inner
      fi
      try_rows=$(((n + c - 1) / c))
      n_cols=$c
      inner=$try_inner
      data_rows=$try_rows
      if ((data_rows <= budget)); then
        break
      fi
    done
  fi

  local rule="" c
  rule="+"
  for ((c = 0; c < n_cols; c++)); do
    rule+="$(printf '%*s' $((inner + 2)) '' | tr ' ' '-')"
    rule+="+"
  done
  echo "$rule"

  local r idx cell line
  for ((r = 0; r < data_rows; r++)); do
    line="|"
    for ((c = 0; c < n_cols; c++)); do
      idx=$((c * data_rows + r))
      cell=""
      if ((idx < n)); then
        cell="$(fit_cell "${items[idx]}" "$inner")"
      fi
      printf -v line '%s %-*s |' "$line" "$inner" "$cell"
    done
    echo "$line"
  done
  echo "$rule"
}

list_serve_entries() {
  local path base
  SERVE_ENTRIES=()
  while IFS= read -r -d '' path; do
    base="$(basename "$path")"
    [[ "$base" == .* ]] && continue
    if [[ -d "$path" ]]; then
      SERVE_ENTRIES+=("${base}/")
    else
      SERVE_ENTRIES+=("$base")
    fi
  done < <(find "$SERVE_DIR" -mindepth 1 -maxdepth 1 -print0 | LC_ALL=C sort -z)
}

# --- banner + pastables -----------------------------------------------------

box_line() {
  local width=$1
  shift
  printf '| %-*.*s |\n' $((width - 4)) $((width - 4)) "$*"
}

print_connect_banner() {
  local connect_ip=$1
  local smb_ok=$2
  local extra
  local http_url="http://${connect_ip}:${HTTP_PORT}"
  local win_unc="\\\\${connect_ip}\\${SMB_SHARE}"
  local width=$TERM_COLS
  local rule

  if ((width > 100)); then
    width=100
  fi
  rule="+$(printf '%*s' $((width - 2)) '' | tr ' ' '-')+"

  echo "$rule"
  box_line "$width" "HTTP  ${http_url}/"
  if [[ "$smb_ok" == "1" ]]; then
    box_line "$width" "SMB   ${win_unc}  port ${SMB_PORT}  user:${SMB_USER}  pass:${SMB_PASS}"
  else
    box_line "$width" "SMB   (not running — HTTP only)"
  fi
  box_line "$width" "bind  ${SERVER_IP}:${HTTP_PORT}  smb:${SMB_PORT}  files:${#SERVE_ENTRIES[@]}"
  extra="$(other_ips_line "$connect_ip")"
  if [[ -n "$extra" ]]; then
    box_line "$width" "also  ${extra}CONNECT_IP=... to pin"
  elif [[ "$connect_ip" == "<IP>" ]]; then
    box_line "$width" "set CONNECT_IP=<reachable-ipv4> — none detected"
  fi
  echo "$rule"
}

print_pastables() {
  local connect_ip=$1
  local http_url="http://${connect_ip}:${HTTP_PORT}"
  local win_unc="\\\\${connect_ip}\\${SMB_SHARE}"
  local smb_unc="//${connect_ip}/${SMB_SHARE}"

  echo "wget ${http_url}/FILE -O FILE"
  echo "wget ${http_url}/FILE -outfile FILE"
  echo "net use ${win_unc} /user:${SMB_USER} ${SMB_PASS}"
  echo "copy ${win_unc}\\FILE ."
  echo "smbclient ${smb_unc} -p ${SMB_PORT} -U ${SMB_USER}%${SMB_PASS} -c 'get FILE'"
  echo "replace FILE with a name from the table  |  Ctrl+C to stop"
}

# Banner + pastables + blanks. Table is last and may scroll.
reserved_lines() {
  local extra=0
  if banner_extra_line "$1"; then
    extra=1
  fi
  echo $((5 + extra + 1 + 6 + 1))
}

# --- servers ----------------------------------------------------------------

HTTP_PID=""
SMB_PID=""
TAIL_PID=""
HTTP_LOG=""
SMB_LOG=""
SMB_STARTED=0

cleanup() {
  local pid
  for pid in "${TAIL_PID:-}" "${HTTP_PID:-}" "${SMB_PID:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  [[ -n "${HTTP_LOG:-}" ]] && rm -f "$HTTP_LOG"
  [[ -n "${SMB_LOG:-}" ]] && rm -f "$SMB_LOG"
}
trap cleanup EXIT INT TERM

start_http() {
  command -v python3 >/dev/null 2>&1 || die "python3 required for HTTP server"
  HTTP_LOG="$(mktemp -t deliver-http.XXXXXX)"
  (cd "$SERVE_DIR" && PYTHONUNBUFFERED=1 python3 -m http.server "$HTTP_PORT" --bind "$SERVER_IP") \
    >"$HTTP_LOG" 2>&1 &
  HTTP_PID=$!
  sleep 0.2
  if ! kill -0 "$HTTP_PID" 2>/dev/null; then
    cat "$HTTP_LOG" >&2 || true
    die "HTTP server failed to start on ${SERVER_IP}:${HTTP_PORT}"
  fi
}

start_smb() {
  local smb_cmd=()
  SMB_LOG="$(mktemp -t deliver-smb.XXXXXX)"

  if command -v impacket-smbserver >/dev/null 2>&1; then
    smb_cmd=(impacket-smbserver "$SMB_SHARE" "$SERVE_DIR" -smb2support
      -username "$SMB_USER" -password "$SMB_PASS" -ip "$SERVER_IP" -port "$SMB_PORT")
  elif command -v smbserver.py >/dev/null 2>&1; then
    smb_cmd=(smbserver.py "$SMB_SHARE" "$SERVE_DIR" -smb2support
      -username "$SMB_USER" -password "$SMB_PASS" -ip "$SERVER_IP" -port "$SMB_PORT")
  elif python3 -c "import impacket.examples.smbserver" 2>/dev/null; then
    smb_cmd=(python3 -m impacket.examples.smbserver "$SMB_SHARE" "$SERVE_DIR" -smb2support
      -username "$SMB_USER" -password "$SMB_PASS" -ip "$SERVER_IP" -port "$SMB_PORT")
  else
    log "WARN: impacket smbserver not found — HTTP only (install: pip install impacket)"
    SMB_STARTED=0
    return 0
  fi

  "${smb_cmd[@]}" >"$SMB_LOG" 2>&1 &
  SMB_PID=$!
  sleep 0.3
  if ! kill -0 "$SMB_PID" 2>/dev/null; then
    log "WARN: SMB server failed to start on ${SERVER_IP}:${SMB_PORT} (need root for 445?)"
    cat "$SMB_LOG" >&2 || true
    SMB_PID=""
    SMB_STARTED=0
    return 0
  fi
  SMB_STARTED=1
}

follow_logs() {
  local files=()
  [[ -n "$HTTP_LOG" && -f "$HTTP_LOG" ]] && files+=("$HTTP_LOG")
  [[ -n "$SMB_LOG" && -f "$SMB_LOG" && "$SMB_STARTED" == "1" ]] && files+=("$SMB_LOG")
  ((${#files[@]} > 0)) || return 0
  tail -n 0 -f "${files[@]}" &
  TAIL_PID=$!
}

print_ui() {
  local connect_ip=$1
  local smb_ok=$2
  local reserved
  reserved="$(reserved_lines "$connect_ip" "$smb_ok")"
  print_connect_banner "$connect_ip" "$smb_ok"
  echo
  print_pastables "$connect_ip" "$smb_ok"
  echo
  print_file_table "$reserved" "${SERVE_ENTRIES[@]}"
}

# --- main -------------------------------------------------------------------

collect_global_ips
CONNECT_IP="$(resolve_connect_ip)"
list_serve_entries
term_size

if [[ "${DRY_RUN:-}" == "1" ]]; then
  print_ui "$CONNECT_IP" "1"
  exit 0
fi

start_http
start_smb
print_ui "$CONNECT_IP" "$SMB_STARTED"
echo
follow_logs
wait "$HTTP_PID"
