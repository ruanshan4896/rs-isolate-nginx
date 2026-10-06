#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/nginx_vhost.sh"

test_nginx_vhost_isolation() {
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # Standard aaPanel vhost file
    cat << 'VEOF' > "${tmp_dir}/demo.com.conf"
server {
    listen 80;
    server_name demo.com;
    root /www/wwwroot/demo.com;
    include enable-php-84.conf;
}
VEOF

    AAPANEL_NGINX_VHOST_DIR="$tmp_dir" isolate_nginx_vhost "demo.com"

    # Verify vhost was updated to point to isolated snippet
    grep -q "include enable-php-84-demo_com\.conf;" "${tmp_dir}/demo.com.conf" || { echo "Vhost snippet include missing"; exit 1; }

    # Verify snippet exists and contains socket route + uploads deny
    local snippet="${tmp_dir}/enable-php-84-demo_com.conf"
    [ -f "$snippet" ] || { echo "Snippet file was not created"; exit 1; }
    grep -q "fastcgi_pass unix:/tmp/php-cgi-84-demo_com\.sock;" "$snippet" || { echo "Snippet socket route missing"; exit 1; }
    grep -q "uploads.*\.php" "$snippet" || { echo "Uploads protection missing"; exit 1; }
    grep -q "deny all;" "$snippet" || { echo "Deny all missing"; exit 1; }

    # Test restore
    AAPANEL_NGINX_VHOST_DIR="$tmp_dir" restore_nginx_vhost "demo.com"
    grep -q "include enable-php-84\.conf;" "${tmp_dir}/demo.com.conf" || { echo "Vhost not restored to enable-php-84.conf"; exit 1; }
    [ ! -f "$snippet" ] || { echo "Snippet was not deleted on restore"; exit 1; }

    rm -rf "$tmp_dir"
    echo "test_nginx_vhost_isolation PASS"
}

test_nginx_vhost_isolation
