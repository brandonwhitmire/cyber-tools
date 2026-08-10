#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${ROOT}/tools"

log() { echo "[sync_extras] $*" >&2; }

log "syncing vendored tools..."
if ! "${ROOT}/sync_tools.sh" "${ROOT}/sync.json"; then
  log "WARN: sync failed (GitHub rate limit?); continuing with extras for already-vendored tools"
fi

log "fetching AccessChk from Sysinternals (official source)..."
/usr/bin/curl -fsSL -o "${TOOLS_DIR}/accesschk.exe" "https://live.sysinternals.com/accesschk.exe"
/usr/bin/curl -fsSL -o "${TOOLS_DIR}/accesschk64.exe" "https://live.sysinternals.com/accesschk64.exe"

python_archive="$(find "${TOOLS_DIR}" -maxdepth 1 -name 'cpython-*-install_only.tar.gz' -print -quit 2>/dev/null || true)"
if [[ -n "${python_archive}" ]]; then
  log "extracting portable Windows Python into tools/python/..."
  rm -rf "${TOOLS_DIR}/python"
  tar -xzf "${python_archive}" -C "${TOOLS_DIR}"
fi

log "setting execute bits on scripts and Linux binaries..."
find "${TOOLS_DIR}" -maxdepth 1 -type f \( \
  -name '*.sh' -o \
  -name 'pspy32' -o -name 'pspy64' -o \
  -name 'kerbrute_linux_amd64' -o \
  -name 'linpeas.sh' -o -name 'lse.sh' -o \
  -name 'nc-x64' -o -name 'nc-x86' -o \
  -name 'socat' -o -name 'nmap' -o \
  -name 'smtp-user-enum.py' -o \
  -name 'roothound-collector.sh' -o -name 'pretender' -o -name 'bloodhound-cli' \
\) -exec chmod +x {} + 2>/dev/null || true

chmod +x "${ROOT}/sync_tools.sh" "${ROOT}/deliver_tools.sh" "${ROOT}/sync_extras.sh" 2>/dev/null || true

log "sync_extras complete"
log "  tools:     ${TOOLS_DIR}/"
log "  accesschk: ${TOOLS_DIR}/accesschk.exe , ${TOOLS_DIR}/accesschk64.exe"
log "  deliver:   ${ROOT}/deliver_tools.sh"
