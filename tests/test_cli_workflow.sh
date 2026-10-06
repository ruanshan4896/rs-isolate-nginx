#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp_base=$(mktemp -d)
mkdir -p "${tmp_base}/vhost" "${tmp_base}/php-fpm.d" "${tmp_base}/docroot/site1.com"
cat << 'VEOF' > "${tmp_base}/vhost/site1.com.conf"
server {
    listen 80;
    server_name site1.com;
    root /www/wwwroot/site1.com;
    include enable-php-84.conf;
}
VEOF

AAPANEL_NGINX_VHOST_DIR="${tmp_base}/vhost" PHP_FPM_DIR="${tmp_base}" bash "${SCRIPT_DIR}/bin/rs-isolate" list | grep -q "DEFAULT" || { echo "Initial list failed"; exit 1; }

AAPANEL_NGINX_VHOST_DIR="${tmp_base}/vhost" PHP_FPM_DIR="${tmp_base}" bash "${SCRIPT_DIR}/bin/rs-isolate" isolate site1.com "${tmp_base}/docroot/site1.com"

AAPANEL_NGINX_VHOST_DIR="${tmp_base}/vhost" PHP_FPM_DIR="${tmp_base}" bash "${SCRIPT_DIR}/bin/rs-isolate" list | grep -q "ISOLATED" || { echo "Isolated list failed"; exit 1; }

AAPANEL_NGINX_VHOST_DIR="${tmp_base}/vhost" PHP_FPM_DIR="${tmp_base}" bash "${SCRIPT_DIR}/bin/rs-isolate" restore site1.com "${tmp_base}/docroot/site1.com"

AAPANEL_NGINX_VHOST_DIR="${tmp_base}/vhost" PHP_FPM_DIR="${tmp_base}" bash "${SCRIPT_DIR}/bin/rs-isolate" list | grep -q "DEFAULT" || { echo "Restored list failed"; exit 1; }

rm -rf "$tmp_base"
echo "test_cli_workflow PASS"
