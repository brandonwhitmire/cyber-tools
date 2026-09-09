#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${ROOT}/tools"

log() { echo "[sync_extras] $*" >&2; }

log "syncing vendored tools..."
if ! "${ROOT}/sync_tools.sh" "${ROOT}/sync.json"; then
  log "WARN: sync failed (GitHub rate limit?); continuing with extras for already-vendored tools"
fi

log "building offline linpeas_oscp.sh (skip if builder unchanged)..."
if ! "${ROOT}/build_linpeas.sh"; then
  log "WARN: linpeas custom build failed; leaving existing tools/linpeas_oscp.sh"
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
  -name 'linpeas.sh' -o -name 'linpeas_oscp.sh' -o -name 'lse.sh' -o \
  -name 'nc-x64' -o -name 'nc-x86' -o \
  -name 'socat' -o -name 'nmap' -o \
  -name 'smtp-user-enum.py' -o \
  -name 'pretender' -o -name 'bloodhound-cli' -o \
  -name 'ligolo-agent' -o -name 'ligolo-proxy' \
\) -exec chmod +x {} + 2>/dev/null || true

# Leftovers from when roothound was type:file (two scripts only).
rm -f "${TOOLS_DIR}/roothound.py" "${TOOLS_DIR}/roothound-collector.sh"

if [[ -d "${TOOLS_DIR}/roothound" ]]; then
  find "${TOOLS_DIR}/roothound" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true
fi
if [[ -f "${TOOLS_DIR}/wesng/wes.py" ]]; then
  chmod +x "${TOOLS_DIR}/wesng/wes.py" 2>/dev/null || true
fi

chmod +x "${ROOT}/sync_tools.sh" "${ROOT}/deliver_tools.sh" "${ROOT}/sync_extras.sh" "${ROOT}/tools.sh" "${ROOT}/build_linpeas.sh" 2>/dev/null || true

log "sync_extras complete"
log "  tools:     ${TOOLS_DIR}/"
log "  accesschk: ${TOOLS_DIR}/accesschk.exe , ${TOOLS_DIR}/accesschk64.exe"
log "  deliver:   ${ROOT}/deliver_tools.sh"
log "  launcher:  ${ROOT}/tools.sh"
