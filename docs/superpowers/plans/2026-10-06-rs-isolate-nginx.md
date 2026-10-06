# rs-isolate-nginx Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, zero-touch, airtight website isolation engine for aaPanel Nginx and PHP-FPM 8.4 with bidirectional POSIX ACLs, ondemand PHP-FPM pools, native upload protection, and zero aaPanel WP Toolkit interference.

**Architecture:** Pure 3-layer architecture: (1) System identity & Bidirectional POSIX ACLs, (2) Dedicated PHP-FPM 8.4 pool with `open_basedir`, (3) Nginx FastCGI routing with native uploads execution block, automated 24/7 by a lightweight Sentinel daemon.

**Tech Stack:** Bash, Linux POSIX ACLs (`setfacl`/`getfacl`), Nginx, PHP-FPM 8.4, systemd.

**Spec:** `docs/superpowers/specs/2026-10-06-rs-isolate-nginx-design.md`

## Global Constraints
- **Target OS & Stack**: Ubuntu 22.04 LTS / Debian, aaPanel (Latest), Nginx, PHP-FPM 8.4.
- **Philosophy**: Ponytail (Minimalist, native-first, zero bloat, no invasive wp-config hacks, no chattr +i locks).
- **PHP Version**: PHP 8.4 (`/www/server/php/84/`).
- **aaPanel Compatibility**: Full compatibility with File Manager, WP Toolkit (updates, clear cache, deploy), and Let's Encrypt SSL.
- **Testing**: 100% test pass rate with mocked aaPanel filesystem before any deployment.

---

### Task 1: Common Utilities & Environment Module

**Files:**
- Create: `lib/common.sh`
- Create: `tests/test_common.sh`

**Interfaces:**
- Produces:
  - `log_info()`, `log_success()`, `log_warn()`, `log_error()`
  - `sanitize_domain_to_user(domain) -> iso_<domain_clean>`
  - `sed_i(pattern, file)` cross-platform in-place replacement
  - `check_prerequisites()` validates root, aaPanel, Nginx, PHP 8.4, and acl package

- [ ] **Step 1: Write the failing test (`tests/test_common.sh`)**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation (`lib/common.sh`)**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 2: Linux User & Bidirectional POSIX ACL Module

**Files:**
- Create: `lib/os_user.sh`
- Create: `tests/test_os_user.sh`

**Interfaces:**
- Consumes: `lib/common.sh`
- Produces:
  - `create_isolated_user(domain, docroot)`
  - `remove_isolated_user(domain)`
  - `apply_site_permissions(domain, docroot)`
  - `restore_site_permissions(domain, docroot)`

- [ ] **Step 1: Write the failing test (`tests/test_os_user.sh`)**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation (`lib/os_user.sh`)**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 3: PHP-FPM 8.4 Dedicated Pool Module

**Files:**
- Create: `lib/php_fpm.sh`
- Create: `tests/test_php_fpm.sh`

**Interfaces:**
- Consumes: `lib/common.sh`
- Produces:
  - `create_php_fpm_pool(domain, docroot)`
  - `remove_php_fpm_pool(domain)`
  - `verify_and_reload_php_fpm()`

- [ ] **Step 1: Write the failing test (`tests/test_php_fpm.sh`)**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation (`lib/php_fpm.sh`)**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 4: Nginx Vhost Routing & Upload Protection Module

**Files:**
- Create: `lib/nginx_vhost.sh`
- Create: `tests/test_nginx_vhost.sh`

**Interfaces:**
- Consumes: `lib/common.sh`
- Produces:
  - `isolate_nginx_vhost(domain)`
  - `restore_nginx_vhost(domain)`
  - `verify_and_reload_nginx()`

- [ ] **Step 1: Write the failing test (`tests/test_nginx_vhost.sh`)**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation (`lib/nginx_vhost.sh`)**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 5: CLI Management Interface

**Files:**
- Create: `bin/rs-isolate`
- Create: `tests/test_cli_help.sh`
- Create: `tests/test_cli_workflow.sh`

**Interfaces:**
- Consumes: `lib/common.sh`, `lib/os_user.sh`, `lib/php_fpm.sh`, `lib/nginx_vhost.sh`
- Produces:
  - `rs-isolate [list|isolate|isolate-all|restore|status|sentinel]`

- [ ] **Step 1: Write the failing tests (`tests/test_cli_help.sh`)**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation (`bin/rs-isolate`)**
- [ ] **Step 4: Write workflow test and verify it passes (`tests/test_cli_workflow.sh`)**
- [ ] **Step 5: Commit**

---

### Task 6: Zero-Touch Sentinel Daemon

**Files:**
- Create: `bin/rs-isolate-sentinel`
- Create: `systemd/rs-isolate-sentinel.service`
- Create: `tests/test_sentinel.sh`

**Interfaces:**
- Consumes: `bin/rs-isolate`
- Produces:
  - Automated 15-second debounce detection and auto-healing daemon

- [ ] **Step 1: Write Sentinel daemon script (`bin/rs-isolate-sentinel`)**
- [ ] **Step 2: Write systemd unit file (`systemd/rs-isolate-sentinel.service`)**
- [ ] **Step 3: Write test and verify Sentinel detection (`tests/test_sentinel.sh`)**
- [ ] **Step 4: Commit**

---

### Task 7: Unified Test Runner, Installer & Documentation

**Files:**
- Create: `tests/run_all_tests.sh`
- Create: `install.sh`
- Create: `README.md`
- Create: `README-vi.md`

- [ ] **Step 1: Write unified test runner (`tests/run_all_tests.sh`)**
- [ ] **Step 2: Write one-line installer (`install.sh`)**
- [ ] **Step 3: Write documentation (`README.md`, `README-vi.md`)**
- [ ] **Step 4: Commit**
