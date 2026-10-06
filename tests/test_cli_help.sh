#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output=$(bash "${SCRIPT_DIR}/bin/rs-isolate" --help)
echo "$output" | grep -q "rs-isolate" || { echo "CLI help failed"; exit 1; }
echo "$output" | grep -q "isolate" || { echo "isolate command missing from help"; exit 1; }
echo "test_cli_help PASS"
