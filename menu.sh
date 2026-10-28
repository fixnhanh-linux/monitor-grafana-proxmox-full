#!/bin/bash
# =============================================================================
#  Menu quan ly Monitor Proxmox + Ceph
#    - pve_ceph_extra_exporter (Ceph recovery + HA groups)
#    - Dashboard Grafana (make_dashboard.py)
#
#  Chay menu:        bash menu.sh
#  Cai tron goi:     bash menu.sh setup   (hoi 1 lan, tu lam het)
#  Chay 1 lenh:      bash menu.sh <lenh>
#      setup | check | install | status | metrics | logs | restart | port <so> |
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
# Ham dung chung (menu le + cai dat tron goi)
# =============================================================================
detect_cluster_name() {
    sed -n 's/^[[:space:]]*cluster_name:[[:space:]]*\([^[:space:]]*\).*/\1/p' /etc/pve/corosync.conf 2>/dev/null | head -1
}

detect_sizes() {  # dat DN DP DC (so node / pool / device class) tu Ceph
    DN=8; DP=8; DC=3
    has ceph && has python3 && timeout 10 ceph status >/dev/null 2>&1 || return 1
    DN=$(timeout 10 ceph osd tree -f json 2>/dev/null | python3 -c \
        'import json,sys;print(sum(1 for x in json.load(sys.stdin)["nodes"] if x["type"]=="host"))' 2>/dev/null || echo 8)
    DP=$(timeout 10 ceph osd pool ls 2>/dev/null | wc -l)
    DC=$(timeout 10 ceph osd crush class ls -f json 2>/dev/null | python3 -c \
        'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 3)
}

detect_ha_groups() {  # moi chuoi HA Groups khac nhau 1 dong (dung dung code cua exporter)
    has python3 || return 0
    python3 - "$DIR/exporter" <<'PY' 2>/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import pve_ceph_extra_exporter as e
for g in sorted(set(e.ha_groups_by_host().values())):
    print(g)
PY
}

dash_defaults() {
    : "${DASH_TITLE:=Proxmox - Ceph Prometheus}" "${DASH_UID:=pve-ceph-prom}" "${DASH_SITE:=}"
    : "${DASH_JOB:=/.*Proxmox-/}" "${DASH_NODES:=8}" "${DASH_POOLS:=8}" "${DASH_CLASSES:=3}"
    : "${DASH_LAT:=nvme=15:25,ssd=50:100,default=100:200}" "${DASH_TIME:=now-15m}" "${DASH_ALIASES:=}"
}

save_dash_conf() {
    local k
    for k in DASH_TITLE DASH_UID DASH_SITE DASH_JOB DASH_NODES DASH_POOLS DASH_CLASSES \
             DASH_LAT DASH_TIME DASH_ALIASES; do
        save_conf "$k" "${!k}"
    done
}

alias_of() {  # ten ngan da luu cho 1 chuoi HA Groups
    local x
    while IFS= read -r x; do
        [ "${x%=*}" = "$1" ] && { echo "${x##*=}"; return; }
    done <<< "${DASH_ALIASES//;;/$'\n'}"
}

ask_aliases() {  # hoi ten ngan cho tung chuoi HA Groups dang co -> DASH_ALIASES
    local groups g t out=""
    groups=$(detect_ha_groups)
    if [ -z "$groups" ]; then
        info "Khong doc duoc HA groups tren may nay -> giu ten ngan da luu (neu co)"
        return 0
    fi
    info "Nhap ten ngan, them :mau neu muon (vd Gold+HIGH:orange). Enter trong = giu ten goc."
    while IFS= read -r g <&3; do
        t=$(ask "$g" "$(alias_of "$g")")
        [ -n "$t" ] && out+="${out:+;;}$g=$t"
    done 3<<< "$groups"
    DASH_ALIASES="$out"
}

gen_dashboard() {  # sinh $DASH_JSON tu cac bien DASH_*
    has python3 || { err "Thieu python3"; return 1; }
    dash_defaults
    local a args=(-o "$DASH_JSON" --title "$DASH_TITLE" --uid "$DASH_UID" --site-regex "$DASH_SITE"
                  --job-regex "$DASH_JOB" --nodes "$DASH_NODES" --pools "$DASH_POOLS"
                  --classes "$DASH_CLASSES" --lat-th "$DASH_LAT" --time-from "$DASH_TIME")
    while IFS= read -r a; do
        [ -n "$a" ] && args+=(--ha-alias "$a")
    done <<< "${DASH_ALIASES//;;/$'\n'}"
    python3 "$MAKE_DASH" "${args[@]}" >/dev/null || { err "Sinh dashboard loi"; return 1; }
    ok "Da tao $DASH_JSON"
}

import_dashboard() {  # import_dashboard URL TOKEN FOLDER
    local url="${1%/}" token="$2" folder="$3" payload resp
    has curl && has python3 || { err "Can curl va python3"; return 1; }
    [ -f "$DASH_JSON" ] || { err "Chua co $DASH_JSON"; return 1; }
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
        err "Import loi: $resp"; return 1
    fi
}

prom_snippet() {  # prom_snippet JOB PORT -> in + luu file mau prometheus.yml
    local job="$1" port="$2" ip f
    ip=$(local_ip); f="$DIR/prometheus-target-$job.yml"
    cat > "$f" <<EOF
# Them vao scrape_configs cua prometheus.yml (CUNG job voi ceph mgr / pve exporter)
  - job_name: $job
    static_configs:
      - targets:
          - $ip:9283   # ceph mgr prometheus (da co)
          - $ip:$port   # pve_ceph_extra_exporter (moi)
EOF
    cat <<EOF

  Them target ${W}$ip:$port${N} vao ${W}CUNG job '$job'${N} voi ceph mgr / pve exporter:

${C}$(sed -n '2,$p' "$f")${N}

  Da luu mau: $f
  Neu job da ton tai thi chi them dong '$ip:$port' vao danh sach targets.
  Tren may Prometheus:
      promtool check config /etc/prometheus/prometheus.yml
      systemctl reload prometheus      # hoac: curl -X POST http://<prom>:9090/-/reload
EOF
}

prom_q() {  # prom_q URL QUERY -> in ket qua dang "{labels} value"
    curl -sfG --max-time 15 "$1/api/v1/query" --data-urlencode "query=$2" | python3 -c '
import json, sys
r = json.load(sys.stdin)["data"]["result"]
for s in r:
    m = s["metric"]
    lab = ",".join("%s=%s" % (k, v) for k, v in sorted(m.items()) if k != "__name__")
    print("{%s} %s" % (lab, s["value"][1]))
'
}

prom_check() {  # prom_check URL -> 0 neu exporter duoc scrape va job khop
    local url="${1%/}" port out cj ej j rc=0
    has curl && has python3 || { err "Can curl va python3"; return 1; }
    curl -sf --max-time 10 "$url/-/ready" >/dev/null || { err "Khong ket noi duoc $url"; return 1; }
    save_conf PROM_URL "$url"
    port=$(current_port)

    echo; info "Target exporter (up{instance=~\".*:$port\"}):"
    out=$(prom_q "$url" "up{instance=~\".*:$port\"}")
    if [ -z "$out" ]; then
        err "Prometheus chua scrape exporter -> them target (menu 10) roi reload Prometheus"; rc=1
    else
        while read -r l; do
            if [[ "$l" == *" 1" ]]; then ok "$l"; else err "$l (target down)"; rc=1; fi
        done <<< "$out"
    fi

    echo; info "Cac job cluster (pve_cluster_info):"
    prom_q "$url" 'count by (job) (pve_cluster_info)' | sed 's/^/         /'

    echo; info "So sanh job: ceph mgr vs exporter:"
    cj=$(prom_q "$url" 'count by (job) (ceph_health_status)' | sed 's/{job=\(.*\)} .*/\1/')
    ej=$(prom_q "$url" 'count by (job) (ceph_custom_recovery_info)' | sed 's/{job=\(.*\)} .*/\1/')
    echo "         ceph mgr : $(echo ${cj:-'<khong co>'})"
    echo "         exporter : $(echo ${ej:-'<khong co>'})"
    for j in $ej; do
        if echo "$cj" | grep -qx "$j"; then ok "job '$j' khop"
        else err "job '$j' cua exporter khong co ceph mgr -> dashboard se khong hien Recovery"; rc=1; fi
    done

    echo; info "Trang thai recovery tung cluster:"
    prom_q "$url" 'ceph_custom_recovery_info' | sed 's/^/         /'
    echo; info "OSD device class:"
    prom_q "$url" 'count by (job, device_class) (ceph_osd_metadata)' | sed 's/^/         /'
    return $rc
}

# =============================================================================
# 9. Sinh dashboard
# =============================================================================
ask_dashboard() {  # hoi cac tuy chon dashboard -> bien DASH_*
    dash_defaults
    DASH_TITLE=$(ask "Tieu de dashboard" "$DASH_TITLE")
    DASH_UID=$(ask "UID (khong dau, khong cach; trung UID se ghi de)" "$DASH_UID")
    DASH_SITE=$(ask "Regex loc datasource Site (bo trong = tat ca Prometheus)" "$DASH_SITE")
    DASH_JOB=$(ask "Regex loc job cluster" "$DASH_JOB")
    if detect_sizes; then
        info "Doc tu Ceph: $DN node, $DP pool, $DC device class"
    else
        DN=$DASH_NODES; DP=$DASH_POOLS; DC=$DASH_CLASSES
    fi
    DASH_NODES=$(ask "So node (chieu cao bang HA)" "$DN")
    DASH_POOLS=$(ask "So pool (chieu cao bang pool)" "$DP")
    DASH_CLASSES=$(ask "So device class" "$DC")
    DASH_LAT=$(ask "Nguong latency ms theo class (canh bao:nghiem trong)" "$DASH_LAT")
    DASH_TIME=$(ask "Khoang thoi gian mac dinh" "$DASH_TIME")
    if confirm "Dat ten ngan + mau cho HA Groups?"; then ask_aliases; fi
}

do_dashboard() {
    title "Sinh dashboard Grafana"
    ask_dashboard
    DASH_JSON=$(ask "File xuat" "$DASH_JSON")
    gen_dashboard || return 1
    save_dash_conf
    info "Import: Grafana -> Dashboards -> New -> Import -> Upload JSON, hoac dung menu 11"
}

# =============================================================================
# 11. Import dashboard qua Grafana API
# =============================================================================
ask_token() {
    info "Tao token: Grafana -> Administration -> Service accounts -> Add token (role Editor)"
    read -rsp "  Service account token (khong hien khi go): " TOKEN; echo
}

do_import() {
    title "Import dashboard len Grafana"
    [ -f "$DASH_JSON" ] || { warn "Chua co $DASH_JSON -> sinh truoc"; do_dashboard || return 1; }
    local url folder
    url=$(ask "Grafana URL" "${GRAFANA_URL:-http://127.0.0.1:3000}")
    ask_token
    [ -n "$TOKEN" ] || { err "Chua nhap token"; return 1; }
    folder=$(ask "Folder UID (bo trong = General)" "${GRAFANA_FOLDER:-}")
    import_dashboard "$url" "$TOKEN" "$folder"
}

# =============================================================================
# 10. Cau hinh Prometheus
# =============================================================================
do_prom() {
    title "Cau hinh Prometheus"
    local job cn
    cn=$(detect_cluster_name)
    job=$(ask "Ten job cua cluster nay trong Prometheus (giong job cua ceph mgr)" "${PROM_JOB:-Proxmox-${cn:-CLUSTER}}")
    save_conf PROM_JOB "$job"
    prom_snippet "$job" "$(current_port)"
}

# =============================================================================
# 12. Kiem tra phia Prometheus
# =============================================================================
do_prom_check() {
    title "Kiem tra du lieu tren Prometheus"
    prom_check "$(ask "Prometheus URL" "${PROM_URL:-http://127.0.0.1:9090}")"
}

# =============================================================================
# 13. Kiem tra tong the
# =============================================================================
do_doctor() {
    do_check
    if [ -f "$UNIT" ]; then do_status; else warn "Exporter chua cai"; fi
    if [ -n "${PROM_URL:-}" ] && [ "${NONINTERACTIVE:-0}" = 0 ]; then
        confirm "Kiem tra them Prometheus $PROM_URL?" && prom_check "$PROM_URL"
    fi
}

# =============================================================================
# S. Cai dat tron goi: hoi het 1 lan, xac nhan, roi tu lam tung buoc
# =============================================================================
do_setup() {
    title "CAI DAT TRON GOI"
    echo "  Tra loi cac cau hoi ben duoi (Enter = dung gia tri trong [ ])."
    echo "  Cau tra loi duoc nho trong .menu.conf cho lan chay sau (khong luu token)."
    dash_defaults
    local role port="" job="" cn gurl="" gfolder="" prom="" TOKEN=""
    local do_ex=0 do_dash=0 do_imp=0 do_chk=0

    echo; echo "  ${W}[1/5] May nay lam gi?${N}"
    echo "     1) Node Ceph: cai exporter + sinh/import dashboard (day du)"
    echo "     2) Chi cai exporter (node Ceph)"
    echo "     3) Chi sinh / import dashboard (may Grafana / may quan tri)"
    role=$(ask "Chon" "${SETUP_ROLE:-1}")
    case "$role" in
        1) do_ex=1; do_dash=1 ;;
        2) do_ex=1 ;;
        3) do_dash=1 ;;
        *) err "Lua chon khong hop le: $role"; return 1 ;;
    esac

    if [ $do_ex = 1 ]; then
        need_root || return 1
        echo; echo "  ${W}[2/5] Exporter${N}"
        port=$(ask "Port exporter" "$(current_port)")
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] \
            || { err "Port khong hop le: $port"; return 1; }
        cn=$(detect_cluster_name)
        [ -n "$cn" ] && info "Ten cluster Proxmox (corosync): $cn"
        job=$(ask "Ten job Prometheus cua cluster (phai trung job cua ceph mgr)" "${PROM_JOB:-Proxmox-${cn:-CLUSTER}}")
    fi

    if [ $do_dash = 1 ]; then
        echo; echo "  ${W}[3/5] Dashboard${N}"
        ask_dashboard
        echo; echo "  ${W}[4/5] Grafana${N}"
        gurl=$(ask "Grafana URL (bo trong = khong import, chi xuat file JSON)" "${GRAFANA_URL:-}")
        if [ -n "$gurl" ]; then
            ask_token
            gfolder=$(ask "Folder UID (bo trong = General)" "${GRAFANA_FOLDER:-}")
            if [ -n "$TOKEN" ]; then do_imp=1; else warn "Khong co token -> chi xuat file JSON"; fi
        fi
    fi

    echo; echo "  ${W}[5/5] Prometheus${N}"
    prom=$(ask "Prometheus URL de kiem tra sau khi cai (bo trong = bo qua)" "${PROM_URL:-}")
    [ -n "$prom" ] && do_chk=1

    title "TOM TAT"
    if [ $do_ex = 1 ]; then
        echo "  Exporter       : cai service $SERVICE tren $(hostname), port $port"
        echo "  Prometheus job : $job  (target $(local_ip):$port)"
    fi
    if [ $do_dash = 1 ]; then
        echo "  Dashboard      : \"$DASH_TITLE\"  uid=$DASH_UID  -> $DASH_JSON"
        echo "  Loc Site / job : ${DASH_SITE:-<tat ca>}  /  $DASH_JOB"
        echo "  Kich thuoc     : $DASH_NODES node, $DASH_POOLS pool, $DASH_CLASSES class   time=$DASH_TIME"
        echo "  Latency (ms)   : $DASH_LAT"
        echo "  HA alias       : ${DASH_ALIASES:-<khong>}" | sed 's/;;/  |  /g'
        if [ $do_imp = 1 ]; then echo "  Import Grafana : $gurl  folder=${gfolder:-General}"
        else echo "  Import Grafana : khong (import tay file JSON)"; fi
    fi
    if [ $do_chk = 1 ]; then echo "  Kiem tra       : $prom"; else echo "  Kiem tra       : bo qua"; fi
    echo
    confirm "Bat dau thuc hien?" || { info "Huy - chua thay doi gi"; return 1; }

    save_conf SETUP_ROLE "$role"
    [ -n "$job" ] && save_conf PROM_JOB "$job"
    [ $do_dash = 1 ] && save_dash_conf
    [ -n "$prom" ] && save_conf PROM_URL "${prom%/}"

    local step=0 total=$((do_ex * 3 + do_dash + do_imp + do_chk)) failed=()
    next() { step=$((step + 1)); echo; echo "${W}${B}>>> [$step/$total] $1${N}"; }

    if [ $do_ex = 1 ]; then
        next "Kiem tra moi truong"
        do_check || { err "Dung lai: sua cac loi tren roi chay lai (menu S)"; return 1; }
        next "Cai exporter (port $port)"
        PORT="$port" bash "$INSTALLER" || { err "Cai exporter loi"; return 1; }
        next "Cau hinh Prometheus"
        prom_snippet "$job" "$port"
    fi
    if [ $do_dash = 1 ]; then
        next "Sinh dashboard"
        gen_dashboard || failed+=("sinh dashboard")
    fi
    if [ $do_imp = 1 ]; then
        next "Import dashboard len Grafana"
        import_dashboard "$gurl" "$TOKEN" "$gfolder" || failed+=("import Grafana")
    fi
    if [ $do_chk = 1 ]; then
        next "Kiem tra Prometheus"
        prom_check "$prom" || failed+=("kiem tra Prometheus")
    fi

    title "KET QUA"
    if [ ${#failed[@]} = 0 ]; then
        ok "Hoan tat $total buoc"
    else
        err "Loi o: ${failed[*]}"
    fi
    [ $do_ex = 1 ] && [ $do_chk = 0 ] && \
        info "Nho them target vao Prometheus roi chay: bash menu.sh prom-check"
    [ $do_dash = 1 ] && [ $do_imp = 0 ] && \
        info "Import tay: Grafana -> Dashboards -> New -> Import -> $DASH_JSON"
    info "Muon doi cau tra loi: chay lai menu S (gia tri cu hien san), hoac sua $CONF"
    [ ${#failed[@]} = 0 ]
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
   ${W}${G}S) CAI DAT TRON GOI${N} - hoi 1 lan, tu lam het cac buoc ben duoi

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
            s|S) do_setup ;;
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
        setup) NONINTERACTIVE=0; do_setup ;;
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
