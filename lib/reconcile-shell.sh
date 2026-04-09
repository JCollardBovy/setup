#!/bin/bash

SHELL_CHANGED=()
SHELL_COMPLIANT=()
SHELL_WARNINGS=()

shell_record_status() {
  local status="$1"
  local label="$2"
  case "$status" in
    changed) SHELL_CHANGED+=("$label") ;;
    compliant) SHELL_COMPLIANT+=("$label") ;;
    warning) SHELL_WARNINGS+=("$label") ;;
  esac
}

shell_category_enabled() {
  array_contains scripting "${SELECTED_CATEGORIES[@]}"
}

shell_template_path() {
  printf '%s/templates/zshrc' "$ROOT_DIR"
}

shell_needs_bootstrap() {
  [[ ! -d "$HOME/.oh-my-zsh" || ! -f "$HOME/.zshrc" ]]
}

install_oh_my_zsh() {
  local installer_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    printf '[DRY RUN] RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL %s)"\n' "$installer_url"
    return 0
  fi

  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL "$installer_url")"
}

copy_zshrc_template() {
  local template
  template="$(shell_template_path)"
  [[ -f "$template" ]] || error "Missing zshrc template: $template"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    printf '[DRY RUN] cp %s %s\n' "$template" "$HOME/.zshrc"
    return 0
  fi

  cp "$template" "$HOME/.zshrc"
}

reconcile_shell() {
  if ! shell_category_enabled; then
    log "Skipping shell bootstrap because scripting is not enabled"
    return 0
  fi

  section "INFO" "Reconciling shell bootstrap"

  if ! shell_needs_bootstrap; then
    shell_record_status compliant "oh-my-zsh and ~/.zshrc already exist"
    return 0
  fi

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    section "APPLY" "Installing oh-my-zsh"
    if install_oh_my_zsh; then
      shell_record_status changed "Installed oh-my-zsh"
    else
      warn "oh-my-zsh installation failed"
      shell_record_status warning "Failed to install oh-my-zsh"
    fi
  else
    shell_record_status compliant "oh-my-zsh already exists"
  fi

  if [[ ! -f "$HOME/.zshrc" ]]; then
    section "APPLY" "Writing ~/.zshrc from template"
    if copy_zshrc_template; then
      shell_record_status changed "Initialized ~/.zshrc from template"
    else
      warn "Could not initialize ~/.zshrc from template"
      shell_record_status warning "Failed to initialize ~/.zshrc from template"
    fi
  else
    shell_record_status compliant "~/.zshrc already exists"
  fi
}

print_shell_report() {
  section "REPORT" "Shell"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    print_block "Planned changes" "${SHELL_CHANGED[@]}"
  else
    print_block "Changed" "${SHELL_CHANGED[@]}"
  fi
  print_block "Already compliant" "${SHELL_COMPLIANT[@]}"
  print_block "Warnings" "${SHELL_WARNINGS[@]}"
}
