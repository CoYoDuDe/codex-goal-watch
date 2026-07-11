#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib-install.sh"
keep_config=0 purge=0
while (($#)); do
  case $1 in --keep-config) keep_config=1 ;; --purge) purge=1 ;; --non-interactive) ;; *)
    printf 'Unknown option: %s\n' "$1" >&2
    exit 2
    ;;
  esac
  shift
done
require_root
service_call disable --now codex-goal-watch.timer || true
service_call stop codex-goal-watch.service || true
rm -f -- "$(target /etc/systemd/system/codex-goal-watch.service)" "$(target /etc/systemd/system/codex-goal-watch.timer)" "$(target /usr/local/bin/codex-goal-watch)"
rm -rf -- "$(target /usr/local/lib/codex-goal-watch)" "$(target /run/codex-goal-watch)"
if ((purge)); then
  rm -rf -- "$(target /etc/codex-goal-watch)" "$(target /var/lib/codex-goal-watch)"
elif ((keep_config)); then
  rm -rf -- "$(target /var/lib/codex-goal-watch)"
else
  rm -rf -- "$(target /etc/codex-goal-watch)" "$(target /var/lib/codex-goal-watch)"
fi
service_call daemon-reload
printf 'Uninstalled codex-goal-watch.\n'
