#!/bin/bash
# =============================================================================
#  FIX NHANH - Monitor Proxmox + Ceph
#    - pve_ceph_extra_exporter (Ceph recovery + HA groups)
#    - Dashboard Grafana (make_dashboard.py)
#
#  Chay menu:        bash menu.sh
#  Cai tron goi:     bash menu.sh setup   (hoi 1 lan, tu lam het)
#  Chay 1 lenh:      bash menu.sh <lenh>
#      setup | check | install | status | metrics | logs | restart | port <so> |
#      uninstall | dashboard | import | prom | prom-check | doctor | update | about | help |
#      remote-add [ten] | remote-list | remote-test | remote-remove |
#      deps | firewall | docker-run | docker-manage
#
#  Ban quyen © 2026 FIX NHANH. Bao luu moi quyen.
# =============================================================================
set -uo pipefail

TOOL_NAME="FIX NHANH · Monitor Proxmox + Ceph"
TOOL_VERSION="2026.10.30"
REPO_URL="https://github.com/fixnhanh-linux/monitor-grafana-proxmox-full"
COPYRIGHT="© 2026 FIX NHANH · Bao luu moi quyen"

DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORTER_SRC="$DIR/exporter/pve_ceph_extra_exporter.py"
INSTALLER="$DIR/exporter/install_exporter.sh"
MAKE_DASH="$DIR/make_dashboard.py"
DASH_JSON="$DIR/proxmox_ceph_dashboard.json"

SERVICE=pve-ceph-extra-exporter
BIN=/usr/local/bin/pve_ceph_extra_exporter.py
UNIT=/etc/systemd/system/$SERVICE.service
CONF="$DIR/.menu.conf"          # nho Grafana URL, Prometheus URL, ... giua cac lan chay
DEFAULT_PORT=9830
REMOTE_DIR=/etc/pve-ceph-extra-exporter     # che do remote: 1 file .env / cluster (chmod 600)
RUNIT=/etc/systemd/system/pve-ceph-extra-exporter@.service

# =============================================================================
# Giao dien: mau, khung can giua
# =============================================================================
# ${#chuoi} dem dung ky tu tieng Viet / khung chi khi locale la UTF-8
if locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$'; then export LC_ALL=C.UTF-8; fi

if [ -t 1 ]; then
    R=$'\e[38;5;203m'; G=$'\e[38;5;114m'; Y=$'\e[38;5;221m'; B=$'\e[38;5;75m'
    C=$'\e[38;5;87m';  M=$'\e[38;5;177m'; O=$'\e[38;5;215m'; D=$'\e[38;5;245m'
    W=$'\e[1m'; N=$'\e[0m'; BC=$'\e[38;5;69m'
    GRAD=($'\e[38;5;51m' $'\e[38;5;45m' $'\e[38;5;39m' $'\e[38;5;33m' $'\e[38;5;63m' $'\e[38;5;99m')
else
    R=; G=; Y=; B=; C=; M=; O=; D=; W=; N=; BC=; GRAD=("" "" "" "" "" "")
fi

setup_ui() {
    COLS=$(tput cols 2>/dev/null || echo 80)
    [[ "$COLS" =~ ^[0-9]+$ ]] && [ "$COLS" -ge 40 ] || COLS=80
    BOXW=$((COLS - 4)); [ $BOXW -gt 84 ] && BOXW=84; [ $BOXW -lt 60 ] && BOXW=60
    LPAD=$(((COLS - BOXW) / 2)); [ $LPAD -lt 0 ] && LPAD=0
    IND=$(printf '%*s' "$LPAD" '')
}
setup_ui

vis_len() {  # do dai hien thi (bo ma mau)
    local s; s=$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'); echo ${#s}
}
hline() { local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }

box_top()    { echo "${IND}${BC}╭$(hline ─ $((BOXW - 2)))╮${N}"; }
box_sep()    { echo "${IND}${BC}├$(hline ─ $((BOXW - 2)))┤${N}"; }
box_bottom() { echo "${IND}${BC}╰$(hline ─ $((BOXW - 2)))╯${N}"; }
box_row() {  # dong can trai trong khung
    local t="$1" pad; pad=$((BOXW - 4 - $(vis_len "$t"))); [ $pad -lt 0 ] && pad=0
    printf '%s%s│%s %s%*s %s│%s\n' "$IND" "$BC" "$N" "$t" "$pad" '' "$BC" "$N"
}
box_center() {  # dong can giua trong khung
    local t="$1" len l r; len=$(vis_len "$t")
    l=$(((BOXW - 2 - len) / 2)); [ $l -lt 0 ] && l=0; r=$((BOXW - 2 - len - l)); [ $r -lt 0 ] && r=0
    printf '%s%s│%s%*s%s%*s%s│%s\n' "$IND" "$BC" "$N" "$l" '' "$t" "$r" '' "$BC" "$N"
}
box_title() {  # ├─ TIEU DE ──────┤
    local t=" $1 " len; len=$(vis_len "$t")
    echo "${IND}${BC}├─${N}${W}${2:-$Y}${t}${N}${BC}$(hline ─ $((BOXW - 3 - len)))┤${N}"
}
box_row2() {  # 2 cot
    local a="$1" b="$2" cw pad; cw=$(((BOXW - 4) / 2))
    pad=$((cw - $(vis_len "$a"))); [ $pad -lt 2 ] && pad=2
    box_row "$a$(printf '%*s' $pad '')$b"
}
mi() { printf '%s%s%3s%s  %s' "${3:-$C}" "$W" "$1" "$N" "$2"; }   # muc menu: phim, chu, mau
kv() {  # nhan: gia tri (tu dem theo so ky tu, printf %-Ns dem byte voi chu co dau)
    local p=$((12 - ${#1})); [ $p -lt 1 ] && p=1
    printf '%s%s%s%*s%s' "$D" "$1" "$N" "$p" '' "$2"
}

ok()   { echo "${IND}  ${G}✔${N}  $*"; }
warn() { echo "${IND}  ${Y}▲${N}  $*"; }
err()  { echo "${IND}  ${R}✘${N}  $*"; }
info() { echo "${IND}  ${C}●${N}  $*"; }
sub()  { sed "s/^/${IND}      /"; }   # thut le output lenh
title() {
    local t=" $* " len l; len=$(vis_len "$t"); l=$(((BOXW - len) / 2)); [ $l -lt 2 ] && l=2
    echo; echo "${IND}${BC}$(hline ━ $l)${N}${W}${C}${t}${N}${BC}$(hline ━ $((BOXW - len - l)))${N}"
}
pause() {
    [ -t 0 ] && [ "${NONINTERACTIVE:-0}" = 0 ] || return 0
    echo; read -rp "${IND}  ${D}Nhan Enter de quay lai menu...${N}" _
}

ask() {  # ask "Cau hoi" "mac dinh" -> in gia tri
    local q="$1" def="${2:-}" ans
    if [ -n "$def" ]; then read -rp "${IND}  ${C}❯${N} $q ${D}[$def]${N}: " ans
    else read -rp "${IND}  ${C}❯${N} $q: " ans; fi
    echo "${ans:-$def}"
}
confirm() {  # confirm "Cau hoi" -> 0 neu dong y
    local ans; read -rp "${IND}  ${Y}?${N} $1 ${D}(y/N)${N}: " ans
    [[ "$ans" =~ ^[YyCc]$ ]]
}

need_root() {
    [ "$(id -u)" = 0 ] && return 0
    err "Can chay bang root (sudo bash menu.sh)"; return 1
}
has() { command -v "$1" >/dev/null 2>&1; }

# =============================================================================
# Cau hinh luu
# =============================================================================
load_conf() { [ -f "$CONF" ] && . "$CONF"; }
save_conf() {  # save_conf KEY VALUE
    touch "$CONF"; chmod 600 "$CONF"
    grep -v "^$1=" "$CONF" > "$CONF.tmp" 2>/dev/null || true
    printf '%s=%q\n' "$1" "$2" >> "$CONF.tmp"
    mv "$CONF.tmp" "$CONF"
}
load_conf

current_flags() {  # co --no-* cua service dang cai (rong = gop tat ca metric 1 port)
    if [ -f "$UNIT" ]; then grep -o -- '--no-[a-z-]*' "$UNIT" | xargs; else echo "${EXPORTER_ARGS:-}"; fi
}
mode_text() {  # mode_text FLAGS
    if [ -z "$1" ]; then echo "gop 1 port (ceph mgr + Proxmox + bo sung)"; else echo "chi metric bo sung ($1)"; fi
}

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
# Nhan dien may (chay 1 lan khi mo menu)
# =============================================================================
detect_env() {
    ENV_OS=$(. /etc/os-release 2>/dev/null && echo "${NAME%% *} ${VERSION_ID:-}${VERSION_CODENAME:+ ($VERSION_CODENAME)}")
    ENV_PVE=""; has pveversion && ENV_PVE=$(pveversion 2>/dev/null | sed -n 's|^pve-manager/\([^/ ]*\).*|\1|p')
    ENV_CEPH=0
    has ceph && timeout 8 ceph status >/dev/null 2>&1 && ENV_CEPH=1
    ENV_GRAFANA=""; ENV_PROM=""
    if has curl; then
        curl -sf --max-time 2 http://127.0.0.1:3000/api/health >/dev/null 2>&1 && ENV_GRAFANA="http://127.0.0.1:3000"
        curl -sf --max-time 2 http://127.0.0.1:9090/-/ready >/dev/null 2>&1 && ENV_PROM="http://127.0.0.1:9090"
    fi
    if [ $ENV_CEPH = 1 ]; then ENV_ROLE=1
    elif [ -n "$ENV_PVE" ]; then ENV_ROLE=3
    else ENV_ROLE=4; fi
}

ceph_health_short() {
    [ "${ENV_CEPH:-0}" = 1 ] || { echo "${D}khong co tren may nay${N}"; return; }
    local h; h=$(timeout 8 ceph health 2>/dev/null | awk '{print $1}')
    case "$h" in
        HEALTH_OK)   echo "${G}${W}HEALTH_OK${N}" ;;
        HEALTH_WARN) echo "${Y}${W}HEALTH_WARN${N}" ;;
        HEALTH_ERR)  echo "${R}${W}HEALTH_ERR${N}" ;;
        *)           echo "${R}khong doc duoc${N}" ;;
    esac
}

# =============================================================================
# 1. Kiem tra moi truong
# =============================================================================
do_check() {
    title "KIEM TRA MOI TRUONG"
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
            err "Khong chay duoc 'ceph status' (thieu /etc/ceph/ceph.client.admin.keyring hoac khong ket noi duoc mon)"; bad=1
        fi
    else
        err "May nay khong co lenh ceph → cai exporter tren 1 node Ceph cua cluster"; bad=1
    fi

    if [ -f /etc/pve/ha/groups.cfg ] || [ -f /etc/pve/ha/rules.cfg ]; then
        ok "Co cau hinh HA: $(ls /etc/pve/ha/groups.cfg /etc/pve/ha/rules.cfg 2>/dev/null | xargs)"
    else
        info "Chua co HA group/rule → cot HA Groups se trong (binh thuong)"
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
        warn "PVE firewall dang bat → mo port $port cho IP Prometheus:"
        echo "Datacenter/Node → Firewall → Add: IN ACCEPT tcp dport $port source <IP Prometheus>" | sub
    fi

    if [ -z "$(current_flags)" ]; then
        if has ceph && timeout 10 ceph mgr services -f json 2>/dev/null | grep -q '"prometheus"'; then
            ok "ceph mgr module prometheus dang bat"
        elif has ceph; then
            err "Chua bat module prometheus cua ceph mgr (can cho che do gop 1 port):"
            echo "ceph mgr module enable prometheus" | sub; bad=1
        fi
        if has pvesh; then ok "pvesh co san (metric Proxmox)"; else err "Thieu pvesh - may nay khong phai node Proxmox"; bad=1; fi
    fi

    has curl || warn "Thieu curl (apt install curl) - can cho xem metric / import Grafana"

    if [ "$bad" = 0 ]; then ok "${G}${W}Moi truong san sang${N}"; else err "${R}${W}Can xu ly cac loi tren truoc khi cai${N}"; fi
    return $bad
}

# =============================================================================
# 2. Cai / cap nhat exporter
# =============================================================================
do_install() {
    title "CAI / CAP NHAT EXPORTER"
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
        info "Ban dang cai: ${old:-?}  →  ban moi: ${new:-?}"
    fi

    local flags="${2-$(current_flags)}"
    info "Che do: ${W}$(mode_text "$flags")${N}"
    if PORT="$port" ARGS="$flags" bash "$INSTALLER" 2>&1 | sub; then
        ok "Da cai service ${W}$SERVICE${N} port ${W}$port${N}"
        info "Buoc tiep theo: them target $(local_ip):$port vao Prometheus (menu 10)"
    else
        err "Cai exporter loi"; return 1
    fi
}

# =============================================================================
# 3. Trang thai
# =============================================================================
do_status() {
    title "TRANG THAI EXPORTER"
    if [ ! -f "$UNIT" ]; then
        warn "Chua cai exporter tren may nay (menu 2 hoac S)"; return 1
    fi
    local st port; st=$(svc_state); port=$(current_port)
    if [ "$st" = active ]; then ok "Service $SERVICE: ${G}${W}$st${N}"; else err "Service $SERVICE: ${R}$st${N}"; fi
    info "Port: ${W}$port${N}   ·   Ban: $(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$BIN" 2>/dev/null)"
    info "Tu khoi dong: $(systemctl is-enabled "$SERVICE" 2>/dev/null)"
    systemctl show "$SERVICE" -p ActiveEnterTimestamp -p NRestarts -p MemoryCurrent 2>/dev/null | sub

    if has curl; then
        local m line; m=$(curl -sf --max-time 20 "http://127.0.0.1:$port/metrics") || { err "Khong goi duoc /metrics"; return 1; }
        echo
        while read -r l; do
            [ -n "$l" ] || continue
            if [[ "$l" == *" 1" ]]; then ok "$l"; else err "$l"; fi
        done <<< "$(echo "$m" | grep '^pve_ceph_extra_exporter_up')"
        line=$(echo "$m" | grep '^ceph_custom_recovery_info')
        [ -n "$line" ] && info "Ceph: ${W}$(echo "$line" | sed 's/.*content="\([^"]*\)".*/\1/')${N}"
        info "Total Health: ${W}$(echo "$m" | awk '/^ceph_custom_recovery_percent /{print $2}') %${N}"
        info "HA groups: $(echo "$m" | grep -c '^pve_ha_groups_custom_info') node"
        info "Thoi gian thu thap moi chu ky (s):"
        echo "$m" | sed -n 's/^pve_ceph_extra_exporter_collect_seconds{collector="\([^"]*\)"} \(.*\)/\1 \2/p' \
            | awk '{printf "%-10s %6.2f s\n", $1, $2}' | sub
        local pid; pid=$(systemctl show -p MainPID --value "$SERVICE" 2>/dev/null)
        if [ -n "$pid" ] && [ "$pid" != 0 ]; then
            info "Tai nguyen: $(ps -o %cpu=,rss= -p "$pid" | awk '{printf "CPU %s%%  RAM %.0f MB", $1, $2/1024}')  (gioi han CPU 25%, RAM 256M)"
        fi
    fi
}

# =============================================================================
# 4. Xem metric
# =============================================================================
do_metrics() {
    title "METRIC HIEN TAI"
    local port; port=$(current_port)
    if [ "$(svc_state)" = active ] && has curl; then
        curl -sf --max-time 20 "http://127.0.0.1:$port/metrics" | grep -v '^#' | sub
    elif has python3 && [ -f "$EXPORTER_SRC" ]; then
        info "Service chua chay → chay thu 1 lan tu file nguon:"
        python3 "$EXPORTER_SRC" --once | grep -v '^#' | sub
    else
        err "Khong lay duoc metric"
    fi
}

# =============================================================================
# 5. Log / 6. Restart / 7. Doi port / 8. Go cai
# =============================================================================
do_logs() {
    title "LOG 50 DONG GAN NHAT"
    journalctl -u "$SERVICE" -n 50 --no-pager 2>/dev/null | sub || err "Khong doc duoc journal"
}

do_restart() {
    title "KHOI DONG LAI EXPORTER"
    need_root || return 1
    systemctl restart "$SERVICE" && sleep 2
    if [ "$(svc_state)" = active ]; then ok "Da khoi dong lai"; else err "Khoi dong lai loi"; do_logs; fi
}

do_port() {
    title "DOI PORT EXPORTER"
    need_root || return 1
    local p="${1:-}"
    [ -n "$p" ] || p=$(ask "Port moi" "$(current_port)")
    do_install "$p" && warn "Nho sua target trong prometheus.yml sang port $p"
}

do_uninstall() {
    title "GO EXPORTER"
    need_root || return 1
    if [ "${NONINTERACTIVE:-0}" = 1 ] || confirm "Go service $SERVICE khoi may nay?"; then
        bash "$INSTALLER" uninstall 2>&1 | sub
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
        info "Khong doc duoc HA groups tren may nay → giu ten ngan da luu (neu co)"
        return 0
    fi
    info "Nhap ten ngan, them :mau neu muon (vd ${W}Gold+HIGH:orange${N}). Enter trong = giu ten goc."
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
    ok "Da tao ${W}$DASH_JSON${N}"
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
        ok "Import thanh cong: ${W}$url$(echo "$resp" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')${N}"
        save_conf GRAFANA_URL "$url"; save_conf GRAFANA_FOLDER "$folder"
    else
        err "Import loi: $resp"; return 1
    fi
}

prom_snippet() {  # prom_snippet JOB PORT [FLAGS] -> in + luu file mau prometheus.yml
    local job="$1" port="$2" flags="${3-$(current_flags)}" ip f
    ip=$(local_ip); f="$DIR/prometheus-target-$job.yml"
    if [ -z "$flags" ]; then
        cat > "$f" <<EOF
# Gop 1 port: job nay CHI CON 1 target (ceph mgr + Proxmox + bo sung deu o :$port)
  - job_name: $job
    scrape_interval: 30s
    scrape_timeout: 25s
    static_configs:
      - targets:
          - $ip:$port   # pve_ceph_extra_exporter (tat ca metric)
EOF
        info "Job ${W}'$job'${N} chi can ${W}1 target $ip:$port${N}:"
        echo; sed -n '2,$p' "$f" | sed "s/^/${IND}    ${O}/; s/$/${N}/"; echo
        warn "XOA target ceph mgr (:9283) va pve exporter (:9221) cu cua cluster nay khoi job,"
        echo "neu khong moi so lieu se bi nhan doi (menu 12 se bao trung)." | sub
        info "Da luu mau: $f"
        info "Tren may Prometheus:"
        printf '%s\n' "promtool check config /etc/prometheus/prometheus.yml" \
            "systemctl reload prometheus      # hoac: curl -X POST http://<prom>:9090/-/reload" | sub
        return 0
    fi
    cat > "$f" <<EOF
# Them vao scrape_configs cua prometheus.yml (CUNG job voi ceph mgr / pve exporter)
  - job_name: $job
    static_configs:
      - targets:
          - $ip:9283   # ceph mgr prometheus (da co)
          - $ip:$port   # pve_ceph_extra_exporter (moi)
EOF
    info "Them target ${W}$ip:$port${N} vao ${W}CUNG job '$job'${N} voi ceph mgr / pve exporter:"
    echo; sed -n '2,$p' "$f" | sed "s/^/${IND}    ${O}/; s/$/${N}/"; echo
    info "Da luu mau: $f"
    info "Neu job da ton tai thi chi them dong '$ip:$port' vao danh sach targets."
    info "Tren may Prometheus:"
    printf '%s\n' "promtool check config /etc/prometheus/prometheus.yml" \
        "systemctl reload prometheus      # hoac: curl -X POST http://<prom>:9090/-/reload" | sub
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

    local ports; ports=$(all_ports); [ -n "$ports" ] || ports=$port
    echo; info "Target exporter (up{instance=~\".*:($ports)\"}):"
    out=$(prom_q "$url" "up{instance=~\".*:($ports)\"}")
    if [ -z "$out" ]; then
        err "Prometheus chua scrape exporter → them target (menu 10) roi reload Prometheus"; rc=1
    else
        while read -r l; do
            if [[ "$l" == *" 1" ]]; then ok "$l"; else err "$l (target down)"; rc=1; fi
        done <<< "$out"
    fi

    echo; info "Cac job cluster (pve_cluster_info):"
    prom_q "$url" 'count by (job) (pve_cluster_info)' | sub

    echo; info "Kiem tra trung target (1 cluster bi scrape 2 lan -> so lieu nhan doi):"
    out=$(prom_q "$url" 'count by (job) (count by (job, instance) (ceph_health_status)) > 1')
    if [ -n "$out" ]; then
        while read -r l; do err "Trung ceph: $l target → xoa target ceph mgr cu (:9283)"; done <<< "$out"; rc=1
    else ok "Khong co job nao bi trung metric ceph"; fi
    out=$(prom_q "$url" 'count by (job) (count by (job, instance) (pve_cluster_info)) > 1')
    if [ -n "$out" ]; then
        while read -r l; do err "Trung Proxmox: $l target → xoa target pve exporter cu (:9221)"; done <<< "$out"; rc=1
    else ok "Khong co job nao bi trung metric Proxmox"; fi

    echo; info "So sanh job: ceph mgr ↔ exporter:"
    cj=$(prom_q "$url" 'count by (job) (ceph_health_status)' | sed 's/{job=\(.*\)} .*/\1/')
    ej=$(prom_q "$url" 'count by (job) (ceph_custom_recovery_info)' | sed 's/{job=\(.*\)} .*/\1/')
    printf '%s\n' "ceph mgr : $(echo ${cj:-'<khong co>'})" "exporter : $(echo ${ej:-'<khong co>'})" | sub
    for j in $ej; do
        if echo "$cj" | grep -qx "$j"; then ok "job '$j' khop"
        else err "job '$j' cua exporter khong co ceph mgr → dashboard se khong hien Recovery"; rc=1; fi
    done

    echo; info "Trang thai recovery tung cluster:"
    prom_q "$url" 'ceph_custom_recovery_info' | sub
    echo; info "OSD device class:"
    prom_q "$url" 'count by (job, device_class) (ceph_osd_metadata)' | sub
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
        info "Doc tu Ceph: ${W}$DN${N} node, ${W}$DP${N} pool, ${W}$DC${N} device class"
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
    title "SINH DASHBOARD GRAFANA"
    ask_dashboard
    DASH_JSON=$(ask "File xuat" "$DASH_JSON")
    gen_dashboard || return 1
    save_dash_conf
    info "Import: Grafana → Dashboards → New → Import → Upload JSON, hoac dung menu 11"
}

# =============================================================================
# 11. Import dashboard qua Grafana API
# =============================================================================
ask_token() {
    info "Tao token: Grafana → Administration → Service accounts → Add token (role Editor)"
    read -rsp "${IND}  ${C}❯${N} Service account token ${D}(khong hien khi go)${N}: " TOKEN; echo
}

do_import() {
    title "IMPORT DASHBOARD LEN GRAFANA"
    [ -f "$DASH_JSON" ] || { warn "Chua co $DASH_JSON → sinh truoc"; do_dashboard || return 1; }
    local url folder
    url=$(ask "Grafana URL" "${GRAFANA_URL:-${ENV_GRAFANA:-http://127.0.0.1:3000}}")
    ask_token
    [ -n "$TOKEN" ] || { err "Chua nhap token"; return 1; }
    folder=$(ask "Folder UID (bo trong = General)" "${GRAFANA_FOLDER:-}")
    import_dashboard "$url" "$TOKEN" "$folder"
}

# =============================================================================
# 10. Cau hinh Prometheus
# =============================================================================
do_prom() {
    title "CAU HINH PROMETHEUS"
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
    title "KIEM TRA DU LIEU TREN PROMETHEUS"
    prom_check "$(ask "Prometheus URL" "${PROM_URL:-${ENV_PROM:-http://127.0.0.1:9090}}")"
}

# =============================================================================
# 13. Kiem tra tong the
# =============================================================================
do_doctor() {
    do_check
    if [ -f "$UNIT" ]; then do_status; else warn "Exporter chua cai tren may nay"; fi
    if [ -n "${PROM_URL:-}" ] && [ "${NONINTERACTIVE:-0}" = 0 ]; then
        confirm "Kiem tra them Prometheus $PROM_URL?" && prom_check "$PROM_URL"
    fi
}

# =============================================================================
# 17-20. Theo doi tu xa: exporter chay tren may monitor, lay du lieu qua API
#        Proxmox (token chi doc) + ceph mgr :9283. 1 cluster = 1 service @<ten>.
# =============================================================================
remote_names() { ls "$REMOTE_DIR"/*.env 2>/dev/null | sed 's|.*/||; s|\.env$||'; }
env_get() { sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -1; }   # env_get FILE KEY

all_ports() {  # moi port exporter tren may nay (local + remote), cach nhau dau |
    { [ -f "$UNIT" ] && current_port
      for n in $(remote_names); do env_get "$REMOTE_DIR/$n.env" PORT; done; } | sort -un | paste -sd'|'
}

next_free_port() {
    local p=$DEFAULT_PORT used
    used="|$(all_ports)|"
    while [[ "$used" == *"|$p|"* ]] || { has ss && ss -ltn 2>/dev/null | grep -q ":$p "; }; do p=$((p + 1)); done
    echo "$p"
}

remote_install_files() {  # cai / cap nhat exporter + unit mau (khong dong cham service dang chay)
    install -m 0755 "$EXPORTER_SRC" "$BIN" || return 1
    install -m 0644 "$DIR/exporter/pve-ceph-extra-exporter@.service" "$RUNIT" || return 1
    install -d -m 0700 "$REMOTE_DIR"
    systemctl daemon-reload
}

remote_test() {  # remote_test ENVFILE -> chay thu 1 lan, in ket qua tung phan; 0 neu pve + ceph OK
    local out rc=0 name v
    out=$(set -a; . "$1"; set +a; REMOTE=1 INTERVAL=30 timeout 90 python3 "$EXPORTER_SRC" --remote --once --timeout 8 2>&1)
    REMOTE_TEST_OUT=$out
    for name in pve ceph ceph_mgr ha; do
        v=$(echo "$out" | sed -n "s/^pve_ceph_extra_exporter_up{collector=\"$name\"} //p")
        local e; e=$(echo "$out" | sed -n "s/^pve_ceph_extra_exporter_last_error{collector=\"$name\",error=\"\(.*\)\"} 1/\1/p")
        case "$name" in
            pve) label="API Proxmox (node, CPU, RAM, HA)" ;; ceph) label="Ceph status (recovery)" ;;
            ceph_mgr) label="Ceph mgr :9283 (OSD, pool, latency)" ;; ha) label="HA groups / rules" ;;
        esac
        if [ "$v" = 1 ]; then ok "$label"
        else err "$label: ${e:-khong co du lieu}"; [ "$name" = pve ] || [ "$name" = ceph ] && rc=1; fi
    done
    local cl; cl=$(echo "$out" | sed -n 's/^pve_cluster_info{id="cluster\/\([^"]*\)".*nodes="\([^"]*\)".*/\1 (\2 node)/p')
    [ -n "$cl" ] && info "Cluster doc duoc: ${W}$cl${N}"
    echo "$out" | grep -q 'HTTP Error 401' && \
        warn "401 = sai token / secret. Kiem tra lai Token ID va secret (menu 17 → nhap lai secret)"
    echo "$out" | grep -q 'HTTP Error 403\|Permission' && \
        warn "403 = token thieu quyen → pveum acl modify / --users monitor@pve --roles PVEAuditor (va --privsep 0)"
    echo "$out" | grep -q 'CERTIFICATE_VERIFY_FAILED' && \
        warn "Cert Proxmox tu ky / CA chua tin cay (PVE_VERIFY_TLS=$(env_get "$1" PVE_VERIFY_TLS)) → Enter (N) o cau 'Proxmox da co cert hop le'"
    echo "$out" | grep -q 'standby' && \
        warn "Mgr da thu deu la standby (chi mgr active tra metric) → nhap TAT CA node o cau IP de tool tu thu tung node; xem mgr active: 'ceph mgr stat'"
    echo "$out" | grep -qi 'refused' && \
        warn "Connection refused = toi duoc may nhung port dong. :9283 → tren cluster chay 'ceph mgr module enable prometheus', xem dia chi bang 'ceph mgr services'; :8006 → pveproxy"
    echo "$out" | grep -qi 'timed out\|unreachable\|No route' && \
        warn "Khong ket noi duoc → kiem tra may nay toi node:8006 va mgr:9283 (firewall)"
    return $rc
}

token_help() {
    box_top
    box_center "${W}${Y}TAO API TOKEN CHI DOC (chay 1 lan tren 1 node bat ky cua cluster)${N}"
    box_sep
    box_row "${O}pveum user add monitor@pve --comment \"FIX NHANH monitor\"${N}"
    box_row "${O}pveum acl modify / --users monitor@pve --roles PVEAuditor${N}"
    box_row "${O}pveum user token add monitor@pve exporter --privsep 0${N}"
    box_sep
    box_row "${D}PVEAuditor chi XEM duoc, khong sua VM / cau hinh / Ceph.${N}"
    box_row "${D}Lenh cuoi in 'value' = secret (chi hien 1 lan) → dung o buoc duoi.${N}"
    box_row "${D}Ceph mgr: ceph mgr module enable prometheus (mo :9283 tren cac mgr).${N}"
    box_bottom
}

do_remote_add() {  # do_remote_add [TEN] -> them / sua 1 cluster
    title "THEM / SUA CLUSTER (THEO DOI TU XA)"
    need_root || return 1
    has python3 || { err "Thieu python3 (apt install python3)"; return 1; }
    token_help; echo
    local name="${1:-}" f hosts tid secret verify mgr job port tmp
    [ -n "$name" ] || name=$(ask "Ten cluster (khong dau, khong cach, vd FPT-HCM)" "")
    [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || { err "Ten khong hop le: '$name'"; return 1; }
    f="$REMOTE_DIR/$name.env"
    [ -f "$f" ] && info "Cluster ${W}$name${N} da co → gia tri cu hien san, Enter de giu"

    hosts=$(ask "IP / ten cac node Proxmox, cach nhau dau phay (nhieu node = tu chuyen khi 1 node chet)" "$(env_get "$f" PVE_API)")
    hosts=${hosts// /}  # "a, b" -> "a,b": file .env bi source, dau cach lam hong dong
    local other h oh
    for other in $(remote_names); do  # cung node da theo doi o cluster khac -> du lieu trung 2 job
        [ "$other" = "$name" ] && continue
        for h in ${hosts//,/ }; do
            for oh in $(env_get "$REMOTE_DIR/$other.env" PVE_API | tr ',' ' '); do
                [ "${h#*://}" = "${oh#*://}" ] || continue
                warn "Node ${W}$h${N} da co trong cluster ${W}$other${N} (port $(env_get "$REMOTE_DIR/$other.env" PORT)) → Prometheus se co 2 job trung du lieu"
                info "Sua cluster do: menu 17 nhap ten ${W}$other${N}; hoac xoa: menu 20"
                confirm "Van tiep tuc them ${W}$name${N}?" || return 1
                break 3
            done
        done
    done
    [ -n "$hosts" ] || { err "Can it nhat 1 node"; return 1; }
    local oldtok; oldtok=$(env_get "$f" PVE_TOKEN)
    local deftid="monitor@pve!exporter"; [ -n "$oldtok" ] && deftid=${oldtok%%=*}
    tid=$(ask "Token ID" "$deftid")
    [[ "$tid" == root@pam!* ]] && warn "Token cua root@pam: tao tren web mac dinh bat Privilege Separation → khong co quyen (403). Nen dung monitor@pve!exporter + PVEAuditor (hop tren)"
    read -rsp "${IND}  ${C}❯${N} Token secret ${D}(khong hien; Enter = giu secret cu)${N}: " secret; echo
    [ -n "$secret" ] || { [ -n "$oldtok" ] && secret=${oldtok#*=}; }
    [ -n "$secret" ] || { err "Chua nhap token secret"; return 1; }
    verify=$(ask "Proxmox da co cert hop le (Let's Encrypt / CA noi bo)? (y/N - cert mac dinh cua Proxmox: Enter)" \
        "$([ "$(env_get "$f" PVE_VERIFY_TLS)" = 1 ] && echo y || echo N)")
    # CEPH_MGR trong = exporter tu thu moi node cua cluster de tim mgr active.
    # File cu ghi san "cac node PVE_API:9283" -> coi nhu trong de duoc tu do.
    local oldmgr; oldmgr=$(env_get "$f" CEPH_MGR)
    mgrdef() { echo "$1" | tr ',' '\n' | sed 's|^ *https\?://||; s|:.*||; s|$|:9283|' | paste -sd,; }
    [ "$oldmgr" = "$(mgrdef "$hosts")" ] || [ "$oldmgr" = "$(mgrdef "$(env_get "$f" PVE_API)")" ] && oldmgr=""
    mgr=$(ask "Ceph mgr host:9283, cach nhau dau phay (Enter = tu tim mgr active tren moi node)" "$oldmgr")
    mgr=${mgr// /}
    job=$(ask "Ten job Prometheus (phai chua 'Proxmox-' de dashboard thay)" "$(env_get "$f" JOB)")
    job=${job:-Proxmox-$name}
    port=$(ask "Port exporter tren may nay" "$(env_get "$f" PORT)")
    port=${port:-$(next_free_port)}
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || { err "Port khong hop le: $port"; return 1; }
    case "$port" in 9283|9221)
        warn "Port $port trung port mac dinh cua $([ "$port" = 9283 ] && echo "ceph mgr" || echo "pve exporter") → de nham target trong prometheus.yml (goi y: $(next_free_port))" ;;
    esac

    install -d -m 0700 "$REMOTE_DIR"
    tmp=$(mktemp "$REMOTE_DIR/.new.XXXX")
    cat > "$tmp" <<EOF
# FIX NHANH - cluster $name (sinh boi menu.sh $(date '+%F %T'))
JOB=$job
PORT=$port
PVE_API=$hosts
PVE_TOKEN=$tid=$secret
PVE_VERIFY_TLS=$([[ "$verify" =~ ^[YyCc] ]] && echo 1 || echo 0)
CEPH_MGR=$mgr
INTERVAL=30
EOF
    chmod 600 "$tmp"

    echo; info "Chay thu ket noi toi cluster ${W}$name${N}..."
    while ! remote_test "$tmp"; do
        if [ "$(env_get "$tmp" PVE_VERIFY_TLS)" = 1 ] && [[ "$REMOTE_TEST_OUT" == *CERTIFICATE_VERIFY_FAILED* ]] \
            && confirm "Tat kiem tra TLS (PVE_VERIFY_TLS=0) roi chay thu lai?"; then
            sed -i 's/^PVE_VERIFY_TLS=1$/PVE_VERIFY_TLS=0/' "$tmp"
            echo; info "Chay thu lai voi PVE_VERIFY_TLS=0..."
            continue
        fi
        confirm "Ket noi chua dat. Van luu va chay service?" || { rm -f "$tmp"; info "Huy - chua luu gi"; return 1; }
        break
    done
    mv -f "$tmp" "$f"
    remote_install_files || { err "Cai file loi"; return 1; }
    systemctl enable "$SERVICE@$name" >/dev/null 2>&1
    systemctl restart "$SERVICE@$name"
    sleep 3
    if curl -sf --max-time 60 "http://127.0.0.1:$port/metrics" | grep -q '^pve_ceph_extra_exporter_up'; then
        ok "Service ${W}$SERVICE@$name${N} chay tai ${W}http://$(local_ip):$port/metrics${N}"
    else
        err "Service chua tra metric → journalctl -u $SERVICE@$name -n 30"; return 1
    fi
    echo; prom_snippet "$job" "$port" ""
}

do_remote_list() {
    title "CAC CLUSTER THEO DOI TU XA"
    local names; names=$(remote_names)
    if [ -z "$names" ]; then info "Chua co cluster nao (menu 17 de them)"; return 0; fi
    printf '%s  %s%-16s %-6s %-10s %-22s %-6s %-5s %-5s %s%s\n' "$IND" "$W" "CLUSTER" "PORT" "SERVICE" \
        "JOB" "PVE" "CEPH" "MGR" "HA" "$N"
    local n f p st m c
    for n in $names; do
        f="$REMOTE_DIR/$n.env"; p=$(env_get "$f" PORT)
        st=$(systemctl is-active "$SERVICE@$n" 2>/dev/null)
        [ "$st" != active ] && has docker && [ "$(container_state "$n")" = running ] && st=docker
        m=$(curl -sf --max-time 10 "http://127.0.0.1:$p/metrics" 2>/dev/null)
        c() { local v; v=$(echo "$m" | sed -n "s/^pve_ceph_extra_exporter_up{collector=\"$1\"} //p")
              if [ "$v" = 1 ]; then printf '%s✔%s' "$G" "$N"; elif [ -z "$v" ]; then printf '%s-%s' "$D" "$N"; else printf '%s✘%s' "$R" "$N"; fi; }
        printf '%s  %-16s %-6s %s%-10s%s %-22s %s     %s     %s     %s\n' "$IND" "$n" "$p" \
            "$([ "$st" = active ] || [ "$st" = docker ] && echo "$G" || echo "$R")" "$st" "$N" "$(env_get "$f" JOB)" \
            "$(c pve)" "$(c ceph)" "$(c ceph_mgr)" "$(c ha)"
    done
    echo
    info "Chi tiet loi: curl -s http://127.0.0.1:<port>/metrics | grep last_error"
    info "Log: journalctl -u $SERVICE@<cluster> -n 30"
}

pick_remote() {  # chon 1 cluster -> in ten
    local names; names=$(remote_names)
    [ -n "$names" ] || { err "Chua co cluster nao"; return 1; }
    info "Cluster dang co: ${W}$(echo $names)${N}" >&2
    ask "Ten cluster" "$(echo "$names" | head -1)"
}

do_remote_test() {
    title "KIEM TRA KET NOI CLUSTER"
    local n; n=$(pick_remote) || return 1
    [ -f "$REMOTE_DIR/$n.env" ] || { err "Khong co cluster '$n'"; return 1; }
    remote_test "$REMOTE_DIR/$n.env"
}

do_remote_remove() {
    title "XOA CLUSTER THEO DOI TU XA"
    need_root || return 1
    local n; n=$(pick_remote) || return 1
    [ -f "$REMOTE_DIR/$n.env" ] || { err "Khong co cluster '$n'"; return 1; }
    confirm "Dung service va xoa cau hinh cluster '$n' (token cung bi xoa)?" || { info "Huy"; return 0; }
    systemctl disable --now "$SERVICE@$n" >/dev/null 2>&1
    has docker && docker rm -f "$(container_of "$n")" >/dev/null 2>&1
    rm -f "$REMOTE_DIR/$n.env"
    ok "Da xoa $n - nho bo target cua no khoi prometheus.yml"
}

# =============================================================================
# 21. Cai goi can thiet  22. Mo firewall  23. Chay bang Docker  24. Quan ly container
# =============================================================================
pkg_manager() {
    local m
    for m in apt-get dnf yum zypper pacman apk; do has "$m" && { echo "$m"; return; }; done
}

do_deps() {
    title "CAI GOI CAN THIET"
    need_root || return 1
    local pm pk missing="" c
    pm=$(pkg_manager)
    [ -n "$pm" ] || { err "Khong nhan ra trinh quan ly goi (apt/dnf/yum/zypper/pacman/apk)"; return 1; }
    info "He dieu hanh: ${W}${ENV_OS:-?}${N} · trinh quan ly goi: ${W}$pm${N}"
    for c in git python3 curl ss; do
        if has "$c"; then ok "$c"; else warn "Thieu $c"; missing+=" $c"; fi
    done
    [ -n "$missing" ] || { ok "Da du goi, khong can cai them"; return 0; }
    case "$pm" in
        apt-get) pk="git python3 curl iproute2" ;;
        dnf|yum) pk="git python3 curl iproute" ;;
        zypper)  pk="git python3 curl iproute2" ;;
        pacman)  pk="git python curl iproute2" ;;
        apk)     pk="bash git python3 curl iproute2" ;;
    esac
    confirm "Cai bang $pm: $pk ?" || { info "Huy"; return 0; }
    case "$pm" in
        apt-get) { apt-get update -qq || warn "apt update co loi (repo enterprise?), van thu cai"; }
                 DEBIAN_FRONTEND=noninteractive apt-get install -y $pk ;;
        dnf|yum) $pm install -y $pk ;;
        zypper)  zypper -n install $pk ;;
        pacman)  pacman -Sy --noconfirm --needed $pk ;;
        apk)     apk add $pk ;;
    esac 2>&1 | tail -5 | sub
    for c in git python3 curl; do has "$c" && ok "$c" || err "Van thieu $c"; done
}

do_firewall() {
    title "MO FIREWALL CHO PROMETHEUS"
    need_root || return 1
    local ports src p fw=""
    ports=$(all_ports | tr '|' ' ')
    [ -n "$ports" ] || ports=$(current_port)
    info "Port exporter tren may nay: ${W}$ports${N}"
    src=$(ask "IP may Prometheus duoc phep truy cap (vd 10.16.16.38)" "${PROM_IP:-}")
    [[ "$src" =~ ^[0-9a-fA-F.:/]+$ ]] || { err "IP khong hop le: $src"; return 1; }
    save_conf PROM_IP "$src"

    if has ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
        fw=ufw
        for p in $ports; do ufw allow from "$src" to any port "$p" proto tcp | sub; done
    fi
    if has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
        fw="$fw firewalld"
        for p in $ports; do
            firewall-cmd -q --permanent --add-rich-rule="rule family=ipv4 source address=$src port port=$p protocol=tcp accept"
        done
        firewall-cmd -q --reload && ok "firewalld: da mo $ports cho $src"
    fi
    if has pve-firewall && pve-firewall status 2>/dev/null | grep -q "enabled/running"; then
        fw="$fw pve-firewall"
        for p in $ports; do
            pvesh create /cluster/firewall/rules --action ACCEPT --type in --proto tcp --dport "$p" \
                --source "$src" --enable 1 --comment "FIX NHANH exporter" >/dev/null 2>&1 \
                && ok "pve-firewall: mo $p cho $src" || err "pve-firewall: khong them duoc rule port $p"
        done
    fi
    if [ -z "$fw" ]; then
        info "Khong co ufw / firewalld / pve-firewall dang bat → khong can mo gi them"
    else
        ok "Da xu ly firewall:${W}$fw${N}"
    fi
    info "Neu giua 2 may con firewall mang (pfSense, FortiGate...) thi mo tcp $ports tu $src"
}

DOCKER_IMAGE=fixnhanh/pve-ceph-exporter
docker_ok() {
    has docker || { err "Chua cai Docker → curl -fsSL https://get.docker.com | sh"; return 1; }
    docker info >/dev/null 2>&1 || { err "Docker chua chay → systemctl enable --now docker"; return 1; }
}
container_of() { echo "fixnhanh-pve-$1"; }
container_state() { docker inspect -f '{{.State.Status}}' "$(container_of "$1")" 2>/dev/null; }

do_docker_run() {
    title "CHAY CLUSTER BANG DOCKER"
    need_root || return 1
    docker_ok || return 1
    local names sel list n f p ver c
    names=$(remote_names)
    [ -n "$names" ] || { err "Chua co cluster nao → them o menu 17 truoc (Docker dung lai file cau hinh do)"; return 1; }
    info "Cluster dang co: ${W}$(echo $names)${N}"
    sel=$(ask "Chay cluster nao bang Docker (ten, cach nhau dau cach, hoac all)" "all")
    if [ "$sel" = all ]; then list=$names; else list=$sel; fi

    ver=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$EXPORTER_SRC")
    info "Build image ${W}$DOCKER_IMAGE:$ver${N}..."
    docker build -q -t "$DOCKER_IMAGE:$ver" -t "$DOCKER_IMAGE:latest" "$DIR/exporter" 2>&1 | sub \
        || { err "Build image loi"; return 1; }

    for n in $list; do
        f="$REMOTE_DIR/$n.env"
        [ -f "$f" ] || { err "Khong co cluster '$n'"; continue; }
        p=$(env_get "$f" PORT); c=$(container_of "$n")
        if [ "$(systemctl is-active "$SERVICE@$n" 2>/dev/null)" = active ]; then
            info "$n: dung service systemd de chuyen sang Docker (cung port $p)"
            systemctl disable --now "$SERVICE@$n" >/dev/null 2>&1
        fi
        docker rm -f "$c" >/dev/null 2>&1
        if docker run -d --name "$c" --restart unless-stopped -p "$p:$p" --env-file "$f" \
                --memory 256m --cpus 0.25 --read-only --cap-drop ALL \
                --security-opt no-new-privileges "$DOCKER_IMAGE:$ver" >/dev/null; then
            sleep 5
            if curl -sf --max-time 60 "http://127.0.0.1:$p/metrics" | grep -q '^pve_ceph_extra_exporter_up'; then
                ok "$n: container ${W}$c${N} chay tai ${W}http://$(local_ip):$p/metrics${N}"
            else
                err "$n: container chua tra metric → docker logs $c"
            fi
        else
            err "$n: docker run loi"
        fi
    done
    info "Target Prometheus khong doi: $(local_ip):<port> nhu khi chay systemd"
}

do_docker_manage() {
    title "QUAN LY CONTAINER"
    docker_ok || return 1
    local out a n c
    out=$(docker ps -a --filter name=fixnhanh-pve- --format '{{.Names}}|{{.Status}}|{{.Ports}}')
    if [ -z "$out" ]; then info "Chua co container nao (menu 23 de tao)"; return 0; fi
    printf '%s  %s%-28s %-28s %s%s\n' "$IND" "$W" "CONTAINER" "TRANG THAI" "PORT" "$N"
    while IFS='|' read -r c st pt; do
        printf '%s  %-28s %s%-28s%s %s\n' "$IND" "$c" "$([[ "$st" == Up* ]] && echo "$G" || echo "$R")" \
            "$(echo "$st" | cut -c1-28)" "$N" "$(echo "$pt" | sed 's/0.0.0.0://; s/, .*//' | cut -c1-20)"
    done <<< "$out"
    echo
    a=$(ask "Thao tac: l=log  r=khoi dong lai  x=xoa (quay ve systemd)  Enter=thoat" "")
    [ -n "$a" ] || return 0
    n=$(pick_remote) || return 1; c=$(container_of "$n")
    case "$a" in
        l|L) docker logs --tail 40 "$c" 2>&1 | sub ;;
        r|R) docker restart "$c" >/dev/null && ok "Da khoi dong lai $c" ;;
        x|X) need_root || return 1
             confirm "Xoa container $c va chay lai bang systemd?" || return 0
             docker rm -f "$c" >/dev/null && ok "Da xoa $c"
             remote_install_files && systemctl enable --now "$SERVICE@$n" >/dev/null 2>&1 \
                 && ok "Da chay lai $n bang systemd" ;;
        *) warn "Thao tac khong hop le: $a" ;;
    esac
}

remote_refresh_after_update() {  # sau cap nhat: chay lai cac service remote bang ban exporter moi
    local names; names=$(remote_names)
    [ -n "$names" ] || return 0
    if [ "$(id -u)" != 0 ]; then warn "Can root de cap nhat ${W}$(echo $names)${N} → chay lai menu 14 bang root"; return 0; fi
    local n sd="" dk=""
    remote_install_files || return 1
    for n in $names; do
        if has docker && [ "$(container_state "$n")" = running ]; then dk+=" $n"
        else systemctl restart "$SERVICE@$n"; sd+=" $n"; fi
    done
    [ -n "$sd" ] && ok "Da chay lai exporter remote (systemd):${W}$sd${N}"
    [ -n "$dk" ] && info "Cluster chay Docker:${W}$dk${N} → menu 23 de build lai image ban moi"
    return 0
}

# =============================================================================
# 14. Cap nhat tool / 15. Cau hinh da luu / 16. Gioi thieu & ban quyen
# =============================================================================
do_update() {
    title "CAP NHAT TOOL"
    if [ ! -d "$DIR/.git" ]; then
        if has git; then
            info "Thu muc tai bang curl → chuyen thanh ban git clone (giu .menu.conf)"
            git -C "$DIR" init -q && git -C "$DIR" remote add origin "$REPO_URL.git" 2>/dev/null
            git -C "$DIR" fetch -q origin main && git -C "$DIR" reset -q --hard origin/main \
                && git -C "$DIR" checkout -q -B main --track origin/main 2>/dev/null \
                || { err "Chuyen sang git loi"; return 1; }
            ok "Da chuyen sang git, ban $(git -C "$DIR" rev-parse --short HEAD)"
            remote_refresh_after_update
            [ "${NONINTERACTIVE:-0}" = 0 ] && { info "Mo lai menu voi ban moi..."; sleep 1; exec bash "$DIR/menu.sh"; }
            return 0
        fi
        has curl || { err "Can git hoac curl de cap nhat"; return 1; }
        info "Khong co git → tai ban moi bang curl"
        curl -sfL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar xz --strip-components=1 -C "$DIR" \
            || { err "Tai ban moi loi"; return 1; }
        ok "Da tai ban moi nhat"
        remote_refresh_after_update
        [ "${NONINTERACTIVE:-0}" = 0 ] && { info "Mo lai menu voi ban moi..."; sleep 1; exec bash "$DIR/menu.sh"; }
        return 0
    fi
    local before after
    before=$(git -C "$DIR" rev-parse --short HEAD)
    git -C "$DIR" pull --ff-only 2>&1 | sub
    after=$(git -C "$DIR" rev-parse --short HEAD)
    if [ "$before" = "$after" ]; then
        ok "Dang la ban moi nhat (${W}$after${N})"; return 0
    fi
    ok "Da cap nhat ${W}$before → $after${N}:"
    git -C "$DIR" log --oneline "$before..$after" | sub
    if [ -f "$UNIT" ] && ! git -C "$DIR" diff --quiet "$before" "$after" -- exporter/; then
        warn "Exporter co thay doi"
        confirm "Cai lai exporter ban moi (giu port $(current_port))?" && do_install "$(current_port)"
    fi
    git -C "$DIR" diff --quiet "$before" "$after" -- exporter/ || remote_refresh_after_update
    if [ "${NONINTERACTIVE:-0}" = 0 ]; then
        info "Mo lai menu voi ban moi..."; sleep 1
        exec bash "$DIR/menu.sh"
    fi
}

do_config() {
    title "CAU HINH DA LUU"
    if [ ! -s "$CONF" ]; then
        info "Chua co cau hinh da luu ($CONF)"; return 0
    fi
    info "File: $CONF"; echo
    local k v
    while IFS= read -r l; do
        k=${l%%=*}; v=$(. "$CONF"; printf '%s' "${!k-}")
        printf '%s    %s%-14s%s %s\n' "$IND" "$C" "$k" "$N" "${v:-${D}<trong>${N}}"
    done < "$CONF"
    echo
    info "Sua: chay lai ${W}S${N} (gia tri cu hien san) hoac sua truc tiep file tren"
    if confirm "Xoa toan bo cau hinh da luu?"; then
        rm -f "$CONF"; ok "Da xoa - lan chay sau se hoi lai tu dau"
        unset "${!DASH_@}" GRAFANA_URL GRAFANA_FOLDER PROM_URL PROM_JOB SETUP_ROLE 2>/dev/null || true
    fi
}

do_about() {
    echo
    box_top
    box_center "${W}${C}$TOOL_NAME${N}"
    box_center "${D}phien ban $TOOL_VERSION${N}"
    box_sep
    box_row "$(kv "Phat trien" "${W}FIX NHANH${N}")"
    box_row "$(kv "Repo" "${REPO_URL#https://}")"
    box_row "$(kv "Thanh phan" "menu.sh · make_dashboard.py · pve_ceph_extra_exporter")"
    box_row "$(kv "Yeu cau" "bash, python3 >= 3.5, curl")"
    box_row "$(kv "Che do" "local (tren node Ceph) · remote (API token)")"
    box_row "$(kv "Giay phep" "xem file LICENSE")"
    box_sep
    box_center "${Y}Ban quyen © 2026 FIX NHANH. Bao luu moi quyen.${N}"
    box_bottom
}

# =============================================================================
# S. Cai dat tron goi: hoi het 1 lan, xac nhan, roi tu lam tung buoc
# =============================================================================
progress() {  # progress STEP TOTAL -> thanh tien do
    local w=24 f; f=$(($1 * w / $2))
    printf '%s%s%s%s' "$G" "$(hline █ $f)" "$D" "$(hline ░ $((w - f)))"; printf '%s' "$N"
}

do_setup() {
    title "CAI DAT TRON GOI"
    info "Tra loi cac cau hoi ben duoi (Enter = dung gia tri trong ${D}[ ]${N})."
    info "Cau tra loi duoc nho trong .menu.conf cho lan chay sau (khong luu token)."
    dash_defaults
    [ -n "${ENV_ROLE:-}" ] || detect_env
    local role port="" job="" cn gurl="" gfolder="" prom="" TOKEN="" flags=""
    local do_ex=0 do_dash=0 do_imp=0 do_chk=0

    echo; echo "${IND}  ${W}${M}[1/5] May nay lam gi?${N}"
    echo "${IND}     ${C}1${N}  Node Ceph: cai exporter + sinh/import dashboard (day du)"
    echo "${IND}     ${C}2${N}  Chi cai exporter (node Ceph)"
    echo "${IND}     ${C}3${N}  Chi sinh / import dashboard (may Grafana / may quan tri)"
    echo "${IND}     ${C}4${N}  May monitor: theo doi cluster TU XA qua API (khong cai gi len node) + dashboard"
    if [ "$ENV_CEPH" = 1 ]; then info "May nay co Ceph → goi y ${W}1${N}"
    else info "May nay khong co Ceph → goi y ${W}4${N} (theo doi tu xa) hoac ${W}3${N} (chi dashboard)"; fi
    role=$(ask "Chon" "${SETUP_ROLE:-$ENV_ROLE}")
    case "$role" in
        1) do_ex=1; do_dash=1 ;;
        2) do_ex=1 ;;
        3) do_dash=1 ;;
        4) do_dash=1
           echo; echo "${IND}  ${W}${M}[2/5] Cluster theo doi tu xa${N}"
           while true; do
               do_remote_add || warn "Cluster vua roi chua them duoc"
               confirm "Them cluster khac?" || break
           done ;;
        *) err "Lua chon khong hop le: $role"; return 1 ;;
    esac
    if [ $do_ex = 1 ] && [ "$ENV_CEPH" != 1 ]; then
        warn "Chon cai exporter nhung may nay khong chay duoc 'ceph status' → buoc kiem tra se dung lai"
        confirm "Van tiep tuc?" || { info "Huy - chay lai va chon 3, hoac chay tren node Ceph"; return 1; }
    fi

    if [ $do_ex = 1 ]; then
        need_root || return 1
        echo; echo "${IND}  ${W}${M}[2/5] Exporter${N}"
        port=$(ask "Port exporter" "$(current_port)")
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] \
            || { err "Port khong hop le: $port"; return 1; }
        info "Gop: exporter phat lai metric ceph mgr + Proxmox (pvesh) → Prometheus chi can 1 target"
        local allin; allin=$(ask "Gop tat ca metric ra 1 port? (Y/n)" "$([ -z "$(current_flags)" ] && echo Y || echo n)")
        if [[ "$allin" =~ ^[Nn] ]]; then flags="--no-ceph-mgr --no-pve"; else flags=""; fi
        cn=$(detect_cluster_name)
        [ -n "$cn" ] && info "Ten cluster Proxmox (corosync): ${W}$cn${N}"
        job=$(ask "Ten job Prometheus cua cluster (phai trung job cua ceph mgr)" "${PROM_JOB:-Proxmox-${cn:-CLUSTER}}")
    fi

    if [ $do_dash = 1 ]; then
        echo; echo "${IND}  ${W}${M}[3/5] Dashboard${N}"
        ask_dashboard
        echo; echo "${IND}  ${W}${M}[4/5] Grafana${N}"
        [ -n "${ENV_GRAFANA:-}" ] && info "Phat hien Grafana tren may nay: ${W}$ENV_GRAFANA${N}"
        gurl=$(ask "Grafana URL (bo trong = khong import, chi xuat file JSON)" "${GRAFANA_URL:-${ENV_GRAFANA:-}}")
        if [ -n "$gurl" ]; then
            ask_token
            gfolder=$(ask "Folder UID (bo trong = General)" "${GRAFANA_FOLDER:-}")
            if [ -n "$TOKEN" ]; then do_imp=1; else warn "Khong co token → chi xuat file JSON"; fi
        fi
    fi

    echo; echo "${IND}  ${W}${M}[5/5] Prometheus${N}"
    [ -n "${ENV_PROM:-}" ] && info "Phat hien Prometheus tren may nay: ${W}$ENV_PROM${N}"
    prom=$(ask "Prometheus URL de kiem tra sau khi cai (bo trong = bo qua)" "${PROM_URL:-${ENV_PROM:-}}")
    [ -n "$prom" ] && do_chk=1

    echo; box_top
    box_center "${W}${Y}TOM TAT${N}"
    box_sep
    if [ $do_ex = 1 ]; then
        box_row "$(kv "Exporter" "service $SERVICE · $(hostname) · port ${W}$port${N}")"
        box_row "$(kv "Che do" "$(mode_text "$flags")")"
        box_row "$(kv "Job Prom" "${W}$job${N} (target $(local_ip):$port)")"
    fi
    if [ $do_dash = 1 ]; then
        box_row "$(kv "Dashboard" "\"$DASH_TITLE\" · uid ${W}$DASH_UID${N}")"
        box_row "$(kv "Loc" "Site ${DASH_SITE:-<tat ca>} · job $DASH_JOB")"
        box_row "$(kv "Kich thuoc" "$DASH_NODES node · $DASH_POOLS pool · $DASH_CLASSES class · $DASH_TIME")"
        box_row "$(kv "Latency" "$DASH_LAT")"
        box_row "$(kv "HA alias" "$(echo "${DASH_ALIASES:-<khong>}" | sed 's/;;/ | /g' | cut -c1-55)")"
        if [ $do_imp = 1 ]; then box_row "$(kv "Grafana" "import → $gurl · folder ${gfolder:-General}")"
        else box_row "$(kv "Grafana" "khong import (import tay file JSON)")"; fi
    fi
    [ "$role" = 4 ] && box_row "$(kv "Tu xa" "$(remote_names | paste -sd' ' | cut -c1-60)")"
    if [ $do_chk = 1 ]; then box_row "$(kv "Kiem tra" "$prom")"; else box_row "$(kv "Kiem tra" "bo qua")"; fi
    box_bottom; echo
    confirm "Bat dau thuc hien?" || { info "Huy - chua thay doi gi"; return 1; }

    save_conf SETUP_ROLE "$role"
    [ -n "$job" ] && save_conf PROM_JOB "$job"
    [ $do_ex = 1 ] && save_conf EXPORTER_ARGS "$flags"
    [ $do_dash = 1 ] && save_dash_conf
    [ -n "$prom" ] && save_conf PROM_URL "${prom%/}"

    local step=0 total=$((do_ex * 3 + do_dash + do_imp + do_chk)) failed=()
    next() {
        step=$((step + 1))
        echo; echo "${IND}${W}${C}▶ [$step/$total]${N} $(progress $step $total) ${W}$1${N}"
    }

    if [ $do_ex = 1 ]; then
        next "Kiem tra moi truong"
        do_check || { err "Dung lai: sua cac loi tren roi chay lai (menu S)"; return 1; }
        next "Cai exporter (port $port)"
        do_install "$port" "$flags" || return 1
        next "Cau hinh Prometheus"
        prom_snippet "$job" "$port" "$flags"
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

    echo; box_top
    if [ ${#failed[@]} = 0 ]; then box_center "${G}${W}✔ HOAN TAT $total BUOC${N}"
    else box_center "${R}${W}✘ LOI O: ${failed[*]}${N}"; fi
    box_bottom
    [ $do_ex = 1 ] && [ $do_chk = 0 ] && \
        info "Nho them target vao Prometheus roi chay: bash menu.sh prom-check"
    [ $do_dash = 1 ] && [ $do_imp = 0 ] && \
        info "Import tay: Grafana → Dashboards → New → Import → $DASH_JSON"
    info "Muon doi cau tra loi: chay lai menu S (gia tri cu hien san), hoac menu 15"
    [ ${#failed[@]} = 0 ]
}

# =============================================================================
# Menu
# =============================================================================
show_help() {
    sed -n '2,16p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
}

banner() {
    # chu FIX NHANH kieu ANSI Shadow, moi dong 1 mau (gradient)
    local -a F=("███████╗" "██╔════╝" "█████╗  " "██╔══╝  " "██║     " "╚═╝     ")
    local -a I=("██╗" "██║" "██║" "██║" "██║" "╚═╝")
    local -a X=("██╗  ██╗" "╚██╗██╔╝" " ╚███╔╝ " " ██╔██╗ " "██╔╝ ██╗" "╚═╝  ╚═╝")
    local -a NN=("███╗   ██╗" "████╗  ██║" "██╔██╗ ██║" "██║╚██╗██║" "██║ ╚████║" "╚═╝  ╚═══╝")
    local -a H=("██╗  ██╗" "██║  ██║" "███████║" "██╔══██║" "██║  ██║" "╚═╝  ╚═╝")
    local -a A=(" █████╗ " "██╔══██╗" "███████║" "██╔══██║" "██║  ██║" "╚═╝  ╚═╝")
    local i
    if [ $BOXW -ge 70 ]; then
        for i in 0 1 2 3 4 5; do
            box_center "${GRAD[$i]}${W}${F[$i]}${I[$i]}${X[$i]}  ${NN[$i]}${H[$i]}${A[$i]}${NN[$i]}${H[$i]}${N}"
        done
    else
        box_center "${C}${W}F I X   N H A N H${N}"
    fi
}

header() {
    clear 2>/dev/null || true
    setup_ui
    local st port ex grafana prom pve
    port=$(current_port)
    if [ -f "$UNIT" ]; then st=$(svc_state); else st="chua cai"; fi
    case "$st" in active) ex="${G}${W}● dang chay${N} :$port" ;; "chua cai") ex="${D}○ chua cai${N}" ;; *) ex="${R}● $st${N}" ;; esac
    pve="${ENV_PVE:+${G}PVE $ENV_PVE${N}}"; pve="${pve:-${D}khong phai node PVE${N}}"
    grafana="${GRAFANA_URL:-${ENV_GRAFANA:-}}"; grafana="${grafana:-${D}chua cau hinh${N}}"
    prom="${PROM_URL:-${ENV_PROM:-}}"; prom="${prom:-${D}chua cau hinh${N}}"

    echo
    box_top
    banner
    box_center "${W}MONITOR PROXMOX + CEPH${N}  ${D}·${N}  ${B}Prometheus${N} ${D}→${N} ${O}Grafana${N}"
    box_center "${D}phien ban $TOOL_VERSION${N}"
    box_title "THONG TIN MAY" "$C"
    box_row2 "$(kv "May" "${W}$(hostname)${N}")" "$(kv "IP" "$(local_ip)")"
    box_row2 "$(kv "Proxmox" "$pve")" "$(kv "Ceph" "$(ceph_health_short)")"
    box_row2 "$(kv "Exporter" "$ex")" "$(kv "OS" "$(echo "$ENV_OS" | cut -c1-24)")"
    box_row "$(kv "Grafana" "$grafana")"
    box_row "$(kv "Prometheus" "$prom")"
    local rn; rn=$(remote_names | wc -l)
    [ "$rn" -gt 0 ] && box_row "$(kv "Tu xa" "${W}$rn${N} cluster: $(remote_names | paste -sd' ' | cut -c1-55)")"
}

menu_body() {
    box_title "CAI DAT NHANH" "$G"
    box_row "$(mi S "${W}Cai dat tron goi${N} ${D}- hoi 1 lan, tu lam het cac buoc ben duoi${N}" "$G")"
    box_title "EXPORTER  ${D}(chay tren node Ceph)${N}" "$M"
    box_row2 "$(mi 1 "Kiem tra moi truong" "$M")"   "$(mi 5 "Xem log" "$M")"
    box_row2 "$(mi 2 "Cai dat / cap nhat" "$M")"    "$(mi 6 "Khoi dong lai" "$M")"
    box_row2 "$(mi 3 "Trang thai exporter" "$M")"   "$(mi 7 "Doi port" "$M")"
    box_row2 "$(mi 4 "Xem metric hien tai" "$M")"   "$(mi 8 "Go cai dat" "$M")"
    box_title "DASHBOARD & PROMETHEUS" "$O"
    box_row2 "$(mi 9 "Sinh dashboard JSON" "$O")"   "$(mi 11 "Import len Grafana" "$O")"
    box_row2 "$(mi 10 "Mau prometheus.yml" "$O")"   "$(mi 12 "Kiem tra Prometheus" "$O")"
    box_row  "$(mi 13 "Kiem tra tong the (moi truong + exporter + Prometheus)" "$O")"
    box_title "THEO DOI TU XA  ${D}(qua API, khong cai len node)${N}" "$G"
    box_row2 "$(mi 17 "Them / sua cluster" "$G")"    "$(mi 19 "Kiem tra ket noi" "$G")"
    box_row2 "$(mi 18 "Danh sach cluster" "$G")"     "$(mi 20 "Xoa cluster" "$G")"
    box_title "HE THONG & DOCKER" "$Y"
    box_row2 "$(mi 21 "Cai goi can thiet" "$Y")"     "$(mi 23 "Chay cluster bang Docker" "$Y")"
    box_row2 "$(mi 22 "Mo firewall cho Prometheus" "$Y")" "$(mi 24 "Quan ly container" "$Y")"
    box_title "TIEN ICH" "$B"
    box_row2 "$(mi 14 "Cap nhat tool (git pull)" "$B")" "$(mi 16 "Gioi thieu & ban quyen" "$B")"
    box_row2 "$(mi 15 "Cau hinh da luu" "$B")"         "$(mi 0 "Thoat" "$R")"
    box_sep
    box_center "${D}$COPYRIGHT${N}"
    box_bottom
}

menu() {
    detect_env
    while true; do
        header
        menu_body
        local c; echo; read -rp "${IND}  ${C}❯${N} ${W}Chon chuc nang:${N} " c
        case "$c" in
            1) do_check ;;      2) do_install ;;   3) do_status ;;
            4) do_metrics ;;    5) do_logs ;;      6) do_restart ;;
            7) do_port ;;       8) do_uninstall ;; 9) do_dashboard ;;
            10) do_prom ;;      11) do_import ;;   12) do_prom_check ;;
            13) do_doctor ;;    14) do_update ;;   15) do_config ;;
            16) do_about ;;
            17) do_remote_add ;; 18) do_remote_list ;; 19) do_remote_test ;; 20) do_remote_remove ;;
            21) do_deps ;; 22) do_firewall ;; 23) do_docker_run ;; 24) do_docker_manage ;;
            s|S) do_setup ;;
            0|q|Q) echo; echo "${IND}  ${D}Tam biet! $COPYRIGHT${N}"; echo; exit 0 ;;
            "") continue ;;
            *) warn "Lua chon khong hop le: $c" ;;
        esac
        pause
    done
}

# ----------------------------------------------------------------- dong lenh
if [ $# -gt 0 ]; then
    NONINTERACTIVE=1
    cmd="$1"; shift
    case "$cmd" in
        setup) NONINTERACTIVE=0; detect_env; do_setup ;;
        check) do_check ;;           install) do_install "${1:-$(current_port)}" ;;
        status) do_status ;;         metrics) do_metrics ;;
        logs) do_logs ;;             restart) do_restart ;;
        port) [ -n "${1:-}" ] || { err "Dung: menu.sh port <so>"; exit 1; }; do_port "$1" ;;
        uninstall) do_uninstall ;;   dashboard) NONINTERACTIVE=0; detect_env; do_dashboard ;;
        import) NONINTERACTIVE=0; detect_env; do_import ;;
        prom) NONINTERACTIVE=0; do_prom ;;
        prom-check) NONINTERACTIVE=0; detect_env; do_prom_check ;;
        doctor) do_doctor ;;         update) do_update ;;
        about) do_about ;;
        remote-add) NONINTERACTIVE=0; do_remote_add "${1:-}" ;;
        remote-list) do_remote_list ;;
        remote-test) NONINTERACTIVE=0; do_remote_test ;;
        remote-remove) NONINTERACTIVE=0; do_remote_remove ;;
        deps) NONINTERACTIVE=0; detect_env; do_deps ;;
        firewall) NONINTERACTIVE=0; do_firewall ;;
        docker-run) NONINTERACTIVE=0; do_docker_run ;;
        docker-manage) NONINTERACTIVE=0; do_docker_manage ;;
        help|-h|--help) show_help ;;
        *) err "Lenh khong ro: $cmd"; show_help; exit 1 ;;
    esac
    exit $?
fi

menu
