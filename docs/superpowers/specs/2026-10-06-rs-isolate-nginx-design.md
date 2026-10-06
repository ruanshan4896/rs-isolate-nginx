# Specification: rs-isolate-nginx (aaPanel Nginx + PHP-FPM 8.4 Pure Site Isolation)

- **Date**: 2026-10-06
- **Status**: Draft
- **Target Platform**: Ubuntu 22.04 / Debian, aaPanel (Latest), Nginx, PHP-FPM 8.4
- **Philosophy**: Ponytail (Minimalist, Native-first, Zero-bloat, 100% Robust) + Superpowers Workflow

---

## 1. Executive Summary

`rs-isolate-nginx` is a zero-touch, native security isolation engine designed specifically for aaPanel running Nginx and PHP-FPM 8.4.

It provides airtight multi-tenant website isolation without breaking native aaPanel features (such as File Manager, WP Toolkit, WordPress core upgrades, cache flushing, or Let's Encrypt SSL management).

### Core Goals
1. **Process Isolation**: Each website executes PHP under a dedicated Linux system user (`iso_<domain>`) via a dedicated PHP-FPM pool (`[<domain>]`) using dynamic `pm = ondemand`.
2. **Filesystem Isolation with POSIX ACLs**: Document root owned by `iso_<domain>:<domain>`, mode 750, with bidirectional POSIX ACLs (`setfacl`) granting `www` full access. This ensures aaPanel WP Toolkit and File Manager can edit, upgrade, and delete files without permissions errors.
3. **Uploads Execution Shield**: Native Nginx location rule blocking any direct execution of `.php` scripts within `wp-content/uploads/` and other user-uploaded directories (`403 Forbidden`).
4. **Zero-Touch Automation (Sentinel)**: Lightweight systemd daemon monitoring aaPanel vhost creation, with a 15-second debounce window to prevent race conditions during site provisioning.
5. **Ponytail Simplicity**: No invasive `wp-config.php` constants injection, no forced Redis overrides, no `chattr +i` locks, and minimal lines of code.

---

## 2. System Architecture

```text
                           Internet / Client Requests
                                      │
                                      ▼
                        ┌───────────────────────────┐
                        │   aaPanel Nginx Server    │
                        │        (User: www)        │
                        └─────────────┬─────────────┘
                                      │
            ┌─────────────────────────┴─────────────────────────┐
            │ fastcgi_pass unix:/tmp/php-cgi-84-siteA.sock       │ fastcgi_pass unix:/tmp/php-cgi-84-siteB.sock
            ▼                                                   ▼
┌───────────────────────────────┐                   ┌───────────────────────────────┐
│     PHP-FPM Pool [siteA]      │                   │     PHP-FPM Pool [siteB]      │
│  User: iso_siteA              │                   │  User: iso_siteB              │
│  Socket: /tmp/php-cgi-84-...  │                   │  Socket: /tmp/php-cgi-84-...  │
│  open_basedir: /www/wwwroot/A │                   │  open_basedir: /www/wwwroot/B │
└───────────────┬───────────────┘                   └───────────────┬───────────────┘
                ▼                                                   ▼
┌───────────────────────────────┐                   ┌───────────────────────────────┐
│   Docroot: /www/wwwroot/siteA │                   │   Docroot: /www/wwwroot/siteB │
│  Owner: iso_siteA (750)       │                   │  Owner: iso_siteB (750)       │
│  ACL: u:www:rwx               │                   │  ACL: u:www:rwx               │
│  Uploads: *.php blocked (403) │                   │  Uploads: *.php blocked (403) │
└───────────────────────────────┘                   └───────────────────────────────┘
```

---

## 3. Detailed Component Specifications

### 3.1. Linux User & Filesystem Permissions (`lib/os_user.sh`)

1. **User Creation**:
   - System user: `iso_<domain_clean>` (max 31 chars, lowercase alphanumeric + underscores).
   - Shell: `/usr/sbin/nologin`.
   - Home dir: `/www/wwwroot/<domain>`.
   - No interactive login.

2. **Filesystem Ownership & Permissions**:
   ```bash
   chown -R iso_${domain_clean}:iso_${domain_clean} "$docroot"
   chmod 750 "$docroot"
   ```

3. **Bidirectional POSIX ACLs**:
   ```bash
   setfacl -R -m u:www:rwx "$docroot"
   setfacl -R -d -m u:www:rwx "$docroot"
   setfacl -R -m u:iso_${domain_clean}:rwx "$docroot"
   setfacl -R -d -m u:iso_${domain_clean}:rwx "$docroot"
   ```
   - **Why this works**: `www` (aaPanel File Manager, WP Toolkit python scripts) has full `rwx` permissions. Any new file created inherits these permissions via default ACL.
   - Other sites (`iso_siteB`) cannot enter or read `siteA` because mode is `750` and `other` has `---` (zero access).

4. **Sensitive Config Protection (`wp-config.php`)**:
   ```bash
   chmod 640 "$docroot/wp-config.php"
   setfacl -m u:www:rw "$docroot/wp-config.php"
   ```
   - **Critical Rule**: NEVER use `chattr +i` on `wp-config.php` or `.user.ini`. Using `chattr +i` breaks aaPanel WP Toolkit auto-updates and cache clearing.

---

### 3.2. PHP-FPM 8.4 Dedicated Pool (`lib/php_fpm.sh`)

1. **Location**:
   `/www/server/php/84/etc/php-fpm.d/${domain_clean}.conf`

2. **Pool Configuration**:
   ```ini
   [${domain}]
   user = iso_${domain_clean}
   group = iso_${domain_clean}

   listen = /tmp/php-cgi-84-${domain_clean}.sock
   listen.owner = www
   listen.group = www
   listen.mode = 0660

   pm = ondemand
   pm.max_children = 20
   pm.process_idle_timeout = 60s
   pm.max_requests = 1000

   php_admin_value[open_basedir] = ${docroot}/:/tmp/:/proc/
   php_admin_value[upload_tmp_dir] = /tmp
   php_admin_value[session.save_path] = /tmp
   php_admin_value[max_execution_time] = 300
   php_admin_value[memory_limit] = 256M
   php_admin_value[upload_max_filesize] = 128M
   php_admin_value[post_max_size] = 128M
   ```

3. **Advantages**:
   - `ondemand`: Zero memory overhead when inactive.
   - `listen.owner = www` and `mode = 0660`: Nginx worker can communicate with socket without running as root.
   - `open_basedir`: Strictly confines PHP code to docroot and `/tmp`.

---

### 3.3. Nginx FastCGI Routing & Upload Protection (`lib/nginx_vhost.sh`)

1. **Snippet Creation**:
   `/www/server/panel/vhost/nginx/enable-php-84-${domain_clean}.conf`

   ```nginx
   # Dedicated PHP-FPM fastcgi route for isolated site
   location ~ [^/]\.php(/|$)
   {
       try_files $uri =404;
       fastcgi_pass unix:/tmp/php-cgi-84-${domain_clean}.sock;
       fastcgi_index index.php;
       include fastcgi.conf;
       include pathinfo.conf;
   }

   # Native uploads protection: block direct PHP script execution
   location ~* /(?:uploads|files)/.*\.php$ {
       deny all;
       return 403;
   }
   ```

2. **Vhost Modification in `/www/server/panel/vhost/nginx/${domain}.conf`**:
   - Replace `include enable-php-84.conf;` with `include enable-php-84-${domain_clean}.conf;`.
   - On `restore`, revert back to `include enable-php-84.conf;` and delete snippet.

---

### 3.4. Zero-Touch Automation Daemon (`bin/rs-isolate-sentinel`)

1. **Event Detection Loop**:
   - Polls `/www/server/panel/vhost/nginx/*.conf` every 5 seconds.
   - Filters out system vhosts (`default.conf`, `0.default.conf`, `phpmyadmin.conf`).

2. **15-Second Debounce & Handshake**:
   - aaPanel site creation involves multiple sequential steps (vhost write -> directory creation -> DB creation -> SSL setup).
   - Sentinel waits until `(now - vhost_mtime) >= 15` AND docroot directory exists.
   - Only then does it trigger `rs-isolate isolate <domain>`.

3. **Permission Drift Auto-Heal**:
   - If aaPanel's "Fix Permissions" or manual chown resets docroot owner to `www:www`, Sentinel detects that owner is not `iso_<domain>` and automatically re-applies isolated ownership and POSIX ACLs.

---

### 3.5. Command Line Interface (`bin/rs-isolate`)

| Command | Description |
|---|---|
| `rs-isolate list` | List all Nginx websites, isolated user, pool status, and docroot |
| `rs-isolate isolate <domain>` | Isolate a specific domain (create user, pool, vhost snippet, reload) |
| `rs-isolate isolate-all` | Isolate all active websites on aaPanel |
| `rs-isolate restore <domain>` | Revert site to standard aaPanel `www:www` pool |
| `rs-isolate status <domain>` | Display health check and configuration audit for domain |
| `rs-isolate sentinel [start\|stop\|restart\|status\|logs]` | Manage Sentinel background service |

---

## 4. Error Handling and Resilience

1. **Syntax Verification Before Reload**:
   - Always run `nginx -t` before reloading Nginx.
   - Always verify PHP-FPM syntax before reloading PHP-FPM (`/www/server/php/84/sbin/php-fpm -t`).
   - If validation fails, immediately rollback changes and alert without interrupting live traffic.

2. **Socket Stale Cleanup**:
   - Remove stale sockets `/tmp/php-cgi-84-${domain_clean}.sock*` before starting or reloading pools.

3. **Graceful Reloads**:
   - Use `systemctl reload nginx` or `/etc/init.d/nginx reload`.
   - Use `systemctl reload php-fpm-84` or `kill -USR2 <master-pid>`.

---

## 5. Automated Test Strategy (TDD)

All functionality will be verified via isolated test scripts in `tests/`:
- `tests/test_cli_help.sh`: CLI commands and flags.
- `tests/test_os_user.sh`: User sanitization, mock permission setting, POSIX ACL generation.
- `tests/test_php_fpm.sh`: Pool file syntax, ondemand directive, open_basedir paths.
- `tests/test_nginx_vhost.sh`: Vhost include substitution, snippet generation, uploads rule, restore clean.
- `tests/test_cli_workflow.sh`: Full mock workflow (create -> isolate -> status -> restore).
- `tests/run_all_tests.sh`: Unified test runner.
