#!/usr/bin/env bash
set -euo pipefail

MANIFEST="${1:-tools.json}"
TOOLS_DIR="tools"

log() { echo "[tool_sync] $*" >&2; }
die() { echo "[tool_sync] ERROR: $*" >&2; exit 1; }

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

# Resolve dest filename from rename map (JSON object). "$lower" => lowercase of original.
resolve_rename() {
  local original=$1
  local rename_json=$2
  local patterns pattern dest

  if [[ -z "$rename_json" || "$rename_json" == "null" || "$rename_json" == "{}" ]]; then
    printf '%s' "$original"
    return 0
  fi

  mapfile -t patterns < <(echo "$rename_json" | jq -r 'keys[]')
  for pattern in "${patterns[@]}"; do
    if [[ "$original" =~ $pattern ]]; then
      dest="$(echo "$rename_json" | jq -r --arg p "$pattern" '.[$p]')"
      if [[ "$dest" == "\$lower" || "$dest" == '$lower' ]]; then
        printf '%s' "${original,,}"
      else
        printf '%s' "$dest"
      fi
      return 0
    fi
  done

  printf '%s' "$original"
}

sync_release() {
  local name=$1 repo=$2 rename_json=$3
  shift 3
  local asset_patterns=("$@")
  local api_url="https://api.github.com/repos/${repo}/releases/latest"

  log "release: ${name} (${repo})"

  local release_json
  release_json="$(github_api "$api_url")"
  local tag
  tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
  [[ -n "$tag" ]] || die "release: ${name}: no tag_name in latest release"

  log "release: ${name}: fetching ${tag}"

  local assets
  assets="$(echo "$release_json" | jq -c '.assets[]?')"
  [[ -n "$assets" ]] || die "release: ${name}: no assets in release ${tag}"

  local downloaded=0
  while IFS= read -r asset; do
    [[ -n "$asset" ]] || continue
    local asset_name asset_url dest_name
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

    dest_name="$(resolve_rename "$asset_name" "$rename_json")"
    log "release: ${name}: downloading ${asset_name} -> ${dest_name}"
    curl -fsSL -o "${TOOLS_DIR}/${dest_name}" "$asset_url"
    downloaded=$((downloaded + 1))
  done <<< "$(echo "$release_json" | jq -c '.assets[]?')"

  [[ "$downloaded" -gt 0 ]] || die "release: ${name}: no assets matched patterns for ${tag}"
  log "release: ${name}: done (${downloaded} asset(s), tag ${tag})"
}

sync_file() {
  local name=$1 repo=$2 ref=$3 rename_json=$4
  shift 4
  local paths=("$@")

  log "file: ${name} (${repo}@${ref})"

  local path
  for path in "${paths[@]}"; do
    local base dest_name url
    base="$(basename "$path")"
    dest_name="$(resolve_rename "$base" "$rename_json")"
    url="https://raw.githubusercontent.com/${repo}/${ref}/${path}"
    log "file: ${name}: fetching ${path} -> ${dest_name}"
    curl -fsSL -o "${TOOLS_DIR}/${dest_name}" "$url"
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

    local name type repo rename_json
    name="$(echo "$tool" | jq -r '.name')"
    type="$(echo "$tool" | jq -r '.type')"
    repo="$(echo "$tool" | jq -r '.repo')"
    rename_json="$(echo "$tool" | jq -c '.rename // {}')"

    case "$type" in
      release)
        mapfile -t assets < <(echo "$tool" | jq -r '.assets[]')
        sync_release "$name" "$repo" "$rename_json" "${assets[@]}"
        ;;
      file)
        local ref
        ref="$(echo "$tool" | jq -r '.ref // "main"')"
        mapfile -t paths < <(echo "$tool" | jq -r '.paths[]')
        sync_file "$name" "$repo" "$ref" "$rename_json" "${paths[@]}"
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
