#!/usr/bin/env bash
# lib/common.sh - Common utilities for rs-isolate-nginx

COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_BLUE="\033[0;34m"
COLOR_RESET="\033[0m"

log_info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"; }
log_success() { echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"; }
log_warn()    { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
log_error()   { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2; }

sanitize_domain_to_user() {
    local domain="$1"
    local clean
    clean=$(echo "$domain" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
    local user="iso_${clean}"
    if [ ${#user} -gt 31 ]; then
        user="${user:0:31}"
        user=$(echo "$user" | sed 's/_$//')
    fi
    echo "$user"
}

sed_i() {
    if [ "$(uname)" = "Darwin" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

check_prerequisites() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log_error "rs-isolate-nginx must be run as root."
        return 1
    fi
    if [ ! -d "/www/server/panel" ]; then
        log_error "aaPanel not detected (/www/server/panel not found)."
        return 1
    fi
    if [ ! -d "/www/server/nginx" ]; then
        log_error "Nginx not detected (/www/server/nginx not found)."
        return 1
    fi
    if [ ! -d "/www/server/php/84" ]; then
        log_error "PHP 8.4 not detected (/www/server/php/84 not found)."
        return 1
    fi
    if ! command -v setfacl >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq acl || true
    fi
    return 0
}
