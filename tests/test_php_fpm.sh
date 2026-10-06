#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/php_fpm.sh"

test_pool_creation_and_removal() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    mkdir -p "${tmp_dir}/php-fpm.d"

    PHP_FPM_DIR="$tmp_dir" create_php_fpm_pool "demo.com" "/www/wwwroot/demo.com"

    local pool_file="${tmp_dir}/php-fpm.d/demo_com.conf"
    [ -f "$pool_file" ] || { echo "Pool file not created"; exit 1; }

    grep -q "\[demo\.com\]" "$pool_file" || { echo "Pool section header missing"; exit 1; }
    grep -q "user = iso_demo_com" "$pool_file" || { echo "User config missing"; exit 1; }
    grep -q "pm = ondemand" "$pool_file" || { echo "pm = ondemand missing"; exit 1; }
    grep -q "open_basedir.*demo\.com" "$pool_file" || { echo "open_basedir missing"; exit 1; }

    # Test removal
    PHP_FPM_DIR="$tmp_dir" remove_php_fpm_pool "demo.com"
    [ ! -f "$pool_file" ] || { echo "Pool file was not removed"; exit 1; }

    rm -rf "$tmp_dir"
    echo "test_pool_creation_and_removal PASS"
}

test_pool_creation_and_removal
