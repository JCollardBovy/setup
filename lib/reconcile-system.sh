#!/bin/bash

SYSTEM_CHANGED=()
SYSTEM_COMPLIANT=()
SYSTEM_WARNINGS=()

record_system_status() {
  local status="$1"
  local label="$2"
  case "$status" in
    changed) SYSTEM_CHANGED+=("$label") ;;
    compliant) SYSTEM_COMPLIANT+=("$label") ;;
    warning) SYSTEM_WARNINGS+=("$label") ;;
  esac
}

run_noncritical() {
  local label="$1"
  shift

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    run "$@"
    return 0
  fi

  if "$@"; then
    return 0
  fi

  warn "$label failed"
  record_system_status warning "$label"
  return 1
}

check_touch_id_sudo() {
  [[ -f /etc/pam.d/sudo_local ]] && grep -q 'pam_tid.so' /etc/pam.d/sudo_local 2>/dev/null
}

apply_touch_id_sudo() {
  run_noncritical "Touch ID for sudo copy" sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local || return 1
  run_noncritical "Touch ID for sudo enable" sudo sed -i '' '3s/.*/auth       sufficient     pam_tid.so/' /etc/pam.d/sudo_local
}

check_firewall_enabled() {
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q 'enabled'
}

apply_firewall_enabled() {
  run_noncritical "Firewall enable" sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
}

check_remote_login_disabled() {
  systemsetup -getremotelogin 2>/dev/null | grep -q 'Off'
}

apply_remote_login_disabled() {
  run_noncritical "Remote login disable" sudo systemsetup -f -setremotelogin off
}

check_guest_disabled() {
  local value
  value="$(defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled 2>/dev/null || echo 0)"
  [[ "$value" == "0" ]]
}

apply_guest_disabled() {
  run_noncritical "Guest account disable" sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
}

check_auto_login_disabled() {
  ! defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser >/dev/null 2>&1
}

apply_auto_login_disabled() {
  run_noncritical "Automatic login disable" sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser
}

check_defaults_value() {
  local domain="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  [[ "$actual" == "$expected" ]]
}

apply_defaults_value() {
  local domain="$1"
  local key="$2"
  local value_type="$3"
  local write_value="$4"
  run_noncritical "defaults write $domain $key" defaults write "$domain" "$key" "$value_type" "$write_value"
}

reconcile_check_apply() {
  local label="$1"
  local check_fn="$2"
  local apply_fn="$3"

  if "$check_fn"; then
    record_system_status compliant "$label"
  else
    section "APPLY" "$label"
    if "$apply_fn"; then
      record_system_status changed "$label"
    fi
  fi
}

reconcile_system_policy() {
  if [[ "${SKIP_SYSTEM:-false}" == "true" ]]; then
    warn "Skipping security and macOS policy reconciliation"
    return 0
  fi

  section "INFO" "Reconciling security policy"
  reconcile_check_apply "Touch ID for sudo" check_touch_id_sudo apply_touch_id_sudo
  reconcile_check_apply "Firewall enabled" check_firewall_enabled apply_firewall_enabled
  reconcile_check_apply "Remote login disabled" check_remote_login_disabled apply_remote_login_disabled
  reconcile_check_apply "Guest account disabled" check_guest_disabled apply_guest_disabled
  reconcile_check_apply "Automatic login disabled" check_auto_login_disabled apply_auto_login_disabled

  section "INFO" "Reconciling macOS defaults"
  reconcile_default "ApplePressAndHoldEnabled disabled" NSGlobalDomain ApplePressAndHoldEnabled -bool false 0
  reconcile_default "KeyRepeat set to 1" NSGlobalDomain KeyRepeat -int 1
  reconcile_default "InitialKeyRepeat set to 10" NSGlobalDomain InitialKeyRepeat -int 10
  reconcile_default "Finder shows hidden files" com.apple.finder AppleShowAllFiles -bool true 1
  reconcile_default "Finder shows status bar" com.apple.finder ShowStatusBar -bool true 1
  reconcile_default "Finder shows path bar" com.apple.finder ShowPathbar -bool true 1
  reconcile_default "Dock autohide enabled" com.apple.dock autohide -bool true 1
  reconcile_default "Dock recents disabled" com.apple.dock show-recents -bool false 0
  reconcile_default "Safari shows full URL" com.apple.Safari ShowFullURLInSmartSearchField -bool true 1
  reconcile_default "Safari safe downloads disabled" com.apple.Safari AutoOpenSafeDownloads -bool false 0
  reconcile_default "Automatic updates check enabled" com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true 1
  reconcile_default "App Store auto update enabled" com.apple.commerce AutoUpdate -bool true 1
  reconcile_default "App Store restart updates enabled" com.apple.commerce AutoUpdateRestartRequired -bool true 1

  section "APPLY" "Refreshing Dock and Finder"
  run_noncritical "Dock refresh" killall Dock || true
  run_noncritical "Finder refresh" killall Finder || true
}

reconcile_default() {
  local label="$1"
  local domain="$2"
  local key="$3"
  local value_type="$4"
  local write_value="$5"
  local expected="${6:-$5}"

  if check_defaults_value "$domain" "$key" "$expected"; then
    record_system_status compliant "$label"
  else
    section "APPLY" "$label"
    if apply_defaults_value "$domain" "$key" "$value_type" "$write_value"; then
      record_system_status changed "$label"
    fi
  fi
}

print_system_report() {
  section "REPORT" "System policy"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    print_block "Planned changes" "${SYSTEM_CHANGED[@]}"
  else
    print_block "Changed" "${SYSTEM_CHANGED[@]}"
  fi
  print_block "Already compliant" "${SYSTEM_COMPLIANT[@]}"
  print_block "Warnings" "${SYSTEM_WARNINGS[@]}"
}
