#!/usr/bin/env bash
# Run on a Linux box: bash tsme6/t/test_tsme_net.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
python3 "$here/tsme_net.py" selftest | tail -n 1 | grep -q 'SELFTEST: PASS'
bash -n "$here/verify.sh"
"$here/verify.sh" --help | grep -q 'discover'
OUT=$(mktemp -d) "$here/verify.sh" --status >/dev/null
echo "tsme6 tests: PASS"
