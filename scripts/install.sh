#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib-install.sh"

user=''
session=''
window=auto
timezone=''
enable=0
install_deps=0
while (($#)); do
  case $1 in
    --user)
      user=${2:?}
      shift 2
      ;;
    --session)
      session=${2:?}
      shift 2
      ;;
    --window)
      window=${2:?}
      shift 2
      ;;
    --timezone)
      timezone=${2:?}
      shift 2
      ;;
    --enable)
      enable=1
      shift
      ;;
    --install-deps)
      install_deps=1
      shift
      ;;
    --non-interactive | --preserve-config) shift ;; *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done
require_root
validate_source
if ((install_deps)); then
  apt-get update
  apt-get install -y screen python3 psmisc util-linux
fi
backup_live
rollback() {
  restore_live
  service_call daemon-reload || true
  exit 1
}
trap rollback ERR
install_payload
if [[ -n $timezone ]]; then
  python3 - "$timezone" <<'PY'
import sys
from zoneinfo import ZoneInfo
ZoneInfo(sys.argv[1])
PY
  printf 'TIMEZONE=%s\n' "$timezone" >"$(target /etc/codex-goal-watch/config).new"
  awk -F= '$1 != "TIMEZONE" {print}' "$(target /etc/codex-goal-watch/config)" >>"$(target /etc/codex-goal-watch/config).new"
  mv "$(target /etc/codex-goal-watch/config).new" "$(target /etc/codex-goal-watch/config)"
fi
migrate_legacy_active
service_call daemon-reload
if [[ -n $session ]]; then
  CGW_ETC="$(target /etc/codex-goal-watch)" CGW_STATE="$(target /var/lib/codex-goal-watch)" CGW_RUN="$(target /run/codex-goal-watch)" CGW_LIB_DIR="$(target /usr/local/lib/codex-goal-watch)" \
    "$(target /usr/local/bin/codex-goal-watch)" add "$session" "$window" --user "${user:-root}" --force
fi
CGW_ETC="$(target /etc/codex-goal-watch)" CGW_STATE="$(target /var/lib/codex-goal-watch)" CGW_RUN="$(target /run/codex-goal-watch)" CGW_LIB_DIR="$(target /usr/local/lib/codex-goal-watch)" "$(target /usr/local/bin/codex-goal-watch)" doctor
CGW_ETC="$(target /etc/codex-goal-watch)" CGW_STATE="$(target /var/lib/codex-goal-watch)" CGW_RUN="$(target /run/codex-goal-watch)" CGW_LIB_DIR="$(target /usr/local/lib/codex-goal-watch)" "$(target /usr/local/bin/codex-goal-watch)" list
CGW_ETC="$(target /etc/codex-goal-watch)" CGW_STATE="$(target /var/lib/codex-goal-watch)" CGW_RUN="$(target /run/codex-goal-watch)" CGW_LIB_DIR="$(target /usr/local/lib/codex-goal-watch)" "$(target /usr/local/bin/codex-goal-watch)" status --all
CGW_ETC="$(target /etc/codex-goal-watch)" CGW_STATE="$(target /var/lib/codex-goal-watch)" CGW_RUN="$(target /run/codex-goal-watch)" CGW_LIB_DIR="$(target /usr/local/lib/codex-goal-watch)" "$(target /usr/local/bin/codex-goal-watch)" inspect --all
if ((enable)); then service_call enable --now codex-goal-watch.timer; fi
trap - ERR
printf 'Installed. Backup: %s\n' "$BACKUP_DIR"
