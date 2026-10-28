#!/bin/bash
# =============================================================================
#  Menu quan ly Monitor Proxmox + Ceph
#    - pve_ceph_extra_exporter (Ceph recovery + HA groups)
#    - Dashboard Grafana (make_dashboard.py)
#
#  Chay menu:        bash menu.sh
#  Chay 1 lenh:      bash menu.sh <lenh>
#      check | install | status | metrics | logs | restart | port <so> |
#      uninstall | dashboard | import | prom | prom-check | doctor | help
# =============================================================================
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORTER_SRC="$DIR/exporter/pve_ceph_extra_exporter.py"
INSTALLER="$DIR/exporter/install_exporter.sh"
MAKE_DASH="$DIR/make_dashboard.py"
DASH_JSON="$DIR/proxmox_ceph_dashboard.json"

SERVICE=pve-ceph-extra-exporter
BIN=/usr/local/bin/pve_ceph_extra_exporter.py
UNIT=/etc/systemd/system/$SERVICE.service
CONF="$DIR/.menu.conf"          # nho Grafana URL, Prometheus URL, ... giua cac lan chay
DEFAULT_PORT=9284

# ----------------------------------------------------------------- giao dien
if [ -t 1 ]; then
    R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; C=$'\e[36m'; W=$'\e[1m'; N=$'\e[0m'
else
    R=; G=; Y=; B=; C=; W=; N=
fi
ok()   { echo "  ${G}[OK]${N}   $*"; }
warn() { echo "  ${Y}[CANH BAO]${N} $*"; }
err()  { echo "  ${R}[LOI]${N}  $*"; }
info() { echo "  ${C}[i]${N}    $*"; }
title(){ echo; echo "${W}${B}== $* ==${N}"; }
pause(){ [ -t 0 ] && [ "${NONINTERACTIVE:-0}" = 0 ] && { echo; read -rp "  Nhan Enter de quay lai menu..." _; }; }

ask() {  # ask "Cau hoi" "mac dinh" -> echo gia tri
    local q="$1" def="${2:-}" ans
    if [ -n "$def" ]; then read -rp "  $q [$def]: " ans; else read -rp "  $q: " ans; fi
    echo "${ans:-$def}"
}
confirm() {  # confirm "Cau hoi" -> 0 neu dong y
    local ans; read -rp "  $1 (y/N): " ans
    [[ "$ans" =~ ^[YyCc]$ ]]
}

need_root() {
    [ "$(id -u)" = 0 ] && return 0
    err "Can chay bang root (sudo bash menu.sh)"; return 1
}
has() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------------------------------------------- cau hinh luu
load_conf() { [ -f "$CONF" ] && . "$CONF"; }
save_conf() {  # save_conf KEY VALUE
    touch "$CONF"; chmod 600 "$CONF"
    grep -v "^$1=" "$CONF" > "$CONF.tmp" 2>/dev/null || true
    printf '%s=%q\n' "$1" "$2" >> "$CONF.tmp"
    mv "$CONF.tmp" "$CONF"
}
load_conf

current_port() {
    if [ -f "$UNIT" ]; then
        sed -n 's/.*--port \([0-9]\+\).*/\1/p' "$UNIT" | head -1
    else
        echo "$DEFAULT_PORT"
    fi
}
local_ip() { hostname -I 2>/dev/null | awk '{print $1}'; }
svc_state() { systemctl is-active "$SERVICE" 2>/dev/null || true; }

# =============================================================================
# 1. Kiem tra moi truong
# =============================================================================
do_check() {
    title "Kiem tra moi truong node"
    local bad=0

    if [ -f /etc/pve/.version ] || has pveversion; then
        ok "Proxmox VE: $(pveversion 2>/dev/null | head -1)"
    else
        warn "Khong thay Proxmox VE (van chay duoc tren node Ceph thuong)"
    fi

    if has python3; then
        local pv; pv=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')
        if python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,5) else 1)'; then
            ok "python3 $pv"
        else
            err "python3 $pv qua cu (can >= 3.5)"; bad=1
        fi
    else
        err "Thieu python3 (apt install python3)"; bad=1
    fi

    if has ceph; then
        ok "Lenh ceph: $(ceph --version 2>/dev/null | awk '{print $3, $5}')"
        if timeout 15 ceph status --format json >/dev/null 2>&1; then
            ok "ceph status chay duoc: $(timeout 15 ceph health 2>/dev/null)"
        else
            err "Khong chay duoc 'ceph status' (thieu /etc/ceph/ceph.client.admin.keyring hoac mon khong ket noi)"; bad=1
        fi
    else
        err "Node nay khong co lenh ceph -> cai exporter tren node Ceph khac"; bad=1
    fi

    if [ -f /etc/pve/ha/groups.cfg ] || [ -f /etc/pve/ha/rules.cfg ]; then
        ok "Co cau hinh HA: $(ls /etc/pve/ha/groups.cfg /etc/pve/ha/rules.cfg 2>/dev/null | xargs)"
    else
        info "Chua co HA group/rule -> cot HA Groups se trong (binh thuong)"
    fi

    local port; port=$(current_port)
    if has ss && ss -ltnp 2>/dev/null | grep -q ":$port "; then
        if ss -ltnp 2>/dev/null | grep ":$port " | grep -q python3; then
            ok "Port $port dang duoc exporter su dung"
        else
            err "Port $port bi chuong trinh khac chiem: $(ss -ltnp | grep ":$port " | awk '{print $NF}')"; bad=1
        fi
    else
        ok "Port $port con trong"
    fi

    if has pve-firewall && pve-firewall status 2>/dev/null | grep -q "enabled/running"; then
        warn "PVE firewall dang bat -> mo port $port cho IP Prometheus:"
        echo "         Datacenter/Node -> Firewall -> Add: IN ACCEPT tcp dport $port source <IP Prometheus>"
    fi

    has curl || { warn "Thieu curl (apt install curl) - can cho xem metric / import Grafana"; }

    [ "$bad" = 0 ] && ok "Moi truong san sang" || err "Can xu ly cac loi tren truoc khi cai"
    return $bad
}

# =============================================================================
# 2. Cai / cap nhat exporter
# =============================================================================
do_install() {
    title "Cai / cap nhat pve_ceph_extra_exporter"
    need_root || return 1
    [ -f "$EXPORTER_SRC" ] || { err "Khong thay $EXPORTER_SRC"; return 1; }
    local port="${1:-}"
    [ -n "$port" ] || port=$(ask "Port exporter" "$(current_port)")
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] \
        || { err "Port khong hop le: $port"; return 1; }

    if [ -f "$BIN" ]; then
        local old new
        old=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$BIN")
        new=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$EXPORTER_SRC")
        info "Ban dang cai: ${old:-?}  ->  ban moi: ${new:-?}"
    fi

    PORT="$port" bash "$INSTALLER" && {
        echo
        info "Buoc tiep theo: them target $(local_ip):$port vao Prometheus (menu 10)"
    }
}

# =============================================================================
# 3. Trang thai
# =============================================================================
do_status() {
    title "Trang thai exporter"
    if [ ! -f "$UNIT" ]; then
        warn "Chua cai exporter (menu 2)"; return 1
    fi
    local st port; st=$(svc_state); port=$(current_port)
    if [ "$st" = active ]; then ok "Service $SERVICE: ${G}$st${N}"; else err "Service $SERVICE: $st"; fi
    info "Port: $port   |   Ban: $(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$BIN" 2>/dev/null)"
    info "Bat tu dong khi khoi dong: $(systemctl is-enabled "$SERVICE" 2>/dev/null)"
    systemctl show "$SERVICE" -p ActiveEnterTimestamp -p NRestarts -p MemoryCurrent 2>/dev/null \
        | sed 's/^/         /'

    if has curl; then
        local m; m=$(curl -sf --max-time 20 "http://127.0.0.1:$port/metrics") || { err "Khong goi duoc /metrics"; return 1; }
        echo
        echo "$m" | grep '^pve_ceph_extra_exporter_up' | while read -r l; do
            [[ "$l" == *" 1" ]] && ok "$l" || err "$l"
        done
        local line; line=$(echo "$m" | grep '^ceph_custom_recovery_info')
        [ -n "$line" ] && info "Ceph: $(echo "$line" | sed 's/.*content="\([^"]*\)".*/\1/')"
        info "Total Health: $(echo "$m" | awk '/^ceph_custom_recovery_percent /{print $2}') %"
        info "HA groups: $(echo "$m" | grep -c '^pve_ha_groups_custom_info') node"
    fi
}

# =============================================================================
# 4. Xem metric
# =============================================================================
do_metrics() {
    title "Metric hien tai"
    local port; port=$(current_port)
    if [ "$(svc_state)" = active ] && has curl; then
        curl -sf --max-time 20 "http://127.0.0.1:$port/metrics" | grep -v '^#'
    elif has python3 && [ -f "$EXPORTER_SRC" ]; then
        info "Service chua chay -> chay thu 1 lan tu file nguon:"
        python3 "$EXPORTER_SRC" --once | grep -v '^#'
    else
        err "Khong lay duoc metric"
    fi
}

# =============================================================================
# 5. Log / 6. Restart / 7. Doi port / 8. Go cai
# =============================================================================
do_logs() {
    title "Log 50 dong gan nhat"
    journalctl -u "$SERVICE" -n 50 --no-pager 2>/dev/null || err "Khong doc duoc journal"
}

do_restart() {
    title "Khoi dong lai exporter"
    need_root || return 1
    systemctl restart "$SERVICE" && sleep 2
    [ "$(svc_state)" = active ] && ok "Da restart" || { err "Restart loi"; do_logs; }
}

do_port() {
    title "Doi port exporter"
    need_root || return 1
    local p="${1:-}"
    [ -n "$p" ] || p=$(ask "Port moi" "$(current_port)")
    do_install "$p" && warn "Nho sua target trong prometheus.yml sang port $p"
}

do_uninstall() {
    title "Go exporter"
    need_root || return 1
    if [ "${NONINTERACTIVE:-0}" = 1 ] || confirm "Go service $SERVICE khoi node nay?"; then
        bash "$INSTALLER" uninstall
    else
        info "Huy"
    fi
}

# =============================================================================
# 9. Sinh dashboard
# =============================================================================
do_dashboard() {
    title "Sinh dashboard Grafana"
    has python3 || { err "Thieu python3"; return 1; }
    local t u s j n p c o
    t=$(ask "Tieu de dashboard" "${DASH_TITLE:-Proxmox - Ceph Prometheus}")
    u=$(ask "UID (khong dau, khong cach)" "${DASH_UID:-pve-ceph-prom}")
    s=$(ask "Regex loc datasource Site (bo trong = tat ca Prometheus)" "${DASH_SITE:-}")
    j=$(ask "Regex loc job cluster" "${DASH_JOB:-/.*Proxmox-/}")

    # goi y so node/pool/class tu ceph neu chay tren node Ceph
    local dn=8 dp=8 dc=3
    if has ceph && timeout 10 ceph status >/dev/null 2>&1; then
        dn=$(timeout 10 ceph osd tree -f json 2>/dev/null | python3 -c \
            'import json,sys;print(sum(1 for x in json.load(sys.stdin)["nodes"] if x["type"]=="host"))' 2>/dev/null || echo 8)
        dp=$(timeout 10 ceph osd pool ls 2>/dev/null | wc -l)
        dc=$(timeout 10 ceph osd crush class ls -f json 2>/dev/null | python3 -c \
            'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 3)
        info "Doc tu Ceph: $dn node, $dp pool, $dc device class"
    fi
    n=$(ask "So node" "$dn"); p=$(ask "So pool" "$dp"); c=$(ask "So device class" "$dc")
    o=$(ask "File xuat" "$DASH_JSON")

    python3 "$MAKE_DASH" -o "$o" --title "$t" --uid "$u" --site-regex "$s" --job-regex "$j" \
        --nodes "$n" --pools "$p" --classes "$c" || { err "Sinh dashboard loi"; return 1; }
    save_conf DASH_TITLE "$t"; save_conf DASH_UID "$u"; save_conf DASH_SITE "$s"; save_conf DASH_JOB "$j"
    DASH_JSON="$o"
    ok "Da tao $o"
    info "Import: Grafana -> Dashboards -> New -> Import -> Upload JSON, hoac dung menu 11"
}

# =============================================================================
# 11. Import dashboard qua Grafana API
# =============================================================================
do_import() {
    title "Import dashboard len Grafana"
    has curl && has python3 || { err "Can curl va python3"; return 1; }
    [ -f "$DASH_JSON" ] || { warn "Chua co $DASH_JSON -> sinh truoc"; do_dashboard || return 1; }

    local url token folder payload resp
    url=$(ask "Grafana URL" "${GRAFANA_URL:-http://127.0.0.1:3000}"); url="${url%/}"
    info "Tao token: Grafana -> Administration -> Service accounts -> Add token (role Editor)"
    read -rsp "  Service account token (khong hien khi go): " token; echo
    [ -n "$token" ] || { err "Chua nhap token"; return 1; }
    folder=$(ask "Folder UID (bo trong = General)" "${GRAFANA_FOLDER:-}")

    if ! curl -sf --max-time 10 -H "Authorization: Bearer $token" "$url/api/health" >/dev/null; then
        err "Khong ket noi duoc $url"; return 1
    fi

    payload=$(mktemp)
    python3 - "$DASH_JSON" "$folder" > "$payload" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["id"] = None
body = {"dashboard": d, "overwrite": True, "message": "menu.sh import"}
if sys.argv[2]:
    body["folderUid"] = sys.argv[2]
print(json.dumps(body, ensure_ascii=False))
PY
    resp=$(curl -s --max-time 30 -X POST -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" --data-binary "@$payload" "$url/api/dashboards/db")
    rm -f "$payload"
    if echo "$resp" | grep -q '"status":"success"'; then
        ok "Import thanh cong: $url$(echo "$resp" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
        save_conf GRAFANA_URL "$url"; save_conf GRAFANA_FOLDER "$folder"
    else
        err "Import loi: $resp"
    fi
}

# =============================================================================
# 10. Cau hinh Prometheus
# =============================================================================
do_prom() {
    title "Cau hinh Prometheus"
    local port job ip
    port=$(current_port); ip=$(local_ip)
    job=$(ask "Ten job cua cluster nay trong Prometheus (giong job cua ceph mgr)" "${PROM_JOB:-Proxmox-CLUSTER}")
    save_conf PROM_JOB "$job"
    cat <<EOF

  Them target ${W}$ip:$port${N} vao ${W}CUNG job${N} voi ceph mgr / pve exporter, vi du:

  ${C}  - job_name: $job
      static_configs:
        - targets:
            - $ip:9283   # ceph mgr prometheus (da co)
            - $ip:$port   # pve_ceph_extra_exporter (moi)${N}

  Neu job dang dung relabel / labels rieng thi chi them dong '$ip:$port' vao danh sach targets.
  Sau do tren may Prometheus:
      promtool check config /etc/prometheus/prometheus.yml
      systemctl reload prometheus      # hoac: curl -X POST http://<prom>:9090/-/reload

  Neu cac ceph metric tren dashboard dung job khac voi job cua pve_cluster_info,
  dashboard se khong khop -> kiem tra bang menu 12.
EOF
}

# =============================================================================
# 12. Kiem tra phia Prometheus
# =============================================================================
prom_q() {  # prom_q URL QUERY -> in ket qua dang "labels value"
    curl -sfG --max-time 15 "$1/api/v1/query" --data-urlencode "query=$2" | python3 -c '
import json, sys
r = json.load(sys.stdin)["data"]["result"]
for s in r:
    m = s["metric"]
    lab = ",".join("%s=%s" % (k, v) for k, v in sorted(m.items()) if k != "__name__")
    print("{%s} %s" % (lab, s["value"][1]))
'
}

do_prom_check() {
    title "Kiem tra du lieu tren Prometheus"
    has curl && has python3 || { err "Can curl va python3"; return 1; }
    local url port out
    url=$(ask "Prometheus URL" "${PROM_URL:-http://127.0.0.1:9090}"); url="${url%/}"
    curl -sf --max-time 10 "$url/-/ready" >/dev/null || { err "Khong ket noi duoc $url"; return 1; }
    save_conf PROM_URL "$url"
    port=$(current_port)

    echo; info "Target exporter (up{instance=~\".*:$port\"}):"
    out=$(prom_q "$url" "up{instance=~\".*:$port\"}")
    if [ -z "$out" ]; then err "Prometheus chua scrape exporter -> xem menu 10"
    else echo "$out" | while read -r l; do [[ "$l" == *" 1" ]] && ok "$l" || err "$l (target down)"; done; fi

    echo; info "Cac job cluster (pve_cluster_info):"
    prom_q "$url" 'count by (job) (pve_cluster_info)' | sed 's/^/         /'

    echo; info "So sanh job: ceph mgr vs exporter:"
    local cj ej
    cj=$(prom_q "$url" 'count by (job) (ceph_health_status)' | sed 's/{job=\(.*\)} .*/\1/')
    ej=$(prom_q "$url" 'count by (job) (ceph_custom_recovery_info)' | sed 's/{job=\(.*\)} .*/\1/')
    echo "         ceph mgr : $(echo ${cj:-'<khong co>'})"
    echo "         exporter : $(echo ${ej:-'<khong co>'})"
    for j in $ej; do
        echo "$cj" | grep -qx "$j" && ok "job '$j' khop" \
            || err "job '$j' cua exporter khong co ceph mgr -> dashboard se khong hien Recovery"
    done

    echo; info "Trang thai recovery tung cluster:"
    prom_q "$url" 'ceph_custom_recovery_info' | sed 's/^/         /'
    echo; info "OSD device class:"
    prom_q "$url" 'count by (job, device_class) (ceph_osd_metadata)' | sed 's/^/         /'
}

# =============================================================================
# 13. Kiem tra tong the
# =============================================================================
do_doctor() {
    do_check
    if [ -f "$UNIT" ]; then do_status; else warn "Exporter chua cai"; fi
    if [ -n "${PROM_URL:-}" ] && [ "${NONINTERACTIVE:-0}" = 0 ]; then
        confirm "Kiem tra them Prometheus $PROM_URL?" && do_prom_check
    fi
}

# =============================================================================
# Menu
# =============================================================================
show_help() {
    sed -n '2,12p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
}

header() {
    clear 2>/dev/null || true
    local st port
    port=$(current_port)
    if [ -f "$UNIT" ]; then st=$(svc_state); else st="chua cai"; fi
    case "$st" in active) st="${G}$st${N}" ;; *) st="${Y}$st${N}" ;; esac
    echo "${W}${B}=================================================================${N}"
    echo "${W}   MONITOR PROXMOX + CEPH  -  menu quan ly${N}"
    echo "${B}=================================================================${N}"
    echo "   Node: ${W}$(hostname)${N} ($(local_ip))   Exporter: $st   Port: $port"
    echo "${B}-----------------------------------------------------------------${N}"
}

menu() {
    while true; do
        header
        cat <<EOF
   ${W}EXPORTER (chay tren node Ceph)${N}
     1) Kiem tra moi truong node
     2) Cai dat / cap nhat exporter
     3) Trang thai exporter
     4) Xem metric hien tai
     5) Xem log
     6) Khoi dong lai
     7) Doi port
     8) Go cai dat

   ${W}DASHBOARD & PROMETHEUS${N}
     9) Sinh dashboard JSON
    10) Huong dan them target vao Prometheus
    11) Import dashboard len Grafana (API)
    12) Kiem tra du lieu tren Prometheus

    13) Kiem tra tong the
     0) Thoat
EOF
        local c; read -rp "  Chon: " c
        case "$c" in
            1) do_check ;;      2) do_install ;;   3) do_status ;;
            4) do_metrics ;;    5) do_logs ;;      6) do_restart ;;
            7) do_port ;;       8) do_uninstall ;; 9) do_dashboard ;;
            10) do_prom ;;      11) do_import ;;   12) do_prom_check ;;
            13) do_doctor ;;
            0|q|Q) echo; exit 0 ;;
            *) warn "Lua chon khong hop le" ;;
        esac
        pause
    done
}

# ----------------------------------------------------------------- dong lenh
if [ $# -gt 0 ]; then
    NONINTERACTIVE=1
    cmd="$1"; shift
    case "$cmd" in
        check) do_check ;;           install) do_install "${1:-$(current_port)}" ;;
        status) do_status ;;         metrics) do_metrics ;;
        logs) do_logs ;;             restart) do_restart ;;
        port) [ -n "${1:-}" ] || { err "Dung: menu.sh port <so>"; exit 1; }; do_port "$1" ;;
        uninstall) do_uninstall ;;   dashboard) NONINTERACTIVE=0; do_dashboard ;;
        import) NONINTERACTIVE=0; do_import ;;
        prom) NONINTERACTIVE=0; do_prom ;;
        prom-check) NONINTERACTIVE=0; do_prom_check ;;
        doctor) do_doctor ;;
        help|-h|--help) show_help ;;
        *) err "Lenh khong ro: $cmd"; show_help; exit 1 ;;
    esac
    exit $?
fi

menu
