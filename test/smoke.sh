#!/usr/bin/env bash
set -euo pipefail

bash -n bin/bluemeth
sh -n install.sh
bash test/behavior.sh

bin/bluemeth -h |
  grep -F 'usage: bluemeth [MIN=60] [--force] | off | status | -h' >/dev/null

bin/bluemeth -h |
  grep -F 'max: 120m (1440m with --force)' >/dev/null

grep -F 'version="v1.0.3"' install.sh >/dev/null
grep -F 'usage: install.sh [main]' install.sh >/dev/null
# shellcheck disable=SC2016
grep -F 'raw.githubusercontent.com/iketiunn/bluemeth/${version}/bin/bluemeth' install.sh >/dev/null

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
