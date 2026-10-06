#!/usr/bin/env bash
# lib/nginx_vhost.sh - Nginx vhost routing and native upload protection

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

    if [ ! -f "$vhost_file" ]; then
        log_error "Vhost file $vhost_file not found."
        return 1
    fi

    # Create dedicated enable-php snippet with native uploads security
    log_info "Creating Nginx FastCGI snippet: $snippet_file..."
    cat << EOF > "$snippet_file"
# BEGIN RS-ISOLATE: ${domain}
location ~ [^/]\.php(/|$)
{
    try_files \$uri =404;
    fastcgi_pass unix:${socket};
    fastcgi_index index.php;
    include fastcgi.conf;
    include pathinfo.conf;
}

# Block direct execution of PHP scripts in uploads / media
location ~* /(?:uploads|files)/.*\.php$ {
    deny all;
    return 403;
}
# END RS-ISOLATE: ${domain}
EOF

    # If vhost_dir is distinct from conf_dir, symlink to vhost_dir as well
    if [ -d "$vhost_dir" ] && [ "$vhost_dir" != "$conf_dir" ]; then
        ln -sf "$snippet_file" "${vhost_dir}/enable-php-84-${domain_clean}.conf" 2>/dev/null || true
    fi

    # Switch include in aaPanel vhost file
    sed_i "s/include enable-php-84\.conf;/include enable-php-84-${domain_clean}\.conf;/g" "$vhost_file"
    log_success "Updated $vhost_file to use dedicated PHP-FPM socket."
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

    if [ -f "$vhost_file" ]; then
        sed_i "s/include enable-php-84-${domain_clean}\.conf;/include enable-php-84\.conf;/g" "$vhost_file"
        log_info "Reverted $vhost_file to standard enable-php-84.conf"
    fi

    if [ -f "$snippet_file" ]; then
        rm -f "$snippet_file"
        log_success "Removed snippet $snippet_file"
    fi

    if [ -d "$vhost_dir" ] && [ "$vhost_dir" != "$conf_dir" ]; then
        rm -f "${vhost_dir}/enable-php-84-${domain_clean}.conf" 2>/dev/null || true
    fi
}

verify_and_reload_nginx() {
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
