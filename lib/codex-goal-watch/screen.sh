#!/usr/bin/env bash
# shellcheck shell=bash

cgw_screen_as() {
  local user=$1
  shift
  if [[ $(id -un) == "$user" ]]; then
    screen "$@"
  else
    runuser -u "$user" -- screen "$@"
  fi
}

cgw_screen_list() {
  local user=$1
  cgw_screen_as "$user" -ls 2>/dev/null | awk '/\t[0-9]+\./ {gsub(/^[[:space:]]+|[[:space:]]+\(.*/, ""); print}'
}

cgw_resolve_session() {
  local requested=$1 user=$2 item found=
  while IFS= read -r item; do
    [[ -z $item ]] && continue
    if [[ $item == "$requested" || $(cgw_short_session "$item") == "$requested" ]]; then
      if [[ -n $found && $found != "$item" ]]; then
        return 2
      fi
      found=$item
    fi
  done < <(cgw_screen_list "$user")
  [[ -n $found ]] || return 1
  printf '%s\n' "$found"
}

cgw_session_pid() { printf '%s\n' "${1%%.*}"; }

cgw_session_has_codex() {
  local session=$1
  pstree -ap "$(cgw_session_pid "$session")" 2>/dev/null | grep -Eiq '(^|[^[:alnum:]_-])codex([^[:alnum:]_-]|$)'
}

cgw_windows() {
  local session=$1 user=$2
  cgw_screen_as "$user" -S "$session" -Q windows 2>/dev/null | tr ' ' '\n' | sed -nE 's/^([0-9]+)\$?.*/\1/p'
}

cgw_hardcopy() {
  local session=$1 user=$2 window=$3 file=$4
  : >"$file"
  cgw_screen_as "$user" -S "$session" -p "$window" -X hardcopy -h "$file" >/dev/null 2>&1 || return 1
  for _ in {1..20}; do
    [[ -s $file ]] && return 0
    sleep 0.05
  done
  return 1
}

cgw_send_resume() {
  local session=$1 user=$2 window=$3 mode=$4 payload
  if [[ $mode == TEXT_AND_ENTER ]]; then
    payload=$'/goal resume\r'
  else
    payload=$'\r'
  fi
  cgw_screen_as "$user" -S "$session" -p "$window" -X stuff "$payload"
}
