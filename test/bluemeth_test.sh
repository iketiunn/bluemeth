#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBJECT="$ROOT_DIR/bin/bluemeth"

TEST_TMP_ROOT="${TMPDIR:-/tmp}/bluemeth-tests.$$"
FAKE_BIN="$TEST_TMP_ROOT/bin"
LOG_FILE="$TEST_TMP_ROOT/commands.log"
TOKEN_FILE="$TEST_TMP_ROOT/run/bluemeth/disablesleep.token"
FAKE_PMSET_STATE="$TEST_TMP_ROOT/pmset-state"

pass_count=0
fail_count=0

cleanup() {
  rm -rf "$TEST_TMP_ROOT"
}
trap cleanup EXIT

setup_fake_commands() {
  rm -rf "$TEST_TMP_ROOT"
  mkdir -p "$FAKE_BIN" "$(dirname "$TOKEN_FILE")"
  : > "$LOG_FILE"
  printf '0\n' > "$FAKE_PMSET_STATE"

  cat > "$FAKE_BIN/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$BLUEMETH_TEST_LOG"
exec "$@"
SH
  chmod +x "$FAKE_BIN/sudo"

  cat > "$FAKE_BIN/pmset" <<'SH'
#!/usr/bin/env bash
printf 'pmset %s\n' "$*" >> "$BLUEMETH_TEST_LOG"
if [[ "${BLUEMETH_TEST_PMSET_FAIL_ARGS:-}" == "$*" ]]; then
  exit 77
fi
case "$*" in
  "-g")
    printf 'System-wide power settings:\n SleepDisabled\t\t%s\nCurrently in use:\n sleep                1\n' "$(cat "$BLUEMETH_TEST_PMSET_STATE")"
    ;;
  "-a disablesleep 1")
    printf '1\n' > "$BLUEMETH_TEST_PMSET_STATE"
    ;;
  "-a disablesleep 0")
    printf '0\n' > "$BLUEMETH_TEST_PMSET_STATE"
    ;;
  *)
    printf 'unexpected pmset args: %s\n' "$*" >&2
    exit 64
    ;;
esac
SH
  chmod +x "$FAKE_BIN/pmset"

  cat > "$FAKE_BIN/sleep" <<'SH'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >> "$BLUEMETH_TEST_LOG"
exit 0
SH
  chmod +x "$FAKE_BIN/sleep"

  cat > "$FAKE_BIN/uuidgen" <<'SH'
#!/usr/bin/env bash
printf 'fake-uuid\n'
SH
  chmod +x "$FAKE_BIN/uuidgen"
}

run_bluemeth() {
  BLUEMETH_TESTING=1 \
  BLUEMETH_TOKEN_FILE="$TOKEN_FILE" \
  BLUEMETH_TEST_LOG="$LOG_FILE" \
  BLUEMETH_TEST_PMSET_STATE="$FAKE_PMSET_STATE" \
  BLUEMETH_TEST_PMSET_FAIL_ARGS="${BLUEMETH_TEST_PMSET_FAIL_ARGS:-}" \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$SUBJECT" "$@"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\nexpected:\n%s\nactual:\n%s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'not ok - %s\nmissing: %s\nin:\n%s\n' "$message" "$needle" "$haystack" >&2
    exit 1
  fi
}

assert_file_contains() {
  local needle="$1"
  local file="$2"
  local message="$3"

  if ! grep -Fq "$needle" "$file"; then
    printf 'not ok - %s\nmissing: %s\nfile:\n%s\n' "$message" "$needle" "$(cat "$file" 2>/dev/null || true)" >&2
    exit 1
  fi
}

assert_file_not_contains() {
  local needle="$1"
  local file="$2"
  local message="$3"

  if grep -Fq "$needle" "$file"; then
    printf 'not ok - %s\nunexpected: %s\nfile:\n%s\n' "$message" "$needle" "$(cat "$file" 2>/dev/null || true)" >&2
    exit 1
  fi
}

test_case() {
  local name="$1"
  shift
  setup_fake_commands

  if ( set -e; "$@" ); then
    pass_count=$((pass_count + 1))
    printf 'ok - %s\n' "$name"
  else
    fail_count=$((fail_count + 1))
    printf 'not ok - %s\n' "$name" >&2
  fi
}

test_help_names_lid_close_sleep_disable() {
  local output
  output="$(run_bluemeth --help)"

  assert_contains "timed lid-close sleep disable" "$output" "help should describe lid-close behavior"
  assert_contains "usage: bluemeth [MIN=60] | off | status | -h" "$output" "help should show usage"
  assert_contains "max: 1440 minutes (24h)" "$output" "help should show max duration"
  if [[ "$output" == *"caffeinate"* ]]; then
    printf 'help should not mention caffeinate\n' >&2
    exit 1
  fi
}

test_default_duration_enables_disablesleep_for_60_minutes() {
  local output
  output="$(run_bluemeth)"

  assert_eq "on: 60m" "$output" "default invocation should print 60 minute duration"
  assert_file_contains "sudo pmset -a disablesleep 1" "$LOG_FILE" "default should enable pmset disablesleep"
  assert_file_contains "sleep 3600" "$LOG_FILE" "default should start 60 minute timer"
  assert_file_not_contains "caffeinate" "$LOG_FILE" "script must not call caffeinate"
}

test_explicit_duration_enables_disablesleep_for_requested_minutes() {
  local output
  output="$(run_bluemeth 30)"

  assert_eq "on: 30m" "$output" "explicit invocation should print requested duration"
  assert_file_contains "sudo pmset -a disablesleep 1" "$LOG_FILE" "explicit duration should enable pmset disablesleep"
  assert_file_contains "sleep 1800" "$LOG_FILE" "explicit duration should convert minutes to seconds"
}

test_invalid_duration_fails_without_pmset() {
  local output
  local status
  set +e
  output="$(run_bluemeth nope 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'invalid duration exited 0\n' >&2
    exit 1
  fi

  assert_contains "usage: bluemeth [MIN=60] | off | status | -h" "$output" "invalid duration should print usage"
  assert_file_not_contains "pmset -a disablesleep" "$LOG_FILE" "invalid duration should not change pmset"
}

test_zero_duration_fails_without_pmset() {
  local output
  local status
  set +e
  output="$(run_bluemeth 0 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'zero duration exited 0\n' >&2
    exit 1
  fi

  assert_contains "minutes must be > 0" "$output" "zero duration should explain failure"
  assert_file_not_contains "pmset -a disablesleep" "$LOG_FILE" "zero duration should not change pmset"
}

test_one_day_duration_is_allowed() {
  local output
  output="$(run_bluemeth 1440)"

  assert_eq "on: 1440m" "$output" "one day should be the maximum allowed duration"
  assert_file_contains "sudo pmset -a disablesleep 1" "$LOG_FILE" "one day should enable pmset disablesleep"
  assert_file_contains "sleep 86400" "$LOG_FILE" "one day should convert to 86400 seconds"
}

test_duration_above_one_day_fails_without_pmset() {
  local output
  local status
  set +e
  output="$(run_bluemeth 1441 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'duration above one day exited 0\n' >&2
    exit 1
  fi

  assert_contains "minutes must be <= 1440 (24h)" "$output" "duration above one day should explain max"
  assert_file_not_contains "pmset -a disablesleep" "$LOG_FILE" "duration above one day should not change pmset"
}

test_extra_arguments_fail_without_pmset() {
  local output
  local status
  set +e
  output="$(run_bluemeth 30 extra 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'extra arguments exited 0\n' >&2
    exit 1
  fi

  assert_contains "usage: bluemeth [MIN=60] | off | status | -h" "$output" "extra arguments should print usage"
  assert_file_not_contains "pmset -a disablesleep" "$LOG_FILE" "extra arguments should not change pmset"
}

test_production_token_file_ignores_environment_override() {
  local env_override_pattern="TOKEN_FILE=\"\${BLUEMETH_TOKEN_FILE"
  local fixed_token_pattern="TOKEN_FILE=\"\$DEFAULT_TOKEN_FILE\""

  if grep -Fq "$env_override_pattern" "$SUBJECT"; then
    printf 'production token file should not read BLUEMETH_TOKEN_FILE directly\n' >&2
    exit 1
  fi

  assert_file_contains 'DEFAULT_TOKEN_FILE="/var/run/bluemeth/disablesleep.token"' "$SUBJECT" "script should define fixed production token path"
  assert_file_contains "$fixed_token_pattern" "$SUBJECT" "script should use fixed production token path outside test mode"
}

test_off_removes_token_and_disables_sleepdisabled() {
  printf 'old-token\n' > "$TOKEN_FILE"

  local output
  output="$(run_bluemeth off)"

  assert_eq "off" "$output" "off should print off"
  assert_file_contains "sudo pmset -a disablesleep 0" "$LOG_FILE" "off should disable pmset disablesleep"
  if [[ -e "$TOKEN_FILE" ]]; then
    printf 'token file still exists\n' >&2
    exit 1
  fi
}

test_off_pmset_failure_leaves_token() {
  printf 'old-token\n' > "$TOKEN_FILE"

  local BLUEMETH_TEST_PMSET_FAIL_ARGS="-a disablesleep 0"
  local output
  local status
  set +e
  output="$(run_bluemeth off 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'off exited 0 when pmset failed\n' >&2
    exit 1
  fi

  assert_eq "old-token" "$(cat "$TOKEN_FILE")" "off should leave token when pmset disable fails"
  assert_file_contains "sudo pmset -a disablesleep 0" "$LOG_FILE" "off should attempt to disable pmset"
  assert_file_not_contains "sudo rm -f $TOKEN_FILE" "$LOG_FILE" "off should not remove token after pmset failure"
  assert_eq "" "$output" "off should not print success when pmset fails"
}

test_enable_pmset_failure_removes_new_token() {
  local BLUEMETH_TEST_PMSET_FAIL_ARGS="-a disablesleep 1"
  local output
  local status
  set +e
  output="$(run_bluemeth 30 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'enable exited 0 when pmset failed\n' >&2
    exit 1
  fi

  if [[ -e "$TOKEN_FILE" ]]; then
    printf 'enable left token after pmset failure: %s\n' "$(cat "$TOKEN_FILE")" >&2
    exit 1
  fi

  assert_file_contains "sudo pmset -a disablesleep 1" "$LOG_FILE" "enable should attempt to set pmset"
  assert_file_contains "sudo rm -f $TOKEN_FILE" "$LOG_FILE" "enable should roll back its token"
  assert_eq "" "$output" "enable should not print success when pmset fails"
}

test_status_reports_sleepdisabled_and_timer_state() {
  printf '1\n' > "$FAKE_PMSET_STATE"
  printf 'token\n' > "$TOKEN_FILE"

  local output
  output="$(run_bluemeth status)"

  assert_contains "SleepDisabled: 1" "$output" "status should parse SleepDisabled"
  assert_contains "timer: active" "$output" "status should report active token"
  if [[ "$output" == *"caffeinate"* || "$output" == *"mode:"* ]]; then
    printf 'status should stay terse\n' >&2
    exit 1
  fi
}

test_status_reports_missing_timer() {
  local output
  output="$(run_bluemeth status)"

  assert_contains "SleepDisabled: 0" "$output" "status should parse disabled SleepDisabled"
  assert_contains "timer: none" "$output" "status should report missing token"
}

test_newer_timer_token_prevents_older_timer_from_turning_off() {
  BLUEMETH_TESTING=1 \
  BLUEMETH_TOKEN_FILE="$TOKEN_FILE" \
  BLUEMETH_TEST_LOG="$LOG_FILE" \
  BLUEMETH_TEST_PMSET_STATE="$FAKE_PMSET_STATE" \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$SUBJECT" 30 >/dev/null

  if [[ ! -f "$TOKEN_FILE" ]]; then
    printf 'newer timer did not create token file\n' >&2
    exit 1
  fi

  local newer_token
  newer_token="$(cat "$TOKEN_FILE")"

  BLUEMETH_TESTING=1 \
  BLUEMETH_TOKEN_FILE="$TOKEN_FILE" \
  BLUEMETH_TEST_LOG="$LOG_FILE" \
  BLUEMETH_TEST_PMSET_STATE="$FAKE_PMSET_STATE" \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$SUBJECT" --expire-token stale-token >/dev/null

  assert_eq "$newer_token" "$(cat "$TOKEN_FILE")" "stale timer should leave newer token in place"
  assert_file_not_contains "sudo pmset -a disablesleep 0" "$LOG_FILE" "stale timer should not disable SleepDisabled"
}

test_matching_timer_token_turns_off() {
  printf 'matching-token\n' > "$TOKEN_FILE"

  BLUEMETH_TESTING=1 \
  BLUEMETH_TOKEN_FILE="$TOKEN_FILE" \
  BLUEMETH_TEST_LOG="$LOG_FILE" \
  BLUEMETH_TEST_PMSET_STATE="$FAKE_PMSET_STATE" \
  PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$SUBJECT" --expire-token matching-token >/dev/null

  assert_file_contains "sudo pmset -a disablesleep 0" "$LOG_FILE" "matching timer should disable SleepDisabled"
  if [[ -e "$TOKEN_FILE" ]]; then
    printf 'matching timer did not remove token file\n' >&2
    exit 1
  fi
}

test_case "help names lid-close sleep disable" test_help_names_lid_close_sleep_disable
test_case "default duration enables disablesleep for 60 minutes" test_default_duration_enables_disablesleep_for_60_minutes
test_case "explicit duration enables disablesleep for requested minutes" test_explicit_duration_enables_disablesleep_for_requested_minutes
test_case "invalid duration fails without pmset" test_invalid_duration_fails_without_pmset
test_case "zero duration fails without pmset" test_zero_duration_fails_without_pmset
test_case "one day duration is allowed" test_one_day_duration_is_allowed
test_case "duration above one day fails without pmset" test_duration_above_one_day_fails_without_pmset
test_case "extra arguments fail without pmset" test_extra_arguments_fail_without_pmset
test_case "production token file ignores environment override" test_production_token_file_ignores_environment_override
test_case "off removes token and disables SleepDisabled" test_off_removes_token_and_disables_sleepdisabled
test_case "off pmset failure leaves token" test_off_pmset_failure_leaves_token
test_case "enable pmset failure removes new token" test_enable_pmset_failure_removes_new_token
test_case "status reports SleepDisabled and timer state" test_status_reports_sleepdisabled_and_timer_state
test_case "status reports missing timer" test_status_reports_missing_timer
test_case "newer timer token prevents older timer from turning off" test_newer_timer_token_prevents_older_timer_from_turning_off
test_case "matching timer token turns off" test_matching_timer_token_turns_off

printf '%s passed, %s failed\n' "$pass_count" "$fail_count"
[[ "$fail_count" -eq 0 ]]
