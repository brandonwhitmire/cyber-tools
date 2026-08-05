#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${ROOT}/tools"
ACCESSCHK_DIR="${TOOLS_DIR}/accesschk"

log() { echo "[install] $*" >&2; }

log "syncing vendored tools..."
if ! "${ROOT}/sync.sh" "${ROOT}/tools.json"; then
  log "WARN: sync failed (GitHub rate limit?); continuing with extras for already-vendored tools"
fi

log "fetching AccessChk from Sysinternals (official source)..."
mkdir -p "${ACCESSCHK_DIR}"
/usr/bin/curl -fsSL -o "${ACCESSCHK_DIR}/accesschk.exe" "https://live.sysinternals.com/accesschk.exe"
/usr/bin/curl -fsSL -o "${ACCESSCHK_DIR}/accesschk64.exe" "https://live.sysinternals.com/accesschk64.exe"

python_archive="$(find "${TOOLS_DIR}/static-python" -maxdepth 1 -name 'cpython-*-install_only.tar.gz' -print -quit 2>/dev/null || true)"
if [[ -n "${python_archive}" ]]; then
  log "extracting portable Windows Python..."
  tar -xzf "${python_archive}" -C "${TOOLS_DIR}/static-python"
fi

log "setting execute bits on scripts and Linux binaries..."
find "${TOOLS_DIR}" -type f \( -name '*.sh' -o -name 'pspy32' -o -name 'pspy64' -o -name 'kerbrute_linux_amd64' -o -name 'linpeas.sh' -o -name 'nc-x64' -o -name 'nc-x86' -o -name 'pspy32-x86' -o -name 'pspy-x64' \) -exec chmod +x {} + 2>/dev/null || true
find "${TOOLS_DIR}/static-binaries" "${TOOLS_DIR}/static-netcat" -type f -exec chmod +x {} + 2>/dev/null || true

chmod +x "${ROOT}/sync.sh" "${ROOT}/scripts/"*.sh 2>/dev/null || true

log "install complete"
log "  tools:    ${TOOLS_DIR}/"
log "  accesschk: ${ACCESSCHK_DIR}/"
log "  serve:    ${ROOT}/scripts/serve.sh"
