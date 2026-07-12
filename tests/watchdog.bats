#!/usr/bin/env bats

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  export CGW_LIB="$REPO/lib/codex-goal-watch"
  export CGW_LIB_DIR="$REPO/lib/codex-goal-watch"
  export CGW_ETC="$BATS_TEST_TMPDIR/etc"
  export CGW_STATE="$BATS_TEST_TMPDIR/state"
  export CGW_RUN="$BATS_TEST_TMPDIR/run"
  export MOCK_FIXTURES="$REPO/tests/fixtures"
  export MOCK_SEND_LOG="$BATS_TEST_TMPDIR/sends"
  export MOCK_SCREEN_SESSIONS='101.alpha:102.beta:'
  export PATH="$REPO/tests/helpers/bin:$PATH"
  export CGW_NOW=1767268800 # 2026-01-01 12:00 UTC
  mkdir -p "$CGW_ETC" "$CGW_STATE" "$CGW_RUN"
  cp "$REPO/config/config.example" "$CGW_ETC/config"
  sed -i 's/TIMEZONE=Europe\/Berlin/TIMEZONE=UTC/;s/GRACE_SECONDS=120/GRACE_SECONDS=0/;s/VERIFY_SECONDS=30/VERIFY_SECONDS=10/' "$CGW_ETC/config"
}

run_cgw() { run "$REPO/bin/codex-goal-watch" "$@"; }

@test "classifier accepts empty and visible resume composers" {
  run python3 "$CGW_LIB/detect.py"
  [ "$status" -eq 0 ]
  run bash -c "python3 '$CGW_LIB/detect.py' < '$MOCK_FIXTURES/ready-empty'"
  [[ "$output" == *'COMPOSER=EMPTY'* ]]
  run bash -c "python3 '$CGW_LIB/detect.py' < '$MOCK_FIXTURES/ready-visible'"
  [[ "$output" == *'COMPOSER=RESUME_VISIBLE'* ]]
}

@test "classifier blocks hidden paste, unknown input, missing goal and replace dialog" {
  run bash -c "python3 '$CGW_LIB/detect.py' < '$MOCK_FIXTURES/hidden'"; [[ "$output" == *'COMPOSER=HIDDEN_PASTE'* ]]
  run bash -c "python3 '$CGW_LIB/detect.py' < '$MOCK_FIXTURES/unknown'"; [[ "$output" == *'COMPOSER=UNKNOWN'* ]]
  run bash -c "python3 '$CGW_LIB/detect.py' < '$MOCK_FIXTURES/no-goal'"; [[ "$output" == *'GOAL=0'* ]]
  run bash -c "python3 '$CGW_LIB/detect.py' < '$MOCK_FIXTURES/replace'"; [[ "$output" == *'REPLACE=1'* ]]
}

@test "time parser handles AM PM 24-hour and next-day calculation" {
  run python3 "$CGW_LIB/timeutil.py" '12:00 PM' UTC "$CGW_NOW"; [ "$status" -eq 0 ]; [ "$output" = "$CGW_NOW" ]
  run python3 "$CGW_LIB/timeutil.py" '00:00' UTC "$CGW_NOW"; [ "$status" -eq 0 ]
  run python3 "$CGW_LIB/timeutil.py" '6:32 PM' Europe/Berlin 1767200400; [ "$status" -eq 0 ]
  run python3 "$CGW_LIB/timeutil.py" '25:99' UTC "$CGW_NOW"; [ "$status" -ne 0 ]
}

@test "wrapped reset and documented empty placeholder become a safe candidate" {
  run bash -c "python3 '$CGW_LIB/detect.py' < '$MOCK_FIXTURES/ready-wrapped-placeholder'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'RESET_TEXT=11:36 PM'* ]]
  [[ "$output" == *'COMPOSER=EMPTY'* ]]
  run python3 "$CGW_LIB/timeutil.py" '11:36 PM' UTC 1767226200
  [ "$status" -eq 0 ]
  [ "$output" -lt 1767226200 ]
}

@test "screen hardcopies use the shared runtime directory" {
  export MOCK_HARDCOPY_LOG="$BATS_TEST_TMPDIR/hardcopies"
  run_cgw add alpha
  run_cgw inspect alpha
  grep -q "^$CGW_RUN/" "$MOCK_HARDCOPY_LOG"
}

@test "hardcopy analysis waits for an asynchronously written screen file" {
  export MOCK_HARDCOPY_ASYNC=1
  run_cgw add alpha
  run_cgw inspect alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *'BLOCKED_COMPOSER_UNCERTAIN'* ]]
}

@test "explicit European dates are retained and parsed without daily rollover" {
  run bash -c "python3 '$CGW_LIB/detect.py' < '$MOCK_FIXTURES/ready-explicit-date'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'RESET_TEXT=18.07.2026 08:31'* ]]
  run python3 "$CGW_LIB/timeutil.py" '18.07.2026 08:31' Europe/Berlin "$CGW_NOW"
  [ "$status" -eq 0 ]
  [ "$output" -gt "$CGW_NOW" ]
}

@test "add enables multiple sessions and disable is session-specific" {
  run_cgw add alpha auto --priority 100; [ "$status" -eq 0 ]
  run_cgw add beta 0 --priority 50; [ "$status" -eq 0 ]
  run_cgw disable beta; [ "$status" -eq 0 ]
  run_cgw list; [[ "$output" == *101.alpha* ]]; [[ "$output" == *102.beta* ]]
  run_cgw deactivate; [ "$status" -ne 0 ]
}

@test "scheduler selects one highest-priority ready session" {
  export MOCK_FIXTURE=ready-empty
  run_cgw add alpha auto --priority 100
  run_cgw add beta auto --priority 50
  run_cgw run; [ "$status" -eq 0 ]
  [ "$(wc -l < "$MOCK_SEND_LOG")" -eq 1 ]
  grep -q '101.alpha' "$MOCK_SEND_LOG"
  ! grep -q '102.beta' "$MOCK_SEND_LOG"
}

@test "global cooldown retains other ready candidates" {
  export MOCK_FIXTURE=ready-empty
  run_cgw add alpha; run_cgw add beta
  run_cgw run
  : > "$MOCK_SEND_LOG"
  export CGW_NOW=1767268801
  run_cgw run; [ "$status" -eq 0 ]
  [ ! -s "$MOCK_SEND_LOG" ]
}

@test "hidden paste requires a session-specific arm and consumes it" {
  export MOCK_FIXTURE=hidden
  run_cgw add alpha
  run_cgw run; [ ! -s "$MOCK_SEND_LOG" ]
  run_cgw arm-enter alpha; [ "$status" -eq 0 ]
  run_cgw run; [ "$status" -eq 0 ]
  [ "$(wc -l < "$MOCK_SEND_LOG")" -eq 1 ]
  run_cgw status alpha; [[ "$output" == *'Armed enter: no'* ]]
}

@test "verification succeeds without assuming screen delivery is Codex success" {
  export MOCK_FIXTURE=ready-empty
  run_cgw add alpha; run_cgw run
  export MOCK_FIXTURE=normal
  export CGW_NOW=1767268811
  run_cgw run; [ "$status" -eq 0 ]
  run_cgw status alpha; [[ "$output" == *'State: RESUME_SUCCEEDED'* ]]
}

@test "unsafe and incomplete states never send" {
  for fixture in unknown no-goal no-reset replace complete; do
    export MOCK_FIXTURE="$fixture"
    run_cgw add alpha --force
    run_cgw run
    [ ! -s "$MOCK_SEND_LOG" ]
    rm -rf "$CGW_ETC/sessions.d" "$CGW_STATE/sessions"
    : > "$MOCK_SEND_LOG"
  done
}

@test "invalid config fails closed and global lock prevents a second run" {
  printf 'EVIL=$(id)\n' >> "$CGW_ETC/config"
  run_cgw doctor; [ "$status" -ne 0 ]
  sed -i '$d' "$CGW_ETC/config"
  export MOCK_FIXTURE=ready-empty
  run_cgw add alpha
  exec 8>"$CGW_RUN/watch.lock"; flock -n 8
  run_cgw run; [[ "$output" == *'global lock'* ]]
}
