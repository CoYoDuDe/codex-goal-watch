#!/usr/bin/env bash
# shellcheck shell=bash

cgw_log() { logger -t codex-goal-watch -- "$*" 2>/dev/null || true; }

cgw_session_identity() {
  local session=$1 window=$2
  printf '%s|%s|%s' "$(cgw_session_pid "$session")" "$session" "$window"
}

cgw_fingerprint() {
  local session=$1 window=$2 reset=$3
  printf '%s|%s|goal_usage_limited|%s' "$(cgw_session_identity "$session" "$window")" "$reset" "${CGW_SESSION[PRIORITY]}" | sha256sum | awk '{print $1}'
}

cgw_record_analysis() {
  local session=$1 full=$2 user=$3 status=$4 window=$5 reset=$6 action=$7 now=$8 fp prior
  cgw_load_state "$session"
  prior=${CGW_STATE_DATA[FINGERPRINT]:-}
  fp=
  if [[ -n $reset ]]; then fp=$(cgw_fingerprint "$full" "$window" "$reset"); fi
  if [[ -n $fp && $fp != "$prior" ]]; then
    CGW_STATE_DATA[ATTEMPTS]=0
    CGW_STATE_DATA[WAITING_SINCE_EPOCH]=$now
    unset 'CGW_STATE_DATA[LAST_ATTEMPT_EPOCH]' 'CGW_STATE_DATA[VERIFY_AFTER_EPOCH]' 'CGW_STATE_DATA[RETRY_AFTER_EPOCH]'
  fi
  # shellcheck disable=SC2153 # State map is declared in sourced state.sh.
  CGW_STATE_DATA[STATUS]=$status
  CGW_STATE_DATA[FINGERPRINT]=$fp
  CGW_STATE_DATA[RESET_EPOCH]=$reset
  CGW_STATE_DATA[RELEASE_EPOCH]=$((${reset:-0} + CGW_CONFIG_GRACE_SECONDS))
  CGW_STATE_DATA[SESSION_IDENTITY]=$(cgw_session_identity "$full" "$window")
  CGW_STATE_DATA[LAST_DETAIL]=$action
  cgw_write_state "$session"
}

cgw_may_resume() {
  local session=$1 now=$2
  cgw_load_state "$session"
  [[ ${CGW_STATE_DATA[STATUS]:-} == READY_TO_RESUME ]] || return 1
  [[ ${CGW_STATE_DATA[ATTEMPTS]:-0} =~ ^[0-9]+$ ]] || return 1
  ((${CGW_STATE_DATA[ATTEMPTS]:-0} < CGW_CONFIG_MAX_ATTEMPTS)) || return 1
  [[ -z ${CGW_STATE_DATA[RETRY_AFTER_EPOCH]:-} || $now -ge ${CGW_STATE_DATA[RETRY_AFTER_EPOCH]} ]] || return 1
}

cgw_send_candidate() {
  local session=$1 full=$2 user=$3 window=$4 action=$5 now=$6 expected=$7 verify
  cgw_load_state "$session"
  [[ ${CGW_STATE_DATA[FINGERPRINT]:-} == "$expected" ]] || return 1
  # Re-read target state immediately before any keypress to reject stale scheduling.
  local current status check_window reset
  current=$(cgw_analyze_session "$full" "$user" "$window")
  IFS=$'\t' read -r status check_window reset _ <<<"$current"
  if [[ $action == HIDDEN ]]; then
    [[ $status == BLOCKED_HIDDEN_PASTE && $check_window == "$window" && $(cgw_fingerprint "$full" "$window" "$reset") == "$expected" ]] || return 1
  else
    [[ $status == READY_TO_RESUME && $check_window == "$window" && $(cgw_fingerprint "$full" "$window" "$reset") == "$expected" ]] || return 1
  fi
  if [[ $action == HIDDEN ]]; then
    cgw_is_armed "$session" || return 1
    action=ENTER_ONLY
  fi
  cgw_send_resume "$full" "$user" "$window" "$action" || return 1
  ((CGW_STATE_DATA[ATTEMPTS] = ${CGW_STATE_DATA[ATTEMPTS]:-0} + 1))
  CGW_STATE_DATA[STATUS]=RESUME_SENT
  CGW_STATE_DATA[LAST_ATTEMPT_EPOCH]=$now
  verify=$((now + CGW_CONFIG_VERIFY_SECONDS))
  CGW_STATE_DATA[VERIFY_AFTER_EPOCH]=$verify
  cgw_write_state "$session"
  cgw_disarm "$session"
  CGW_GLOBAL[COOLDOWN_UNTIL]=$((now + CGW_CONFIG_GLOBAL_ACTION_COOLDOWN_SECONDS))
  CGW_GLOBAL[LAST_ACTION_SESSION]=$session
  # shellcheck disable=SC2034 # Read by the global-state writer in sourced state.sh.
  CGW_GLOBAL[LAST_ACTION_EPOCH]=$now
  cgw_write_global_state
  cgw_log "resume sent session=$session window=$window"
  return 0
}
