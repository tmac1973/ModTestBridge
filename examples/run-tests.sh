#!/usr/bin/env bash
# Run a mod's in-game tests through ModTestBridge and exit non-zero if any failed.
#   examples/run-tests.sh [--restart] [test]     (default test: all)
# --restart quits the game, backs up the saves and relaunches into MTB_WORLD as MTB_CHARACTER first (for testing a new
# build of your mod). Works with the ExampleTests pattern: "[TEST] result ..." per test, "[TEST] done ..." at the end.
set -euo pipefail
MTB="${MTB:-$(command -v mtb || echo "$(dirname "$0")/../claude-plugin/bin/mtb")}"
restart=0; [[ "${1:-}" == "--restart" ]] && { restart=1; shift; }
test="${1:-all}"

if (( restart )); then "$MTB" restart >/dev/null; else "$MTB" wait-world 60 >/dev/null; fi

from=$("$MTB" mark)   # where the log is now
"$MTB" run "example_test $test" "[TEST] done" "${TEST_TIMEOUT:-900}" >/dev/null || { echo "no result (timed out)"; exit 2; }

# Every result line since we started, and the failed checks.
"$MTB" log "$from" "[TEST] result" 2>/dev/null | sed 's/.*\[TEST\] result //'
"$MTB" log "$from" "pass=false" 2>/dev/null | grep '\[TEST\] check' | sed 's/.*\[TEST\] check /  FAILED /' || true
summary=$("$MTB" log "$from" "[TEST] done" 2>/dev/null | tail -1 | sed 's/.*\[TEST\] done //')
echo "$summary"
[[ "$summary" == *"failed=0"* ]]
