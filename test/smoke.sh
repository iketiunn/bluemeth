#!/usr/bin/env bash
set -euo pipefail

bash -n bin/bluemeth

bin/bluemeth -h |
  grep -F 'usage: bluemeth [MIN=60] | off | status | -h' >/dev/null

! grep -Eq -- '--bluemeth-test|--expire-token|BLUEMETH_TEST_MODE|BLUEMETH_TOKEN_FILE|TEST_MODE|SUDO=|PMSET=|SLEEP=' bin/bluemeth
