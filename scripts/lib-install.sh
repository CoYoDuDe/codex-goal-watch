#!/usr/bin/env bash
# Shared safe installation helpers; invoked only by dedicated scripts.
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_ROOT=${CGW_INSTALL_ROOT:-}
target() { printf '%s%s\n' "$INSTALL_ROOT" "$1"; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || {
  printf '%s\n' 'must run as root' >&2
  exit 1
}; }
atomic_install() {
  local source=$1 destination=$2 mode=$3 dir tmp
  dir=$(dirname "$destination")
  install -d -m 0755 "$dir"
  tmp=$(mktemp "$dir/.cgw.XXXXXX")
  install -m "$mode" "$source" "$tmp"
  mv -f "$tmp" "$destination"
}
copy_tree_atomic() {
  local source=$1 destination=$2 stage
  install -d -m 0755 "$(dirname "$destination")"
  stage=$(mktemp -d "$(dirname "$destination")/.cgw-tree.XXXXXX")
  cp -a "$source"/. "$stage"/
  find "$stage" -type d -exec chmod 0755 {} +
  find "$stage" -type f -name '*.sh' -exec chmod 0644 {} +
  find "$stage" -type f -name '*.py' -exec chmod 0755 {} +
  rm -rf "$destination"
  mv "$stage" "$destination"
}
service_call() { systemctl "$@"; }
backup_live() {
  BACKUP_DIR=$(mktemp -d "$(target /var/backups)/codex-goal-watch.XXXXXX")
  chmod 0700 "$BACKUP_DIR"
  for path in /usr/local/bin/codex-goal-watch /usr/local/lib/codex-goal-watch /etc/codex-goal-watch /etc/systemd/system/codex-goal-watch.service /etc/systemd/system/codex-goal-watch.timer /var/lib/codex-goal-watch; do
    [[ -e $(target "$path") ]] || continue
    mkdir -p "$BACKUP_DIR$(dirname "$path")"
    cp -a -- "$(target "$path")" "$BACKUP_DIR$path"
  done
}
restore_live() {
  [[ -n ${BACKUP_DIR:-} && -d $BACKUP_DIR ]] || return 0
  for path in /usr/local/bin/codex-goal-watch /usr/local/lib/codex-goal-watch /etc/codex-goal-watch /etc/systemd/system/codex-goal-watch.service /etc/systemd/system/codex-goal-watch.timer /var/lib/codex-goal-watch; do
    rm -rf -- "$(target "$path")"
    [[ -e $BACKUP_DIR$path ]] || continue
    mkdir -p "$(dirname "$(target "$path")")"
    cp -a -- "$BACKUP_DIR$path" "$(target "$path")"
  done
}
validate_source() {
  bash -n "$PROJECT_ROOT/bin/codex-goal-watch"
  find "$PROJECT_ROOT/lib/codex-goal-watch" -name '*.sh' -print0 | xargs -0 -r -n1 bash -n
  python3 -m py_compile "$PROJECT_ROOT"/lib/codex-goal-watch/*.py
}
install_payload() {
  atomic_install "$PROJECT_ROOT/bin/codex-goal-watch" "$(target /usr/local/bin/codex-goal-watch)" 0755
  copy_tree_atomic "$PROJECT_ROOT/lib/codex-goal-watch" "$(target /usr/local/lib/codex-goal-watch)"
  atomic_install "$PROJECT_ROOT/VERSION" "$(target /usr/local/lib/codex-goal-watch/VERSION)" 0644
  atomic_install "$PROJECT_ROOT/systemd/codex-goal-watch.service" "$(target /etc/systemd/system/codex-goal-watch.service)" 0644
  atomic_install "$PROJECT_ROOT/systemd/codex-goal-watch.timer" "$(target /etc/systemd/system/codex-goal-watch.timer)" 0644
  install -d -m 0700 "$(target /etc/codex-goal-watch)" "$(target /etc/codex-goal-watch/sessions.d)" "$(target /var/lib/codex-goal-watch)" "$(target /run/codex-goal-watch)"
  if [[ ! -e $(target /etc/codex-goal-watch/config) ]]; then atomic_install "$PROJECT_ROOT/config/config.example" "$(target /etc/codex-goal-watch/config)" 0600; fi
  chmod 0600 "$(target /etc/codex-goal-watch/config)"
}
migrate_legacy_active() {
  local etc active session window
  etc=$(target /etc/codex-goal-watch)
  active="$etc/active"
  [[ -r $active && ! -d $etc/sessions.d ]] && install -d -m 0700 "$etc/sessions.d"
  [[ -r $active ]] || return 0
  [[ -n $(find "$etc/sessions.d" -type f -name '*.conf' -print -quit) ]] && return 0
  session=$(sed -n '1p' "$active" | tr -d '\r\n')
  window=$(sed -n '2p' "$active" | tr -d '\r\n')
  [[ -n $session ]] || return 0
  CGW_ETC="$etc" CGW_STATE="$(target /var/lib/codex-goal-watch)" CGW_RUN="$(target /run/codex-goal-watch)" CGW_LIB_DIR="$(target /usr/local/lib/codex-goal-watch)" \
    "$(target /usr/local/bin/codex-goal-watch)" add "$session" "${window:-auto}" --force
  mv -f "$active" "$active.migrated-v0.1.0"
  rm -f -- "$etc/armed-enter"
}
