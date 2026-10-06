#!/usr/bin/env bash
# lib/os_user.sh - Linux user creation and bidirectional POSIX ACL management

create_isolated_user() {
    local domain="$1"
    local docroot="${2:-/www/wwwroot/${domain}}"
    local user
    user=$(sanitize_domain_to_user "$domain")

    if id "$user" >/dev/null 2>&1; then
        log_info "System user $user already exists."
        return 0
    fi

    log_info "Creating dedicated system user $user for $domain..."
    useradd --system --no-create-home --home-dir "$docroot" --shell /usr/sbin/nologin --user-group "$user"
    log_success "User $user created successfully."
}

remove_isolated_user() {
    local domain="$1"
    local user
    user=$(sanitize_domain_to_user "$domain")

    if id "$user" >/dev/null 2>&1; then
        log_info "Removing system user $user..."
        userdel "$user" 2>/dev/null || true
        groupdel "$user" 2>/dev/null || true
        log_success "User $user removed."
    fi
}

apply_site_permissions() {
    local domain="$1"
    local docroot="${2:-/www/wwwroot/${domain}}"
    local user
    user=$(sanitize_domain_to_user "$domain")

    if [ ! -d "$docroot" ]; then
        log_error "Document root $docroot does not exist."
        return 1
    fi

    log_info "Applying isolation permissions on $docroot for user $user..."

    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        chown -R "${user}:${user}" "$docroot" 2>/dev/null || true
    fi
    chmod 750 "$docroot"

    # Bidirectional POSIX ACLs: give both www and user full rwx access
    if command -v setfacl >/dev/null 2>&1; then
        setfacl -R -m u:www:rwx "$docroot" 2>/dev/null || true
        setfacl -R -d -m u:www:rwx "$docroot" 2>/dev/null || true
        setfacl -R -m u:"${user}":rwx "$docroot" 2>/dev/null || true
        setfacl -R -d -m u:"${user}":rwx "$docroot" 2>/dev/null || true
    fi

    # Secure wp-config.php without chattr +i
    local config_file="$docroot/wp-config.php"
    if [ -f "$config_file" ]; then
        if [ "${EUID:-$(id -u)}" -eq 0 ]; then
            chown "${user}:${user}" "$config_file" 2>/dev/null || true
        fi
        chmod 640 "$config_file"
        if command -v setfacl >/dev/null 2>&1; then
            setfacl -m u:www:rw "$config_file" 2>/dev/null || true
        fi
        log_info "Secured $config_file (640 with www:rw ACL)"
    fi
    log_success "Permissions applied successfully."
}

restore_site_permissions() {
    local domain="$1"
    local docroot="${2:-/www/wwwroot/${domain}}"

    if [ ! -d "$docroot" ]; then
        return 0
    fi

    log_info "Restoring standard aaPanel permissions (www:www) on $docroot..."
    if command -v setfacl >/dev/null 2>&1; then
        setfacl -R -b "$docroot" 2>/dev/null || true
    fi

    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        chown -R www:www "$docroot" 2>/dev/null || true
    fi
    chmod 755 "$docroot"
    find "$docroot" -type f -exec chmod 644 {} + 2>/dev/null || true
    find "$docroot" -type d -exec chmod 755 {} + 2>/dev/null || true
    log_success "Restored standard aaPanel permissions."
}
