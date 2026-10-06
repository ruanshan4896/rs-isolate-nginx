#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Verify syntax
bash -n "${SCRIPT_DIR}/bin/rs-isolate-sentinel"
[ -f "${SCRIPT_DIR}/systemd/rs-isolate-sentinel.service" ] || { echo "Systemd service missing"; exit 1; }

# Test run-once mode
tmp_base=$(mktemp -d)
mkdir -p "${tmp_base}/vhost" "${tmp_base}/php-fpm.d" "${tmp_base}/www/site2.com"
cat << VEOF > "${tmp_base}/vhost/site2.com.conf"
server {
    listen 80;
    server_name site2.com;
    root ${tmp_base}/www/site2.com;
    include enable-php-84.conf;
}
VEOF

AAPANEL_NGINX_VHOST_DIR="${tmp_base}/vhost" PHP_FPM_DIR="${tmp_base}" bash "${SCRIPT_DIR}/bin/rs-isolate-sentinel" run-once
[ -f "${tmp_base}/vhost/enable-php-84-site2_com.conf" ] || { echo "Sentinel run-once failed to isolate site2.com"; exit 1; }

rm -rf "$tmp_base"
echo "test_sentinel PASS"
