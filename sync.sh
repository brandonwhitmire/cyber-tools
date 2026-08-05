#!/usr/bin/env bash
set -euo pipefail

MANIFEST="${1:-tools.json}"
TOOLS_DIR="tools"

log() { echo "[sync] $*" >&2; }
die() { echo "[sync] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_cmd bash
require_cmd jq
require_cmd git
require_cmd curl

[[ -f "$MANIFEST" ]] || die "manifest not found: $MANIFEST"

# TODO(stretch): support pinning tools to a specific tag or commit SHA for reproducible builds.

api_headers=(-H "Accept: application/vnd.github+json" -H "User-Agent: meta-tools-sync")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  api_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

github_api() {
  local url=$1
  curl -fsSL "${api_headers[@]}" "$url"
}

sync_release() {
  local name=$1 repo=$2
  shift 2
  local asset_patterns=("$@")
  local dest="${TOOLS_DIR}/${name}"
  local api_url="https://api.github.com/repos/${repo}/releases/latest"

  log "release: ${name} (${repo})"

  local release_json
  release_json="$(github_api "$api_url")"
  local tag
  tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
  [[ -n "$tag" ]] || die "release: ${name}: no tag_name in latest release"

  if [[ -f "${dest}/.version" ]] && [[ "$(cat "${dest}/.version")" == "$tag" ]]; then
    log "release: ${name}: up to date (${tag}), skipping"
    return 0
  fi

  log "release: ${name}: fetching ${tag}"
  rm -rf "$dest"
  mkdir -p "$dest"

  local assets
  assets="$(echo "$release_json" | jq -c '.assets[]?')"
  [[ -n "$assets" ]] || die "release: ${name}: no assets in release ${tag}"

  local downloaded=0
  while IFS= read -r asset; do
    [[ -n "$asset" ]] || continue
    local asset_name asset_url
    asset_name="$(echo "$asset" | jq -r '.name')"
    asset_url="$(echo "$asset" | jq -r '.browser_download_url')"

    local match=0
    for pattern in "${asset_patterns[@]}"; do
      if [[ "$asset_name" =~ $pattern ]]; then
        match=1
        break
      fi
    done
    [[ "$match" -eq 1 ]] || continue

    log "release: ${name}: downloading ${asset_name}"
    curl -fsSL -o "${dest}/${asset_name}" "$asset_url"
    downloaded=$((downloaded + 1))
  done <<< "$(echo "$release_json" | jq -c '.assets[]?')"

  [[ "$downloaded" -gt 0 ]] || die "release: ${name}: no assets matched patterns for ${tag}"

  echo "$tag" > "${dest}/.version"
  log "release: ${name}: done (${downloaded} asset(s), tag ${tag})"
}

sync_file() {
  local name=$1 repo=$2 ref=$3
  shift 3
  local paths=("$@")
  local dest="${TOOLS_DIR}/${name}"

  log "file: ${name} (${repo}@${ref})"
  mkdir -p "$dest"

  local path
  for path in "${paths[@]}"; do
    local url="https://raw.githubusercontent.com/${repo}/${ref}/${path}"
    local out="${dest}/${path}"
    mkdir -p "$(dirname "$out")"
    log "file: ${name}: fetching ${path}"
    curl -fsSL -o "$out" "$url"
  done

  log "file: ${name}: done (${#paths[@]} file(s))"
}

sync_repo() {
  local name=$1 repo=$2 ref=$3
  local dest="${TOOLS_DIR}/${name}"
  local clone_url="https://github.com/${repo}.git"

  log "repo: ${name} (${repo}@${ref})"
  rm -rf "$dest"
  git clone --depth 1 --branch "$ref" "$clone_url" "$dest"
  rm -rf "${dest}/.git"
  log "repo: ${name}: done"
}

# TODO(stretch): per-tool post-fetch build hook (compile Go/Rust tools before commit).

main() {
  local count
  count="$(jq '.tools | length' "$MANIFEST")"
  log "manifest: ${MANIFEST} (${count} tool(s))"

  mkdir -p "$TOOLS_DIR"

  local i
  for ((i = 0; i < count; i++)); do
    local tool
    tool="$(jq -c ".tools[$i]" "$MANIFEST")"

    local name type repo
    name="$(echo "$tool" | jq -r '.name')"
    type="$(echo "$tool" | jq -r '.type')"
    repo="$(echo "$tool" | jq -r '.repo')"

    case "$type" in
      release)
        mapfile -t assets < <(echo "$tool" | jq -r '.assets[]')
        sync_release "$name" "$repo" "${assets[@]}"
        ;;
      file)
        local ref
        ref="$(echo "$tool" | jq -r '.ref // "main"')"
        mapfile -t paths < <(echo "$tool" | jq -r '.paths[]')
        sync_file "$name" "$repo" "$ref" "${paths[@]}"
        ;;
      repo)
        local ref
        ref="$(echo "$tool" | jq -r '.ref // "main"')"
        sync_repo "$name" "$repo" "$ref"
        ;;
      *)
        log "WARN: unknown type '${type}' for tool '${name}', skipping"
        ;;
    esac
  done

  log "sync complete"
}

main "$@"
