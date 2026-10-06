#!/usr/bin/env bash
# lib/nginx_vhost.sh - Nginx vhost routing and native upload protection

_CURRENT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${_CURRENT_LIB_DIR}/fastcgi_cache.sh" ]; then
    source "${_CURRENT_LIB_DIR}/fastcgi_cache.sh"
fi

get_nginx_vhost_dir() {
    echo "${AAPANEL_NGINX_VHOST_DIR:-/www/server/panel/vhost/nginx}"
}

get_nginx_conf_dir() {
    local default_conf="/www/server/nginx/conf"
    if [ -n "${AAPANEL_NGINX_CONF_DIR:-}" ]; then
        echo "$AAPANEL_NGINX_CONF_DIR"
    elif [ -d "$default_conf" ]; then
        echo "$default_conf"
    else
        get_nginx_vhost_dir
    fi
}

isolate_nginx_vhost() {
    local domain="$1"
    local user
    user=$(sanitize_domain_to_user "$domain")
    local domain_clean="${user#iso_}"
    local vhost_dir
    vhost_dir=$(get_nginx_vhost_dir)
    local vhost_file="${vhost_dir}/${domain}.conf"
    local conf_dir
    conf_dir=$(get_nginx_conf_dir)
    local snippet_file="${conf_dir}/enable-php-84-${domain_clean}.conf"
    local socket="/tmp/php-cgi-84-${domain_clean}.sock"
    local zone_name="CZ_${domain_clean}"

    if [ ! -f "$vhost_file" ]; then
        log_error "Vhost file $vhost_file not found."
        return 1
    fi

    # Clean up any misplaced snippet in vhost_dir that would break nginx.conf wildcard inclusion
    if [ "$vhost_dir" != "$conf_dir" ] && [ -f "${vhost_dir}/enable-php-84-${domain_clean}.conf" ]; then
        rm -f "${vhost_dir}/enable-php-84-${domain_clean}.conf" 2>/dev/null || true
    fi

    # Setup FastCGI Cache in RAM by default
    ensure_nginx_cache_include
    setup_site_cache_dir "$domain"
    local cache_d
    cache_d=$(get_nginx_cache_base_dir)
    local cache_dir
    cache_dir=$(get_site_cache_path "$domain_clean")
    cat << EOF > "${cache_d}/${domain_clean}.conf"
# FastCGI Cache Zone for ${domain}
fastcgi_cache_path ${cache_dir} levels=1:2 keys_zone=${zone_name}:10m inactive=60m max_size=512m;
EOF

    # Create dedicated enable-php snippet in conf_dir (/www/server/nginx/conf)
    log_info "Creating Nginx FastCGI snippet: $snippet_file..."
    cat << EOF > "$snippet_file"
# BEGIN RS-ISOLATE: ${domain}
# FastCGI Cache Skip Rules
set \$skip_cache 0;
if (\$request_method = POST) {
    set \$skip_cache 1;
}
if (\$query_string != "") {
    set \$skip_cache 1;
}
if (\$request_uri ~* "(/wp-admin/|/xmlrpc.php|/wp-.*.php|/feed/|index.php|sitemap(_index)?.xml)") {
    set \$skip_cache 1;
}
if (\$http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in") {
    set \$skip_cache 1;
}

location ~ [^/]\.php(/|$)
{
    try_files \$uri =404;
    fastcgi_pass unix:${socket};
    fastcgi_index index.php;
    include fastcgi.conf;
    include pathinfo.conf;

    # FastCGI Cache
    fastcgi_cache ${zone_name};
    fastcgi_cache_valid 200 301 302 60m;
    fastcgi_cache_bypass \$skip_cache;
    fastcgi_no_cache \$skip_cache;
    add_header X-FastCGI-Cache \$upstream_cache_status;
}

# Block direct execution of PHP scripts in uploads / media
location ~* /(?:uploads|files)/.*\.php$ {
    deny all;
    return 403;
}
# END RS-ISOLATE: ${domain}
EOF

    # Switch include in aaPanel vhost file
    sed_i "s/include enable-php-84\.conf;/include enable-php-84-${domain_clean}\.conf;/g" "$vhost_file"
    log_success "Updated $vhost_file to use dedicated PHP-FPM socket and FastCGI Cache."
}

restore_nginx_vhost() {
    local domain="$1"
    local user
    user=$(sanitize_domain_to_user "$domain")
    local domain_clean="${user#iso_}"
    local vhost_dir
    vhost_dir=$(get_nginx_vhost_dir)
    local vhost_file="${vhost_dir}/${domain}.conf"
    local conf_dir
    conf_dir=$(get_nginx_conf_dir)
    local snippet_file="${conf_dir}/enable-php-84-${domain_clean}.conf"
    local cache_d
    cache_d=$(get_nginx_cache_base_dir)

    if [ -f "$vhost_file" ]; then
        sed_i "s/include enable-php-84-${domain_clean}\.conf;/include enable-php-84\.conf;/g" "$vhost_file"
        log_info "Reverted $vhost_file to standard enable-php-84.conf"
    fi

    if [ -f "$snippet_file" ]; then
        rm -f "$snippet_file"
        log_success "Removed snippet $snippet_file"
    fi

    if [ -f "${cache_d}/${domain_clean}.conf" ]; then
        rm -f "${cache_d}/${domain_clean}.conf" 2>/dev/null || true
    fi
    purge_site_cache "$domain" >/dev/null 2>&1 || true

    if [ "$vhost_dir" != "$conf_dir" ] && [ -f "${vhost_dir}/enable-php-84-${domain_clean}.conf" ]; then
        rm -f "${vhost_dir}/enable-php-84-${domain_clean}.conf" 2>/dev/null || true
    fi
}

verify_and_reload_nginx() {
    local vhost_dir
    vhost_dir=$(get_nginx_vhost_dir)
    local conf_dir
    conf_dir=$(get_nginx_conf_dir)

    # Automatically migrate and clean up any misplaced snippets from vhost_dir
    if [ -d "$vhost_dir" ] && [ "$vhost_dir" != "$conf_dir" ]; then
        for old_snip in "$vhost_dir"/enable-php-84-*.conf; do
            if [ -f "$old_snip" ]; then
                cp -f "$old_snip" "$conf_dir/" 2>/dev/null || true
                rm -f "$old_snip" 2>/dev/null || true
            fi
        done
    fi

    log_info "Verifying Nginx configuration syntax..."
    if command -v nginx >/dev/null 2>&1; then
        if ! nginx -t >/tmp/nginx_test.log 2>&1; then
            log_error "Nginx syntax test failed! Details in /tmp/nginx_test.log"
            cat /tmp/nginx_test.log >&2
            return 1
        fi
        log_info "Reloading Nginx gracefully..."
        nginx -s reload >/dev/null 2>&1 || systemctl reload nginx >/dev/null 2>&1 || true
        log_success "Nginx reloaded."
    fi
    return 0
}
