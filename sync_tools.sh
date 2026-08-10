#!/usr/bin/env bash
set -euo pipefail

MANIFEST="${1:-sync.json}"
TOOLS_DIR="tools"

log() { echo "[sync_tools] $*" >&2; }
die() { echo "[sync_tools] ERROR: $*" >&2; exit 1; }

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

# Extract archive into tools/, keeping only basenames matching extract_keep regexes.
# Deletes the archive afterward. Kept files are written lowercase into TOOLS_DIR.
extract_archive() {
  local archive=$1
  shift
  local keep_patterns=("$@")
  local archive_path="${TOOLS_DIR}/${archive}"
  local tmp kept=0

  [[ -f "$archive_path" ]] || die "extract: archive not found: ${archive_path}"
  [[ "${#keep_patterns[@]}" -gt 0 ]] || die "extract: ${archive}: extract_keep is required when extract=true"

  tmp="$(mktemp -d "${TOOLS_DIR}/.extract.XXXXXX")"

  case "${archive,,}" in
    *.zip)
      require_cmd unzip
      unzip -q -o "$archive_path" -d "$tmp"
      ;;
    *.tar.gz|*.tgz)
      tar --no-same-owner -xzf "$archive_path" -C "$tmp"
      ;;
    *.tar)
      tar --no-same-owner -xf "$archive_path" -C "$tmp"
      ;;
    *)
      die "extract: unsupported archive type: ${archive}"
      ;;
  esac

  local file base dest pattern
  while IFS= read -r -d '' file; do
    base="$(basename "$file")"
    for pattern in "${keep_patterns[@]}"; do
      if [[ "$base" =~ $pattern ]]; then
        dest="${base,,}"
        log "extract: ${archive}: keeping ${base} -> ${dest}"
        mv -f "$file" "${TOOLS_DIR}/${dest}"
        kept=$((kept + 1))
        break
      fi
    done
  done < <(find "$tmp" -type f -print0)

  [[ "$kept" -gt 0 ]] || { rm -rf "$tmp"; die "extract: ${archive}: no files matched extract_keep patterns"; }
  rm -rf "$tmp"
  rm -f "$archive_path"
  log "extract: ${archive}: done (${kept} file(s))"
}

sync_release() {
  local name=$1 repo=$2 rename_json=$3 do_extract=$4
  shift 4
  local keep_patterns=()
  local asset_patterns=()

  # Remaining args: keep patterns, then "--", then asset patterns
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    keep_patterns+=("$1")
    shift
  done
  [[ $# -gt 0 && "$1" == "--" ]] || die "release: ${name}: internal arg parse error"
  shift
  asset_patterns=("$@")

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

    if [[ "$do_extract" == "true" ]]; then
      extract_archive "$dest_name" "${keep_patterns[@]}"
    fi
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

    local name type repo rename_json do_extract
    name="$(echo "$tool" | jq -r '.name')"
    type="$(echo "$tool" | jq -r '.type')"
    repo="$(echo "$tool" | jq -r '.repo')"
    rename_json="$(echo "$tool" | jq -c '.rename // {}')"
    do_extract="$(echo "$tool" | jq -r '.extract // false')"

    case "$type" in
      release)
        mapfile -t assets < <(echo "$tool" | jq -r '.assets[]')
        local keep_patterns=()
        if [[ "$do_extract" == "true" ]]; then
          if echo "$tool" | jq -e '.extract_keep | type == "array"' >/dev/null; then
            mapfile -t keep_patterns < <(echo "$tool" | jq -r '.extract_keep[]')
          elif echo "$tool" | jq -e '.extract_keep | type == "string"' >/dev/null; then
            keep_patterns=("$(echo "$tool" | jq -r '.extract_keep')")
          else
            die "release: ${name}: extract=true requires extract_keep (string or array of regexes)"
          fi
        fi
        sync_release "$name" "$repo" "$rename_json" "$do_extract" "${keep_patterns[@]}" -- "${assets[@]}"
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
