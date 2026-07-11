#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib-install.sh"
require_root
validate_source
command -v shellcheck >/dev/null && shellcheck -e SC1091 "$PROJECT_ROOT/bin/codex-goal-watch" "$PROJECT_ROOT"/lib/codex-goal-watch/*.sh
command -v shfmt >/dev/null && shfmt -d -i 2 -ci "$PROJECT_ROOT/bin/codex-goal-watch" "$PROJECT_ROOT"/lib/codex-goal-watch/*.sh "$PROJECT_ROOT"/scripts/*.sh
command -v bats >/dev/null && bats "$PROJECT_ROOT/tests"
was_enabled=0
if service_call is-enabled --quiet codex-goal-watch.timer; then was_enabled=1; fi
backup_live
rollback() {
  restore_live
  service_call daemon-reload || true
  if ((was_enabled)); then service_call enable --now codex-goal-watch.timer || true; fi
  exit 1
}
trap rollback ERR
service_call stop codex-goal-watch.timer || true
service_call stop codex-goal-watch.service || true
install_payload
migrate_legacy_active
find "$(target /var/lib/codex-goal-watch)" -name armed-enter -type f -delete
service_call daemon-reload
if ((was_enabled)); then service_call enable --now codex-goal-watch.timer || true; fi
CGW_ETC="$(target /etc/codex-goal-watch)" CGW_STATE="$(target /var/lib/codex-goal-watch)" CGW_RUN="$(target /run/codex-goal-watch)" CGW_LIB_DIR="$(target /usr/local/lib/codex-goal-watch)" "$(target /usr/local/bin/codex-goal-watch)" doctor
CGW_ETC="$(target /etc/codex-goal-watch)" CGW_STATE="$(target /var/lib/codex-goal-watch)" CGW_RUN="$(target /run/codex-goal-watch)" CGW_LIB_DIR="$(target /usr/local/lib/codex-goal-watch)" "$(target /usr/local/bin/codex-goal-watch)" status --all
CGW_ETC="$(target /etc/codex-goal-watch)" CGW_STATE="$(target /var/lib/codex-goal-watch)" CGW_RUN="$(target /run/codex-goal-watch)" CGW_LIB_DIR="$(target /usr/local/lib/codex-goal-watch)" "$(target /usr/local/bin/codex-goal-watch)" inspect --all
trap - ERR
printf 'Updated. Backup: %s\n' "$BACKUP_DIR"
