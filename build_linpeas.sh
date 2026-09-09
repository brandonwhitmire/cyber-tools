#!/usr/bin/env bash
# Build an offline-safe linpeas_oscp.sh from PEASS-ng's builder.
# Rebuilds only when linpeas_oscp.json or upstream builder inputs change.
#
#   ./build_linpeas.sh            # skip if srcsha matches
#   ./build_linpeas.sh --force    # always rebuild
#   FORCE=1 ./build_linpeas.sh
#
# Edit linpeas_oscp.json to change excluded/included modules.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${1:-}"
FORCE="${FORCE:-0}"

if [[ "${CONFIG}" == "--force" || "${CONFIG}" == "-f" ]]; then
  FORCE=1
  CONFIG=""
fi
CONFIG="${CONFIG:-${ROOT}/linpeas_oscp.json}"

TOOLS_DIR="${ROOT}/tools"

log() { echo "[build_linpeas] $*" >&2; }
die() { echo "[build_linpeas] ERROR: $*" >&2; exit 1; }

[[ -f "$CONFIG" ]] || die "config not found: $CONFIG"
command -v jq >/dev/null 2>&1 || die "jq required"
command -v git >/dev/null 2>&1 || die "git required"
command -v python3 >/dev/null 2>&1 || die "python3 required"
command -v curl >/dev/null 2>&1 || die "curl required"

if ! python3 -c "import yaml" 2>/dev/null; then
  die "PyYAML required (Arch: python-yaml  |  Debian: python3-yaml  |  pip: pyyaml)"
fi

repo="$(jq -r '.repo' "$CONFIG")"
ref="$(jq -r '.ref // "master"' "$CONFIG")"
out_name="$(jq -r '.output // "linpeas_oscp.sh"' "$CONFIG")"
preset="$(jq -r '.preset // "all-no-fat"' "$CONFIG")"
no_net="$(jq -r '.no_network_scanning // true' "$CONFIG")"
dest="${TOOLS_DIR}/${out_name}"

mapfile -t exclude < <(jq -r '.exclude[]? // empty' "$CONFIG")
mapfile -t include < <(jq -r '.include[]? // empty' "$CONFIG")

api_headers=(-H "Accept: application/vnd.github+json" -H "User-Agent: cyber-tools-linpeas")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  api_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

latest_path_sha() {
  local path=$1
  local url="https://api.github.com/repos/${repo}/commits?sha=${ref}&path=${path}&per_page=1"
  curl -fsSL "${api_headers[@]}" "$url" | jq -r '.[0].sha // empty'
}

config_sha="$(sha256sum "$CONFIG" | awk '{print $1}')"
builder_sha="$(latest_path_sha "linPEAS/builder" || true)"
lists_sha="$(latest_path_sha "build_lists" || true)"

if [[ -n "$builder_sha" && -n "$lists_sha" ]]; then
  srcsha="$(printf '%s\n%s\n%s\n' "$config_sha" "$builder_sha" "$lists_sha" | sha256sum | awk '{print $1}')"
else
  srcsha=""
  log "WARN: could not query GitHub for builder SHAs; will clone and hash locally"
fi

existing=""
if [[ -f "$dest" ]]; then
  existing="$(sed -n 's/^# cyber-tools-srcsha: //p' "$dest" | head -1)"
fi

if [[ "$FORCE" != "1" && -n "$srcsha" && -n "$existing" && "$existing" == "$srcsha" ]]; then
  log "up to date (${out_name}, srcsha ${srcsha:0:12}…)"
  exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/linpeas-build.XXXXXX")"
cleanup() { /usr/bin/rm -rf "$tmp"; }
trap cleanup EXIT

clone="${tmp}/PEASS-ng"
clone_url="https://github.com/${repo}.git"
log "cloning ${repo}@${ref} (sparse: linPEAS/builder + build_lists)"

if git clone --depth 1 --filter=blob:none --sparse --branch "$ref" "$clone_url" "$clone" 2>/dev/null; then
  git -C "$clone" sparse-checkout set linPEAS/builder build_lists
else
  log "sparse clone failed; falling back to depth-1 clone"
  git clone --depth 1 --branch "$ref" "$clone_url" "$clone"
fi

[[ -d "${clone}/linPEAS/builder" ]] || die "clone missing linPEAS/builder"
[[ -d "${clone}/build_lists" ]] || die "clone missing build_lists (builder needs regexes.yaml)"

if [[ -z "$srcsha" ]]; then
  srcsha="$(
    {
      sha256sum "$CONFIG"
      (cd "${clone}/linPEAS/builder" && find . -type f | LC_ALL=C sort | xargs -r sha256sum)
      (cd "${clone}/build_lists" && sha256sum sensitive_files.yaml regexes.yaml)
    } | sha256sum | awk '{print $1}'
  )"
  if [[ "$FORCE" != "1" && -n "$existing" && "$existing" == "$srcsha" ]]; then
    log "up to date after local hash (${out_name})"
    exit 0
  fi
fi

builder_args=()
join_csv() {
  local IFS=,
  printf '%s' "$*"
}

if ((${#include[@]} > 0)); then
  builder_args+=(--include "$(join_csv "${include[@]}")")
else
  case "$preset" in
    all) builder_args+=(--all) ;;
    all-no-fat) builder_args+=(--all-no-fat) ;;
    small) builder_args+=(--small) ;;
    *) die "unknown preset: ${preset} (use all, all-no-fat, small, or set include)" ;;
  esac
fi

if [[ "$no_net" == "true" ]]; then
  builder_args+=(--no-network-scanning)
fi
if ((${#exclude[@]} > 0)); then
  builder_args+=(--exclude "$(join_csv "${exclude[@]}")")
fi

built="${tmp}/${out_name}"
log "building ${out_name} (${preset}, exclude=${exclude[*]:-none})"
(
  cd "${clone}/linPEAS"
  PYTHONUNBUFFERED=1 python3 -m builder.linpeas_builder "${builder_args[@]}" --output "$built"
)

[[ -f "$built" ]] || die "builder did not write ${built}"

{
  echo "#!/bin/sh"
  echo "# cyber-tools-srcsha: ${srcsha}"
  echo "# cyber-tools: offline OSCP linpeas (see linpeas_oscp.json)"
  echo "# runtime: REGEXES=0 ./${out_name} -q -e"
  # drop the original shebang; keep the rest
  tail -n +2 "$built"
} >"${built}.headed"
mv -f "${built}.headed" "$built"
chmod +x "$built"

mkdir -p "$TOOLS_DIR"
mv -f "$built" "$dest"
chmod +x "$dest"
log "wrote ${dest} (srcsha ${srcsha:0:12}…)"
