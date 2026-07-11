#!/usr/bin/env bash
# shellcheck shell=bash

cgw_now() {
  if [[ ${CGW_NOW:-} =~ ^[0-9]+$ ]]; then printf '%s\n' "$CGW_NOW"; else date +%s; fi
}

cgw_parse_reset_epoch() {
  local text=$1 now=${2:-$(cgw_now)}
  python3 "$CGW_LIB/timeutil.py" "$text" "$CGW_CONFIG_TIMEZONE" "$now"
}
