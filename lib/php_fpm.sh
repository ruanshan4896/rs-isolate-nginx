#!/usr/bin/env bash
# lib/php_fpm.sh - Dedicated PHP-FPM 8.4 pool management

get_php_fpm_base_dir() {
    echo "${PHP_FPM_DIR:-/www/server/php/84/etc}"
}

ensure_php_fpm_include() {
    local base_dir
    base_dir=$(get_php_fpm_base_dir)
    local fpm_conf="${base_dir}/php-fpm.conf"
    local pool_dir="${base_dir}/php-fpm.d"
    local include_line="include = ${pool_dir}/*.conf"

    if [ -f "$fpm_conf" ]; then
        if ! grep -E "^\s*include\s*=\s*.*php-fpm\.d" "$fpm_conf" >/dev/null 2>&1; then
            echo "" >> "$fpm_conf"
            echo "; Included pool configurations for rs-isolate" >> "$fpm_conf"
            echo "$include_line" >> "$fpm_conf"
            log_info "Added include directive to $fpm_conf"
        fi
    fi
}

create_php_fpm_pool() {
    local domain="$1"
    local docroot="${2:-/www/wwwroot/${domain}}"
    local user
    user=$(sanitize_domain_to_user "$domain")
    local domain_clean="${user#iso_}"
    local base_dir
    base_dir=$(get_php_fpm_base_dir)
    local pool_dir="${base_dir}/php-fpm.d"
    local pool_file="${pool_dir}/${domain_clean}.conf"
    local socket="/tmp/php-cgi-84-${domain_clean}.sock"

    mkdir -p "$pool_dir" 2>/dev/null || true
    ensure_php_fpm_include

    log_info "Configuring dedicated PHP-FPM pool for $domain..."
    local cache_dir="/www/server/nginx/cache/${domain_clean}"

    # Also update .user.ini if present to allow cache directory
    local user_ini="${docroot}/.user.ini"
    if [ -f "$user_ini" ]; then
        if ! grep -Fq "${cache_dir}" "$user_ini" 2>/dev/null; then
            chattr -i "$user_ini" 2>/dev/null || true
            sed_i "s|^\(open_basedir=.*\)$|\1:${cache_dir}/|" "$user_ini" 2>/dev/null || true
            chattr +i "$user_ini" 2>/dev/null || true
        fi
    fi

    cat << EOF > "$pool_file"
[${domain}]
user = ${user}
group = ${user}
listen = ${socket}
listen.owner = www
listen.group = www
listen.mode = 0660

pm = ondemand
pm.max_children = 20
pm.process_idle_timeout = 60s
pm.max_requests = 1000

php_admin_value[open_basedir] = ${docroot}/:/tmp/:/proc/:${cache_dir}/
php_admin_value[upload_tmp_dir] = /tmp
php_admin_value[session.save_path] = /tmp
php_admin_value[max_execution_time] = 300
php_admin_value[memory_limit] = 256M
php_admin_value[upload_max_filesize] = 128M
php_admin_value[post_max_size] = 128M
EOF

    # Remove any stale socket
    rm -f "${socket}"* 2>/dev/null || true
    log_success "Created PHP-FPM pool: $pool_file"
}

remove_php_fpm_pool() {
    local domain="$1"
    local user
    user=$(sanitize_domain_to_user "$domain")
    local domain_clean="${user#iso_}"
    local base_dir
    base_dir=$(get_php_fpm_base_dir)
    local pool_file="${base_dir}/php-fpm.d/${domain_clean}.conf"
    local socket="/tmp/php-cgi-84-${domain_clean}.sock"

    if [ -f "$pool_file" ]; then
        rm -f "$pool_file"
        rm -f "${socket}"* 2>/dev/null || true
        log_success "Removed PHP-FPM pool: $pool_file"
    fi
}

verify_and_reload_php_fpm() {
    log_info "Verifying PHP-FPM 8.4 syntax..."
    local fpm_bin="/www/server/php/84/sbin/php-fpm"
    if [ -x "$fpm_bin" ]; then
        if ! "$fpm_bin" -t >/tmp/fpm_test.log 2>&1; then
            log_error "PHP-FPM syntax test failed! Details in /tmp/fpm_test.log"
            cat /tmp/fpm_test.log >&2
            return 1
        fi
    fi

    log_info "Restarting PHP-FPM 8.4 to bind sockets..."
    if [ -x "/etc/init.d/php-fpm-84" ]; then
        /etc/init.d/php-fpm-84 restart >/dev/null 2>&1 || /etc/init.d/php-fpm-84 reload >/dev/null 2>&1 || true
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl restart php-fpm-84 >/dev/null 2>&1 || systemctl reload php-fpm-84 >/dev/null 2>&1 || true
    fi
    log_success "PHP-FPM 8.4 reloaded/restarted."
    return 0
}
