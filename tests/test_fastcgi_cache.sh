#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/fastcgi_cache.sh"
source "${SCRIPT_DIR}/lib/nginx_vhost.sh"

test_fastcgi_cache_workflow() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local mock_cache_root="${tmp_dir}/cache"

    cat << VEOF > "${tmp_dir}/demo.com.conf"
server {
    listen 80;
    server_name demo.com;
    root /www/wwwroot/demo.com;
    include enable-php-84.conf;
}
VEOF

    # Test enable site cache
    AAPANEL_NGINX_VHOST_DIR="$tmp_dir" AAPANEL_NGINX_CONF_DIR="$tmp_dir" RS_CACHE_ROOT="$mock_cache_root" isolate_nginx_vhost "demo.com"

    local snippet="${tmp_dir}/enable-php-84-demo_com.conf"
    [ -f "$snippet" ] || { echo "Snippet file missing"; exit 1; }
    grep -q "fastcgi_cache CZ_demo_com;" "$snippet" || { echo "FastCGI cache directive missing in snippet"; exit 1; }
    grep -q "fastcgi_cache_bypass \$skip_cache;" "$snippet" || { echo "Cache bypass missing"; exit 1; }
    grep -q "add_header X-FastCGI-Cache" "$snippet" || { echo "Cache header missing"; exit 1; }

    # Zone definition in fastcgi_cache.d
    local zone_conf="${tmp_dir}/fastcgi_cache.d/demo_com.conf"
    [ -f "$zone_conf" ] || { echo "Zone conf missing"; exit 1; }
    grep -q "keys_zone=CZ_demo_com" "$zone_conf" || { echo "Zone name missing in zone conf"; exit 1; }

    # Test cache purge
    touch "${mock_cache_root}/demo_com/dummy.cache"
    AAPANEL_NGINX_CONF_DIR="$tmp_dir" RS_CACHE_ROOT="$mock_cache_root" purge_site_cache "demo.com"
    [ ! -f "${mock_cache_root}/demo_com/dummy.cache" ] || { echo "Dummy cache file not purged"; exit 1; }

    # Test cache disable
    AAPANEL_NGINX_CONF_DIR="$tmp_dir" RS_CACHE_ROOT="$mock_cache_root" disable_site_cache "demo.com"
    grep -q "fastcgi_cache CZ_demo_com;" "$snippet" && { echo "Cache directive still present after disable"; exit 1; }
    [ ! -f "$zone_conf" ] || { echo "Zone conf not removed after disable"; exit 1; }

    rm -rf "$tmp_dir"
    echo "test_fastcgi_cache_workflow PASS"
}

test_fastcgi_cache_workflow
