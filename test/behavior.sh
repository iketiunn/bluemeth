#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/bin/bluemeth"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bluemeth.XXXXXX")"
FAKE_BIN="$TEST_ROOT/bin"
RUNTIME_DIR="$TEST_ROOT/run"
TOKEN_FILE="$RUNTIME_DIR/disablesleep.token"
LOCK_FILE="$TEST_ROOT/bluemeth.lock"
LOG_FILE="$TEST_ROOT/commands.log"
STATE_FILE="$TEST_ROOT/sleep-disabled"
SUBJECT="$TEST_ROOT/bluemeth"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  echo "not ok - $1" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local haystack="$2"

  [[ "$haystack" == *"$needle"* ]] || fail "missing: $needle"
}

wait_for_log() {
  local needle="$1"

  for _ in {1..50}; do
    grep -Fq -- "$needle" "$LOG_FILE" && return 0
    sleep 0.02
  done

  fail "command was not run: $needle"
}

wait_for_file() {
  local path="$1"

  for _ in {1..50}; do
    [[ -f "$path" ]] && return 0
    sleep 0.02
  done

  fail "file was not created: $path"
}

setup() {
  rm -rf "$FAKE_BIN" "$TOKEN_FILE" "$LOG_FILE" "$STATE_FILE"
  mkdir -p "$FAKE_BIN" "$(dirname "$TOKEN_FILE")"
  : > "$LOG_FILE"
  printf '0\n' > "$STATE_FILE"

  cat > "$FAKE_BIN/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH

  cat > "$FAKE_BIN/pmset" <<'SH'
#!/usr/bin/env bash
printf 'pmset %s\n' "$*" >> "$BLUEMETH_TEST_LOG"
if [[ "${BLUEMETH_TEST_PMSET_FAIL_ARGS:-}" == "$*" ]]; then
  exit 77
fi
case "$*" in
  '-g')
    printf 'System-wide power settings:\n SleepDisabled\t\t%s\n' "$(cat "$BLUEMETH_TEST_STATE")"
    ;;
  '-a disablesleep 1')
    printf '1\n' > "$BLUEMETH_TEST_STATE"
    ;;
  '-a disablesleep 0')
    if [[ -n "${BLUEMETH_TEST_BLOCK_DISABLE_READY:-}" ]]; then
      : > "$BLUEMETH_TEST_BLOCK_DISABLE_READY"
      while [[ ! -f "$BLUEMETH_TEST_BLOCK_DISABLE_RELEASE" ]]; do
        sleep 0.01
      done
    fi
    printf '0\n' > "$BLUEMETH_TEST_STATE"
    ;;
  'sleepnow')
    ;;
  *)
    exit 64
    ;;
esac
SH

  cat > "$FAKE_BIN/sleep" <<'SH'
#!/usr/bin/env bash
if [[ -n "${BLUEMETH_TEST_SLEEP_RELEASE:-}" ]]; then
  while [[ ! -f "$BLUEMETH_TEST_SLEEP_RELEASE" ]]; do
    /bin/sleep 0.01
  done
fi
exit 0
SH

  cat > "$FAKE_BIN/ioreg" <<'SH'
#!/usr/bin/env bash
printf '  |   "AppleClamshellState" = %s\n' "${BLUEMETH_TEST_LID:-No}"
printf '  |   "AppleClamshellCausesSleep" = %s\n' "${BLUEMETH_TEST_LID_CAUSES_SLEEP:-No}"
SH

  cat > "$FAKE_BIN/lockf" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == -k ]] || exit 64
lock_file="$2"
shift 2
lock_dir="${lock_file}.test-lock"

while ! mkdir "$lock_dir" 2>/dev/null; do
  if [[ -n "${BLUEMETH_TEST_LOCK_WAIT_READY:-}" ]]; then
    : > "$BLUEMETH_TEST_LOCK_WAIT_READY"
  fi
  sleep 0.01
done
trap 'rmdir "$lock_dir"' EXIT

"$@"
SH

  cat > "$FAKE_BIN/touch" <<'SH'
#!/usr/bin/env bash
printf 'touch-umask %s\n' "$(umask)" >> "$BLUEMETH_TEST_LOG"
exec /usr/bin/touch "$@"
SH

  chmod +x "$FAKE_BIN"/*

  sed \
    -e "s|TOKEN_FILE=\"/var/run/bluemeth/disablesleep.token\"|TOKEN_FILE=\"$TOKEN_FILE\"|" \
    -e "s|LOCK_FILE=\"/var/run/bluemeth.lock\"|LOCK_FILE=\"$LOCK_FILE\"|" \
    -e "s|/usr/bin/sudo|$FAKE_BIN/sudo|g" \
    -e "s|/usr/bin/lockf|$FAKE_BIN/lockf|g" \
    -e "s|/usr/bin/touch|$FAKE_BIN/touch|g" \
    -e "s|/usr/bin/pmset|$FAKE_BIN/pmset|g" \
    -e "s|/usr/sbin/ioreg|$FAKE_BIN/ioreg|g" \
    -e "s|/bin/sleep|$FAKE_BIN/sleep|g" \
    "$SOURCE" > "$SUBJECT"
  chmod +x "$SUBJECT"
}

run_bluemeth() {
  BLUEMETH_TEST_LOG="$LOG_FILE" \
  BLUEMETH_TEST_STATE="$STATE_FILE" \
  BLUEMETH_TEST_LID="${BLUEMETH_TEST_LID:-No}" \
  BLUEMETH_TEST_LID_CAUSES_SLEEP="${BLUEMETH_TEST_LID_CAUSES_SLEEP:-No}" \
  BLUEMETH_TEST_PMSET_FAIL_ARGS="${BLUEMETH_TEST_PMSET_FAIL_ARGS:-}" \
  BLUEMETH_TEST_BLOCK_DISABLE_READY="${BLUEMETH_TEST_BLOCK_DISABLE_READY:-}" \
  BLUEMETH_TEST_BLOCK_DISABLE_RELEASE="${BLUEMETH_TEST_BLOCK_DISABLE_RELEASE:-}" \
  BLUEMETH_TEST_SLEEP_RELEASE="${BLUEMETH_TEST_SLEEP_RELEASE:-}" \
  BLUEMETH_TEST_LOCK_WAIT_READY="${BLUEMETH_TEST_LOCK_WAIT_READY:-}" \
  "$SUBJECT" "$@"
}

test_leading_zero_duration_is_decimal() {
  local output
  output="$(run_bluemeth 08 2>/dev/null)"

  assert_contains 'on: 8m' "$output"
  wait_for_log 'pmset -a disablesleep 1'
}

test_explicit_empty_duration_is_rejected() {
  local output result

  set +e
  output="$(run_bluemeth '' 2>&1)"
  result=$?
  set -e

  [[ "$result" -ne 0 ]] || fail 'explicit empty duration started the default timer'
  assert_contains 'usage: bluemeth' "$output"
  if grep -Fq -- 'pmset -a disablesleep 1' "$LOG_FILE"; then
    fail 'explicit empty duration changed sleep state'
  fi
}

test_duration_above_two_hours_requires_force() {
  local output result

  set +e
  output="$(run_bluemeth 121 2>&1)"
  result=$?
  set -e

  [[ "$result" -ne 0 ]] || fail 'duration above two hours succeeded without --force'
  assert_contains 'minutes above 120 require --force' "$output"
  if grep -Fq -- 'pmset -a disablesleep 1' "$LOG_FILE"; then
    fail 'rejected duration changed sleep state'
  fi
}

test_force_allows_one_day_ceiling() {
  local output

  output="$(run_bluemeth 1440 --force 2>&1)"

  assert_contains 'warning: a closed, running MacBook may overheat in a bag or sleeve; keep it ventilated' "$output"
  assert_contains 'on: 1440m' "$output"
  wait_for_log 'pmset -a disablesleep 1'
}

test_force_does_not_bypass_one_day_ceiling() {
  local output result

  set +e
  output="$(run_bluemeth 1441 --force 2>&1)"
  result=$?
  set -e

  [[ "$result" -ne 0 ]] || fail '--force bypassed one-day ceiling'
  assert_contains 'minutes must be <= 1440' "$output"
}

test_warning_is_stderr_and_success_is_stdout() {
  local stdout_file="$TEST_ROOT/stdout"
  local stderr_file="$TEST_ROOT/stderr"

  run_bluemeth 1 >"$stdout_file" 2>"$stderr_file"

  [[ "$(cat "$stdout_file")" == 'on: 1m' ]] || fail 'activation stdout changed'
  assert_contains 'warning: a closed, running MacBook may overheat in a bag or sleeve; keep it ventilated' "$(cat "$stderr_file")"
}

test_enable_refuses_unowned_disabled_sleep_state() {
  local output result

  printf '1\n' > "$STATE_FILE"

  set +e
  output="$(run_bluemeth 30 2>&1)"
  result=$?
  set -e

  [[ "$result" -ne 0 ]] || fail 'enable took ownership of an ambiguous disabled sleep state'
  assert_contains 'sleep is already disabled without an active bluemeth timer' "$output"
  [[ ! -f "$TOKEN_FILE" ]] || fail 'refused enable created a token'
}

test_enable_refuses_unknown_sleep_state() {
  local BLUEMETH_TEST_PMSET_FAIL_ARGS='-g'
  local output result

  set +e
  output="$(run_bluemeth 30 2>&1)"
  result=$?
  set -e

  [[ "$result" -ne 0 ]] || fail 'enable proceeded without a readable sleep state'
  assert_contains 'unable to determine current sleep state' "$output"
  [[ ! -f "$TOKEN_FILE" ]] || fail 'unknown sleep state created a token'
  if grep -Fq -- 'pmset -a disablesleep 1' "$LOG_FILE"; then
    fail 'unknown sleep state changed sleep settings'
  fi
}

test_failed_replacement_preserves_previous_timer() {
  local BLUEMETH_TEST_PMSET_FAIL_ARGS='-a disablesleep 1'
  local original_token='previous 9999999999'
  local output result

  printf '%s\n' "$original_token" > "$TOKEN_FILE"
  printf '1\n' > "$STATE_FILE"

  set +e
  output="$(run_bluemeth 30 2>&1)"
  result=$?
  set -e

  [[ "$result" -ne 0 ]] || fail 'failed replacement reported success'
  [[ -z "$output" ]] || fail 'failed replacement emitted success output or warning'
  [[ "$(cat "$TOKEN_FILE")" == "$original_token" ]] || fail 'failed replacement destroyed the previous timer token'
}

test_runtime_lock_is_private_without_hiding_timer_state() {
  run_bluemeth 1 >/dev/null 2>&1

  [[ "$(/usr/bin/stat -f '%Lp' "$RUNTIME_DIR")" == 755 ]] || fail 'timer directory is not readable for status'
  [[ "$(/usr/bin/stat -f '%Lp' "$LOCK_FILE")" == 600 ]] || fail 'lock file is not mode 600'
  grep -Eq '^touch-umask 0?077$' "$LOG_FILE" || fail 'lock file was not created under umask 077'
}

test_expiry_sleeps_when_closed_lid_normally_sleeps() {
  local BLUEMETH_TEST_LID=Yes
  local BLUEMETH_TEST_LID_CAUSES_SLEEP=Yes

  run_bluemeth 1 >/dev/null 2>&1
  wait_for_log 'pmset sleepnow'
}

test_expiry_does_not_sleep_when_lid_is_open() {
  local BLUEMETH_TEST_LID=No
  local BLUEMETH_TEST_LID_CAUSES_SLEEP=Yes

  run_bluemeth 1 >/dev/null 2>&1
  sleep 0.1
  if grep -Fq -- 'pmset sleepnow' "$LOG_FILE"; then
    fail 'open lid requested sleep'
  fi
}

test_expiry_leaves_external_display_clamshell_mode_awake() {
  local BLUEMETH_TEST_LID=Yes
  local BLUEMETH_TEST_LID_CAUSES_SLEEP=No

  run_bluemeth 1 >/dev/null 2>&1
  sleep 0.1
  if grep -Fq -- 'pmset sleepnow' "$LOG_FILE"; then
    fail 'external-display clamshell mode requested sleep'
  fi
}

test_off_sleeps_when_closed_lid_normally_sleeps() {
  local BLUEMETH_TEST_LID=Yes
  local BLUEMETH_TEST_LID_CAUSES_SLEEP=Yes

  printf 'token 9999999999\n' > "$TOKEN_FILE"
  printf '1\n' > "$STATE_FILE"
  run_bluemeth off >/dev/null 2>&1

  wait_for_log 'pmset sleepnow'
}

test_off_leaves_external_display_clamshell_mode_awake() {
  local BLUEMETH_TEST_LID=Yes
  local BLUEMETH_TEST_LID_CAUSES_SLEEP=No

  printf 'token 9999999999\n' > "$TOKEN_FILE"
  printf '1\n' > "$STATE_FILE"
  run_bluemeth off >/dev/null 2>&1

  if grep -Fq -- 'pmset sleepnow' "$LOG_FILE"; then
    fail 'off requested sleep in external-display clamshell mode'
  fi
}

test_off_failure_does_not_report_success_or_remove_token() {
  local BLUEMETH_TEST_PMSET_FAIL_ARGS='-a disablesleep 0'
  local output result

  printf 'token 9999999999\n' > "$TOKEN_FILE"
  printf '1\n' > "$STATE_FILE"

  set +e
  output="$(run_bluemeth off 2>&1)"
  result=$?
  set -e

  [[ "$result" -ne 0 ]] || fail 'off returned success after pmset failure'
  [[ "$output" != *'off'* ]] || fail 'off printed success after pmset failure'
  [[ -f "$TOKEN_FILE" ]] || fail 'off removed token after pmset failure'
}

test_new_session_cannot_be_cancelled_by_expiring_session() {
  local ready="$TEST_ROOT/disable-ready"
  local release="$TEST_ROOT/disable-release"
  local replacement_expiry="$TEST_ROOT/replacement-expiry"
  local replacement_wait="$TEST_ROOT/replacement-wait"
  local BLUEMETH_TEST_BLOCK_DISABLE_READY="$ready"
  local BLUEMETH_TEST_BLOCK_DISABLE_RELEASE="$release"
  local replacement_pid

  run_bluemeth 1 >/dev/null 2>&1
  wait_for_file "$ready"

  BLUEMETH_TEST_BLOCK_DISABLE_READY='' \
    BLUEMETH_TEST_BLOCK_DISABLE_RELEASE='' \
    BLUEMETH_TEST_SLEEP_RELEASE="$replacement_expiry" \
    BLUEMETH_TEST_LOCK_WAIT_READY="$replacement_wait" \
    run_bluemeth 1 >/dev/null 2>&1 &
  replacement_pid=$!
  wait_for_file "$replacement_wait"
  touch "$release"
  wait "$replacement_pid"

  for _ in {1..50}; do
    [[ "$(cat "$STATE_FILE")" == 0 ]] && break
    sleep 0.02
  done

  [[ "$(cat "$STATE_FILE")" == 1 ]] || fail 'old timer disabled sleep after replacement session started'
  [[ -f "$TOKEN_FILE" ]] || fail 'old timer removed the replacement session token'

  touch "$replacement_expiry"
  for _ in {1..50}; do
    [[ "$(cat "$STATE_FILE")" == 0 && ! -f "$TOKEN_FILE" ]] && return 0
    sleep 0.02
  done

  fail 'replacement session did not expire cleanly'
}

setup
test_leading_zero_duration_is_decimal
setup
test_explicit_empty_duration_is_rejected
setup
test_duration_above_two_hours_requires_force
setup
test_force_allows_one_day_ceiling
setup
test_force_does_not_bypass_one_day_ceiling
setup
test_warning_is_stderr_and_success_is_stdout
setup
test_enable_refuses_unowned_disabled_sleep_state
setup
test_enable_refuses_unknown_sleep_state
setup
test_failed_replacement_preserves_previous_timer
setup
test_runtime_lock_is_private_without_hiding_timer_state
setup
test_expiry_sleeps_when_closed_lid_normally_sleeps
setup
test_expiry_does_not_sleep_when_lid_is_open
setup
test_expiry_leaves_external_display_clamshell_mode_awake
setup
test_off_sleeps_when_closed_lid_normally_sleeps
setup
test_off_leaves_external_display_clamshell_mode_awake
setup
test_off_failure_does_not_report_success_or_remove_token
setup
test_new_session_cannot_be_cancelled_by_expiring_session

echo '17 passed, 0 failed'
