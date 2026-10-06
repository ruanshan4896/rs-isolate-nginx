# rs-isolate-nginx

**Native Multi-Tenant Website Isolation Engine for aaPanel Nginx & PHP-FPM 8.4**

`rs-isolate-nginx` provides true Linux user and process isolation for WordPress and PHP websites hosted on aaPanel with Nginx and PHP-FPM 8.4.

Built on the **Ponytail** philosophy: Minimalist, Native-first, Zero bloat, and 100% compatible with aaPanel core features (File Manager, WP Toolkit, WordPress auto-updates, cache clearing, and Let's Encrypt SSL).

---

## Key Features

1. **Dedicated PHP-FPM 8.4 Pools**:
   - Each site runs in its own pool (`[<domain>]`) under a unique system user (`iso_<domain>`).
   - Dynamic `pm = ondemand`: Consumes zero RAM when idle.
   - `open_basedir` confines PHP execution strictly to the site's docroot and `/tmp`.

2. **Bidirectional POSIX ACLs**:
   - Site directory is owned by `iso_<domain>:iso_<domain>` (`mode 750`).
   - `setfacl` grants `www` and `iso_<domain>` full `rwx` permissions.
   - **aaPanel WP Toolkit & File Manager can edit, update WP core, and clear cache without permission errors.**
   - Other sites (`iso_siteB`) are 100% blocked from entering or reading files.

3. **Native Uploads Protection**:
   - Nginx rule blocks direct execution of `.php` scripts in `wp-content/uploads/` with HTTP `403 Forbidden`.

4. **Zero-Touch Sentinel Daemon**:
   - Automatically detects newly created sites on aaPanel.
   - 15-second debounce window ensures aaPanel completes site, DB, and SSL provisioning before applying isolation.
   - Self-heals permission drift if docroot ownership is reset.

---

## Quick Install (on VPS)

```bash
cd /opt
git clone <repo-url> rs-isolate-nginx
cd rs-isolate-nginx
sudo bash install.sh
```

---

## CLI Usage
### FastCGI RAM Cache (Native Till Krüss Nginx Cache Plugin support)
Each website automatically gets a **dedicated FastCGI Cache zone in RAM (`/dev/shm`)** with POSIX ACL permissions for multi-tenant isolation:

```bash
# View Cache Zone details to configure in WordPress Admin (Tools -> Nginx)
rs-isolate cache status example.com

# Purge / Flush RAM cache for a domain
rs-isolate cache purge example.com

# Disable FastCGI cache for a domain
rs-isolate cache disable example.com

# Re-enable FastCGI cache
rs-isolate cache enable example.com
```


```bash
# List all websites and isolation status
rs-isolate list

# Isolate a specific domain
rs-isolate isolate mysite.com

# Isolate all existing websites
rs-isolate isolate-all

# Audit domain isolation status
rs-isolate status mysite.com

# Restore a domain to standard aaPanel setup
rs-isolate restore mysite.com

# Manage Sentinel daemon
rs-isolate sentinel status
rs-isolate sentinel logs
```
