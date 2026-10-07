#!/usr/bin/env bash
# lib/fastcgi_cache.sh - Per-site FastCGI Cache engine with multi-tenant RAM isolation

get_nginx_cache_base_dir() {
    local conf_dir
    conf_dir=$(get_nginx_conf_dir)
    echo "${conf_dir}/fastcgi_cache.d"
}

get_site_cache_path() {
    local domain_clean="$1"
    echo "${RS_CACHE_ROOT:-/var/cache/rs-isolate}/${domain_clean}"
}

ensure_nginx_cache_include() {
    local conf_dir
    conf_dir=$(get_nginx_conf_dir)
    local nginx_conf="${conf_dir}/nginx.conf"
    local cache_d
    cache_d=$(get_nginx_cache_base_dir)

    mkdir -p "$cache_d" 2>/dev/null || true

    # Global fastcgi cache parameters (avoid duplicate fastcgi_cache_key if defined by aaPanel)
    local global_conf="${cache_d}/00-global.conf"
    local has_existing_key=0
    if grep -rq "fastcgi_cache_key" /www/server/panel/vhost/nginx/ 2>/dev/null; then
        has_existing_key=1
    fi

    if [ ! -f "$global_conf" ]; then
        cat << 'GEOF' > "$global_conf"
# Global FastCGI Cache configuration for rs-isolate
fastcgi_cache_use_stale error timeout invalid_header updating http_500 http_503;
fastcgi_ignore_headers Cache-Control Expires Set-Cookie;
GEOF
        if [ "$has_existing_key" -eq 0 ]; then
            echo 'fastcgi_cache_key "$scheme$request_method$host$request_uri";' >> "$global_conf"
        fi
    else
        # Remove duplicate key if aaPanel already defined it
        if [ "$has_existing_key" -eq 1 ]; then
            sed_i '/fastcgi_cache_key/d' "$global_conf"
        fi
    fi

    # Ensure include directive exists in http block of nginx.conf
    if [ -f "$nginx_conf" ]; then
        if ! grep -Fq "fastcgi_cache.d/*.conf" "$nginx_conf"; then
            # Insert before the first include or before closing http block
            if grep -Fq "include /www/server/panel/vhost/nginx/*.conf;" "$nginx_conf"; then
                sed_i "/include \/www\/server\/panel\/vhost\/nginx\/\*\.conf;/i \    include ${cache_d}/\*\.conf;" "$nginx_conf"
            else
                sed_i "/^http\s*{/a \    include ${cache_d}/\*\.conf;" "$nginx_conf"
            fi
            log_info "Added FastCGI cache include to $nginx_conf"
        fi
    fi
}

setup_site_cache_dir() {
    local domain="$1"
    local user
    user=$(sanitize_domain_to_user "$domain")
    local domain_clean="${user#iso_}"
    local cache_dir
    cache_dir=$(get_site_cache_path "$domain_clean")

    mkdir -p "$cache_dir" 2>/dev/null || true
    chown -R www:www "$cache_dir" 2>/dev/null || true
    chmod -R 775 "$cache_dir" 2>/dev/null || true

    # Grant POSIX ACL for isolated user so WordPress plugin can purge directly
    if command -v setfacl >/dev/null 2>&1; then
        setfacl -R -m u:${user}:rwx,d:u:${user}:rwx "$cache_dir" 2>/dev/null || true
    fi
}

enable_site_cache() {
    local domain="$1"
    local user
    user=$(sanitize_domain_to_user "$domain")
    local domain_clean="${user#iso_}"
    local cache_d
    cache_d=$(get_nginx_cache_base_dir)
    local cache_dir
    cache_dir=$(get_site_cache_path "$domain_clean")
    local zone_name="CZ_${domain_clean}"
    local zone_conf="${cache_d}/${domain_clean}.conf"

    ensure_nginx_cache_include
    setup_site_cache_dir "$domain"

    # Ensure PHP-FPM pool open_basedir includes the cache directory
    local base_fpm_dir
    base_fpm_dir=$(get_php_fpm_base_dir 2>/dev/null || echo "/www/server/php/84/etc")
    local pool_file="${base_fpm_dir}/php-fpm.d/${domain_clean}.conf"
    if [ -f "$pool_file" ]; then
        if ! grep -Fq "${cache_dir}" "$pool_file"; then
            sed_i "s|^\(php_admin_value\[open_basedir\]\s*=.*\)|\1:${cache_dir}/|" "$pool_file" 2>/dev/null || true
        fi
    fi

    local docroot="/www/wwwroot/${domain}"
    local user_ini="${docroot}/.user.ini"
    if [ -f "$user_ini" ]; then
        if ! grep -Fq "${cache_dir}" "$user_ini" 2>/dev/null; then
            chattr -i "$user_ini" 2>/dev/null || true
            sed_i "s|^\(open_basedir=.*\)$|\1:${cache_dir}/|" "$user_ini" 2>/dev/null || true
            chattr +i "$user_ini" 2>/dev/null || true
        fi
    fi

    local wp_config="${docroot}/wp-config.php"
    if [ -f "$wp_config" ]; then
        if ! grep -Fq "RT_WP_NGINX_HELPER_CACHE_PATH" "$wp_config"; then
            sed_i "/\/\* That's all/i define('RT_WP_NGINX_HELPER_CACHE_PATH', '${cache_dir}');" "$wp_config" 2>/dev/null || \
            echo "define('RT_WP_NGINX_HELPER_CACHE_PATH', '${cache_dir}');" >> "$wp_config"
        else
            sed_i "s|define(.*'RT_WP_NGINX_HELPER_CACHE_PATH'.*|define('RT_WP_NGINX_HELPER_CACHE_PATH', '${cache_dir}');|g" "$wp_config" 2>/dev/null || true
        fi
    fi

    # 1. Define per-site cache zone in RAM
    log_info "Configuring cache zone for $domain in RAM: $cache_dir..."
    cat << EOF > "$zone_conf"
# FastCGI Cache Zone for ${domain}
fastcgi_cache_path ${cache_dir} levels=1:2 keys_zone=${zone_name}:10m inactive=60m max_size=64m;
EOF

    # 2. Update snippet to include cache directives
    local conf_dir
    conf_dir=$(get_nginx_conf_dir)
    local snippet_file="${conf_dir}/enable-php-84-${domain_clean}.conf"

    if [ -f "$snippet_file" ]; then
        if ! grep -Fq "fastcgi_cache ${zone_name};" "$snippet_file"; then
            # Recreate snippet with cache enabled
            isolate_nginx_vhost "$domain"
        fi
    fi
    log_success "FastCGI Cache enabled for $domain (Zone: $zone_name)"
}

disable_site_cache() {
    local domain="$1"
    local user
    user=$(sanitize_domain_to_user "$domain")
    local domain_clean="${user#iso_}"
    local cache_d
    cache_d=$(get_nginx_cache_base_dir)
    local zone_conf="${cache_d}/${domain_clean}.conf"

    # Remove zone definition
    rm -f "$zone_conf" 2>/dev/null || true

    # Recreate snippet without cache directives
    local conf_dir
    conf_dir=$(get_nginx_conf_dir)
    local snippet_file="${conf_dir}/enable-php-84-${domain_clean}.conf"
    local socket="/tmp/php-cgi-84-${domain_clean}.sock"

    cat << EOF > "$snippet_file"
# BEGIN RS-ISOLATE: ${domain} (CACHE: DISABLED)
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

    purge_site_cache "$domain" >/dev/null 2>&1 || true
    log_success "FastCGI Cache disabled for $domain"
}

purge_site_cache() {
    local domain="$1"
    local user
    user=$(sanitize_domain_to_user "$domain")
    local domain_clean="${user#iso_}"
    local cache_dir
    cache_dir=$(get_site_cache_path "$domain_clean")

    if [ -d "$cache_dir" ]; then
        find "$cache_dir" -mindepth 1 -delete 2>/dev/null || rm -rf "${cache_dir:?}"/* 2>/dev/null || true
        log_success "Flushed FastCGI Cache for $domain ($cache_dir)"
    else
        log_info "Cache directory $cache_dir is already empty."
    fi
}

status_site_cache() {
    local domain="$1"
    local user
    user=$(sanitize_domain_to_user "$domain")
    local domain_clean="${user#iso_}"
    local cache_d
    cache_d=$(get_nginx_cache_base_dir)
    local zone_conf="${cache_d}/${domain_clean}.conf"
    local cache_dir
    cache_dir=$(get_site_cache_path "$domain_clean")
    local zone_name="CZ_${domain_clean}"

    echo "FastCGI Cache Status: $domain"
    echo "-----------------------------------"
    if [ -f "$zone_conf" ]; then
        echo "Status:          ENABLED"
        echo "Zone Name:       $zone_name"
        echo "Cache Zone Path: $cache_dir"
        if [ -d "$cache_dir" ]; then
            local usage
            usage=$(du -sh "$cache_dir" 2>/dev/null | awk "{print \$1}" || echo "0B")
            echo "RAM Usage:       $usage"
        fi
        echo ""
        echo "Plugin (Nginx Cache by Till Krüss) Config:"
        echo "  Cache Zone Path: $cache_dir"
    else
        echo "Status:          DISABLED"
        echo "Cache Zone Path: (Not configured)"
    fi
}
