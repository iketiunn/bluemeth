#!/usr/bin/env bash
set -euo pipefail

bash -n bin/bluemeth

bin/bluemeth -h |
  grep -F 'usage: bluemeth [MIN=60] | off | status | -h' >/dev/null

grep -F 'sleep:' bin/bluemeth >/dev/null
grep -F 'timer:' bin/bluemeth >/dev/null
grep -F 'm left' bin/bluemeth >/dev/null

if ! grep -F '  set -e' bin/bluemeth >/dev/null; then
  echo 'privileged enable block must fail before pmset when marker setup fails' >&2
  exit 1
fi

# shellcheck disable=SC2016
if grep -F 'expires_at="$4"' bin/bluemeth >/dev/null; then
  echo 'expires_at must be computed after sudo authentication' >&2
  exit 1
fi

# shellcheck disable=SC2016
if grep -F '"$seconds" "$expires_at"' bin/bluemeth >/dev/null; then
  echo 'expires_at must not be passed into the privileged block' >&2
  exit 1
fi

if grep -Eq -- '--bluemeth-test|--expire-token|BLUEMETH_TEST_MODE|BLUEMETH_TOKEN_FILE|TEST_MODE|SUDO=|PMSET=|SLEEP=' bin/bluemeth; then
  exit 1
fi
