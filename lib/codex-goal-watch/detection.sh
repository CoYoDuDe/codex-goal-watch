#!/usr/bin/env bash
# shellcheck shell=bash

cgw_detect_file() {
  declare -gA CGW_DETECT=()
  local file=$1 line key value
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^([A-Z_]+)=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    CGW_DETECT["$key"]=$value
  done < <(python3 "$CGW_LIB/detect.py" <"$file")
}

cgw_capture_file() {
  install -d -m 0700 "$CGW_RUN"
  mktemp "$CGW_RUN/hardcopy.XXXXXX"
}

cgw_find_window() {
  local session=$1 user=$2 configured=$3 tmp window matches=() inspected=0
  tmp=$(cgw_capture_file)
  trap 'rm -f -- "$tmp"' RETURN
  if [[ $configured != auto ]]; then
    cgw_hardcopy "$session" "$user" "$configured" "$tmp" || return 1
    cgw_detect_file "$tmp"
    printf '%s\n' "$configured"
    return 0
  fi
  while IFS= read -r window; do
    [[ -z $window ]] && continue
    inspected=$((inspected + 1))
    ((inspected <= CGW_CONFIG_WINDOW_SCAN_MAX)) || break
    cgw_hardcopy "$session" "$user" "$window" "$tmp" || continue
    cgw_detect_file "$tmp"
    if [[ ${CGW_DETECT[LIMIT]} == 1 || ${CGW_DETECT[GOAL]} == 1 || ${CGW_DETECT[COMPLETE]} == 1 || ${CGW_DETECT[REPLACE]} == 1 ]]; then
      matches+=("$window")
    fi
  done < <(cgw_windows "$session" "$user")
  ((${#matches[@]} == 1)) || return 2
  printf '%s\n' "${matches[0]}"
}

cgw_analyze_session() {
  # Prints state, chosen window, raw reset text and an action class. Never sends input.
  local session=$1 user=$2 configured=$3 window tmp reset_epoch release_epoch now
  now=$(cgw_now)
  if window=$(cgw_find_window "$session" "$user" "$configured"); then
    :
  else
    local rc=$?
    case $rc in
      2) printf 'BLOCKED_COMPOSER_UNCERTAIN\t\t\tNONE\n' ;;
      *) printf 'ERROR\t\t\tNONE\n' ;;
    esac
    return 0
  fi
  tmp=$(cgw_capture_file)
  trap 'rm -f -- "$tmp"' RETURN
  cgw_hardcopy "$session" "$user" "$window" "$tmp" || {
    printf 'ERROR\t%s\t\tNONE\n' "$window"
    return
  }
  cgw_detect_file "$tmp"
  if [[ ${CGW_DETECT[COMPLETE]} == 1 ]]; then
    printf 'GOAL_COMPLETE\t%s\t\tNONE\n' "$window"
    return
  fi
  if [[ ${CGW_DETECT[REPLACE]} == 1 ]]; then
    printf 'REPLACE_GOAL_CONFIRMATION_BLOCKED\t%s\t\tNONE\n' "$window"
    return
  fi
  if [[ ${CGW_DETECT[LIMIT]} != 1 || ${CGW_DETECT[GOAL]} != 1 ]]; then
    printf 'NO_LIMIT\t%s\t\tNONE\n' "$window"
    return
  fi
  [[ -n ${CGW_DETECT[RESET_TEXT]} ]] || {
    printf 'GOAL_USAGE_LIMITED\t%s\t\tNONE\n' "$window"
    return
  }
  reset_epoch=$(cgw_parse_reset_epoch "${CGW_DETECT[RESET_TEXT]}" "$now") || {
    printf 'ERROR\t%s\t\tNONE\n' "$window"
    return
  }
  release_epoch=$((reset_epoch + CGW_CONFIG_GRACE_SECONDS))
  case ${CGW_DETECT[COMPOSER]} in
    EMPTY) action=TEXT_AND_ENTER ;;
    RESUME_VISIBLE) action=ENTER_ONLY ;;
    HIDDEN_PASTE) action=HIDDEN ;;
    UNKNOWN) action=UNKNOWN ;;
    *) action=UNCERTAIN ;;
  esac
  if ((now < release_epoch)); then
    printf 'WAITING_FOR_RESET\t%s\t%s\t%s\n' "$window" "$reset_epoch" "$action"
    return
  fi
  case $action in
    TEXT_AND_ENTER | ENTER_ONLY) printf 'READY_TO_RESUME\t%s\t%s\t%s\n' "$window" "$reset_epoch" "$action" ;;
    HIDDEN) printf 'BLOCKED_HIDDEN_PASTE\t%s\t%s\t%s\n' "$window" "$reset_epoch" "$action" ;;
    UNKNOWN) printf 'BLOCKED_UNKNOWN_INPUT\t%s\t%s\t%s\n' "$window" "$reset_epoch" "$action" ;;
    *) printf 'BLOCKED_COMPOSER_UNCERTAIN\t%s\t%s\t%s\n' "$window" "$reset_epoch" "$action" ;;
  esac
}
