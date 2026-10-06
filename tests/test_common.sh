#!/usr/bin/env bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

test_sanitize_domain() {
    local u1 u2 u3
    u1=$(sanitize_domain_to_user "example.com")
    [ "$u1" = "iso_example_com" ] || { echo "Failed u1: $u1"; exit 1; }

    u2=$(sanitize_domain_to_user "My-Blog.sub.domain.vn")
    [ "$u2" = "iso_my_blog_sub_domain_vn" ] || { echo "Failed u2: $u2"; exit 1; }

    u3=$(sanitize_domain_to_user "a-very-long-domain-name-that-exceeds-maximum-linux-username-length.com")
    [ ${#u3} -le 31 ] || { echo "Username exceeds 31 chars: ${#u3}"; exit 1; }

    echo "test_sanitize_domain PASS"
}

test_sanitize_domain
