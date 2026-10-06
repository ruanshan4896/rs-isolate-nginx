#!/usr/bin/env bash
# install.sh - 1-line installer for rs-isolate-nginx on aaPanel Ubuntu/Debian

set -eu
set -o pipefail 2>/dev/null || true

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] rs-isolate-nginx must be installed as root.\033[0m" >&2
    exit 1
fi

INSTALL_DIR="/opt/rs-isolate-nginx"
echo -e "\033[0;34m[INFO] Installing rs-isolate-nginx to ${INSTALL_DIR}...\033[0m"

mkdir -p "$INSTALL_DIR"
cp -r bin lib systemd "$INSTALL_DIR/"
chmod +x "${INSTALL_DIR}/bin/"*

ln -sf "${INSTALL_DIR}/bin/rs-isolate" /usr/local/bin/rs-isolate
ln -sf "${INSTALL_DIR}/bin/rs-isolate-sentinel" /usr/local/bin/rs-isolate-sentinel

# Install & start systemd Sentinel daemon
if [ -d "/etc/systemd/system" ]; then
    cp "${INSTALL_DIR}/systemd/rs-isolate-sentinel.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now rs-isolate-sentinel
    echo -e "\033[0;32m[SUCCESS] Sentinel background daemon activated and enabled on boot!\033[0m"
fi

echo -e "\033[0;32m===========================================================\033[0m"
echo -e "\033[0;32m  rs-isolate-nginx installed successfully!                 \033[0m"
echo -e "\033[0;32m===========================================================\033[0m"
echo "Usage:"
echo "  rs-isolate list          # List all sites and status"
echo "  rs-isolate isolate <dom> # Isolate a site"
echo "  rs-isolate isolate-all   # Isolate all current sites"
echo "  rs-isolate status <dom>  # Audit site isolation status"
echo "  rs-isolate sentinel logs # Watch live Zero-Touch daemon logs"
