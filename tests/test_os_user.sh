#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os_user.sh"

test_permissions_logic() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    mkdir -p "${tmp_dir}/wp-content/uploads"
    touch "${tmp_dir}/wp-config.php"

    apply_site_permissions "demo.com" "$tmp_dir"

    # Verify docroot is 750
    local mode
    if [ "$(uname)" = "Darwin" ]; then
        mode=$(stat -f "%OLp" "$tmp_dir")
    else
        mode=$(stat -c "%a" "$tmp_dir")
    fi
    [ "$mode" = "750" ] || { echo "Docroot mode mismatch: $mode"; exit 1; }

    # Verify wp-config.php is 640
    local cfg_mode
    if [ "$(uname)" = "Darwin" ]; then
        cfg_mode=$(stat -f "%OLp" "${tmp_dir}/wp-config.php")
    else
        cfg_mode=$(stat -c "%a" "${tmp_dir}/wp-config.php")
    fi
    [ "$cfg_mode" = "640" ] || { echo "wp-config mode mismatch: $cfg_mode"; exit 1; }

    # Test restore
    restore_site_permissions "demo.com" "$tmp_dir"
    local rest_mode
    if [ "$(uname)" = "Darwin" ]; then
        rest_mode=$(stat -f "%OLp" "$tmp_dir")
    else
        rest_mode=$(stat -c "%a" "$tmp_dir")
    fi
    [ "$rest_mode" = "755" ] || { echo "Restored docroot mode mismatch: $rest_mode"; exit 1; }

    rm -rf "$tmp_dir"
    echo "test_permissions_logic PASS"
}

test_permissions_logic
