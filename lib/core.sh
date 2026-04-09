#!/bin/bash

set -eo pipefail

log() {
  if [[ "${VERBOSE:-false}" == "true" ]]; then
    echo "[INFO] $*"
  fi
}

warn() {
  echo "[WARN] $*" >&2
}

error() {
  echo "[ERROR] $*" >&2
  exit 1
}

section() {
  echo
  echo "[$1] $2"
}

run() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    printf '[DRY RUN] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

capture_or_empty() {
  local output=""
  if output="$("$@" 2>/dev/null)"; then
    printf '%s\n' "$output"
  else
    return 0
  fi
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

array_contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

array_size() {
  local array_name="$1"
  local count=0
  eval "count=\${#$array_name[@]}"
  printf '%s' "$count"
}

dedupe_lines() {
  awk 'NF && !seen[$0]++'
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

print_block() {
  local title="$1"
  shift
  local items=("$@")
  local visible=()
  local item
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || continue
    visible+=("$item")
  done

  if [[ "${#visible[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "$title"
  for item in "${visible[@]}"; do
    echo "  - $item"
  done
}

copy_if_missing() {
  local source_path="$1"
  local target_path="$2"

  if [[ -f "$target_path" ]]; then
    return 0
  fi

  [[ -f "$source_path" ]] || error "Missing source file for bootstrap copy: $source_path"

  mkdir -p "$(dirname "$target_path")"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    printf '[DRY RUN] cp %s %s\n' "$source_path" "$target_path"
  else
    cp "$source_path" "$target_path"
  fi
}

append_result() {
  local array_name="$1"
  local value="$2"
  eval "$array_name+=(\"\$value\")"
}

install_homebrew_if_needed() {
  local brew_bin=""
  local installer_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    brew_bin="/usr/local/bin/brew"
  fi

  if [[ -z "$brew_bin" ]]; then
    section "BOOTSTRAP" "Installing Homebrew"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      printf '[DRY RUN] /bin/bash -c "$(curl -fsSL %s)"\n' "$installer_url"
      return 0
    fi
    /bin/bash -c "$(curl -fsSL "$installer_url")"

    if [[ -x "/opt/homebrew/bin/brew" ]]; then
      brew_bin="/opt/homebrew/bin/brew"
    elif [[ -x "/usr/local/bin/brew" ]]; then
      brew_bin="/usr/local/bin/brew"
    else
      error "Homebrew installation failed."
    fi
  fi

  [[ -n "$brew_bin" ]] || return 0
  eval "$("$brew_bin" shellenv)"
  export HOMEBREW_NO_AUTO_UPDATE=1
}

persist_homebrew_shellenv() {
  local brew_bin
  brew_bin="$(command -v brew || true)"
  [[ -n "$brew_bin" ]] || error "brew is not available"

  local shell_name profile_file
  shell_name="$(basename "${SHELL:-zsh}")"
  case "$shell_name" in
    zsh) profile_file="$HOME/.zprofile" ;;
    bash) profile_file="$HOME/.bash_profile" ;;
    *) profile_file="$HOME/.profile" ;;
  esac

  if [[ ! -f "$profile_file" ]]; then
    run touch "$profile_file"
  fi

  if ! grep -q 'brew shellenv' "$profile_file" 2>/dev/null; then
    section "BOOTSTRAP" "Persisting Homebrew shell environment to $profile_file"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      printf '[DRY RUN] append %s\n' "eval \"\$($brew_bin shellenv)\" -> $profile_file"
    else
      echo "eval \"\$($brew_bin shellenv)\"" >> "$profile_file"
    fi
  fi
}

ensure_yq_if_needed() {
  if ! has_command yq; then
    section "BOOTSTRAP" "Installing yq"
    run brew install yq
  fi
}
