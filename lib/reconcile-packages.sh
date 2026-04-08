#!/bin/bash

INSTALLED_BREW=()
INSTALLED_CASK=()
INSTALLED_NPM=()
INSTALLED_PIP=()
OUTDATED_BREW=()
OUTDATED_CASK=()
UPGRADABLE_CASK=()
DEFERRED_CASK_UPGRADES=()

MISSING_BREW=()
MISSING_CASK=()
MISSING_NPM=()
MISSING_PIP=()
EXTRA_BREW=()
EXTRA_CASK=()

APPLIED_INSTALLS=()
APPLIED_UPGRADES=()

load_installed_packages() {
  if has_command brew; then
    if [[ "$(array_size DESIRED_BREW)" -gt 0 ]]; then
      read_lines_to_array INSTALLED_BREW brew leaves
    fi
    if [[ "$(array_size DESIRED_CASK)" -gt 0 ]]; then
      read_lines_to_array INSTALLED_CASK brew list --cask
    fi
    if [[ "${SKIP_UPDATES:-false}" != "true" && "$(array_size DESIRED_BREW)" -gt 0 ]]; then
      read_lines_to_array OUTDATED_BREW brew outdated --formula
    fi
    if [[ "${SKIP_UPDATES:-false}" != "true" && "$(array_size DESIRED_CASK)" -gt 0 ]]; then
      read_lines_to_array OUTDATED_CASK brew outdated --cask
    fi
    lowercase_array INSTALLED_BREW
    lowercase_array INSTALLED_CASK
    lowercase_array OUTDATED_BREW
    lowercase_array OUTDATED_CASK
  fi

  if has_command npm && [[ "$(array_size DESIRED_NPM)" -gt 0 ]]; then
    read_lines_to_array INSTALLED_NPM npm list -g --depth=0 --parseable
    normalize_parseable_names INSTALLED_NPM
  fi

  if has_command pip3 && [[ "$(array_size DESIRED_PIP)" -gt 0 ]]; then
    read_lines_to_array INSTALLED_PIP pip3 list --format=freeze
    normalize_freeze_names INSTALLED_PIP
  fi
}

normalize_parseable_names() {
  local array_name="$1"
  local current=()
  eval "current=(\"\${$array_name[@]-}\")"
  local normalized=()
  local item
  for item in "${current[@]-}"; do
    normalized+=("${item##*/}")
  done
  lowercase_array normalized
  if [[ "$(array_size normalized)" -eq 0 ]]; then
    eval "$array_name=()"
  else
    eval "$array_name=(\"\${normalized[@]}\")"
  fi
}

normalize_freeze_names() {
  local array_name="$1"
  local current=()
  eval "current=(\"\${$array_name[@]-}\")"
  local normalized=()
  local item
  for item in "${current[@]-}"; do
    normalized+=("${item%%==*}")
  done
  lowercase_array normalized
  if [[ "$(array_size normalized)" -eq 0 ]]; then
    eval "$array_name=()"
  else
    eval "$array_name=(\"\${normalized[@]}\")"
  fi
}

lowercase_array() {
  local array_name="$1"
  local current=()
  eval "current=(\"\${$array_name[@]-}\")"
  local normalized=()
  local item
  for item in "${current[@]-}"; do
    normalized+=("$(to_lower "$item")")
  done
  if [[ "$(array_size normalized)" -eq 0 ]]; then
    eval "$array_name=()"
  else
    eval "$array_name=(\"\${normalized[@]}\")"
  fi
}

compute_package_plan() {
  compute_missing MISSING_BREW DESIRED_BREW INSTALLED_BREW
  compute_missing MISSING_CASK DESIRED_CASK INSTALLED_CASK
  compute_missing MISSING_NPM DESIRED_NPM INSTALLED_NPM
  compute_missing MISSING_PIP DESIRED_PIP INSTALLED_PIP

  compute_managed_outdated OUTDATED_BREW OUTDATED_BREW DESIRED_BREW
  compute_managed_outdated OUTDATED_CASK OUTDATED_CASK DESIRED_CASK

  if [[ "${#CATEGORY_FILTERS[@]}" -eq 0 ]]; then
    compute_extra EXTRA_BREW INSTALLED_BREW DESIRED_BREW
    compute_extra EXTRA_CASK INSTALLED_CASK DESIRED_CASK
  else
    EXTRA_BREW=()
    EXTRA_CASK=()
  fi
  classify_outdated_casks
}

compute_missing() {
  local target_name="$1"
  local desired_name="$2"
  local installed_name="$3"
  local desired=() installed=() result=()
  eval "desired=(\"\${$desired_name[@]-}\")"
  eval "installed=(\"\${$installed_name[@]-}\")"

  local item
  for item in "${desired[@]-}"; do
    if ! array_contains "$item" "${installed[@]-}"; then
      result+=("$item")
    fi
  done
  if [[ "$(array_size result)" -eq 0 ]]; then
    eval "$target_name=()"
  else
    eval "$target_name=(\"\${result[@]}\")"
  fi
}

compute_extra() {
  local target_name="$1"
  local installed_name="$2"
  local desired_name="$3"
  local desired=() installed=() result=()
  eval "desired=(\"\${$desired_name[@]-}\")"
  eval "installed=(\"\${$installed_name[@]-}\")"

  local item
  for item in "${installed[@]-}"; do
    if ! array_contains "$item" "${desired[@]-}"; then
      result+=("$item")
    fi
  done
  if [[ "$(array_size result)" -eq 0 ]]; then
    eval "$target_name=()"
  else
    eval "$target_name=(\"\${result[@]}\")"
  fi
}

compute_managed_outdated() {
  local target_name="$1"
  local outdated_name="$2"
  local desired_name="$3"
  local outdated=() desired=() result=()
  eval "outdated=(\"\${$outdated_name[@]-}\")"
  eval "desired=(\"\${$desired_name[@]-}\")"

  local item
  for item in "${outdated[@]-}"; do
    if array_contains "$item" "${desired[@]-}"; then
      result+=("$item")
    fi
  done
  if [[ "$(array_size result)" -eq 0 ]]; then
    eval "$target_name=()"
  else
    eval "$target_name=(\"\${result[@]}\")"
  fi
}

is_cask_deferred_if_running() {
  local cask="$1"
  case "$cask" in
    google-chrome) return 0 ;;
    *) return 1 ;;
  esac
}

is_cask_running() {
  local cask="$1"
  case "$cask" in
    google-chrome)
      pgrep -x "Google Chrome" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

classify_outdated_casks() {
  UPGRADABLE_CASK=()
  DEFERRED_CASK_UPGRADES=()

  local cask
  for cask in "${OUTDATED_CASK[@]-}"; do
    if is_cask_deferred_if_running "$cask" && is_cask_running "$cask"; then
      DEFERRED_CASK_UPGRADES+=("$cask")
    else
      UPGRADABLE_CASK+=("$cask")
    fi
  done
}

print_package_plan() {
  section "PLAN" "Package reconciliation"
  print_block "Missing brew" "${MISSING_BREW[@]-}"
  print_block "Missing cask" "${MISSING_CASK[@]-}"
  print_block "Missing npm" "${MISSING_NPM[@]-}"
  print_block "Missing pip" "${MISSING_PIP[@]-}"
  print_block "Outdated brew" "${OUTDATED_BREW[@]-}"
  print_block "Outdated cask" "${UPGRADABLE_CASK[@]-}"
  print_block "Deferred cask upgrades because the app is running" "${DEFERRED_CASK_UPGRADES[@]-}"
  if [[ "${#CATEGORY_FILTERS[@]}" -eq 0 ]]; then
    print_block "Extra explicit brew installs not declared" "${EXTRA_BREW[@]-}"
    print_block "Extra casks not declared" "${EXTRA_CASK[@]-}"
  else
    echo "Extra package drift is skipped during category-scoped runs."
  fi
}

reconcile_packages() {
  section "INFO" "Inspecting installed packages"
  load_installed_packages
  compute_package_plan
  print_package_plan

  if [[ "${SKIP_INSTALL:-false}" != "true" ]]; then
    install_missing_packages
  fi

  if [[ "${SKIP_UPDATES:-false}" != "true" ]]; then
    update_existing_packages
  fi
}

install_missing_packages() {
  if [[ "$(array_size MISSING_BREW)" -gt 0 ]]; then
    section "APPLY" "Installing missing brew formulae"
    run brew install "${MISSING_BREW[@]-}"
    APPLIED_INSTALLS+=("${MISSING_BREW[@]-}")
  fi

  if [[ "$(array_size MISSING_CASK)" -gt 0 ]]; then
    section "APPLY" "Installing missing casks"
    run brew install --cask "${MISSING_CASK[@]-}"
    APPLIED_INSTALLS+=("${MISSING_CASK[@]-}")
  fi

  if [[ "$(array_size MISSING_NPM)" -gt 0 ]]; then
    if ! has_command npm; then
      warn "npm not found; skipping npm installs"
    else
      section "APPLY" "Installing missing npm packages"
      run npm install -g "${MISSING_NPM[@]-}"
      APPLIED_INSTALLS+=("${MISSING_NPM[@]-}")
    fi
  fi

  if [[ "$(array_size MISSING_PIP)" -gt 0 ]]; then
    if ! has_command pip3; then
      warn "pip3 not found; skipping pip installs"
    else
      section "APPLY" "Installing missing pip packages"
      run pip3 install "${MISSING_PIP[@]-}"
      APPLIED_INSTALLS+=("${MISSING_PIP[@]-}")
    fi
  fi
}

update_existing_packages() {
  if has_command brew; then
    section "APPLY" "Updating Homebrew metadata"
    run brew update
  fi

  if [[ "$(array_size OUTDATED_BREW)" -gt 0 ]]; then
    section "APPLY" "Upgrading outdated brew formulae"
    run brew upgrade "${OUTDATED_BREW[@]-}"
    APPLIED_UPGRADES+=("${OUTDATED_BREW[@]-}")
  fi

  if [[ "$(array_size UPGRADABLE_CASK)" -gt 0 ]]; then
    section "APPLY" "Upgrading outdated casks"
    run brew upgrade --cask "${UPGRADABLE_CASK[@]-}"
    APPLIED_UPGRADES+=("${UPGRADABLE_CASK[@]-}")
  fi

  if has_command npm && [[ "$(array_size DESIRED_NPM)" -gt 0 ]]; then
    section "APPLY" "Updating managed npm packages"
    run npm update -g "${DESIRED_NPM[@]-}"
  fi

  if has_command pip3 && [[ "$(array_size DESIRED_PIP)" -gt 0 ]]; then
    section "APPLY" "Updating managed pip packages"
    run pip3 install --upgrade "${DESIRED_PIP[@]-}"
  fi
}

print_package_report() {
  section "REPORT" "Packages"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    print_block "Planned installs" "${APPLIED_INSTALLS[@]-}"
    print_block "Planned upgrades" "${APPLIED_UPGRADES[@]-}"
  else
    print_block "Installed" "${APPLIED_INSTALLS[@]-}"
    print_block "Upgraded" "${APPLIED_UPGRADES[@]-}"
  fi
  print_block "Deferred cask upgrades because the app is running" "${DEFERRED_CASK_UPGRADES[@]-}"
  if [[ "${#CATEGORY_FILTERS[@]}" -eq 0 ]]; then
    print_block "Manual follow-up: undeclared explicit brew installs" "${EXTRA_BREW[@]-}"
    print_block "Manual follow-up: undeclared casks" "${EXTRA_CASK[@]-}"
  fi
}
