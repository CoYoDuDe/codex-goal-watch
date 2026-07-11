#!/usr/bin/env bash
# shellcheck shell=bash

cgw_state_file() { printf '%s/state' "$(cgw_session_state_dir "$1")"; }
cgw_global_state_file() { printf '%s/global/scheduler' "$CGW_STATE"; }

cgw_load_state() {
  declare -gA CGW_STATE_DATA=()
  local file line key value
  file=$(cgw_state_file "$1")
  [[ -r $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^([A-Z_]+)=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    [[ $value != *$'\n'* && $value != *$'\r'* ]] || continue
    CGW_STATE_DATA["$key"]=$value
  done <"$file"
}

cgw_write_state() {
  local session=$1 file dir tmp key
  dir=$(cgw_session_state_dir "$session")
  file=$(cgw_state_file "$session")
  install -d -m 0700 "$dir"
  tmp=$(mktemp "$dir/.state.XXXXXX")
  for key in STATUS FINGERPRINT RESET_EPOCH RELEASE_EPOCH ATTEMPTS LAST_ATTEMPT_EPOCH VERIFY_AFTER_EPOCH RETRY_AFTER_EPOCH WAITING_SINCE_EPOCH SESSION_IDENTITY LAST_DETAIL; do
    [[ -v CGW_STATE_DATA[$key] ]] && printf '%s=%s\n' "$key" "${CGW_STATE_DATA[$key]}" >>"$tmp"
  done
  chmod 0600 "$tmp"
  mv -f "$tmp" "$file"
}

cgw_clear_state() { rm -f -- "$(cgw_state_file "$1")"; }

cgw_load_global_state() {
  declare -gA CGW_GLOBAL=()
  local file line key value
  file=$(cgw_global_state_file)
  [[ -r $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^([A-Z_]+)=([0-9A-Za-z_.:-]+)$ ]] || continue
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    CGW_GLOBAL["$key"]=$value
  done <"$file"
}

cgw_write_global_state() {
  local file dir tmp key
  dir="$CGW_STATE/global"
  file=$(cgw_global_state_file)
  install -d -m 0700 "$dir"
  tmp=$(mktemp "$dir/.scheduler.XXXXXX")
  for key in COOLDOWN_UNTIL LAST_ACTION_SESSION LAST_ACTION_EPOCH; do
    [[ -v CGW_GLOBAL[$key] ]] && printf '%s=%s\n' "$key" "${CGW_GLOBAL[$key]}" >>"$tmp"
  done
  chmod 0600 "$tmp"
  mv -f "$tmp" "$file"
}

cgw_arm_file() { printf '%s/armed-enter' "$(cgw_session_state_dir "$1")"; }
cgw_is_armed() { [[ -f $(cgw_arm_file "$1") ]]; }
cgw_arm() {
  install -d -m 0700 "$(cgw_session_state_dir "$1")"
  umask 077
  printf 'armed=%s\n' "$(cgw_now)" >"$(cgw_arm_file "$1")"
}
cgw_disarm() { rm -f -- "$(cgw_arm_file "$1")"; }

cgw_cancel_pending_session() {
  cgw_load_state "$1"
  unset 'CGW_STATE_DATA[FINGERPRINT]' 'CGW_STATE_DATA[ATTEMPTS]' 'CGW_STATE_DATA[LAST_ATTEMPT_EPOCH]' 'CGW_STATE_DATA[VERIFY_AFTER_EPOCH]' 'CGW_STATE_DATA[RETRY_AFTER_EPOCH]' 'CGW_STATE_DATA[WAITING_SINCE_EPOCH]'
  CGW_STATE_DATA[STATUS]=IDLE
  cgw_write_state "$1"
}
