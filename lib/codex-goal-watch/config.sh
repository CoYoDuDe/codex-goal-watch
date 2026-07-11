#!/usr/bin/env bash
# shellcheck shell=bash

declare -Ag CGW_CONFIG=()
declare -Ag CGW_SESSION=()

cgw_defaults() {
  CGW_CONFIG=(
    [TIMEZONE]=Europe/Berlin
    [GRACE_SECONDS]=120
    [RETRY_SECONDS]=900
    [VERIFY_SECONDS]=30
    [MAX_ATTEMPTS]=3
    [WINDOW_SCAN_MAX]=30
    [SCREEN_USER]=root
    [LOG_LEVEL]=info
    [HARD_COPY_LINES]=100
    [MAX_CONCURRENT_SESSIONS]=1
    [GLOBAL_ACTION_COOLDOWN_SECONDS]=120
  )
}

cgw_allowed_global_key() {
  case "$1" in
    TIMEZONE | GRACE_SECONDS | RETRY_SECONDS | VERIFY_SECONDS | MAX_ATTEMPTS | WINDOW_SCAN_MAX | SCREEN_USER | LOG_LEVEL | HARD_COPY_LINES | MAX_CONCURRENT_SESSIONS | GLOBAL_ACTION_COOLDOWN_SECONDS) return 0 ;;
    *) return 1 ;;
  esac
}

cgw_parse_kv_file() {
  local file=$1 target=$2 line key value number=0
  [[ -r $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    number=$((number + 1))
    [[ -z $line || $line == \#* ]] && continue
    if [[ ! $line =~ ^([A-Z_]+)=(.*)$ ]]; then
      cgw_error "Invalid configuration syntax in $file:$number"
      return 1
    fi
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    local forbidden_substitution="\$("
    [[ $value != *$'\n'* && $value != *$'\r'* && $value != *"$forbidden_substitution"* && $value != *'`'* ]] || {
      cgw_error "Unsafe configuration value in $file:$number"
      return 1
    }
    if [[ $target == global ]]; then
      cgw_allowed_global_key "$key" || {
        cgw_error "Unknown configuration key: $key"
        return 1
      }
      CGW_CONFIG["$key"]=$value
    else
      case $key in SESSION | WINDOW | USER | PRIORITY | ENABLED | CREATED_EPOCH) CGW_SESSION["$key"]=$value ;;
      *)
        cgw_error "Unknown session key in $file: $key"
        return 1
        ;;
      esac
    fi
  done <"$file"
}

cgw_is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }

cgw_validate_global_config() {
  local key value
  for key in GRACE_SECONDS RETRY_SECONDS VERIFY_SECONDS MAX_ATTEMPTS WINDOW_SCAN_MAX HARD_COPY_LINES MAX_CONCURRENT_SESSIONS GLOBAL_ACTION_COOLDOWN_SECONDS; do
    value=${CGW_CONFIG[$key]}
    if ! cgw_is_uint "$value" || ((value > 864000)); then
      cgw_error "Invalid $key"
      return 1
    fi
  done
  ((CGW_CONFIG[MAX_ATTEMPTS] >= 1 && CGW_CONFIG[WINDOW_SCAN_MAX] >= 1 && CGW_CONFIG[HARD_COPY_LINES] >= 20)) || {
    cgw_error "Configuration value below safe minimum"
    return 1
  }
  [[ ${CGW_CONFIG[SCREEN_USER]} =~ ^[a-z_][a-z0-9_-]*$ ]] || {
    cgw_error "Invalid SCREEN_USER"
    return 1
  }
  [[ ${CGW_CONFIG[LOG_LEVEL]} =~ ^(debug|info|warn|error)$ ]] || {
    cgw_error "Invalid LOG_LEVEL"
    return 1
  }
  [[ ${CGW_CONFIG[MAX_CONCURRENT_SESSIONS]} == 1 ]] || {
    cgw_error "v0.1.0 only supports MAX_CONCURRENT_SESSIONS=1"
    return 1
  }
  python3 - "${CGW_CONFIG[TIMEZONE]}" <<'PY' >/dev/null 2>&1
import sys
from zoneinfo import ZoneInfo
ZoneInfo(sys.argv[1])
PY
}

cgw_load_config() {
  cgw_defaults
  cgw_parse_kv_file "$CGW_ETC/config" global || return
  cgw_validate_global_config
}

cgw_short_session() { printf '%s\n' "${1#*.}"; }
cgw_session_key() { printf '%s' "$1" | sha256sum | awk '{print substr($1, 1, 24)}'; }
cgw_session_file() { printf '%s/sessions.d/%s.conf' "$CGW_ETC" "$(cgw_session_key "$1")"; }
cgw_session_state_dir() { printf '%s/sessions/%s' "$CGW_STATE" "$(cgw_session_key "$1")"; }

cgw_validate_session() {
  [[ -n ${CGW_SESSION[SESSION]:-} && ${CGW_SESSION[SESSION]} != *$'\n'* ]] || return 1
  [[ ${CGW_SESSION[WINDOW]:-auto} == auto || ${CGW_SESSION[WINDOW]:-} =~ ^[0-9]+$ ]] || return 1
  [[ ${CGW_SESSION[USER]:-} =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
  cgw_is_uint "${CGW_SESSION[PRIORITY]:-}" && ((CGW_SESSION[PRIORITY] <= 100000)) || return 1
  [[ ${CGW_SESSION[ENABLED]:-} == 0 || ${CGW_SESSION[ENABLED]:-} == 1 ]] || return 1
}

cgw_load_session_file() {
  local file=$1
  CGW_SESSION=()
  cgw_parse_kv_file "$file" session || return
  cgw_validate_session || {
    cgw_error "Invalid session registry: $file"
    return 1
  }
}

cgw_write_session() {
  local file tmp
  file=$(cgw_session_file "${CGW_SESSION[SESSION]}")
  install -d -m 0700 "$(dirname "$file")"
  tmp=$(mktemp "$(dirname "$file")/.session.XXXXXX")
  {
    printf 'SESSION=%s\n' "${CGW_SESSION[SESSION]}"
    printf 'WINDOW=%s\n' "${CGW_SESSION[WINDOW]}"
    printf 'USER=%s\n' "${CGW_SESSION[USER]}"
    printf 'PRIORITY=%s\n' "${CGW_SESSION[PRIORITY]}"
    printf 'ENABLED=%s\n' "${CGW_SESSION[ENABLED]}"
    printf 'CREATED_EPOCH=%s\n' "${CGW_SESSION[CREATED_EPOCH]}"
  } >"$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$file"
}

cgw_find_session_file() {
  local wanted=$1 file
  shopt -s nullglob
  for file in "$CGW_ETC"/sessions.d/*.conf; do
    cgw_load_session_file "$file" || return 1
    if [[ ${CGW_SESSION[SESSION]} == "$wanted" || $(cgw_short_session "${CGW_SESSION[SESSION]}") == "$wanted" ]]; then
      printf '%s\n' "$file"
      return 0
    fi
  done
  return 1
}

cgw_iter_session_files() {
  shopt -s nullglob
  printf '%s\n' "$CGW_ETC"/sessions.d/*.conf
}
