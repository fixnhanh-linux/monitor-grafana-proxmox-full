#!/bin/bash
# Cai pve_ceph_extra_exporter len 1 node Proxmox co Ceph.
# Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.
#   bash install_exporter.sh            # cai / cap nhat, port 9284
#   PORT=9300 bash install_exporter.sh  # doi port
#   bash install_exporter.sh uninstall
set -euo pipefail

PORT="${PORT:-9284}"
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN=/usr/local/bin/pve_ceph_extra_exporter.py
UNIT=/etc/systemd/system/pve-ceph-extra-exporter.service

[ "$(id -u)" = 0 ] || { echo "Can chay bang root"; exit 1; }

if [ "${1:-}" = "uninstall" ]; then
    systemctl disable --now pve-ceph-extra-exporter 2>/dev/null || true
    rm -f "$BIN" "$UNIT"
    systemctl daemon-reload
    echo "Da go pve-ceph-extra-exporter"
    exit 0
fi

command -v python3 >/dev/null || { echo "Thieu python3"; exit 1; }
command -v ceph >/dev/null || { echo "Node nay khong co lenh ceph"; exit 1; }
ceph status --format json >/dev/null || { echo "Khong chay duoc 'ceph status' (thieu keyring?)"; exit 1; }

install -m 0755 "$DIR/pve_ceph_extra_exporter.py" "$BIN"

cat > "$UNIT" <<EOF
[Unit]
Description=Proxmox Ceph extra exporter (recovery + HA groups)
After=network-online.target ceph.target pve-cluster.service

[Service]
ExecStart=/usr/bin/python3 $BIN --port $PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pve-ceph-extra-exporter
systemctl restart pve-ceph-extra-exporter
sleep 2

if curl -sf "http://127.0.0.1:$PORT/metrics" | grep -E '^(ceph_custom_recovery_info|pve_ceph_extra_exporter_up)'; then
    echo
    echo "OK - exporter chay tai http://$(hostname -I | awk '{print $1}'):$PORT/metrics"
    echo "Them target nay vao CUNG job Prometheus voi ceph mgr / pve exporter cua cluster."
else
    echo "Exporter chua tra metric, xem: journalctl -u pve-ceph-extra-exporter -n 50"
    exit 1
fi
