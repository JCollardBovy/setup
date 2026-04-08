#!/bin/bash

XCODE_CHANGED=()
XCODE_COMPLIANT=()
XCODE_NOTES=()

xcode_category_enabled() {
  array_contains ios "${SELECTED_CATEGORIES[@]}"
}

check_xcode_clt() {
  xcode-select -p >/dev/null 2>&1
}

install_xcode_clt() {
  run xcode-select --install
}

check_full_xcode() {
  [[ -d /Applications/Xcode.app ]]
}

install_full_xcode() {
  if ! has_command mas; then
    run brew install mas
  fi
  run mas install 497799835
}

reconcile_xcode() {
  if [[ "${SKIP_XCODE:-false}" == "true" ]]; then
    warn "Skipping Xcode reconciliation"
    return 0
  fi

  if ! xcode_category_enabled; then
    log "Skipping Xcode reconciliation because ios is not enabled"
    return 0
  fi

  section "INFO" "Reconciling Xcode"
  if check_xcode_clt; then
    XCODE_COMPLIANT+=("Xcode Command Line Tools installed")
  else
    section "APPLY" "Installing Xcode Command Line Tools"
    install_xcode_clt
    XCODE_CHANGED+=("Requested Xcode Command Line Tools installation")
    XCODE_NOTES+=("Command Line Tools installation may require manual confirmation in a GUI dialog")
  fi

  if check_full_xcode; then
    XCODE_COMPLIANT+=("Full Xcode installed")
  else
    section "APPLY" "Installing full Xcode via App Store"
    install_full_xcode
    XCODE_CHANGED+=("Requested full Xcode installation")
    XCODE_NOTES+=("Full Xcode installation requires App Store authentication for mas")
  fi
}

print_xcode_report() {
  section "REPORT" "Xcode"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    print_block "Planned changes" "${XCODE_CHANGED[@]}"
  else
    print_block "Changed" "${XCODE_CHANGED[@]}"
  fi
  print_block "Already compliant" "${XCODE_COMPLIANT[@]}"
  print_block "Notes" "${XCODE_NOTES[@]}"
}
