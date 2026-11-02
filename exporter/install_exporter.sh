#!/bin/bash
# Cai pve_ceph_extra_exporter len 1 node Proxmox co Ceph.
# Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.
#   bash install_exporter.sh            # cai / cap nhat, port 9830
#   PORT=9300 bash install_exporter.sh  # doi port
#   ARGS="--no-ceph-mgr --no-pve" bash install_exporter.sh  # chi xuat metric bo sung
#   bash install_exporter.sh uninstall
set -euo pipefail

PORT="${PORT:-9830}"
ARGS="${ARGS:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN=/usr/local/bin/pve_ceph_extra_exporter.py
UNIT=/etc/systemd/system/pve-ceph-extra-exporter.service

[ "$(id -u)" = 0 ] || { echo "Must run as root"; exit 1; }

if [ "${1:-}" = "uninstall" ]; then
    systemctl disable --now pve-ceph-extra-exporter 2>/dev/null || true
    rm -f "$BIN" "$UNIT"
    systemctl daemon-reload
    echo "pve-ceph-extra-exporter removed"
    exit 0
fi

command -v python3 >/dev/null || { echo "python3 missing"; exit 1; }
command -v ceph >/dev/null || { echo "No ceph command on this node"; exit 1; }
ceph status --format json >/dev/null || { echo "Cannot run 'ceph status' (missing keyring?)"; exit 1; }

install -m 0755 "$DIR/pve_ceph_extra_exporter.py" "$BIN"

cat > "$UNIT" <<EOF
[Unit]
Description=Proxmox Ceph extra exporter (recovery + HA groups)
After=network-online.target ceph.target pve-cluster.service

[Service]
ExecStart=/usr/bin/python3 $BIN --port $PORT $ARGS
Restart=always
RestartSec=5
# Gioi han tai nguyen: exporter khong bao gio gianh CPU / RAM / IO voi VM
Nice=10
CPUQuota=25%
MemoryMax=256M
IOSchedulingClass=idle
TasksMax=64

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pve-ceph-extra-exporter
systemctl restart pve-ceph-extra-exporter
sleep 2

if curl -sf "http://127.0.0.1:$PORT/metrics" | grep -E '^(ceph_custom_recovery_info|pve_ceph_extra_exporter_up)'; then
    echo
    echo "OK - exporter running at http://$(hostname -I | awk '{print $1}'):$PORT/metrics"
    if [ -z "$ARGS" ]; then
        echo "Merged mode: the cluster's Prometheus job needs ONLY this 1 target (remove the old :9283 / :9221 targets)."
    else
        echo "Add this target to the SAME Prometheus job as the cluster's ceph mgr / pve exporter."
    fi
else
    echo "Exporter returns no metrics yet, see: journalctl -u pve-ceph-extra-exporter -n 50"
    exit 1
fi
