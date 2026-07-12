#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/bin/bluemeth"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bluemeth.XXXXXX")"
FAKE_BIN="$TEST_ROOT/bin"
TOKEN_FILE="$TEST_ROOT/run/disablesleep.token"
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

  chmod +x "$FAKE_BIN"/*

  sed \
    -e "s|TOKEN_FILE=\"/var/run/bluemeth/disablesleep.token\"|TOKEN_FILE=\"$TOKEN_FILE\"|" \
    -e "s|LOCK_FILE=\"/var/run/bluemeth.lock\"|LOCK_FILE=\"$TEST_ROOT/bluemeth.lock\"|" \
    -e "s|/usr/bin/sudo|$FAKE_BIN/sudo|g" \
    -e "s|/usr/bin/lockf|$FAKE_BIN/lockf|g" \
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
  output="$(run_bluemeth 08)"

  assert_contains 'on: 8m' "$output"
  wait_for_log 'pmset -a disablesleep 1'
}

test_expiry_sleeps_when_closed_lid_normally_sleeps() {
  local BLUEMETH_TEST_LID=Yes
  local BLUEMETH_TEST_LID_CAUSES_SLEEP=Yes

  run_bluemeth 1 >/dev/null
  wait_for_log 'pmset sleepnow'
}

test_expiry_does_not_sleep_when_lid_is_open() {
  local BLUEMETH_TEST_LID=No
  local BLUEMETH_TEST_LID_CAUSES_SLEEP=Yes

  run_bluemeth 1 >/dev/null
  sleep 0.1
  if grep -Fq -- 'pmset sleepnow' "$LOG_FILE"; then
    fail 'open lid requested sleep'
  fi
}

test_expiry_sleeps_when_lid_closed_in_external_display_clamshell_mode() {
  local BLUEMETH_TEST_LID=Yes
  local BLUEMETH_TEST_LID_CAUSES_SLEEP=No

  run_bluemeth 1 >/dev/null
  wait_for_log 'pmset sleepnow'
}

test_off_sleeps_when_closed_lid_normally_sleeps() {
  local BLUEMETH_TEST_LID=Yes
  local BLUEMETH_TEST_LID_CAUSES_SLEEP=Yes

  printf 'token 9999999999\n' > "$TOKEN_FILE"
  printf '1\n' > "$STATE_FILE"
  run_bluemeth off >/dev/null

  wait_for_log 'pmset sleepnow'
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

  run_bluemeth 1 >/dev/null
  wait_for_file "$ready"

  BLUEMETH_TEST_BLOCK_DISABLE_READY='' \
    BLUEMETH_TEST_BLOCK_DISABLE_RELEASE='' \
    BLUEMETH_TEST_SLEEP_RELEASE="$replacement_expiry" \
    BLUEMETH_TEST_LOCK_WAIT_READY="$replacement_wait" \
    run_bluemeth 1 >/dev/null &
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
test_expiry_sleeps_when_closed_lid_normally_sleeps
setup
test_expiry_does_not_sleep_when_lid_is_open
setup
test_expiry_sleeps_when_lid_closed_in_external_display_clamshell_mode
setup
test_off_sleeps_when_closed_lid_normally_sleeps
setup
test_off_failure_does_not_report_success_or_remove_token
setup
test_new_session_cannot_be_cancelled_by_expiring_session

echo '7 passed, 0 failed'
