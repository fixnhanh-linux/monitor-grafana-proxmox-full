#!/bin/bash
# =============================================================================
#  FIX NHANH - Giam sat Ceph tren Proxmox bang Zabbix Agent 2
#  Copyright (c) 2026 FIX NHANH. All rights reserved.
#
#  Chay tren 1 may bat ky SSH duoc vao cac node Proxmox (vd may monitor):
#    bash template-zabbix/setup_ceph_zabbix.sh [ZABBIX_IP] [NODE1 NODE2 ...]
#  hoac proxmox-ceph-monitor.sh muc 27 (zabbix-ceph).
#
#  Tren tung node:
#    - cai / cau hinh zabbix-agent2 (Server, ServerActive, plugin Ceph bo qua cert tu ky)
#    - cron moi phut ghi `ceph health` ra /etc/zabbix/cephstatus.txt (du phong khi API loi)
#  Tren node dau tien:
#    - bat ceph mgr module restful, tao API key user zabbix-monitor, cert tu ky
#    - in 3 macro de dien vao template "Ceph by Zabbix agent 2" tren Zabbix web
#
#  Khong con dung system.run[*] / docfile.sh: template du phong
#  template-zabbix/ceph-health-fallback.yaml doc file bang vfs.file.contents.
# =============================================================================
set -uo pipefail

ok()   { echo "  [OK] $*"; }
info() { echo "  [..] $*"; }
warn() { echo "  [!!] $*"; }
die()  { echo "  [XX] $*"; exit 1; }

ZABBIX_SERVER_IP=${1:-}
shift 2>/dev/null || true
PROXMOX_NODES=${*:-}

[ -n "$ZABBIX_SERVER_IP" ] || { read -rp "Zabbix server / proxy IP [10.8.10.201]: " ZABBIX_SERVER_IP; ZABBIX_SERVER_IP=${ZABBIX_SERVER_IP:-10.8.10.201}; }
[ -n "$PROXMOX_NODES" ] || read -rp "Proxmox node IPs (space separated, e.g. 10.0.0.1 10.0.0.2): " PROXMOX_NODES
[ -n "$PROXMOX_NODES" ] || die "No Proxmox node entered"

# SSH: uu tien key; node nao chua co key thi dung mat khau root (hoi 1 lan, sshpass)
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
NEED_PASS=0
for node in $PROXMOX_NODES; do
    ssh "${SSH_OPTS[@]}" -o BatchMode=yes root@"$node" true 2>/dev/null || { NEED_PASS=1; break; }
done
SSH_PASSWORD=""
if [ "$NEED_PASS" = 1 ]; then
    info "Some nodes have no SSH key access → the root password is used (asked once)"
    if ! command -v sshpass >/dev/null; then
        info "Installing sshpass..."
        { command -v apt-get >/dev/null && apt-get install -y -qq sshpass; } \
            || { command -v dnf >/dev/null && dnf install -y -q sshpass; } \
            || die "sshpass is required (or install SSH keys on the nodes with ssh-copy-id)"
    fi
    read -rsp "Root password of the Proxmox nodes (same for all): " SSH_PASSWORD; echo
    [ -n "$SSH_PASSWORD" ] || die "No password entered"
fi
run_on() {  # run_on NODE ARGS... (script doc tu stdin)
    local node=$1; shift
    if [ -n "$SSH_PASSWORD" ]; then
        SSHPASS=$SSH_PASSWORD sshpass -e ssh "${SSH_OPTS[@]}" root@"$node" "bash -s" -- "$@"
    else
        ssh "${SSH_OPTS[@]}" root@"$node" "bash -s" -- "$@"
    fi
}

echo "============================================================"
echo " Zabbix Agent 2 for Ceph  ·  server $ZABBIX_SERVER_IP"
echo " Nodes: $PROXMOX_NODES"
echo "============================================================"

FAILED=""
for node in $PROXMOX_NODES; do
    echo; echo ">>> $node"
    run_on "$node" "$ZABBIX_SERVER_IP" <<'EOF' || FAILED="$FAILED $node"
ZABBIX_SERVER_IP=$1
# 1. Cai zabbix-agent2 neu chua co
if ! dpkg -s zabbix-agent2 >/dev/null 2>&1; then
    echo "  [..] Installing zabbix-agent2..."
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq zabbix-agent2 >/dev/null 2>&1
    dpkg -s zabbix-agent2 >/dev/null 2>&1 || {
        echo "  [XX] zabbix-agent2 cannot be installed (add the Zabbix repo: https://www.zabbix.com/download)"; exit 1; }
fi
echo "  [OK] zabbix-agent2 $(dpkg-query -W -f '${Version}' zabbix-agent2)"

# 2. Cau hinh agent (giu ban sao .bak)
CONF=/etc/zabbix/zabbix_agent2.conf
[ -f "$CONF" ] || { echo "  [XX] $CONF not found"; exit 1; }
cp -p "$CONF" "$CONF.bak"
sed -i "s/^Server=.*/Server=${ZABBIX_SERVER_IP}/; s/^ServerActive=.*/ServerActive=${ZABBIX_SERVER_IP}/" "$CONF"
grep -q '^Plugins.Ceph.InsecureSkipVerify=' "$CONF" || echo 'Plugins.Ceph.InsecureSkipVerify=true' >> "$CONF"
echo "  [OK] $CONF: Server=$ZABBIX_SERVER_IP, Ceph plugin accepts the self-signed restful cert"

# 3. Du phong: cron moi phut ghi ceph health ra file, template doc bang vfs.file.contents
cat > /etc/zabbix/cephstatus.sh <<'INNER'
#!/bin/sh
{ ceph health 2>&1; date; } > /etc/zabbix/cephstatus.txt.tmp && mv /etc/zabbix/cephstatus.txt.tmp /etc/zabbix/cephstatus.txt
chmod 644 /etc/zabbix/cephstatus.txt
INNER
chmod 755 /etc/zabbix/cephstatus.sh
rm -f /etc/zabbix/docfile.sh   # ban cu doc file qua system.run, khong dung nua
/etc/zabbix/cephstatus.sh || echo "  [!!] 'ceph health' failed (no Ceph monitor on this node?)"
(crontab -l 2>/dev/null | grep -vF /etc/zabbix/cephstatus.sh; echo '* * * * * /etc/zabbix/cephstatus.sh') | crontab -
echo "  [OK] cron: /etc/zabbix/cephstatus.sh every minute → /etc/zabbix/cephstatus.txt"

# 4. Khoi dong agent
systemctl enable --now zabbix-agent2 >/dev/null 2>&1
systemctl restart zabbix-agent2
systemctl is-active -q zabbix-agent2 && echo "  [OK] zabbix-agent2 running" || { echo "  [XX] zabbix-agent2 is not running: journalctl -u zabbix-agent2"; exit 1; }
EOF
done

FIRST=$(echo "$PROXMOX_NODES" | awk '{print $1}')
echo; echo ">>> Ceph RESTful API (node $FIRST)"
run_on "$FIRST" <<'EOF'
if ! ceph mgr module enable restful 2>/dev/null; then
    echo "  [!!] The restful mgr module is not available on this Ceph version."
    echo "       The 'Ceph by Zabbix agent 2' template needs it; use the Prometheus / Grafana path (menu 17) instead."
    exit 0
fi
ceph restful create-key zabbix-monitor >/dev/null 2>&1
ceph restful create-self-signed-cert >/dev/null 2>&1
ceph restful restart >/dev/null 2>&1
sleep 3
KEY=$(ceph restful list-keys 2>/dev/null | grep '"zabbix-monitor"' | cut -d'"' -f4)
URL=$(ceph mgr services 2>/dev/null | grep '"restful"' | cut -d'"' -f4)
echo
echo "  ****************************************************************"
echo "   Zabbix web → Data collection → Hosts → <host> → Macros"
echo "  ****************************************************************"
echo "   {\$CEPH.API.KEY} = ${KEY:-<run: ceph restful list-keys>}"
echo "   {\$CEPH.USER}    = zabbix-monitor"
echo "   {\$CEPH.API.URL} = ${URL:-https://<active-mgr-ip>:8003}"
echo "  ****************************************************************"
EOF

echo
echo "Templates to link on each host in Zabbix:"
echo "  - Ceph by Zabbix agent 2 (built into Zabbix) + the 3 macros above"
echo "  - template-zabbix/ceph-health-fallback.yaml (import once: Data collection → Templates → Import)"
if [ -n "$FAILED" ]; then echo; warn "Failed on:$FAILED"; exit 1; fi
echo; ok "Done"
