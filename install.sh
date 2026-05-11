#!/bin/bash
# Copyright (c) 2026 Florian Hesse — comnic IT (https://comnic-it.de)
# License: MIT (see LICENSE in the same directory)
#
# Sets up signotec-stpadserver as a systemd service and wires Apache as a
# WSS reverse proxy. Run as root.
#
# Requirements:
#   - docker.io installed (apt-get install docker.io)
#   - calling user in the docker group
#   - Apache 2 running with an SSL vhost at /etc/apache2/sites-enabled/orbit-ssl.conf
#
# Steps:
#   1. docker build (downloads the signotec installer at build time)
#   2. systemd unit install + enable
#   3. Apache modules + reverse-proxy snippet
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APACHE_SITE="/etc/apache2/sites-enabled/orbit-ssl.conf"
IMAGE_TAG="${SIGNOTEC_IMAGE_TAG:-signotec-stpadserver:wine}"

echo "[1/4] Building Docker image ($IMAGE_TAG) — fetches signotec installer"
docker build -t "$IMAGE_TAG" "$SCRIPT_DIR"

echo "[2/4] Installing + starting systemd unit"
install -m 0644 "$SCRIPT_DIR/systemd/signotec-stpadserver.service" \
    /etc/systemd/system/signotec-stpadserver.service
systemctl daemon-reload
systemctl enable --now signotec-stpadserver.service
sleep 6
systemctl --no-pager --full status signotec-stpadserver.service | head -10

echo "[3/4] Enabling Apache modules + injecting reverse-proxy snippet"
a2enmod proxy proxy_http proxy_wstunnel headers >/dev/null
if [ -f "$APACHE_SITE" ] && ! grep -q "/signotec-ws/" "$APACHE_SITE"; then
    sed -i '/<\/VirtualHost>/i\\n# signotec STPadServer reverse proxy (auto-injected)' "$APACHE_SITE"
    sed -i "/# signotec STPadServer reverse proxy/r $SCRIPT_DIR/apache/orbit-ssl-signotec.snippet" "$APACHE_SITE"
    echo "  -> snippet inserted into $APACHE_SITE"
fi

echo "[4/4] Apache config-test + reload"
apache2ctl configtest
systemctl reload apache2

echo
echo "Done."
echo "Next steps in your web app:"
echo "  - Connect type:  Network"
echo "  - WSS endpoint:  /signotec-ws/"
echo "  - Pad IP:        <ip>:1002  (e.g. 192.168.111.156:1002)"
echo
echo "  Container status: docker ps --filter name=signotec-stpadserver"
echo "  Container logs:   journalctl -u signotec-stpadserver -f"
