#!/bin/bash

CATALOG_FILE="${CATALOG_FILE:-./catalog.yaml}"
CONFIG_FILE="${CONFIG_FILE:-./config.yaml}"

SELECTED_CATEGORIES=()
DECLARED_CATEGORIES=()
DESIRED_BREW=()
DESIRED_CASK=()
DESIRED_NPM=()
DESIRED_PIP=()

validate_config_files() {
  [[ -f "$CATALOG_FILE" ]] || error "Missing catalog file: $CATALOG_FILE"
  [[ -f "$CONFIG_FILE" ]] || error "Missing config file: $CONFIG_FILE"
}

read_lines_to_array() {
  local array_name="$1"
  shift
  local cmd_output
  cmd_output="$("$@" 2>/dev/null || true)"
  eval "$array_name=()"
  if [[ -n "$cmd_output" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      eval "$array_name+=(\"\$line\")"
    done <<< "$cmd_output"
  fi
}

load_declared_categories() {
  read_lines_to_array DECLARED_CATEGORIES yq -r '.categories | keys | .[]' "$CATALOG_FILE"
}

load_selected_categories() {
  read_lines_to_array SELECTED_CATEGORIES yq -r '.enabled_categories[]' "$CONFIG_FILE"
}

validate_category_selection() {
  local category
  local seen_selection=""
  for category in "${SELECTED_CATEGORIES[@]}"; do
    if ! array_contains "$category" "${DECLARED_CATEGORIES[@]}"; then
      error "Unknown category in config: $category"
    fi

    if grep -qxF "$category" <<< "$seen_selection"; then
      error "Duplicate category in config: $category"
    fi
    seen_selection+="${category}"$'\n'
  done
}

apply_cli_category_filter() {
  if [[ "${#CATEGORY_FILTERS[@]}" -eq 0 ]]; then
    return 0
  fi

  local filtered=()
  local category
  for category in "${CATEGORY_FILTERS[@]}"; do
    if ! array_contains "$category" "${SELECTED_CATEGORIES[@]}"; then
      error "Category filter is not enabled in config: $category"
    fi
    filtered+=("$category")
  done
  if [[ "$(array_size filtered)" -eq 0 ]]; then
    SELECTED_CATEGORIES=()
  else
    SELECTED_CATEGORIES=("${filtered[@]}")
  fi
}

read_type_for_category() {
  local category="$1"
  local package_type="$2"
  yq -r ".categories.\"$category\".\"$package_type\"[]?" "$CATALOG_FILE" 2>/dev/null || true
}

read_override_type() {
  local package_type="$1"
  local action="$2"
  yq -r ".overrides.\"$package_type\".\"$action\"[]?" "$CONFIG_FILE" 2>/dev/null || true
}

resolve_desired_packages() {
  local temp_brew="" temp_cask="" temp_npm="" temp_pip=""
  local category

  for category in "${SELECTED_CATEGORIES[@]}"; do
    temp_brew+=$(read_type_for_category "$category" brew)$'\n'
    temp_cask+=$(read_type_for_category "$category" cask)$'\n'
    temp_npm+=$(read_type_for_category "$category" npm)$'\n'
    temp_pip+=$(read_type_for_category "$category" pip)$'\n'
  done

  temp_brew+=$(read_override_type brew add)$'\n'
  temp_cask+=$(read_override_type cask add)$'\n'
  temp_npm+=$(read_override_type npm add)$'\n'
  temp_pip+=$(read_override_type pip add)$'\n'

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    DESIRED_BREW+=("$(to_lower "$item")")
  done <<< "$(printf '%s' "$temp_brew" | dedupe_lines)"

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    DESIRED_CASK+=("$(to_lower "$item")")
  done <<< "$(printf '%s' "$temp_cask" | dedupe_lines)"

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    DESIRED_NPM+=("$(to_lower "$item")")
  done <<< "$(printf '%s' "$temp_npm" | dedupe_lines)"

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    DESIRED_PIP+=("$(to_lower "$item")")
  done <<< "$(printf '%s' "$temp_pip" | dedupe_lines)"

  remove_overrides DESIRED_BREW brew
  remove_overrides DESIRED_CASK cask
  remove_overrides DESIRED_NPM npm
  remove_overrides DESIRED_PIP pip
}

remove_overrides() {
  local array_name="$1"
  local package_type="$2"
  local removals=()
  read_lines_to_array removals yq -r ".overrides.\"$package_type\".remove[]?" "$CONFIG_FILE"

  [[ "$(array_size removals)" -gt 0 ]] || return 0

  local current=()
  eval "current=(\"\${$array_name[@]-}\")"
  local filtered=()
  local item
  for item in "${current[@]-}"; do
    if ! array_contains "$item" "${removals[@]-}"; then
      filtered+=("$item")
    fi
  done
  if [[ "$(array_size filtered)" -eq 0 ]]; then
    eval "$array_name=()"
  else
    eval "$array_name=(\"\${filtered[@]-}\")"
  fi
}

print_selection_summary() {
  section "INFO" "Enabled categories: ${SELECTED_CATEGORIES[*]}"
  echo "Desired state"
  echo "  brew: $(array_size DESIRED_BREW)"
  echo "  cask: $(array_size DESIRED_CASK)"
  echo "  npm: $(array_size DESIRED_NPM)"
  echo "  pip: $(array_size DESIRED_PIP)"
}
