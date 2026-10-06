#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL=0
PASSED=0

echo "=========================================================="
echo "    RUNNING RS-ISOLATE-NGINX AUTOMATED TEST SUITE        "
echo "=========================================================="

for test_script in "${SCRIPT_DIR}"/test_*.sh; do
    [ -f "$test_script" ] || continue
    t_name=$(basename "$test_script")
    [ "$t_name" = "run_all_tests.sh" ] && continue

    TOTAL=$((TOTAL + 1))
    echo -n "Running $t_name ... "
    if bash "$test_script" >/dev/null 2>&1; then
        echo "[PASS]"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL]"
        bash "$test_script"
        exit 1
    fi
done

echo "=========================================================="
echo "Tests Passed: $PASSED / $TOTAL"
echo "=========================================================="
