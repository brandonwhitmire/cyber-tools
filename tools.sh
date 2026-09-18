#!/usr/bin/env bash
# `tools` launcher for cyber-tools.
#
# Execute:
#   ./tools.sh              # find repo, run deliver_tools.sh
#
# Source (defines a `tools` command; cd persists after Ctrl+C):
#   source /path/to/cyber-tools/tools.sh
#
# Install into ~/.zshrc or ~/.bashrc:
#   ./tools.sh --install

_cyber_tools_is_repo() {
  [[ -f "$1/deliver_tools.sh" && -d "$1/tools" && -f "$1/sync.json" ]]
}

_cyber_tools_self_dir() {
  local src
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    src="${BASH_SOURCE[0]}"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    src="${(%):-%x}"
  else
    src="$0"
  fi
  if command -v readlink >/dev/null 2>&1; then
    src="$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")"
  fi
  (cd "$(dirname "$src")" && pwd)
}

cyber_tools_find() {
  local d candidate

  if [[ -n "${CYBER_TOOLS_DIR:-}" ]]; then
    if _cyber_tools_is_repo "$CYBER_TOOLS_DIR"; then
      printf '%s\n' "$CYBER_TOOLS_DIR"
      return 0
    fi
    echo "tools: CYBER_TOOLS_DIR is not a cyber-tools repo: ${CYBER_TOOLS_DIR}" >&2
    return 1
  fi

  d="$(_cyber_tools_self_dir)"
  if _cyber_tools_is_repo "$d"; then
    printf '%s\n' "$d"
    return 0
  fi

  d="${PWD:-.}"
  while [[ "$d" != "/" ]]; do
    if _cyber_tools_is_repo "$d"; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done

  local candidates=(
    "$HOME/Descargas/DEVELOPMENT/cyber-tools"
    "$HOME/Development/cyber-tools"
    "$HOME/DEVELOPMENT/cyber-tools"
    "$HOME/src/cyber-tools"
    "$HOME/git/cyber-tools"
    "$HOME/cyber-tools"
  )
  for candidate in "${candidates[@]}"; do
    if _cyber_tools_is_repo "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  while IFS= read -r -d '' candidate; do
    d="$(dirname "$candidate")"
    if _cyber_tools_is_repo "$d"; then
      printf '%s\n' "$d"
      return 0
    fi
  done < <(find "$HOME" -maxdepth 6 -type f -name deliver_tools.sh -print0 2>/dev/null)

  echo "tools: could not find cyber-tools (set CYBER_TOOLS_DIR)" >&2
  return 1
}

tools() {
  local repo
  repo="$(cyber_tools_find)" || return 1
  cd "$repo" || return 1
  ./deliver_tools.sh "$@"
}

_cyber_tools_install() {
  local repo rc line
  repo="$(cyber_tools_find)" || return 1
  line="source \"${repo}/tools.sh\""

  if [[ -n "${ZSH_VERSION:-}" ]] || [[ "${SHELL:-}" == *zsh ]]; then
    rc="${HOME}/.zshrc"
  else
    rc="${HOME}/.bashrc"
  fi

  if [[ -f "$rc" ]] && grep -Fqx "$line" "$rc"; then
    echo "tools: already installed in ${rc}"
    return 0
  fi

  printf '\n# cyber-tools: type `tools` to serve the staging directory\n%s\n' "$line" >>"$rc"
  echo "tools: added to ${rc}"
  echo "tools: run:  source ${rc}"
  echo "tools: then: tools"
}

_cyber_tools_is_sourced() {
  if [[ -n "${ZSH_EVAL_CONTEXT:-}" ]]; then
    case "$ZSH_EVAL_CONTEXT" in
      *:file*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "$0" ]]
}

if _cyber_tools_is_sourced; then
  return 0 2>/dev/null || true
fi

set -euo pipefail

case "${1:-}" in
  --install)
    _cyber_tools_install
    ;;
  -i)
    # bare -i still installs; -i tun0 / -i eth0 goes to deliver_tools.sh
    if [[ $# -eq 1 ]]; then
      _cyber_tools_install
    else
      REPO="$(cyber_tools_find)"
      cd "$REPO"
      exec ./deliver_tools.sh "$@"
    fi
    ;;
  --help|-h)
    echo "Usage: tools.sh [--install] [deliver_tools.sh options...]"
    echo "  tools.sh              find cyber-tools and run deliver_tools.sh"
    echo "  tools.sh --install    append a source line to ~/.zshrc or ~/.bashrc"
    echo "  tools.sh -i tun0      advertise tun0 (default: tun0, then eth0)"
    echo "  tools.sh --ip 10.10.14.5   pin the connect IPv4"
    echo "  tools.sh -p 9000      HTTP port (also --port / --http-port; default 8888)"
    echo "  source tools.sh       define a \`tools\` function in the current shell"
    ;;
  *)
    REPO="$(cyber_tools_find)"
    cd "$REPO"
    exec ./deliver_tools.sh "$@"
    ;;
esac
