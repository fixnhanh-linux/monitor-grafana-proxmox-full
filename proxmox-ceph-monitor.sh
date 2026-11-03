#!/bin/bash
# =============================================================================
#  FIX NHANH - Monitor Proxmox + Ceph
#    - pve_ceph_extra_exporter (Ceph recovery + HA groups)
#    - Grafana dashboards (dashboard-grafana/make_dashboard.py), Prometheus alerts (prometheus/)
#    - Zabbix: Ceph via Zabbix agent 2 (template-zabbix/)
#
#  Open the menu:    proxmox-menu        (or bash proxmox-ceph-monitor.sh; the shortcut is installed when run as root)
#  Update all:       proxmox-menu refresh   (git pull + reinstall exporter + dashboards + checks)
#  Run one command:  proxmox-menu <command>
#      setup | check | install | status | metrics | logs | restart | port <number> |
#      uninstall | dashboard | import | prom | prom-check | doctor | update | refresh | about | help |
#      remote-add [name] | remote-list | remote-test | remote-remove | services | watchdog |
#      prom-all | prom-push | prom-rules | urls | deps | firewall | docker-run | docker-manage | docker-net |
#      zabbix-ceph | ha-sync
#
#  Copyright © 2026 FIX NHANH. All rights reserved.
# =============================================================================
set -uo pipefail

TOOL_NAME="FIX NHANH · Monitor Proxmox + Ceph"
TOOL_VERSION="2026.10.30"
REPO_URL="https://github.com/fixnhanh-linux/monitor-grafana-proxmox-full"
COPYRIGHT="© 2026 FIX NHANH · All rights reserved"

DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$DIR/proxmox-ceph-monitor.sh"   # file nay (menu.sh chi la ten cu, goi lai file nay)
EXPORTER_SRC="$DIR/exporter/pve_ceph_extra_exporter.py"
INSTALLER="$DIR/exporter/install_exporter.sh"
MAKE_DASH="$DIR/dashboard-grafana/make_dashboard.py"
DASH_JSON="$DIR/dashboard-local.json"   # file menu 9 sinh ra, KHONG nam trong git (git pull khong bi chan)
DASH_REPO_JSON="$DIR/dashboard-grafana/proxmox_ceph_dashboard.json"   # ban mau trong repo (cau hinh mac dinh)
HA_COLOR_STATE="$DIR/.ha-colors.json"   # mau da gan cho tung loai CPU (giu nguyen khi co nhom moi)
HA_SEEN="$DIR/.ha-groups.seen"          # chuoi HA Groups da co mau -> timer ha-sync so sanh

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
    echo; read -rp "${IND}  ${D}Press Enter to return to the menu...${N}" _
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
    err "Must run as root (sudo proxmox-menu)"; return 1
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
    if [ -z "$1" ]; then echo "merged on 1 port (ceph mgr + Proxmox + extras)"; else echo "extra metrics only ($1)"; fi
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
    [ "${ENV_CEPH:-0}" = 1 ] || { echo "${D}not on this host${N}"; return; }
    local h; h=$(timeout 8 ceph health 2>/dev/null | awk '{print $1}')
    case "$h" in
        HEALTH_OK)   echo "${G}${W}HEALTH_OK${N}" ;;
        HEALTH_WARN) echo "${Y}${W}HEALTH_WARN${N}" ;;
        HEALTH_ERR)  echo "${R}${W}HEALTH_ERR${N}" ;;
        *)           echo "${R}unreadable${N}" ;;
    esac
}

# =============================================================================
# 1. Kiem tra moi truong
# =============================================================================
do_check() {
    title "ENVIRONMENT CHECK"
    local bad=0

    if [ -f /etc/pve/.version ] || has pveversion; then
        ok "Proxmox VE: $(pveversion 2>/dev/null | head -1)"
    else
        warn "Proxmox VE not found (still works on a plain Ceph node)"
    fi

    if has python3; then
        local pv; pv=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')
        if python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,5) else 1)'; then
            ok "python3 $pv"
        else
            err "python3 $pv too old (need >= 3.5)"; bad=1
        fi
    else
        err "python3 missing (apt install python3)"; bad=1
    fi

    if has ceph; then
        ok "ceph command: $(ceph --version 2>/dev/null | awk '{print $3, $5}')"
        if timeout 15 ceph status --format json >/dev/null 2>&1; then
            ok "ceph status OK: $(timeout 15 ceph health 2>/dev/null)"
        else
            err "Cannot run 'ceph status' (missing /etc/ceph/ceph.client.admin.keyring or cannot reach the mons)"; bad=1
        fi
    else
        err "No ceph command on this host → install the exporter on a Ceph node of the cluster"; bad=1
    fi

    if [ -f /etc/pve/ha/groups.cfg ] || [ -f /etc/pve/ha/rules.cfg ]; then
        ok "HA config found: $(ls /etc/pve/ha/groups.cfg /etc/pve/ha/rules.cfg 2>/dev/null | xargs)"
    else
        info "No HA group/rule → HA Groups column shows "-" (normal)"
    fi

    local port; port=$(current_port)
    if has ss && ss -ltnp 2>/dev/null | grep -q ":$port "; then
        if ss -ltnp 2>/dev/null | grep ":$port " | grep -q python3; then
            ok "Port $port is used by the exporter"
        else
            err "Port $port is taken by another program: $(ss -ltnp | grep ":$port " | awk '{print $NF}')"; bad=1
        fi
    else
        ok "Port $port is free"
    fi

    if has pve-firewall && pve-firewall status 2>/dev/null | grep -q "enabled/running"; then
        warn "PVE firewall is enabled → open port $port for the Prometheus IP:"
        echo "Datacenter/Node → Firewall → Add: IN ACCEPT tcp dport $port source <Prometheus IP>" | sub
    fi

    if [ -z "$(current_flags)" ]; then
        if has ceph && timeout 10 ceph mgr services -f json 2>/dev/null | grep -q '"prometheus"'; then
            ok "ceph mgr prometheus module is enabled"
        elif has ceph; then
            err "ceph mgr prometheus module is not enabled (required for merged 1-port mode):"
            echo "ceph mgr module enable prometheus" | sub; bad=1
        fi
        if has pvesh; then ok "pvesh available (Proxmox metrics)"; else err "pvesh missing - this host is not a Proxmox node"; bad=1; fi
    fi

    has curl || warn "curl missing (apt install curl) - needed for metrics / Grafana import"

    if [ "$bad" = 0 ]; then ok "${G}${W}Environment ready${N}"; else err "${R}${W}Fix the errors above before installing${N}"; fi
    return $bad
}

# =============================================================================
# 2. Cai / cap nhat exporter
# =============================================================================
do_install() {
    title "INSTALL / UPDATE EXPORTER"
    need_root || return 1
    [ -f "$EXPORTER_SRC" ] || { err "$EXPORTER_SRC not found"; return 1; }
    local port="${1:-}"
    [ -n "$port" ] || port=$(ask "Exporter port" "$(current_port)")
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] \
        || { err "Invalid port: $port"; return 1; }

    if [ -f "$BIN" ]; then
        local old new
        old=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$BIN")
        new=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$EXPORTER_SRC")
        info "Installed: ${old:-?}  →  new: ${new:-?}"
    fi

    local flags="${2-$(current_flags)}"
    info "Mode: ${W}$(mode_text "$flags")${N}"
    if PORT="$port" ARGS="$flags" bash "$INSTALLER" 2>&1 | sub; then
        ok "Installed service ${W}$SERVICE${N} port ${W}$port${N}"
        info "Next: add target $(local_ip):$port to Prometheus (menu 10)"
    else
        err "Exporter install failed"; return 1
    fi
}

# =============================================================================
# 3. Trang thai
# =============================================================================
do_status() {
    title "EXPORTER STATUS"
    if [ ! -f "$UNIT" ]; then
        warn "Exporter not installed on this host (menu 2 or S)"; return 1
    fi
    local st port; st=$(svc_state); port=$(current_port)
    if [ "$st" = active ]; then ok "Service $SERVICE: ${G}${W}$st${N}"; else err "Service $SERVICE: ${R}$st${N}"; fi
    info "Port: ${W}$port${N}   ·   Version: $(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$BIN" 2>/dev/null)"
    info "Start on boot: $(systemctl is-enabled "$SERVICE" 2>/dev/null)"
    systemctl show "$SERVICE" -p ActiveEnterTimestamp -p NRestarts -p MemoryCurrent 2>/dev/null | sub

    if has curl; then
        local m line; m=$(curl -sf --max-time 20 "http://127.0.0.1:$port/metrics") || { err "Cannot fetch /metrics"; return 1; }
        echo
        while read -r l; do
            [ -n "$l" ] || continue
            if [[ "$l" == *" 1" ]]; then ok "$l"; else err "$l"; fi
        done <<< "$(echo "$m" | grep '^pve_ceph_extra_exporter_up')"
        line=$(echo "$m" | grep '^ceph_custom_recovery_info')
        [ -n "$line" ] && info "Ceph: ${W}$(echo "$line" | sed 's/.*content="\([^"]*\)".*/\1/')${N}"
        info "Total Health: ${W}$(echo "$m" | awk '/^ceph_custom_recovery_percent /{print $2}') %${N}"
        info "HA groups: $(echo "$m" | grep -c '^pve_ha_groups_custom_info') nodes"
        info "Collect time per cycle (s):"
        echo "$m" | sed -n 's/^pve_ceph_extra_exporter_collect_seconds{collector="\([^"]*\)"} \(.*\)/\1 \2/p' \
            | awk '{printf "%-10s %6.2f s\n", $1, $2}' | sub
        local pid; pid=$(systemctl show -p MainPID --value "$SERVICE" 2>/dev/null)
        if [ -n "$pid" ] && [ "$pid" != 0 ]; then
            info "Resources: $(ps -o %cpu=,rss= -p "$pid" | awk '{printf "CPU %s%%  RAM %.0f MB", $1, $2/1024}')  (limit CPU 25%, RAM 256M)"
        fi
    fi
}

# =============================================================================
# 4. Xem metric
# =============================================================================
do_metrics() {
    title "CURRENT METRICS"
    local port; port=$(current_port)
    if [ "$(svc_state)" = active ] && has curl; then
        curl -sf --max-time 20 "http://127.0.0.1:$port/metrics" | grep -v '^#' | sub
    elif has python3 && [ -f "$EXPORTER_SRC" ]; then
        info "Service not running → one-shot run from source:"
        python3 "$EXPORTER_SRC" --once | grep -v '^#' | sub
    else
        err "Cannot get metrics"
    fi
}

# =============================================================================
# 5. Log / 6. Restart / 7. Doi port / 8. Go cai
# =============================================================================
do_logs() {
    title "LAST 50 LOG LINES"
    journalctl -u "$SERVICE" -n 50 --no-pager 2>/dev/null | sub || err "Cannot read journal"
}

do_restart() {
    title "RESTART EXPORTER"
    need_root || return 1
    systemctl restart "$SERVICE" && sleep 2
    if [ "$(svc_state)" = active ]; then ok "Restarted"; else err "Restart failed"; do_logs; fi
}

do_port() {
    title "CHANGE EXPORTER PORT"
    need_root || return 1
    local p="${1:-}"
    [ -n "$p" ] || p=$(ask "New port" "$(current_port)")
    do_install "$p" && warn "Remember to change the target in prometheus.yml to port $p"
}

do_uninstall() {
    title "UNINSTALL EXPORTER"
    need_root || return 1
    if [ "${NONINTERACTIVE:-0}" = 1 ] || confirm "Remove service $SERVICE from this host?"; then
        bash "$INSTALLER" uninstall 2>&1 | sub
    else
        info "Cancelled"
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
        info "Cannot read HA groups on this host → keeping saved short names (if any)"
        return 0
    fi
    info "Enter a short name, add :color if you like (e.g. ${W}Gold+HIGH:purple${N}). Empty = keep the original name. Nodes with a problem turn red / orange."
    while IFS= read -r g <&3; do
        t=$(ask "$g" "$(alias_of "$g")")
        [ -n "$t" ] && out+="${out:+;;}$g=$t"
    done 3<<< "$groups"
    DASH_ALIASES="$out"
}

gen_dashboard() {  # sinh $DASH_JSON tu cac bien DASH_*
    has python3 || { err "python3 missing"; return 1; }
    dash_defaults
    local a args=(-o "$DASH_JSON" --title "$DASH_TITLE" --uid "$DASH_UID" --site-regex "$DASH_SITE"
                  --job-regex "$DASH_JOB" --nodes "$DASH_NODES" --pools "$DASH_POOLS"
                  --classes "$DASH_CLASSES" --lat-th "$DASH_LAT" --time-from "$DASH_TIME")
    while IFS= read -r a; do
        [ -n "$a" ] && args+=(--ha-alias "$a")
    done <<< "${DASH_ALIASES//;;/$'\n'}"
    # Nhom chua dat ten ngan van co mau rieng (theo loai CPU): nhom tai cho + moi datasource
    # Prometheus tren Grafana (dashboard nhieu Site) + Prometheus da luu
    local n
    HA_GROUPS=$({ detect_ha_groups; grafana_ha_groups; } | grep -v '^$' | sort -u)
    while IFS= read -r a; do
        [ -n "$a" ] && args+=(--ha-group "$a")
    done <<< "$HA_GROUPS"
    [ -n "${PROM_URL:-}" ] && args+=(--prom-url "$PROM_URL")
    python3 "$MAKE_DASH" "${args[@]}" --color-state "$HA_COLOR_STATE" >/dev/null || { err "Dashboard generation failed"; return 1; }
    n=$(grep -c . <<< "$HA_GROUPS")
    ok "Created ${W}$DASH_JSON${N} (HA Groups colors: $n group strings found)"
    if [ -n "$HA_GROUPS" ]; then
        { cat "$HA_SEEN" 2>/dev/null; echo "$HA_GROUPS"; } | grep -v '^$' | sort -u > "$HA_SEEN.tmp" && mv -f "$HA_SEEN.tmp" "$HA_SEEN"
    fi
    return 0
}

dash_update_all() {  # sinh lai + import moi dashboard, loi ghi vao DASH_FAIL (dung cho refresh / ha-sync)
    DASH_FAIL=()
    if gen_dashboard; then
        if [ -n "${GRAFANA_URL:-}" ] && [ -s "$GRAFANA_TOKEN_FILE" ]; then
            import_dashboard "$GRAFANA_URL" "$(cat "$GRAFANA_TOKEN_FILE")" "${GRAFANA_FOLDER:-}" </dev/null || DASH_FAIL+=("import Grafana")
        else
            warn "No saved Grafana URL / token → import manually: menu 11 (save the token once)"
        fi
    else DASH_FAIL+=("generate dashboard"); fi
    # Cac dashboard khac (dashboard-*.json: khach hang, ban rieng CMC / FPT ...): sinh lai bang
    # tham so luu trong chinh file (fixnhanhArgs) + nhom HA vua tim (chung bang mau), giu folder tren Grafana
    local f a main=$DASH_JSON extra=(--color-state "$HA_COLOR_STATE")
    while IFS= read -r a; do [ -n "$a" ] && extra+=(--ha-group "$a"); done <<< "${HA_GROUPS:-}"
    for f in "$DIR"/dashboard-*.json; do
        [ -f "$f" ] && [ "$f" != "$main" ] || continue
        if ! grep -q '"fixnhanhArgs"' "$f"; then
            warn "$(basename "$f"): generated by an old version (no saved args) → recreate it once with dashboard-grafana/make_dashboard.py (README: Multiple dashboards)"
            continue
        fi
        if python3 "$MAKE_DASH" --regen "$f" "${extra[@]}" >/dev/null; then
            ok "Regenerated $(basename "$f")"
            if [ -n "${GRAFANA_URL:-}" ] && [ -s "$GRAFANA_TOKEN_FILE" ]; then
                DASH_JSON=$f import_dashboard "$GRAFANA_URL" "$(cat "$GRAFANA_TOKEN_FILE")" "" </dev/null || DASH_FAIL+=("import $(basename "$f")")
            fi
        else DASH_FAIL+=("generate $(basename "$f")"); fi
    done
    DASH_JSON=$main
    [ "${#DASH_FAIL[@]}" = 0 ]
}

# Timer ha-sync: 5 phut / lan xem co chuoi HA Groups MOI (host moi, nhom moi, site moi) khong;
# co thi sinh lai + import moi dashboard -> nhom moi tu co mau, nhom cu giu nguyen mau.
HA_UNIT=pve-ceph-ha-colors
do_ha_sync() {
    dash_defaults
    local now new
    now=$({ detect_ha_groups; grafana_ha_groups; } | grep -v '^$' | sort -u)
    [ -n "$now" ] || { info "No HA groups found → nothing to do"; return 0; }
    new=$(comm -13 <(sort -u "$HA_SEEN" 2>/dev/null) <(echo "$now"))
    [ -n "$new" ] || { ok "No new HA groups"; return 0; }
    info "New HA groups: $(echo "$new" | paste -sd '|')"
    dash_update_all || { err "Needs attention: ${DASH_FAIL[*]}"; return 1; }
}

ha_timer_on() {  # cai timer ha-sync 1 lan (can root + systemd + token Grafana da luu)
    [ "$(id -u)" = 0 ] && has systemctl && [ -n "${GRAFANA_URL:-}" ] && [ -s "$GRAFANA_TOKEN_FILE" ] || return 0
    local d=${SYSTEMD_DIR:-/etc/systemd/system}
    systemctl is-enabled -q "$HA_UNIT.timer" 2>/dev/null && grep -qF "$SELF" "$d/$HA_UNIT.service" 2>/dev/null && return 0
    printf '[Unit]\nDescription=FIX NHANH HA Groups colors: regenerate dashboards when new HA groups appear\n\n[Service]\nType=oneshot\nExecStart=/bin/bash "%s" ha-sync\nSyslogIdentifier=pve-ceph-ha-colors\n' "$SELF" \
        > "$d/$HA_UNIT.service"
    printf '[Unit]\nDescription=FIX NHANH HA Groups colors (every 5 minutes)\n\n[Timer]\nOnBootSec=5min\nOnUnitActiveSec=5min\n\n[Install]\nWantedBy=timers.target\n' \
        > "$d/$HA_UNIT.timer"
    systemctl daemon-reload && systemctl enable --now "$HA_UNIT.timer" >/dev/null 2>&1 \
        && ok "Auto colors on: new HA groups get a color within 5 minutes (journalctl -t pve-ceph-ha-colors)" \
        || warn "Could not enable $HA_UNIT.timer"
}

grafana_ha_groups() {  # chuoi HA Groups cua moi datasource Prometheus (khop Site) qua Grafana proxy
    [ -n "${GRAFANA_URL:-}" ] && [ -s "$GRAFANA_TOKEN_FILE" ] && has curl && has python3 || return 0
    local base tok ds uid
    base=$(gurl "${GRAFANA_URL%/}"); tok=$(cat "$GRAFANA_TOKEN_FILE")
    ds=$(gcurl -sf --max-time 10 -H "Authorization: Bearer $tok" "$base/api/datasources" 2>/dev/null | python3 -c '
import json, re, sys
site = sys.argv[1]
rx = site[1:-1] if len(site) > 1 and site.startswith("/") and site.endswith("/") else site
for d in json.load(sys.stdin):
    if d.get("type") == "prometheus" and (not rx or re.search(rx, d.get("name", ""))):
        print(d["uid"])
' "${DASH_SITE:-}" 2>/dev/null) || return 0
    while IFS= read -r uid; do
        [ -n "$uid" ] || continue
        gcurl -sfG --max-time 10 -H "Authorization: Bearer $tok" \
            "$base/api/datasources/proxy/uid/$uid/api/v1/query" \
            --data-urlencode "query=count by (groups) (pve_ha_groups_custom_info)" 2>/dev/null | python3 -c '
import json, sys
for s in json.load(sys.stdin)["data"]["result"]:
    print(s["metric"].get("groups", ""))
' 2>/dev/null
    done <<< "$ds"
    return 0
}

# Grafana cert tu ky: GHIM dung cert do (curl --cacert), KHONG tat kiem tra TLS.
# Cert ghi ten khac IP trong URL -> goi bang ten trong cert, --connect-to tro ve IP that.
GRAFANA_CERT_FILE="$DIR/.grafana-cert.pem"
gurl() {  # URL -> URL dung ten trong cert (neu da ghim va cert khong ghi IP)
    if [ -n "${GRAFANA_TLSNAME:-}" ] && [ -n "${GRAFANA_TLSIP:-}" ]; then
        echo "$1" | sed "s|://$GRAFANA_TLSIP\([:/]\)|://$GRAFANA_TLSNAME\1|; s|://$GRAFANA_TLSIP\$|://$GRAFANA_TLSNAME|"
    else echo "$1"; fi
}
gcurl() {
    local a=()
    [ -n "${GRAFANA_CACERT:-}" ] && [ -f "$GRAFANA_CACERT" ] && a+=(--cacert "$GRAFANA_CACERT")
    [ -n "${GRAFANA_TLSNAME:-}" ] && [ -n "${GRAFANA_TLSIP:-}" ] && a+=(--connect-to "$GRAFANA_TLSNAME::$GRAFANA_TLSIP:")
    curl "${a[@]}" "$@"
}

grafana_pin_cert() {  # grafana_pin_cert https://HOST:PORT -> 0 neu da ghim
    local url="$1" hp host port tmp fp subj san name=""
    has openssl || { err "openssl is required to fetch the cert (apt install openssl)"; return 1; }
    hp=$(echo "$url" | sed -E 's|^https://||; s|/.*||'); host=${hp%:*}; port=${hp##*:}
    [ "$port" = "$hp" ] && port=443
    tmp=$(mktemp)
    openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null | openssl x509 > "$tmp" 2>/dev/null
    [ -s "$tmp" ] || { rm -f "$tmp"; err "Cannot fetch the cert from $host:$port"; return 1; }
    fp=$(openssl x509 -in "$tmp" -noout -fingerprint -sha256 | cut -d= -f2)
    subj=$(openssl x509 -in "$tmp" -noout -subject | sed 's/^subject= *//')
    san=$(openssl x509 -in "$tmp" -noout -ext subjectAltName 2>/dev/null | tail -n +2 | xargs)
    info "Cert of ${W}$host:$port${N}:"
    printf '%s\n' "Subject : $subj" "Names/IP: ${san:-<no SAN>}" "SHA-256 : $fp" | sub
    info "Compare in the browser: click 'Not secure' → Certificate → the SHA-256 fingerprint must MATCH"
    # Cert khong ghi IP dang dung -> goi bang ten trong cert
    if [[ "$san" != *"IP Address:$host"* ]] && [[ "$san" != *"DNS:$host"* ]]; then
        name=$(echo "$san" | tr ',' '\n' | sed -n 's/^ *DNS://p' | head -1)
        [ -n "$name" ] || name=$(echo "$subj" | sed -n 's/.*CN *= *\([^,/]*\).*/\1/p')
        [ -n "$name" ] && info "Cert does not list $host → calling by name ${W}$name${N}, pointed at $host"
    fi
    if ! confirm "Fingerprint matches, trust this cert (only for this tool's Grafana calls)?"; then rm -f "$tmp"; info "Cancelled"; return 1; fi
    install -m 600 "$tmp" "$GRAFANA_CERT_FILE"; rm -f "$tmp"
    GRAFANA_CACERT=$GRAFANA_CERT_FILE; GRAFANA_TLSNAME=$name; GRAFANA_TLSIP=${name:+$host}
    save_conf GRAFANA_CACERT "$GRAFANA_CACERT"; save_conf GRAFANA_TLSNAME "$GRAFANA_TLSNAME"; save_conf GRAFANA_TLSIP "$GRAFANA_TLSIP"
    ok "Cert pinned → $GRAFANA_CERT_FILE (if the Grafana cert changes, run menu 11 again and the tool will ask)"
}

# Noi ro vi sao khong goi duoc URL (cert, sai http/https, firewall, port dong) va cach sua.
explain_curl_fail() {  # explain_curl_fail URL PATH GREP
    local url="$1" rc w host
    curl -s --max-time 8 -o /dev/null "$url$2" 2>/dev/null; rc=$?
    host=$(echo "$url" | sed -E 's|^https?://||; s|/.*||')
    err "Cannot connect to $url (curl error $rc)"
    case "$rc" in
        60|51|58|77) warn "TLS cert of $host is not trusted by this host (self-signed / internal CA)"
           info "Option 1: use http:// if Grafana does not use TLS"
           info "Option 2: install the CA on this host: openssl s_client -connect $host -showcerts </dev/null | openssl x509 > /usr/local/share/ca-certificates/grafana.crt && update-ca-certificates" ;;
        35) warn "TLS handshake failed → this port may serve http, not https" ;;
        7)  warn "Connection refused → wrong port, or Grafana is not listening on this IP" ;;
        28) warn "Timed out → blocked by a firewall, or the public IP is not reachable from inside (try Grafana's internal IP)" ;;
        6)  warn "Cannot resolve $host" ;;
        22) warn "Grafana returned an HTTP error (wrong path / reverse proxy?)" ;;
    esac
    if w=$(url_probe "$url" "$2" "$3" 2>/dev/null) && [ "$w" != "$url" ]; then
        ok "But ${W}$w${N} works → use this URL (menu 15 to save it)"
    fi
}

# Dashboard chon datasource qua bien Site (loc theo DASH_SITE): Grafana khong co datasource
# Prometheus nao khop thi moi o deu "No data" -> bao truoc khi import.
grafana_ds_check() {  # grafana_ds_check URL TOKEN -> 1 neu nguoi dung huy
    local url="$1" token="$2" ds code out
    ds=$(gcurl -s --max-time 10 -w '\n%{http_code}' -H "Authorization: Bearer $token" "$(gurl "$url")/api/datasources")
    code=${ds##*$'\n'}; ds=${ds%$'\n'*}
    if [ "$code" != 200 ]; then
        [ "$code" = 401 ] && { err "Token invalid / expired (401)"; forget_token; return 1; }
        info "Cannot list datasources (HTTP $code, token lacks permission) → skipping the check"
        return 0
    fi
    out=$(printf '%s' "$ds" | python3 -c '
import json, re, sys
site, prom = sys.argv[1], sys.argv[2].rstrip("/")
ds = [d for d in json.load(sys.stdin) if d.get("type") == "prometheus"]
rx = site[1:-1] if len(site) > 1 and site.startswith("/") and site.endswith("/") else site
for d in ds:
    hit = (not rx) or re.search(rx, d.get("name", "")) is not None
    same = prom and d.get("url", "").rstrip("/") == prom
    print("%s|%s|%s|%s" % ("Y" if hit else "N", "Y" if same else "N", d.get("name", ""), d.get("url", "")))
' "${DASH_SITE:-}" "${PROM_URL:-}" 2>/dev/null) || { info "Cannot list datasources → skipping the check"; return 0; }
    if [ -z "$out" ]; then
        err "Grafana has no Prometheus datasource → the dashboard will be empty"
        info "Grafana → Connections → Data sources → Add → Prometheus, URL ${PROM_URL:-http://<prometheus>:9090}"
        confirm "Import anyway?" || return 1; return 0
    fi
    info "Prometheus datasources on Grafana (✔ = shown in the Site variable):"
    local hit same name dsurl nhit=0
    while IFS='|' read -r hit same name dsurl; do
        [ "$hit" = Y ] && nhit=$((nhit + 1))
        printf '%s      %s %s%s  %s%s\n' "$IND" "$([ "$hit" = Y ] && echo "${G}✔${N}" || echo "${D}·${N}")" \
            "$name" "$N" "${D}$dsurl" "$([ "$same" = Y ] && echo "  ${G}← configured Prometheus${N}")${N}"
    done <<< "$out"
    if [ "$nhit" = 0 ]; then
        warn "No datasource matches the Site regex '${DASH_SITE}' → change it in menu 9 (empty = all) and regenerate"
        confirm "Import anyway?" || return 1
    fi
    if [ -n "${PROM_URL:-}" ] && ! grep -q '^.|Y|' <<< "$out"; then
        warn "No datasource points to $PROM_URL (the Prometheus scraping the exporter) → check when choosing Site"
    fi
    return 0
}

import_dashboard() {  # import_dashboard URL TOKEN FOLDER
    local url="${1%/}" token="$2" folder="$3" payload resp
    has curl && has python3 || { err "curl and python3 are required"; return 1; }
    [ -f "$DASH_JSON" ] || { err "$DASH_JSON not found"; return 1; }
    if ! gcurl -sf --max-time 10 -H "Authorization: Bearer $token" "$(gurl "$url")/api/health" >/dev/null; then
        gcurl -s --max-time 8 -o /dev/null "$(gurl "$url")/api/health" 2>/dev/null
        case "$?:$url" in
            60:https://*|51:https://*)  # cert tu ky -> de nghi ghim cert (van kiem tra TLS)
                warn "Grafana uses a self-signed / internal CA cert → not trusted by this host"
                grafana_pin_cert "$url" || return 1
                gcurl -sf --max-time 10 "$(gurl "$url")/api/health" >/dev/null \
                    || { explain_curl_fail "$url" "/api/health" '"database"'; return 1; } ;;
            *) explain_curl_fail "$url" "/api/health" '"database"'; return 1 ;;
        esac
    fi
    grafana_ds_check "$url" "$token" || return 1
    # Khong chi folder -> giu folder hien tai cua dashboard tren Grafana (import de khong
    # tu chuyen dashboard ve General)
    if [ -z "$folder" ]; then
        local duid; duid=$(python3 -c 'import json,sys,re; u=str(json.load(open(sys.argv[1],encoding="utf-8")).get("uid") or ""); print(re.sub(r"[^A-Za-z0-9_]*[^A-Za-z0-9_-][^A-Za-z0-9_]*|-{2,}","-",u).strip("-")[:40])' "$DASH_JSON" 2>/dev/null)
        [ -n "$duid" ] && folder=$(gcurl -s --max-time 10 -H "Authorization: Bearer $token" "$(gurl "$url")/api/dashboards/uid/$duid" 2>/dev/null \
            | python3 -c 'import json,sys; print((json.load(sys.stdin).get("meta") or {}).get("folderUid") or "")' 2>/dev/null)
        [ -n "$folder" ] && info "Keeping the dashboard's current folder (folder uid ${W}$folder${N})"
    fi
    payload=$(mktemp)
    python3 - "$DASH_JSON" "$folder" > "$payload" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["id"] = None
# Grafana chi nhan UID [A-Za-z0-9_-] <= 40 ky tu (file sinh tu ban cu co the sai)
uid = re.sub(r"[^A-Za-z0-9_]*[^A-Za-z0-9_-][^A-Za-z0-9_]*|-{2,}", "-", str(d.get("uid") or "")).strip("-")[:40] or "pve-ceph-prom"
if uid != d.get("uid"):
    sys.stderr.write("UID '%s' -> '%s'\n" % (d.get("uid"), uid))
    d["uid"] = uid
body = {"dashboard": d, "overwrite": True, "message": "proxmox-ceph-monitor.sh import"}
if sys.argv[2]:
    body["folderUid"] = sys.argv[2]
print(json.dumps(body))  # ASCII: khong phu thuoc locale may (LANG=C)
PY
    resp=$(gcurl -s --max-time 30 -X POST -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" --data-binary "@$payload" "$(gurl "$url")/api/dashboards/db")
    case "$resp" in
        *'"message"'*[Pp]ermission*|*'Access denied'*|*'"status":403'*)
            warn "Token lacks permission → the service account needs the Editor role (Viewer is read-only)" ;;
    esac
    rm -f "$payload"
    if echo "$resp" | grep -Eq '"status": *"success"'; then
        ok "Imported: ${W}$url$(echo "$resp" | sed -En 's/.*"url": *"([^"]*)".*/\1/p')${N}"
        save_conf GRAFANA_URL "$url"; save_conf GRAFANA_FOLDER "$folder"
    else
        err "Import failed: $resp"
        case "$resp" in *[Ii]nvalid*[Kk]ey*|*[Uu]nauthorized*|*"status":401*) forget_token ;; esac
        return 1
    fi
}

prom_snippet() {  # prom_snippet JOB PORT [FLAGS] -> in + luu file mau prometheus.yml
    local job="$1" port="$2" flags="${3-$(current_flags)}" ip f
    ip=$(local_ip); f="$DIR/prometheus-target-$job.yml"
    if [ -z "$flags" ]; then
        cat > "$f" <<EOF
# Merged 1 port: this job needs ONLY 1 target (ceph mgr + Proxmox + extras all on :$port)
  - job_name: $job
    scrape_interval: 30s
    scrape_timeout: 25s
    static_configs:
      - targets:
          - $ip:$port   # pve_ceph_extra_exporter (all metrics)
EOF
        info "Job ${W}'$job'${N} needs only ${W}1 target $ip:$port${N}:"
        echo; sed -n '2,$p' "$f" | sed "s/^/${IND}    ${O}/; s/$/${N}/"; echo
        warn "REMOVE this cluster's old ceph mgr (:9283) and pve exporter (:9221) targets from the job,"
        echo "otherwise every value is doubled (menu 12 reports duplicates)." | sub
        info "Sample saved: $f"
        info "On the Prometheus host:"
        printf '%s\n' "promtool check config /etc/prometheus/prometheus.yml" \
            "systemctl reload prometheus      # or: curl -X POST http://<prom>:9090/-/reload" | sub
        return 0
    fi
    cat > "$f" <<EOF
# Add to scrape_configs in prometheus.yml (SAME job as ceph mgr / pve exporter)
  - job_name: $job
    static_configs:
      - targets:
          - $ip:9283   # ceph mgr prometheus (existing)
          - $ip:$port   # pve_ceph_extra_exporter (new)
EOF
    info "Add target ${W}$ip:$port${N} to the ${W}SAME job '$job'${N} as ceph mgr / pve exporter:"
    echo; sed -n '2,$p' "$f" | sed "s/^/${IND}    ${O}/; s/$/${N}/"; echo
    info "Sample saved: $f"
    info "If the job already exists, just add '$ip:$port' to its targets."
    info "On the Prometheus host:"
    printf '%s\n' "promtool check config /etc/prometheus/prometheus.yml" \
        "systemctl reload prometheus      # or: curl -X POST http://<prom>:9090/-/reload" | sub
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
    has curl && has python3 || { err "curl and python3 are required"; return 1; }
    curl -sf --max-time 10 "$url/-/ready" >/dev/null || { err "Cannot connect to $url"; return 1; }
    save_conf PROM_URL "$url"
    port=$(current_port)

    local ports; ports=$(all_ports); [ -n "$ports" ] || ports=$port
    echo; info "Target exporter (up{instance=~\".*:($ports)\"}):"
    out=$(prom_q "$url" "up{instance=~\".*:($ports)\"}")
    if [ -z "$out" ]; then
        err "Prometheus does not scrape the exporter → add the target (menu 10) and reload Prometheus"; rc=1
    else
        local tip myips; myips=" $(hostname -I 2>/dev/null) "
        while read -r l; do
            if [[ "$l" == *" 1" ]]; then ok "$l"; else err "$l (target down)"; rc=1; fi
            # target down vi tro sai may: exporter chay o may nay, target phai la IP may nay
            tip=$(echo "$l" | sed -n 's/.*instance=\([^:,}]*\):.*/\1/p')
            if [ -n "$tip" ] && [ "$myips" != "  " ] && [[ "$myips" != *" $tip "* ]] && [[ "$l" != *" 1" ]]; then
                warn "  ↑ target points to $tip, not this host ($(echo $myips)) → run menu 10 again, just press Enter at the IP question"
                info "  On the Prometheus host check: curl -s http://$(local_ip):<port>/metrics | head -3  (fails → menu 22 opens the firewall)"
            fi
        done <<< "$out"
    fi

    echo; info "Cluster jobs (pve_cluster_info):"
    prom_q "$url" 'count by (job) (pve_cluster_info)' | sub

    echo; info "Duplicate target check (1 cluster scraped twice -> doubled values):"
    out=$(prom_q "$url" 'count by (job) (count by (job, instance) (ceph_health_status)) > 1')
    if [ -n "$out" ]; then
        while read -r l; do err "Duplicate ceph: $l targets → remove the old ceph mgr target (:9283)"; done <<< "$out"; rc=1
    else ok "No job has duplicate ceph metrics"; fi
    out=$(prom_q "$url" 'count by (job) (count by (job, instance) (pve_cluster_info)) > 1')
    if [ -n "$out" ]; then
        while read -r l; do err "Duplicate Proxmox: $l targets → remove the old pve exporter target (:9221)"; done <<< "$out"; rc=1
    else ok "No job has duplicate Proxmox metrics"; fi

    echo; info "Job comparison: ceph mgr ↔ exporter:"
    cj=$(prom_q "$url" 'count by (job) (ceph_health_status)' | sed 's/{job=\(.*\)} .*/\1/')
    ej=$(prom_q "$url" 'count by (job) (ceph_custom_recovery_info)' | sed 's/{job=\(.*\)} .*/\1/')
    printf '%s\n' "ceph mgr : $(echo ${cj:-'<none>'})" "exporter : $(echo ${ej:-'<none>'})" | sub
    for j in $ej; do
        if echo "$cj" | grep -qx "$j"; then ok "job '$j' matches"
        else err "exporter job '$j' has no ceph mgr → the dashboard will not show Recovery"; rc=1; fi
    done

    echo; info "Recovery state per cluster:"
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
    DASH_TITLE=$(ask "Dashboard title" "$DASH_TITLE")
    DASH_UID=$(ask "UID (no spaces; same UID overwrites)" "$DASH_UID")
    local u2; u2=$(echo "$DASH_UID" | sed -E 's/[^A-Za-z0-9_-]+/-/g; s/-{2,}/-/g; s/^-+|-+$//g' | cut -c1-40)
    [ "$u2" != "$DASH_UID" ] && { warn "UID allows only letters, digits, - and _ (max 40) → using '${u2:=pve-ceph-prom}'"; DASH_UID=$u2; }
    DASH_SITE=$(ask "Site datasource regex (empty = all Prometheus)" "$DASH_SITE")
    DASH_JOB=$(ask "Cluster job regex" "$DASH_JOB")
    if detect_sizes; then
        info "Read from Ceph: ${W}$DN${N} node, ${W}$DP${N} pool, ${W}$DC${N} device class"
    else
        DN=$DASH_NODES; DP=$DASH_POOLS; DC=$DASH_CLASSES
    fi
    DASH_NODES=$(ask "Node count (HA table height)" "$DN")
    DASH_POOLS=$(ask "Pool count (pool table height)" "$DP")
    DASH_CLASSES=$(ask "Device class count" "$DC")
    DASH_LAT=$(ask "Latency thresholds ms per class (warning:critical)" "$DASH_LAT")
    DASH_TIME=$(ask "Default time range" "$DASH_TIME")
    if confirm "Set short names + colors for HA Groups?"; then ask_aliases; fi
}

do_dashboard() {
    title "GENERATE GRAFANA DASHBOARD"
    info "${W}1${N} Internal  ${D}- all clusters, Site / Job pickers, detailed alarms, HA Groups, Exporter row${N}"
    info "${W}2${N} Customer  ${D}- locked to 1 cluster, hides Site / Job and internal panels, read-only${N}"
    if [ "$(ask "Dashboard type" "1")" = 2 ]; then do_dashboard_customer; return; fi
    ask_dashboard
    DASH_JSON=$(ask "Output file" "$DASH_JSON")
    if [ "$(cd "$(dirname "$DASH_JSON")" 2>/dev/null && pwd)/$(basename "$DASH_JSON")" = "$DASH_REPO_JSON" ]; then
        warn "$DASH_REPO_JSON is tracked by git → overwriting it blocks updates (menu 14); using $DIR/dashboard-local.json"
        DASH_JSON="$DIR/dashboard-local.json"
    fi
    gen_dashboard || return 1
    save_dash_conf
    info "Import: Grafana → Dashboards → New → Import → Upload JSON, or use menu 11"
}

# Dashboard khach hang: 1 file / khach (dashboard-kh-<job>.json), khoa job, chi 1 datasource.
# Import vao folder rieng cua khach roi cap quyen Viewer cho khach tren folder do.
do_dashboard_customer() {
    has python3 || { err "python3 missing"; return 1; }
    dash_defaults
    local jobs="" job name ds slug title uid out
    if [ -n "${PROM_URL:-}" ]; then
        jobs=$(curl -sG --max-time 10 "$PROM_URL/api/v1/label/job/values" 2>/dev/null \
            | python3 -c 'import json,sys;print(" ".join(j for j in json.load(sys.stdin).get("data",[]) if "Proxmox-" in j))' 2>/dev/null)
        [ -n "$jobs" ] && info "Jobs on Prometheus: ${W}$jobs${N}"
    fi
    job=$(ask "Customer job (cluster)" ""); [ -n "$job" ] || { err "No job entered"; return 1; }
    if [ -n "$jobs" ] && [[ " $jobs " != *" $job "* ]]; then
        warn "Job '$job' not found on $PROM_URL → check the name (case-sensitive)"
        confirm "Continue anyway?" || return 1
    fi
    name=$(ask "Customer name (shown in the title)" "${job#Proxmox-}")
    ds=$(ask "Grafana Prometheus DATASOURCE name holding this job (exact, e.g. Prometheus FPT HCM)" "")
    [ -n "$ds" ] || { err "Datasource name required (the customer only sees this datasource)"; return 1; }
    slug=$(echo "$job" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+|-+$//g')
    title=$(ask "Title" "$name - Proxmox Ceph")
    uid=$(ask "UID (unique for this customer)" "kh-$slug")
    out="$DIR/dashboard-kh-$slug.json"
    # Ten datasource -> regex khop dung 1 ten (escape ky tu dac biet)
    local rx; rx="/^$(printf '%s' "$ds" | sed 's/[][\.^$*+?(){}|/]/\\&/g')\$/"
    python3 "$MAKE_DASH" -o "$out" --customer-job "$job" --site-regex "$rx" --title "$title" --uid "$uid" \
        --nodes "$DASH_NODES" --pools "$DASH_POOLS" --classes "$DASH_CLASSES" \
        --lat-th "$DASH_LAT" --time-from "$DASH_TIME" >/dev/null || { err "Dashboard generation failed"; return 1; }
    ok "Created ${W}$out${N} (locked to job ${W}$job${N}, datasource ${W}$ds${N})"
    info "Permissions: create a folder for the customer in Grafana, import into it, grant the customer Viewer on that folder"
    DASH_JSON=$out
    if confirm "Import to Grafana now?"; then
        local url folder
        url=$(ask "Grafana URL" "${GRAFANA_URL:-}")
        ask_token; [ -n "$TOKEN" ] || { err "No token entered"; return 1; }
        folder=$(ask "Customer folder UID (empty = General)" "")
        import_dashboard "$url" "$TOKEN" "$folder"
    else
        info "Import later: menu 11 → pick $(basename "$out")"
    fi
}

# =============================================================================
# 11. Import dashboard qua Grafana API
# =============================================================================
# Token Grafana: go 1 lan, luu rieng trong .grafana-token (chmod 600, khong nam trong git,
# khong nam trong .menu.conf). Token sai / het han (401) thi tu xoa va hoi lai lan sau.
GRAFANA_TOKEN_FILE="$DIR/.grafana-token"
ask_token() {
    TOKEN=""
    if [ -s "$GRAFANA_TOKEN_FILE" ]; then
        TOKEN=$(cat "$GRAFANA_TOKEN_FILE")
        info "Using the saved Grafana token ${D}($GRAFANA_TOKEN_FILE; delete: menu 15)${N}"
        return 0
    fi
    info "Create a token: Grafana → Administration → Service accounts → Add token (role Editor)"
    read -rsp "${IND}  ${C}❯${N} Service account token ${D}(hidden while typing)${N}: " TOKEN; echo
    if [ -n "$TOKEN" ] && confirm "Save the token so it is not asked again (root-only file)?"; then
        ( umask 077; printf '%s' "$TOKEN" > "$GRAFANA_TOKEN_FILE" ) && ok "Token saved → $GRAFANA_TOKEN_FILE"
    fi
}
forget_token() { [ -f "$GRAFANA_TOKEN_FILE" ] && rm -f "$GRAFANA_TOKEN_FILE" && warn "Saved token removed (invalid / expired) → enter it again next time"; }

do_import() {
    title "IMPORT DASHBOARD TO GRAFANA"
    local url folder f files=() i=1 pick
    # Co dashboard khach hang (dashboard-kh-*.json) -> cho chon file nao
    for f in "$DIR"/dashboard-*.json; do [ -f "$f" ] && files+=("$f"); done
    if [ "${#files[@]}" -gt 1 ]; then
        for f in "${files[@]}"; do info "${W}$i${N} $(basename "$f")"; i=$((i + 1)); done
        pick=$(ask "Which file to import" "1")
        [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#files[@]}" ] || { err "Invalid choice"; return 1; }
        DASH_JSON=${files[$((pick - 1))]}
    fi
    [ -f "$DASH_JSON" ] || { warn "$DASH_JSON not found → generating it first"; do_dashboard || return 1; }
    url=$(ask "Grafana URL" "${GRAFANA_URL:-${ENV_GRAFANA:-http://127.0.0.1:3000}}")
    ask_token
    [ -n "$TOKEN" ] || { err "No token entered"; return 1; }
    folder=$(ask "Folder UID (empty = keep current / General)" "${GRAFANA_FOLDER:-}")
    import_dashboard "$url" "$TOKEN" "$folder"
}

# =============================================================================
# 10. Cau hinh Prometheus
# =============================================================================
do_prom() {
    title "PROMETHEUS CONFIG"
    local job cn
    if [ -f "$UNIT" ]; then
        cn=$(detect_cluster_name)
        job=$(ask "Prometheus job name for this cluster (same as the ceph mgr job)" "${PROM_JOB:-Proxmox-${cn:-CLUSTER}}")
        save_conf PROM_JOB "$job"
        prom_snippet "$job" "$(current_port)"
    fi
    if [ -n "$(remote_names)" ]; then
        [ -f "$UNIT" ] && echo
        prom_all
    elif [ ! -f "$UNIT" ]; then
        warn "No exporter on this host yet → menu 2 (install on a Ceph node) or 17 (remote monitoring)"
    fi
}

# Gop moi exporter tren may nay (local + tung cluster tu xa) thanh 1 file scrape_configs,
# kiem tra tung exporter dang tra metric gi, bo job trung ten (Prometheus khong cho trung).
prom_all() {
    local ip f n p job m bad st jobs="|" cnt=0 skip=0 dn="" cl
    f="$DIR/prometheus-scrape-all.yml"
    while :; do
        ip=$(ask "IP of THIS host (monitor) that Prometheus scrapes - usually just press Enter" "$(local_ip)")
        # Nhap nham IP may Prometheus -> target tro ve chinh Prometheus, khong co du lieu
        if hostname -I 2>/dev/null | tr ' ' '\n' | grep -qx "$ip"; then break; fi
        warn "$ip is not an IP of this host ($(hostname -I 2>/dev/null | xargs)) → the exporters run here, the target must be this host's IP"
        confirm "Use $ip anyway (e.g. NAT IP / VIP)?" && break
    done
    {
        echo "# FIX NHANH - generated by proxmox-ceph-monitor.sh on $(hostname) ($ip) at $(date '+%F %T')"
        echo "# Paste the jobs below under scrape_configs: in prometheus.yml (keep the indentation)."
        echo "scrape_configs:"
    } > "$f"

    printf '%s  %s%-18s %-22s %-20s %s%s\n' "$IND" "$W" "CLUSTER" "JOB" "TARGET" "STATUS" "$N"
    local -A MET
    add_job() {  # add_job TEN JOB PORT -> ghi job vao file (metric da lay san trong MET)
        local name="$1" job="$2" port="$3" up col
        m=${MET[$port]}
        up=$(echo "$m" | sed -n 's/^pve_ceph_extra_exporter_up{collector="\([^"]*\)"} \(.*\)/\1=\2/p')
        bad=$(echo "$up" | sed -n 's/=0$//p' | paste -sd, -)
        cl=$(echo "$m" | sed -n 's/^pve_cluster_info{id="cluster\/\([^"]*\)".*/\1/p' | head -1)
        if [ -z "$m" ]; then st="exporter not responding"; col=$R
        elif [ -n "$bad" ]; then st="failing: $bad"; col=$Y
        else st="OK${cl:+ (cluster $cl)}"; col=$G; fi
        if [[ "$jobs" == *"|$job|"* ]]; then
            st="DUPLICATE JOB → skipped"; col=$R; skip=$((skip + 1))
            echo "  # SKIPPED $name: job '$job' is already used by another cluster (Prometheus forbids duplicate job_name)" >> "$f"
        else
            jobs="$jobs$job|"; cnt=$((cnt + 1))
            cat >> "$f" <<EOF
  # $name - $st
  - job_name: $job
    scrape_interval: 30s
    scrape_timeout: 25s
    static_configs:
      - targets: ['$ip:$port']
EOF
        fi
        printf '%s  %-18s %-22s %-20s %s%s%s\n' "$IND" "$name" "$job" "$ip:$port" "$col" "$st" "$N"
        if [ -n "$cl" ] && [[ "$st" != DUPLICATE* ]]; then
            [[ "$dn" == *"|$cl|"* ]] && warn "  ↑ cluster ${W}$cl${N} is already in another job → duplicate data, remove one (menu 20)"
            dn="$dn|$cl|"
        fi
    }

    local list="" rank
    if [ -f "$UNIT" ]; then
        if [ -n "$(current_flags)" ]; then
            warn "Local exporter runs in non-merged mode (--no-*) → use the separate sample above, not added to this file"
        else
            list="(local)|${PROM_JOB:-Proxmox-$(detect_cluster_name)}|$(current_port)"$'\n'
        fi
    fi
    for n in $(remote_names); do
        job=$(env_get "$REMOTE_DIR/$n.env" JOB)
        list+="$n|${job:-$(default_job "$n")}|$(env_get "$REMOTE_DIR/$n.env" PORT)"$'\n'
    done
    # Lay metric 1 lan / exporter, xep exporter chay tot len truoc: khi 2 cluster trung job
    # thi giu cai dang OK, bo cai loi / khong tra loi.
    local ranked=""
    while IFS='|' read -r n job p; do
        [ -n "$n" ] || continue
        MET[$p]=$(curl -sf --max-time 15 "http://127.0.0.1:$p/metrics" 2>/dev/null)
        if [ -z "${MET[$p]}" ]; then rank=2
        elif echo "${MET[$p]}" | grep -q '^pve_ceph_extra_exporter_up{.*} 0$'; then rank=1
        else rank=0; fi
        ranked+="$rank|$n|$job|$p"$'\n'
    done <<< "$list"
    while IFS='|' read -r rank n job p; do
        [ -n "$n" ] && add_job "$n" "$job" "$p"
    done < <(printf '%s' "$ranked" | sort -t'|' -k1,1n -k2,2)
    {
        echo
        echo "# Alert rules (optional): copy prometheus/pve-ceph-alerts.yml to the Prometheus host and add:"
        echo "# rule_files:"
        echo "#   - /etc/prometheus/rules/pve-ceph-alerts.yml"
    } >> "$f"

    echo
    if has promtool; then
        if promtool check config "$f" >/dev/null 2>&1; then ok "promtool: syntax OK"
        else err "promtool error:"; promtool check config "$f" 2>&1 | sub; fi
    fi
    info "Wrote ${W}$cnt jobs${N} to ${W}$f${N}$([ "$skip" -gt 0 ] && echo " ($skip duplicate jobs skipped)")"
    echo; sed -n '4,$p' "$f" | sed "s/^/${IND}    ${O}/; s/$/${N}/"; echo
    warn "Remove these clusters' old targets (:9283 ceph mgr, :9221 pve exporter) from Prometheus, otherwise values are doubled"
    info "Firewall on this host for the Prometheus IP: menu 22."
    info "${W}Prometheus with split files (scrape_config_files, e.g. /etc/prometheus/scrape_configs/*.yml):${N}"
    echo "copy this WHOLE file into that directory (it already starts with scrape_configs:)" | sub
    printf '%s\n' "scp root@$ip:$f /etc/prometheus/scrape_configs/$(prom_file_name)" | sub
    info "${W}Prometheus single file (default):${N}"
    echo "paste the '- job_name:' blocks under scrape_configs: in prometheus.yml (do not copy the scrape_configs: line)" | sub
    info "Then on the Prometheus host:"
    printf '%s\n' "promtool check config /etc/prometheus/prometheus.yml" \
        "systemctl reload prometheus      # or: curl -X POST http://<prom>:9090/-/reload" | sub
    if [ "$cnt" -gt 0 ] && has ssh && has scp; then
        echo; confirm "Push the file to the Prometheus host over SSH now (duplicate check, promtool, reload)?" && prom_push "$f"
    fi
}

# SSH toi may Prometheus: dung chung 1 ket noi (hoi mat khau toi da 1 lan / 2 phut),
# chua co key thi de nghi tao + ssh-copy-id.
SSH_CM=(-o ControlMaster=auto -o "ControlPath=${TMPDIR:-/tmp}/.monitor-ssh-%C" -o ControlPersist=120 -o ConnectTimeout=10)
rssh() { ssh "${SSH_CM[@]}" "$@"; }
rscp() { scp "${SSH_CM[@]}" "$@"; }

ssh_prepare() {  # ssh_prepare USER@HOST
    ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "$1" true 2>/dev/null && return 0
    warn "No SSH key access to $1 yet → every command would ask for a password"
    if has ssh-copy-id && confirm "Create an SSH key and install it on $1 now (password once, never again)?"; then
        [ -f "$HOME/.ssh/id_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" || return 1
        ssh-copy-id -o StrictHostKeyChecking=accept-new "$1" >/dev/null 2>&1 && ok "Key installed, no more password prompts" \
            || warn "ssh-copy-id failed → you will be asked for the password (once)"
    else
        info "The password will be asked once for this run"
    fi
}

ask_prom_cfg() {  # file prometheus.yml tren may Prometheus (khong phai thu muc / glob)
    case "${PROM_CFG:-}" in *"*"*|*/scrape_configs/*|*/rules/*|*/) PROM_CFG="" ;; esac  # gia tri sai da luu truoc day
    local c
    while :; do
        c=$(ask "MAIN Prometheus config file (usually just press Enter)" "${PROM_CFG:-/etc/prometheus/prometheus.yml}")
        case "$c" in
            *'*'*|*/scrape_configs/*|*/rules/*|*/) err "'$c' is not the main file → enter the prometheus.yml file (e.g. /etc/prometheus/prometheus.yml)" >&2 ;;
            *) echo "$c"; return ;;
        esac
        PROM_CFG=""
    done
}

# Script Python chay TREN may Prometheus (qua ssh stdin): tim / go block "- job_name: X" trong
# cac file scrape. Block bi go khi trung ten job hoac chua target cua exporter.
#   python3 - plan|apply DIR FILE_CUA_TOOL,... JOB1,JOB2 IP:PORT,...
prom_jobs_py() {
    cat <<'PY'
import glob, os, re, sys
mode, d, mine, jobs, tgs = sys.argv[1:6]
mine = set(x for x in mine.split(",") if x)
jobs = set(x for x in jobs.split(",") if x)
tgs = [x for x in tgs.split(",") if x]
start = re.compile(r"^(\s*)-\s*job_name:\s*[\"']?([^\"'\s#]+)")
for path in sorted(glob.glob(os.path.join(d, "*.yml")) + glob.glob(os.path.join(d, "*.yaml"))):
    if os.path.basename(path) in mine:
        continue
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    keep, i, hit = [], 0, []
    while i < len(lines):
        m = start.match(lines[i])
        if not m:
            keep.append(lines[i]); i += 1; continue
        ind, name, j = len(m.group(1)), m.group(2), i + 1
        while j < len(lines):
            s = lines[j]
            if s.strip() and not s.lstrip().startswith("#") and len(s) - len(s.lstrip()) <= ind:
                break
            j += 1
        block = "\n".join(lines[i:j])
        why = "same job name" if name in jobs else ("same target " + ",".join(t for t in tgs if t in block)
                                               if any(t in block for t in tgs) else "")
        if why:
            hit.append((name, i + 1, j, why))
        else:
            keep.extend(lines[i:j])
        i = j
    if not hit:
        continue
    for name, a, b, why in hit:
        print("%s|%s|lines %d-%d|%s" % (os.path.basename(path), name, a, b, why))
    if mode == "apply":
        text = "\n".join(keep)
        if "job_name" in text:
            open(path, "w", encoding="utf-8").write(text)
        else:  # file khong con job nao -> bo (da co ban sao luu)
            os.remove(path); print("%s|(no jobs left -> file removed)" % os.path.basename(path))
PY
}

prom_host_slug() { (hostname -s 2>/dev/null || hostname) | tr 'A-Z' 'a-z'; }
prom_file_name() { echo "proxmox-ceph-$(prom_host_slug).yml"; }      # ten file tren may Prometheus
prom_file_old() { echo "proxmox-fixnhanh-$(hostname -s 2>/dev/null || hostname).yml"; }  # ten cu (ban 9f7a591)

# Day file scrape len may Prometheus dung scrape_config_files: kiem tra job trung o file khac
# (Prometheus se khong khoi dong), canh bao target :9283/:9221 cu, promtool loi thi tra lai file cu.
prom_push() {
    local f="${1:-$DIR/prometheus-scrape-all.yml}" host def dir cfg dst jobs pat out
    [ -s "$f" ] || { err "$f not found → run menu 10 first"; return 1; }
    def=${PROM_SSH:-}
    [ -z "$def" ] && [ -n "${PROM_URL:-}" ] && def="root@$(echo "$PROM_URL" | sed -E 's|^https?://||; s|[:/].*||')"
    host=$(ask "SSH to the Prometheus host (user@ip)" "$def")
    [ -n "$host" ] || { err "No Prometheus host entered"; return 1; }
    ssh_prepare "$host"
    cfg=$(ask_prom_cfg)
    dir=$(ask "scrape_config_files directory" "${PROM_DIR:-/etc/prometheus/scrape_configs}")
    dst="$dir/$(prom_file_name)"

    info "Checking ${W}$host${N}..."
    out=$(rssh "$host" "echo SSH_OK; test -d '$dir' && echo DIR_OK; grep -q '^scrape_config_files:' '$cfg' && echo CFG_OK; command -v promtool >/dev/null && echo PROMTOOL_OK; true" 2>&1)
    [[ "$out" == *SSH_OK* ]] || { err "SSH to $host failed:"; echo "$out" | sub; info "Key-based SSH login is required: ssh-copy-id $host"; return 1; }
    [[ "$out" == *DIR_OK* ]] || { err "Directory $dir does not exist on $host"; return 1; }
    [[ "$out" == *CFG_OK* ]] || warn "$cfg has no 'scrape_config_files:' pointing to $dir → Prometheus will not read this file"
    [[ "$out" == *PROMTOOL_OK* ]] || warn "No promtool on the Prometheus host → skipping the syntax check"
    save_conf PROM_SSH "$host"; save_conf PROM_DIR "$dir"; save_conf PROM_CFG "$cfg"

    jobs=$(sed -n 's/^  - job_name: //p' "$f" | paste -sd'|' -)
    local mine="^($(prom_file_name)|$(prom_file_old)):" old="$dir/$(prom_file_old)"
    # Job cu o file khac: trung job_name (Prometheus khong khoi dong) hoac cung target exporter
    # (trung du lieu) -> de nghi THAY THE: sao luu ca thu muc, go dung cac block job do.
    local tg bak=""
    tg=$(grep -oE "[0-9.]+:[0-9]+" "$f" | sort -u | paste -sd, -)
    out=$(rssh "$host" "PYTHONIOENCODING=utf-8 python3 - plan '$dir' '$(prom_file_name),$(prom_file_old)' '${jobs//|/,}' '$tg'" < <(prom_jobs_py) 2>&1)
    if [ -n "$out" ]; then
        warn "Existing Prometheus jobs with the same name / target as the exporter:"
        echo "$out" | sed 's/|/  ·  /g' | sub
        info "Replace = back up all of $dir, remove the jobs above from the old files, add the exporter jobs; restore everything if promtool fails"
        confirm "Replace the old jobs with the exporter?" || { info "Kept as is. Change JOB in menu 17 to run both side by side"; return 1; }
        bak="${PROM_BAK_BASE:-/root}/prom-bak-$(date +%Y%m%d-%H%M%S)"
        out=$(rssh "$host" "cp -a '$dir' '$bak' && PYTHONIOENCODING=utf-8 python3 - apply '$dir' '$(prom_file_name),$(prom_file_old)' '${jobs//|/,}' '$tg'" < <(prom_jobs_py) 2>&1) || {
            err "Removing old jobs failed:"; echo "$out" | sub
            rssh "$host" "[ -d '$bak' ] && find '$dir' -maxdepth 1 -type f \\( -name '*.yml' -o -name '*.yaml' \\) -delete && cp -a '$bak/.' '$dir/'" \
                && warn "Restored $dir from $bak"
            return 1; }
        echo "$out" | sub
        ok "Backup: ${W}$host:$bak${N}"
    fi
    out=$(rssh "$host" "cd '$dir' && grep -HnE ':(9283|9221)\\b' *.yml *.yaml 2>/dev/null | grep -vE '$mine'")
    if [ -n "$out" ]; then
        warn "Existing ceph mgr / pve exporter targets (REMOVE them if they are the same cluster, otherwise values double):"
        echo "$out" | sub
    fi

    restore_bak() {  # tra lai thu muc da sao luu (khi da go job cu ma buoc sau loi)
        [ -n "$bak" ] && rssh "$host" "find '$dir' -maxdepth 1 -type f \\( -name '*.yml' -o -name '*.yaml' \\) -delete; cp -a '$bak/.' '$dir/'" \
            && warn "Restored $dir from $bak"
    }
    confirm "Copy file → ${W}$host:$dst${N} and reload Prometheus?" || { restore_bak; info "Cancelled"; return 0; }
    rscp -q "$f" "$host:$dst.new" || { err "scp failed"; restore_bak; return 1; }
    # File ten cu (proxmox-fixnhanh-*) cung chua cac job nay -> cat di, loi thi tra lai
    out=$(rssh "$host" "cp -p '$dst' '$dst.bak' 2>/dev/null; mv '$dst.new' '$dst'
        [ -f '$old' ] && mv '$old' '$old.old'
        if command -v promtool >/dev/null && ! promtool check config '$cfg' >/tmp/.promcheck 2>&1; then
            if [ -f '$dst.bak' ]; then mv '$dst.bak' '$dst'; else rm -f '$dst'; fi
            [ -f '$old.old' ] && mv '$old.old' '$old'
            if [ -n '$bak' ]; then find '$dir' -maxdepth 1 -type f \\( -name '*.yml' -o -name '*.yaml' \\) -delete; cp -a '$bak/.' '$dir/'; fi
            cat /tmp/.promcheck; echo CHECK_FAIL; exit 1
        fi
        rm -f '$old.old'
        systemctl reload prometheus 2>/dev/null || curl -sf -X POST http://127.0.0.1:9090/-/reload || { echo RELOAD_FAIL; exit 1; }
        echo PUSH_OK" 2>&1)
    if [[ "$out" == *PUSH_OK* ]]; then
        ok "Copied ${W}$dst${N} and reloaded Prometheus"
        info "Check the targets: menu 12 (after ~1 minute)"
        echo; confirm "Also push the alert rules (prometheus/pve-ceph-alerts.yml)?" && prom_rules_push "$host" "$cfg"
    elif [[ "$out" == *CHECK_FAIL* ]]; then
        err "promtool error → old files restored, Prometheus unaffected:"; echo "$out" | grep -v CHECK_FAIL | sub; return 1
    else
        err "File copied but reload failed → on the Prometheus host: systemctl reload prometheus"; echo "$out" | sub; return 1
    fi
}

# Day prometheus/pve-ceph-alerts.yml len may Prometheus: dat vao thu muc rule_files dang dung
# (them dong rule_files neu thieu), promtool check rules + config, loi thi tra lai ca 2 file.
prom_rules_push() {
    local src="$DIR/prometheus/pve-ceph-alerts.yml" host="${1:-}" cfg="${2:-}" out e entries="" def dir dst covered="" add=""
    [ -s "$src" ] || { err "$src not found"; return 1; }
    has ssh && has scp || { err "ssh and scp are required"; return 1; }
    [ -n "$host" ] || host=$(ask "SSH to the Prometheus host (user@ip)" "${PROM_SSH:-}")
    [ -n "$host" ] || { err "No Prometheus host entered"; return 1; }
    ssh_prepare "$host"
    [ -n "$cfg" ] || cfg=$(ask_prom_cfg)

    out=$(rssh "$host" "echo SSH_OK; command -v promtool >/dev/null && echo PROMTOOL_OK
        grep -q '^rule_files:[[:space:]]*\$' '$cfg' && echo RF_BLOCK
        grep -q '^rule_files:' '$cfg' && echo RF_KEY
        sed -n '/^rule_files:/,/^[^[:space:]#-]/p' '$cfg' | sed -n 's/^[[:space:]]*-[[:space:]]*/RF:/p'; true" 2>&1)
    [[ "$out" == *SSH_OK* ]] || { err "SSH to $host failed:"; echo "$out" | sub; info "ssh-copy-id $host"; return 1; }
    [[ "$out" == *PROMTOOL_OK* ]] || warn "No promtool on the Prometheus host → rules cannot be checked before reload"
    entries=$(echo "$out" | sed -n "s/^RF://p" | tr -d "\"'" | sed 's/[[:space:]]*#.*//')

    # Mac dinh: thu muc cua dong rule_files dang dung glob (vd /etc/prometheus/rules/*.yml)
    def=$(echo "$entries" | grep '\*' | head -1); def=${def%/*}
    dir=$(ask "Rules directory on the Prometheus host" "${PROM_RULES_DIR:-${def:-/etc/prometheus/rules}}")
    dst="$dir/pve-ceph-alerts.yml"
    while IFS= read -r e; do
        # shellcheck disable=SC2053  # e la glob cua Prometheus, co y de khop mau
        [ -n "$e" ] && [[ "$dst" == $e ]] && covered=1
    done <<< "$entries"
    if [ -z "$covered" ]; then
        if [[ "$out" == *RF_BLOCK* ]] || [[ "$out" != *RF_KEY* ]]; then
            warn "$cfg does not load $dir → will add '  - $dir/*.yml' to rule_files (backup $cfg.bak)"
            add=1
        else
            err "$cfg has a one-line rule_files ([...]) → add '$dir/*.yml' there by hand and run again"; return 1
        fi
    fi
    save_conf PROM_SSH "$host"; save_conf PROM_CFG "$cfg"; save_conf PROM_RULES_DIR "$dir"

    confirm "Copy alert rules → ${W}$host:$dst${N} and reload Prometheus?" || { info "Cancelled"; return 0; }
    rssh "$host" "mkdir -p '$dir'" && rscp -q "$src" "$host:$dst.new" || { err "Copy failed"; return 1; }
    out=$(rssh "$host" "cp -p '$dst' '$dst.bak' 2>/dev/null; mv '$dst.new' '$dst'
        if [ '$add' = 1 ]; then
            cp -p '$cfg' '$cfg.bak'
            if grep -q '^rule_files:' '$cfg'; then sed -i '/^rule_files:[[:space:]]*\$/a\\  - $dir/*.yml' '$cfg'
            else printf '\nrule_files:\n  - %s/*.yml\n' '$dir' >> '$cfg'; fi
        fi
        if command -v promtool >/dev/null && ! { promtool check rules '$dst' && promtool check config '$cfg'; } >/tmp/.promcheck 2>&1; then
            if [ -f '$dst.bak' ]; then mv '$dst.bak' '$dst'; else rm -f '$dst'; fi
            [ '$add' = 1 ] && mv '$cfg.bak' '$cfg'
            cat /tmp/.promcheck; echo CHECK_FAIL; exit 1
        fi
        systemctl reload prometheus 2>/dev/null || curl -sf -X POST http://127.0.0.1:9090/-/reload || { echo RELOAD_FAIL; exit 1; }
        echo PUSH_OK" 2>&1)
    if [[ "$out" == *PUSH_OK* ]]; then
        ok "Copied ${W}$dst${N}$([ "$add" = 1 ] && echo ", added rule_files to $cfg") and reloaded Prometheus"
        info "View alerts: ${PROM_URL:-http://<prometheus>:9090}/alerts  (Telegram / email delivery: configure Alertmanager)"
    elif [[ "$out" == *CHECK_FAIL* ]]; then
        err "promtool error → old files restored, Prometheus unaffected:"; echo "$out" | grep -v CHECK_FAIL | sub; return 1
    else
        err "File copied but reload failed → on the Prometheus host: systemctl reload prometheus"; echo "$out" | sub; return 1
    fi
}

# =============================================================================
# 12. Kiem tra phia Prometheus
# =============================================================================
do_prom_check() {
    title "CHECK DATA ON PROMETHEUS"
    prom_check "$(ask "Prometheus URL" "${PROM_URL:-${ENV_PROM:-http://127.0.0.1:9090}}")"
}

# =============================================================================
# 13. Kiem tra tong the
# =============================================================================
do_doctor() {
    do_check
    if [ -f "$UNIT" ]; then do_status; else warn "Exporter not installed on this host"; fi
    if [ -n "${PROM_URL:-}" ] && [ "${NONINTERACTIVE:-0}" = 0 ]; then
        confirm "Also check Prometheus $PROM_URL?" && prom_check "$PROM_URL"
    fi
}

# =============================================================================
# 17-20. Theo doi tu xa: exporter chay tren may monitor, lay du lieu qua API
#        Proxmox (token chi doc) + ceph mgr :9283. 1 cluster = 1 service @<ten>.
# =============================================================================
default_job() { case "$1" in Proxmox-*) echo "$1" ;; *) echo "Proxmox-$1" ;; esac; }  # khong lap "Proxmox-Proxmox-"
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
        else err "$label: ${e:-no data}"; [ "$name" = pve ] || [ "$name" = ceph ] && rc=1; fi
    done
    local cl; cl=$(echo "$out" | sed -n 's/^pve_cluster_info{id="cluster\/\([^"]*\)".*nodes="\([^"]*\)".*/\1 (\2 nodes)/p')
    [ -n "$cl" ] && info "Cluster read: ${W}$cl${N}"
    echo "$out" | grep -q 'HTTP Error 401' && \
        warn "401 = wrong token / secret. Check the Token ID and secret (menu 17 → re-enter the secret)"
    if echo "$out" | grep -q 'HTTP Error 403\|Permission'; then
        local tid user; tid=$(env_get "$1" PVE_TOKEN); tid=${tid%%=*}; user=${tid%%!*}
        warn "403 = token lacks read access (Sys.Audit on /). Run on one node of the cluster:"
        printf '%s\n' "pveum acl modify / --users '$user' --roles PVEAuditor" \
            "pveum acl modify / --tokens '$tid' --roles PVEAuditor   # token created with Privilege Separation" | sub
        info "Check privsep: pveum user token list '$user'  (privsep = 1 needs the second command)"
    fi
    echo "$out" | grep -q 'CERTIFICATE_VERIFY_FAILED' && \
        warn "Proxmox cert is self-signed / untrusted CA (PVE_VERIFY_TLS=$(env_get "$1" PVE_VERIFY_TLS)) → press Enter (N) at 'Does Proxmox have a valid cert'"
    echo "$out" | grep -q 'standby' && \
        warn "All mgrs tried are standby (only the active mgr returns metrics) → enter ALL nodes at the IP question so each is tried; active mgr: 'ceph mgr stat'"
    echo "$out" | grep -qi 'refused' && \
        warn "Connection refused = host reachable but port closed. :9283 → on the cluster run 'ceph mgr module enable prometheus', see the address with 'ceph mgr services'; :8006 → pveproxy"
    echo "$out" | grep -qi 'timed out\|unreachable\|No route' && \
        warn "Cannot connect → check this host to node:8006 and mgr:9283 (firewall)"
    return $rc
}

token_help() {
    box_top
    box_center "${W}${Y}CREATE A READ-ONLY API TOKEN (run once on any node of the cluster)${N}"
    box_sep
    box_row "${O}pveum user add monitor@pve --comment \"FIX NHANH monitor\"${N}"
    box_row "${O}pveum acl modify / --users monitor@pve --roles PVEAuditor${N}"
    box_row "${O}pveum user token add monitor@pve exporter --privsep 0${N}"
    box_sep
    box_row "${D}PVEAuditor can only READ, it cannot change VMs / config / Ceph.${N}"
    box_row "${D}The last command prints 'value' = secret (shown once) → used below.${N}"
    box_row "${D}Ceph mgr: ceph mgr module enable prometheus (opens :9283 on the mgrs).${N}"
    box_bottom
}

do_remote_add() {  # do_remote_add [TEN] -> them / sua 1 cluster
    title "ADD / EDIT CLUSTER (REMOTE MONITORING)"
    need_root || return 1
    has python3 || { err "python3 missing (apt install python3)"; return 1; }
    token_help; echo
    local name="${1:-}" f hosts tid secret verify mgr job port tmp
    [ -n "$name" ] || name=$(ask "Cluster name (no spaces, e.g. FPT-HCM)" "")
    [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || { err "Invalid name: '$name'"; return 1; }
    f="$REMOTE_DIR/$name.env"
    [ -f "$f" ] && info "Cluster ${W}$name${N} exists → current values shown, Enter keeps them"

    hosts=$(ask "Proxmox node IPs / names, comma separated (several nodes = failover when one dies)" "$(env_get "$f" PVE_API)")
    hosts=${hosts// /}  # "a, b" -> "a,b": file .env bi source, dau cach lam hong dong
    local other h oh
    for other in $(remote_names); do  # cung node da theo doi o cluster khac -> du lieu trung 2 job
        [ "$other" = "$name" ] && continue
        for h in ${hosts//,/ }; do
            for oh in $(env_get "$REMOTE_DIR/$other.env" PVE_API | tr ',' ' '); do
                [ "${h#*://}" = "${oh#*://}" ] || continue
                warn "Node ${W}$h${N} is already in cluster ${W}$other${N} (port $(env_get "$REMOTE_DIR/$other.env" PORT)) → Prometheus would get 2 jobs with the same data"
                info "Edit that cluster: menu 17 with name ${W}$other${N}; or remove it: menu 20"
                confirm "Add ${W}$name${N} anyway?" || return 1
                break 3
            done
        done
    done
    [ -n "$hosts" ] || { err "At least 1 node is required"; return 1; }
    local oldtok; oldtok=$(env_get "$f" PVE_TOKEN)
    local deftid="monitor@pve!exporter"; [ -n "$oldtok" ] && deftid=${oldtok%%=*}
    tid=$(ask "Token ID" "$deftid")
    [[ "$tid" == root@pam!* ]] && warn "root@pam token: created in the web UI with Privilege Separation by default → no permissions (403). Prefer monitor@pve!exporter + PVEAuditor (box above)"
    if [ -n "$oldtok" ] && [ "$tid" = "${oldtok%%=*}" ]; then
        read -rsp "${IND}  ${C}❯${N} Token secret ${D}(hidden; Enter = keep the old secret)${N}: " secret; echo
        [ -n "$secret" ] || secret=${oldtok#*=}
    else  # token moi / doi Token ID: secret cu thuoc token khac -> bat buoc nhap
        read -rsp "${IND}  ${C}❯${N} Token secret of ${W}$tid${N} ${D}(hidden)${N}: " secret; echo
    fi
    [ -n "$secret" ] || { err "No token secret entered"; return 1; }
    verify=$(ask "Does Proxmox have a valid cert (Let's Encrypt / internal CA)? (y/N - default Proxmox cert: Enter)" \
        "$([ "$(env_get "$f" PVE_VERIFY_TLS)" = 1 ] && echo y || echo N)")
    # CEPH_MGR trong = exporter tu thu moi node cua cluster de tim mgr active.
    # File cu ghi san "cac node PVE_API:9283" -> coi nhu trong de duoc tu do.
    local oldmgr; oldmgr=$(env_get "$f" CEPH_MGR)
    mgrdef() { echo "$1" | tr ',' '\n' | sed 's|^ *https\?://||; s|:.*||; s|$|:9283|' | paste -sd,; }
    [ "$oldmgr" = "$(mgrdef "$hosts")" ] || [ "$oldmgr" = "$(mgrdef "$(env_get "$f" PVE_API)")" ] && oldmgr=""
    mgr=$(ask "Ceph mgr host:9283, comma separated (Enter = auto-find the active mgr on every node)" "$oldmgr")
    mgr=${mgr// /}
    # Nhap nham so port (vd 9831 = port exporter) vao day -> exporter coi "9831" la ten may
    while [ -n "$mgr" ] && echo "$mgr" | tr ',' '\n' | grep -qE '^[0-9]+$'; do
        err "'$mgr': each entry must be an IP / hostname (e.g. 10.2.50.11:9283), not a port number. The exporter port is asked next"
        mgr=$(ask "Ceph mgr host:9283 (Enter = auto-find)" ""); mgr=${mgr// /}
    done
    job=$(ask "Prometheus job name (must contain 'Proxmox-' for the dashboard)" "$(env_get "$f" JOB)")
    job=${job:-$(default_job "$name")}
    port=$(ask "Exporter port on this host" "$(env_get "$f" PORT)")
    port=${port:-$(next_free_port)}
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || { err "Invalid port: $port"; return 1; }
    case "$port" in 9283|9221)
        warn "Port $port is the default port of $([ "$port" = 9283 ] && echo "ceph mgr" || echo "pve exporter") → easy to confuse targets in prometheus.yml (suggested: $(next_free_port))" ;;
    esac

    install -d -m 0700 "$REMOTE_DIR"
    tmp=$(mktemp "$REMOTE_DIR/.new.XXXX")
    cat > "$tmp" <<EOF
# FIX NHANH - cluster $name (generated by proxmox-ceph-monitor.sh $(date '+%F %T'))
JOB=$job
PORT=$port
PVE_API=$hosts
PVE_TOKEN=$tid=$secret
PVE_VERIFY_TLS=$([[ "$verify" =~ ^[YyCc] ]] && echo 1 || echo 0)
CEPH_MGR=$mgr
INTERVAL=30
EOF
    chmod 600 "$tmp"

    echo; info "Testing the connection to cluster ${W}$name${N}..."
    while ! remote_test "$tmp"; do
        if [ "$(env_get "$tmp" PVE_VERIFY_TLS)" = 1 ] && [[ "$REMOTE_TEST_OUT" == *CERTIFICATE_VERIFY_FAILED* ]] \
            && confirm "Disable TLS verification (PVE_VERIFY_TLS=0) and test again?"; then
            sed -i 's/^PVE_VERIFY_TLS=1$/PVE_VERIFY_TLS=0/' "$tmp"
            echo; info "Testing again with PVE_VERIFY_TLS=0..."
            continue
        fi
        confirm "Connection not OK. Save and start the service anyway?" || { rm -f "$tmp"; info "Cancelled - nothing saved"; return 1; }
        break
    done
    mv -f "$tmp" "$f"
    remote_install_files || { err "Installing files failed"; return 1; }
    systemctl enable "$SERVICE@$name" >/dev/null 2>&1
    systemctl restart "$SERVICE@$name"
    sleep 3
    if curl -sf --max-time 60 "http://127.0.0.1:$port/metrics" | grep -q '^pve_ceph_extra_exporter_up'; then
        ok "Service ${W}$SERVICE@$name${N} running at ${W}http://$(local_ip):$port/metrics${N}"
    else
        err "Service returns no metrics yet → journalctl -u $SERVICE@$name -n 30"; return 1
    fi
    echo; prom_snippet "$job" "$port" ""
}

do_remote_list() {
    title "REMOTE CLUSTERS"
    local names; names=$(remote_names)
    if [ -z "$names" ]; then info "No cluster yet (menu 17 to add)"; return 0; fi
    printf '%s  %s%-16s %-6s %-10s %-22s %-16s %-6s %-5s %-5s %s%s\n' "$IND" "$W" "CLUSTER" "PORT" "SERVICE" \
        "JOB" "REAL CLUSTER" "PVE" "CEPH" "MGR" "HA" "$N"
    local n f p st m c real dup=""
    local -A MET REAL CNT JOBN
    for n in $names; do  # lay metric truoc de biet 2 cau hinh nao cung doc 1 cluster / trung job
        f="$REMOTE_DIR/$n.env"; p=$(env_get "$f" PORT)
        MET[$n]=$(curl -sf --max-time 10 "http://127.0.0.1:$p/metrics" 2>/dev/null)
        real=$(echo "${MET[$n]}" | sed -n 's/^pve_cluster_info{id="cluster\/\([^"]*\)".*/\1/p' | head -1)
        REAL[$n]=$real; [ -n "$real" ] && CNT[$real]=$(( ${CNT[$real]:-0} + 1 ))
        c=$(env_get "$f" JOB); c=${c:-$(default_job "$n")}; JOBN[$c]=$(( ${JOBN[$c]:-0} + 1 ))
    done
    for n in $names; do
        f="$REMOTE_DIR/$n.env"; p=$(env_get "$f" PORT); m=${MET[$n]}; real=${REAL[$n]}
        st=$(systemctl is-active "$SERVICE@$n" 2>/dev/null)
        [ "$st" != active ] && has docker && [ "$(container_state "$n")" = running ] && st=docker
        c() { local v; v=$(echo "$m" | sed -n "s/^pve_ceph_extra_exporter_up{collector=\"$1\"} //p")
              if [ "$v" = 1 ]; then printf '%s✔%s' "$G" "$N"; elif [ -z "$v" ]; then printf '%s-%s' "$D" "$N"; else printf '%s✘%s' "$R" "$N"; fi; }
        local rc=$D jc="" job; job=$(env_get "$f" JOB); job=${job:-$(default_job "$n")}
        [ -n "$real" ] && rc=$C
        [ -n "$real" ] && [ "${CNT[$real]:-0}" -gt 1 ] && { rc=$R; dup+=" $n"; }
        [ "${JOBN[$job]:-0}" -gt 1 ] && { jc=$R; dup+=" $n"; }
        printf '%s  %-16s %-6s %s%-10s%s %s%-22s%s %s%-16s%s %s     %s     %s     %s\n' "$IND" "$n" "$p" \
            "$([ "$st" = active ] || [ "$st" = docker ] && echo "$G" || echo "$R")" "$st" "$N" \
            "$jc" "$job" "$N" "$rc" "${real:--}" "$N" \
            "$(c pve)" "$(c ceph)" "$(c ceph_mgr)" "$(c ha)"
    done
    echo
    if [ -n "$dup" ]; then
        warn "Red rows: 2 configs read the same cluster (REAL CLUSTER) or share a JOB → doubled values on the dashboard"
        info "Keep the one that is ✔, remove the other: menu 20"
    fi
    info "Error details: curl -s http://127.0.0.1:<port>/metrics | grep last_error"
    info "Log: journalctl -u $SERVICE@<cluster> -n 30"
}

pick_remote() {  # chon 1 cluster -> in ten
    local names; names=$(remote_names)
    [ -n "$names" ] || { err "No cluster yet"; return 1; }
    info "Clusters: ${W}$(echo $names)${N}" >&2
    ask "Cluster name" "$(echo "$names" | head -1)"
}

do_remote_test() {
    title "TEST CLUSTER CONNECTION"
    local n; n=$(pick_remote) || return 1
    [ -f "$REMOTE_DIR/$n.env" ] || { err "No cluster '$n'"; return 1; }
    remote_test "$REMOTE_DIR/$n.env"
}

do_remote_remove() {
    title "REMOVE REMOTE CLUSTER"
    need_root || return 1
    local n; n=$(pick_remote) || return 1
    [ -f "$REMOTE_DIR/$n.env" ] || { err "No cluster '$n'"; return 1; }
    confirm "Stop the service and delete the config of cluster '$n' (the token is deleted too)?" || { info "Cancelled"; return 0; }
    systemctl disable --now "$SERVICE@$n" >/dev/null 2>&1
    has docker && docker rm -f "$(container_of "$n")" >/dev/null 2>&1
    rm -f "$REMOTE_DIR/$n.env"
    ok "Removed $n - remember to drop its target from Prometheus"
}

# =============================================================================
# 21. Cai goi can thiet  22. Mo firewall  23. Chay bang Docker  24. Quan ly container
# =============================================================================
pkg_manager() {
    local m
    for m in apt-get dnf yum zypper pacman apk; do has "$m" && { echo "$m"; return; }; done
}

do_deps() {
    title "INSTALL REQUIRED PACKAGES"
    need_root || return 1
    local pm pk missing="" c
    pm=$(pkg_manager)
    [ -n "$pm" ] || { err "No known package manager found (apt/dnf/yum/zypper/pacman/apk)"; return 1; }
    info "OS: ${W}${ENV_OS:-?}${N} · package manager: ${W}$pm${N}"
    for c in git python3 curl ss; do
        if has "$c"; then ok "$c"; else warn "Missing $c"; missing+=" $c"; fi
    done
    [ -n "$missing" ] || { ok "All packages present, nothing to install"; return 0; }
    case "$pm" in
        apt-get) pk="git python3 curl iproute2" ;;
        dnf|yum) pk="git python3 curl iproute" ;;
        zypper)  pk="git python3 curl iproute2" ;;
        pacman)  pk="git python curl iproute2" ;;
        apk)     pk="bash git python3 curl iproute2" ;;
    esac
    confirm "Install with $pm: $pk ?" || { info "Cancelled"; return 0; }
    case "$pm" in
        apt-get) { apt-get update -qq || warn "apt update failed (enterprise repo?), trying to install anyway"; }
                 DEBIAN_FRONTEND=noninteractive apt-get install -y $pk ;;
        dnf|yum) $pm install -y $pk ;;
        zypper)  zypper -n install $pk ;;
        pacman)  pacman -Sy --noconfirm --needed $pk ;;
        apk)     apk add $pk ;;
    esac 2>&1 | tail -5 | sub
    for c in git python3 curl; do has "$c" && ok "$c" || err "Still missing $c"; done
}

do_firewall() {
    title "OPEN FIREWALL FOR PROMETHEUS"
    need_root || return 1
    local ports src p fw=""
    ports=$(all_ports | tr '|' ' ')
    [ -n "$ports" ] || ports=$(current_port)
    info "Exporter ports on this host: ${W}$ports${N}"
    src=$(ask "Prometheus host IP allowed to connect (e.g. 10.16.16.24)" "${PROM_IP:-}")
    [[ "$src" =~ ^[0-9a-fA-F.:/]+$ ]] || { err "Invalid IP: $src"; return 1; }
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
        firewall-cmd -q --reload && ok "firewalld: opened $ports for $src"
    fi
    if has pve-firewall && pve-firewall status 2>/dev/null | grep -q "enabled/running"; then
        fw="$fw pve-firewall"
        for p in $ports; do
            pvesh create /cluster/firewall/rules --action ACCEPT --type in --proto tcp --dport "$p" \
                --source "$src" --enable 1 --comment "FIX NHANH exporter" >/dev/null 2>&1 \
                && ok "pve-firewall: opened $p for $src" || err "pve-firewall: cannot add a rule for port $p"
        done
    fi
    if [ -z "$fw" ]; then
        info "No active ufw / firewalld / pve-firewall → nothing to open"
    else
        ok "Firewall updated:${W}$fw${N}"
    fi
    info "If a network firewall sits between the hosts (pfSense, FortiGate...), open tcp $ports from $src"
}

DOCKER_IMAGE=fixnhanh/pve-ceph-exporter
docker_ok() {
    has docker || { err "Docker not installed → curl -fsSL https://get.docker.com | sh"; return 1; }
    docker info >/dev/null 2>&1 || { err "Docker is not running → systemctl enable --now docker"; return 1; }
}
container_of() { echo "fixnhanh-pve-$1"; }
container_state() { docker inspect -f '{{.State.Status}}' "$(container_of "$1")" 2>/dev/null; }

do_docker_run() {
    title "RUN CLUSTERS IN DOCKER"
    need_root || return 1
    docker_ok || return 1
    local names sel list n f p ver c
    names=$(remote_names)
    [ -n "$names" ] || { err "No cluster yet → add one in menu 17 first (Docker reuses that config file)"; return 1; }
    info "Clusters: ${W}$(echo $names)${N}"
    sel=$(ask "Which clusters to run in Docker (names separated by spaces, or all)" "all")
    if [ "$sel" = all ]; then list=$names; else list=$sel; fi

    ver=$(docker_build_image) || return 1
    for n in $list; do docker_run_cluster "$n" "$ver"; done
    info "Prometheus target unchanged: $(local_ip):<port> as with systemd"
}

docker_build_image() {  # build image theo VERSION cua exporter -> in version (da co thi bo qua)
    local ver; ver=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$EXPORTER_SRC")
    if docker image inspect "$DOCKER_IMAGE:$ver" >/dev/null 2>&1; then
        info "Image ${W}$DOCKER_IMAGE:$ver${N} already exists" >&2
    else
        info "Build image ${W}$DOCKER_IMAGE:$ver${N}..." >&2
        docker build -q -t "$DOCKER_IMAGE:$ver" -t "$DOCKER_IMAGE:latest" "$DIR/exporter" 2>&1 | sub >&2
        docker image inspect "$DOCKER_IMAGE:$ver" >/dev/null 2>&1 || { err "Image build failed" >&2; return 1; }
    fi
    echo "$ver"
}

docker_run_cluster() {  # docker_run_cluster TEN VERSION -> (tao lai) container cua cluster, kiem tra metric
    local n="$1" ver="$2" f p c
    f="$REMOTE_DIR/$n.env"
    [ -f "$f" ] || { err "No cluster '$n'"; return 1; }
    p=$(env_get "$f" PORT); c=$(container_of "$n")
    if [ "$(systemctl is-active "$SERVICE@$n" 2>/dev/null)" = active ]; then
        info "$n: stopping the systemd service to move to Docker (same port $p)"
        systemctl disable --now "$SERVICE@$n" >/dev/null 2>&1
    fi
    docker rm -f "$c" >/dev/null 2>&1
    if ! docker run -d --name "$c" --restart unless-stopped -p "$p:$p" --env-file "$f" \
            --memory 256m --cpus 0.25 --read-only --cap-drop ALL \
            --security-opt no-new-privileges "$DOCKER_IMAGE:$ver" >/dev/null; then
        err "$n: docker run failed"; return 1
    fi
    sleep 5
    if curl -sf --max-time 60 "http://127.0.0.1:$p/metrics" | grep -q '^pve_ceph_extra_exporter_up'; then
        ok "$n: container ${W}$c${N} ($ver) running at ${W}http://$(local_ip):$p/metrics${N}"
    else
        err "$n: container returns no metrics yet → docker logs $c"; return 1
    fi
}

# =============================================================================
# refresh: chay sau git pull, KHONG hoi gi - dung cau hinh da luu (.menu.conf, token .grafana-token)
#   cd /root/monitor-grafana-proxmox-full && git pull && bash proxmox-ceph-monitor.sh refresh
# =============================================================================
do_refresh() {
    title "UPDATE EVERYTHING ($(tool_rev))"
    local fail=()
    echo "${IND}  ${W}[1/4] Exporter${N}"
    if [ "$(id -u)" != 0 ]; then warn "Root is required to reinstall the exporter → skipped"
    else
        if [ -f "$UNIT" ]; then
            install -m 0755 "$EXPORTER_SRC" "$BIN" && systemctl restart "$SERVICE" \
                && ok "Local exporter: version $(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$BIN")" || fail+=("exporter local")
        fi
        if [ -n "$(remote_names)" ]; then
            remote_refresh_after_update >/dev/null || fail+=("exporter remote")
            # Cluster chay Docker: build image ban moi (neu chua co) roi tao lai container, cung port
            local n dk=() cur ver
            for n in $(remote_names); do has docker && [ "$(container_state "$n")" = running ] && dk+=("$n"); done
            if [ "${#dk[@]}" -gt 0 ]; then
                if ver=$(docker_build_image); then
                    for n in "${dk[@]}"; do
                        cur=$(docker inspect -f '{{.Config.Image}}' "$(container_of "$n")" 2>/dev/null)
                        if [ "$cur" = "$DOCKER_IMAGE:$ver" ]; then ok "$n: container already on $ver"
                        else docker_run_cluster "$n" "$ver" || fail+=("container $n"); fi
                    done
                else fail+=("build image"); fi
            fi
            for n in $(remote_names); do
                [ "$(systemctl is-active "$SERVICE@$n" 2>/dev/null)" = active ] && ok "$n: systemd service restarted on the new version"
            done
        fi
        [ -f "$UNIT" ] || [ -n "$(remote_names)" ] || info "No exporter on this host"
    fi

    echo; echo "${IND}  ${W}[2/4] Dashboard${N}"
    dash_update_all || fail+=("${DASH_FAIL[@]}")
    ha_timer_on

    echo; echo "${IND}  ${W}[3/4] Services${N}"
    svc_table || true

    echo; echo "${IND}  ${W}[4/4] Prometheus${N}"
    if [ -n "${PROM_URL:-}" ]; then prom_check "$PROM_URL" || fail+=("Prometheus")
    else info "Prometheus URL not set (menu 15)"; fi

    echo
    if [ "${#fail[@]}" = 0 ]; then ok "${W}Done, no errors${N}"
    else err "Needs attention: ${fail[*]}"; return 1; fi
}

# =============================================================================
# 26. Dich vu & suc khoe: moi exporter (local, @cluster, container) + Docker + watchdog
# =============================================================================
WD_BIN=/usr/local/bin/pve-ceph-exporter-watchdog
WD_UNIT=pve-ceph-exporter-watchdog

svc_list() {  # in "kind|ten|unit/container|port" cho moi dich vu tren may nay
    [ -f "$UNIT" ] && echo "systemd|exporter (local)|$SERVICE|$(current_port)"
    local n p
    for n in $(remote_names); do
        p=$(env_get "$REMOTE_DIR/$n.env" PORT)
        if has docker && [ -n "$(container_state "$n")" ]; then echo "docker|$n|$(container_of "$n")|$p"
        else echo "systemd|$n|$SERVICE@$n|$p"; fi
    done
    has docker && echo "daemon|Docker|docker|"
    systemctl cat "$WD_UNIT.timer" >/dev/null 2>&1 && echo "timer|watchdog|$WD_UNIT.timer|"
    systemctl cat "$HA_UNIT.timer" >/dev/null 2>&1 && echo "timer|HA colors|$HA_UNIT.timer|"
    return 0
}

svc_state_of() {  # svc_state_of KIND UNIT -> active / inactive / failed / exited ...
    case "$1" in
        docker) docker inspect -f '{{.State.Status}}' "$2" 2>/dev/null | sed 's/^running$/active/' ;;
        *) systemctl is-active "$2" 2>/dev/null ;;
    esac
}
svc_boot_of() {  # tu chay khi khoi dong may?
    case "$1" in
        docker) docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$2" 2>/dev/null ;;
        *) systemctl is-enabled "$2" 2>/dev/null ;;
    esac
}
svc_health_of() {  # svc_health_of PORT -> ok / treo / - ; exporter cu khong co /health tra trang chu 200 = ok
    [ -n "$1" ] || { echo "-"; return; }
    case "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$1/health" 2>/dev/null)" in
        200) echo "ok" ;; 503) echo "hung" ;; *) echo "no answer" ;;
    esac
}

svc_verify() {  # svc_verify KIND UNIT PORT -> doi toi 40s cho active + /health ok
    local i st h="-"
    for i in $(seq 1 20); do
        st=$(svc_state_of "$1" "$2"); [ -n "$3" ] && h=$(svc_health_of "$3")
        [ "$st" = active ] && { [ -z "$3" ] || [ "$h" = ok ]; } && { ok "$2: active${3:+, /health ok}"; return 0; }
        sleep 2
    done
    err "$2: $st${3:+, /health $h} after 40s"
    case "$1" in docker) docker logs --tail 15 "$2" 2>&1 | sub ;; *) journalctl -u "$2" -n 15 --no-pager 2>/dev/null | sub ;; esac
    return 1
}

svc_do() {  # svc_do ACTION KIND UNIT PORT ; ACTION = restart / stop / start / boot-on / boot-off
    local a="$1" k="$2" u="$3" p="$4" before
    case "$k:$a" in
        daemon:restart|daemon:stop)
            before=$(docker ps --format '{{.Names}}' 2>/dev/null)
            [ -n "$before" ] && warn "Restarting Docker → all containers stop for a few seconds: $(echo $before)" ;;
    esac
    case "$k:$a" in
        docker:boot-on)  docker update --restart unless-stopped "$u" >/dev/null && ok "$u: starts on boot" ;;
        docker:boot-off) docker update --restart no "$u" >/dev/null && ok "$u: does not start on boot" ;;
        docker:*)        docker "$a" "$u" >/dev/null 2>&1 || { err "docker $a $u failed"; return 1; } ;;
        *:boot-on)       systemctl enable "$u" >/dev/null 2>&1 && ok "$u: enabled" ;;
        *:boot-off)      systemctl disable "$u" >/dev/null 2>&1 && ok "$u: disabled" ;;
        *)               systemctl "$a" "$u" || { err "systemctl $a $u failed"; return 1; } ;;
    esac
    case "$a" in
        restart|start) svc_verify "$k" "$u" "$p" || return 1 ;;
        stop) sleep 1; ok "$u: $(svc_state_of "$k" "$u")"
              [ "$k" != daemon ] && systemctl is-active -q "$WD_UNIT.timer" 2>/dev/null \
                  && info "Watchdog only checks running services → it will not restart what you just stopped" ;;
    esac
    if [ "$k" = daemon ] && [ "$a" = restart ] && [ -n "$before" ]; then
        sleep 3; local c miss=""
        for c in $before; do docker ps --format '{{.Names}}' | grep -qx "$c" || miss+=" $c"; done
        if [ -n "$miss" ]; then warn "Containers not back up:$miss"; confirm "Start them?" && docker start $miss | sub
        else ok "All containers are back up"; fi
    fi
}

svc_table() {  # in bang, luu danh sach vao SVC_ROWS
    mapfile -t SVC_ROWS < <(svc_list)
    if [ "${#SVC_ROWS[@]}" = 0 ]; then warn "No services on this host yet (menu 2 / 17)"; return 1; fi
    printf '%s  %s%-3s %-26s %-8s %-10s %-14s %-6s %s%s\n' "$IND" "$W" "#" "NAME" "TYPE" "STATE" "/HEALTH" "PORT" "START ON BOOT" "$N"
    local i=1 r k nm u p st h bt c
    for r in "${SVC_ROWS[@]}"; do
        IFS='|' read -r k nm u p <<< "$r"
        st=$(svc_state_of "$k" "$u"); bt=$(svc_boot_of "$k" "$u")
        h="-"; [ "$st" = active ] && h=$(svc_health_of "$p")
        case "$st" in active) c=$G ;; inactive|exited) c=$D ;; *) c=$R ;; esac
        printf '%s  %-3s %-26s %-8s %s%-10s%s %s%-14s%s %-6s %s\n' "$IND" "$i" "$nm" "$k" "$c" "${st:-?}" "$N" \
            "$([ "$h" = ok ] && echo "$G" || { [ "$h" = - ] && echo "$D" || echo "$R"; })" "$h" "$N" "${p:--}" "${bt:--}"
        i=$((i + 1))
    done
}

do_services() {
    title "SERVICES & HEALTH"
    need_root || return 1
    local cmd a sel idx r k nm u p targets
    while :; do
        svc_table || return 1
        echo
        info "${W}r${N} restart  ${W}s${N} stop  ${W}t${N} start  ${W}l${N} logs  ${W}b${N}/${W}B${N} enable/disable start on boot  ${W}w${N} watchdog"
        info "E.g. ${W}r 2${N} · ${W}r a${N} (all exporters) · ${W}l 1${N} · Enter = back"
        cmd=$(ask "Command" ""); [ -n "$cmd" ] || return 0
        a=${cmd%% *}; sel=${cmd#* }; [ "$sel" = "$cmd" ] && sel=""
        if [ "$a" = w ]; then do_watchdog; echo; continue; fi
        targets=()
        if [ "$sel" = a ]; then
            for r in "${SVC_ROWS[@]}"; do case "$r" in systemd\|*|docker\|*) targets+=("$r") ;; esac; done
        elif [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#SVC_ROWS[@]}" ]; then
            targets=("${SVC_ROWS[$((sel - 1))]}")
        else err "Pick a number from the table or 'a'"; continue; fi
        for r in "${targets[@]}"; do
            IFS='|' read -r k nm u p <<< "$r"
            case "$a" in
                r) svc_do restart "$k" "$u" "$p" ;;
                s) confirm "Stop $u?" && svc_do stop "$k" "$u" "$p" ;;
                t) svc_do start "$k" "$u" "$p" ;;
                l) case "$k" in docker) docker logs --tail 40 "$u" 2>&1 | sub ;;
                                *) journalctl -u "$u" -n 40 --no-pager 2>/dev/null | sub ;; esac ;;
                b) svc_do boot-on "$k" "$u" "$p" ;;
                B) svc_do boot-off "$k" "$u" "$p" ;;
                *) err "Unknown command '$a'"; break ;;
            esac
        done
        echo
    done
}

# Watchdog: 2 phut / lan goi /health cua moi exporter DANG CHAY; loi 2 lan lien tiep thi
# khoi dong lai dung cai do (systemd restart / docker restart), ghi log vao journal.
do_watchdog() {
    if systemctl is-active -q "$WD_UNIT.timer" 2>/dev/null; then
        ok "Watchdog is on (every 2 minutes). Recent restarts:"
        journalctl -t pve-ceph-watchdog -n 10 --no-pager 2>/dev/null | sub
        confirm "Turn the watchdog off?" || return 0
        systemctl disable --now "$WD_UNIT.timer" >/dev/null 2>&1
        rm -f "${SYSTEMD_DIR:-/etc/systemd/system}/$WD_UNIT.timer" "${SYSTEMD_DIR:-/etc/systemd/system}/$WD_UNIT.service" "$WD_BIN"
        systemctl daemon-reload; ok "Watchdog turned off and removed"; return 0
    fi
    info "Watchdog: every 2 minutes checks /health of running exporters; hung / no answer twice in a row → restart it"
    confirm "Turn the watchdog on?" || return 0
    cat > "$WD_BIN" <<EOF
#!/bin/bash
# FIX NHANH - watchdog exporter (generated by proxmox-ceph-monitor.sh). /health failing twice in a row -> restart.
S=/run/pve-ceph-watchdog; mkdir -p "\$S"
chk() {  # chk TEN PORT LENH_RESTART...
    local name=\$1 port=\$2 code n; shift 2
    code=\$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://127.0.0.1:\$port/health")
    if [ "\$code" = 200 ]; then rm -f "\$S/\$name"; return; fi
    n=\$(( \$(cat "\$S/\$name" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "\$S/\$name"
    logger -t pve-ceph-watchdog "\$name :\$port /health=\$code (attempt \$n)"
    if [ "\$n" -ge 2 ]; then logger -t pve-ceph-watchdog "restarting \$name"; "\$@"; rm -f "\$S/\$name"; fi
}
if systemctl is-active -q $SERVICE; then
    chk local "\$(sed -n 's/.*--port \([0-9]\+\).*/\1/p' $UNIT | head -1)" systemctl restart $SERVICE
fi
for f in $REMOTE_DIR/*.env; do
    [ -f "\$f" ] || continue
    n=\$(basename "\$f" .env); p=\$(sed -n 's/^PORT=//p' "\$f" | tail -1)
    if command -v docker >/dev/null && [ "\$(docker inspect -f '{{.State.Status}}' fixnhanh-pve-\$n 2>/dev/null)" = running ]; then
        chk "\$n" "\$p" docker restart "fixnhanh-pve-\$n"
    elif systemctl is-active -q "$SERVICE@\$n"; then
        chk "\$n" "\$p" systemctl restart "$SERVICE@\$n"
    fi
done
EOF
    chmod 755 "$WD_BIN"
    printf '[Unit]\nDescription=FIX NHANH watchdog exporter Proxmox Ceph\n\n[Service]\nType=oneshot\nExecStart=%s\n' "$WD_BIN" \
        > "${SYSTEMD_DIR:-/etc/systemd/system}/$WD_UNIT.service"
    printf '[Unit]\nDescription=FIX NHANH watchdog exporter (every 2 minutes)\n\n[Timer]\nOnBootSec=3min\nOnUnitActiveSec=2min\n\n[Install]\nWantedBy=timers.target\n' \
        > "${SYSTEMD_DIR:-/etc/systemd/system}/$WD_UNIT.timer"
    systemctl daemon-reload && systemctl enable --now "$WD_UNIT.timer" >/dev/null 2>&1 \
        && ok "Watchdog on. View: journalctl -t pve-ceph-watchdog" || err "Enabling the timer failed"
}

# =============================================================================
# 25. Doi dai IP Docker (docker0 + mang moi): tranh trung dai IP noi bo / VPN
# =============================================================================
do_docker_net() {
    title "CHANGE DOCKER IP RANGE"
    need_root || return 1
    has docker && has python3 || { err "docker and python3 are required"; return 1; }
    local f=${DOCKER_DAEMON_JSON:-/etc/docker/daemon.json} bak cur bip pool before after n miss="" out
    cur=$(ip -4 addr show docker0 2>/dev/null | awk '/inet /{print $2}')
    info "docker0 now: ${W}${cur:-none}${N}"
    docker network ls -q 2>/dev/null | xargs -r docker network inspect -f '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null | sub
    info "systemd services (exporter @cluster) ${G}are not affected${N}; Docker containers ${Y}stop for a few seconds${N} while Docker restarts, then come back"
    info "Networks made earlier with 'docker network create' keep their old range (delete / recreate to change them)"

    bip=$(ask "IP for docker0 (IP/prefix)" "192.168.20.1/24")
    pool=$(ask "Range for future Docker networks (e.g. 192.168.21.0/24; Enter = skip)" "")
    # Kiem tra: dung dinh dang, thuoc dai noi bo, khong trung route dang co tren may
    if ! out=$(python3 - "$bip" "$pool" "$(ip -4 route 2>/dev/null | grep -v 'docker0\|br-')" <<'PY'
import ipaddress, sys
bip, pool, routes = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    nets = [ipaddress.ip_interface(bip).network] + ([ipaddress.ip_network(pool)] if pool else [])
except ValueError as e:
    print("ERR invalid format: %s" % e); sys.exit(1)
for n in nets:
    if not n.is_private:
        print("PUBLIC %s is a public Internet range -> this host could no longer reach real hosts in it" % n)
    for line in routes.splitlines():
        dst = line.split()[0] if line.split() else ""
        if dst in ("default", ""):
            continue
        try:
            r = ipaddress.ip_network(dst, strict=False)
        except ValueError:
            continue
        if n.overlaps(r):
            print("OVERLAP %s overlaps an existing route: %s" % (n, line.strip()))
PY
    ); then err "${out#ERR }"; return 1; fi
    if [ -n "$out" ]; then
        echo "$out" | sed 's/^PUBLIC /▲ /; s/^OVERLAP /▲ /' | sub
        confirm "Use this range anyway?" || return 1
    fi

    before=$(docker ps --format '{{.Names}}' | sort)
    [ -n "$before" ] && info "Running containers: ${W}$(echo $before)${N}"
    confirm "Write $f and restart Docker?" || { info "Cancelled"; return 0; }
    bak="$f.bak-$(date +%Y%m%d-%H%M%S)"
    [ -f "$f" ] && cp -p "$f" "$bak"
    mkdir -p "$(dirname "$f")"
    python3 - "$f" "$bip" "$pool" <<'PY' || { err "Writing $f failed (old file is not valid JSON?)"; return 1; }
import json, os, sys
f, bip, pool = sys.argv[1:4]
d = json.load(open(f)) if os.path.exists(f) and os.path.getsize(f) else {}
d["bip"] = bip
if pool:
    d["default-address-pools"] = [{"base": pool, "size": 28 if int(pool.split("/")[1]) <= 24 else int(pool.split("/")[1])}]
json.dump(d, open(f, "w"), indent=2)
PY
    if ! systemctl restart docker; then
        err "Docker does not start with the new config → old file restored"
        if [ -f "$bak" ]; then cp -p "$bak" "$f"; else rm -f "$f"; fi
        systemctl restart docker; journalctl -u docker -n 10 --no-pager | sub; return 1
    fi
    sleep 5
    ok "docker0: ${W}$(ip -4 addr show docker0 | awk '/inet /{print $2}')${N} ${D}(old file: ${bak:-none})${N}"
    after=$(docker ps --format '{{.Names}}' | sort)
    for n in $before; do grep -qx "$n" <<< "$after" || miss+=" $n"; done
    if [ -n "$miss" ]; then
        warn "Containers not back up:${W}$miss${N}"
        confirm "Start these containers?" && docker start $miss | sub
    elif [ -n "$before" ]; then
        ok "All containers are back up"
    fi
}

# =============================================================================
# 27. Zabbix: giam sat Ceph bang Zabbix Agent 2 (script trong template-zabbix/, chay qua SSH)
# =============================================================================
do_zabbix_ceph() {
    title "ZABBIX: CEPH VIA ZABBIX AGENT 2"
    has ssh || { err "ssh is required"; return 1; }
    info "Configures zabbix-agent2 on every node over SSH, a ceph health fallback file, and the Ceph RESTful API key"
    info "Zabbix templates: ${W}Ceph by Zabbix agent 2${N} (built in) + ${W}template-zabbix/ceph-health-fallback.yaml${N}"
    info "Without agent: ${W}template-zabbix/pve-ceph-exporter-by-http.yaml${N} reads this exporter over HTTP (README: Zabbix)"
    local zip nodes
    zip=$(ask "Zabbix server / proxy IP" "${ZABBIX_IP:-10.8.10.201}")
    nodes=$(ask "Proxmox node IPs (space separated)" "${ZABBIX_NODES:-}")
    [ -n "$nodes" ] || { err "No node entered"; return 1; }
    save_conf ZABBIX_IP "$zip"; save_conf ZABBIX_NODES "$nodes"
    # shellcheck disable=SC2086  # tach danh sach node thanh tung tham so
    bash "$DIR/template-zabbix/setup_ceph_zabbix.sh" "$zip" $nodes 2>&1 | sub
}

do_docker_manage() {
    title "MANAGE CONTAINERS"
    docker_ok || return 1
    local out a n c
    out=$(docker ps -a --filter name=fixnhanh-pve- --format '{{.Names}}|{{.Status}}|{{.Ports}}')
    if [ -z "$out" ]; then info "No container yet (menu 23 to create)"; return 0; fi
    printf '%s  %s%-28s %-28s %s%s\n' "$IND" "$W" "CONTAINER" "STATUS" "PORT" "$N"
    while IFS='|' read -r c st pt; do
        printf '%s  %-28s %s%-28s%s %s\n' "$IND" "$c" "$([[ "$st" == Up* ]] && echo "$G" || echo "$R")" \
            "$(echo "$st" | cut -c1-28)" "$N" "$(echo "$pt" | sed 's/0.0.0.0://; s/, .*//' | cut -c1-20)"
    done <<< "$out"
    echo
    a=$(ask "Action: l=logs  r=restart  x=remove (back to systemd)  Enter=exit" "")
    [ -n "$a" ] || return 0
    n=$(pick_remote) || return 1; c=$(container_of "$n")
    case "$a" in
        l|L) docker logs --tail 40 "$c" 2>&1 | sub ;;
        r|R) docker restart "$c" >/dev/null && ok "Restarted $c" ;;
        x|X) need_root || return 1
             confirm "Remove container $c and run it with systemd again?" || return 0
             docker rm -f "$c" >/dev/null && ok "Removed $c"
             remote_install_files && systemctl enable --now "$SERVICE@$n" >/dev/null 2>&1 \
                 && ok "$n running with systemd again" ;;
        *) warn "Invalid action: $a" ;;
    esac
}

remote_refresh_after_update() {  # sau cap nhat: chay lai cac service remote bang ban exporter moi
    local names; names=$(remote_names)
    [ -n "$names" ] || return 0
    if [ "$(id -u)" != 0 ]; then warn "Root is required to update ${W}$(echo $names)${N} → run menu 14 again as root"; return 0; fi
    local n sd="" dk=""
    remote_install_files || return 1
    for n in $names; do
        if has docker && [ "$(container_state "$n")" = running ]; then dk+=" $n"
        else systemctl restart "$SERVICE@$n"; sd+=" $n"; fi
    done
    [ -n "$sd" ] && ok "Remote exporters restarted (systemd):${W}$sd${N}"
    [ -n "$dk" ] && info "Clusters in Docker:${W}$dk${N} → refresh / menu 23 rebuilds the new image"
    return 0
}

# =============================================================================
# 14. Cap nhat tool / 15. Cau hinh da luu / 16. Gioi thieu & ban quyen
# =============================================================================
do_update() {
    title "UPDATE TOOL"
    if [ ! -d "$DIR/.git" ]; then
        if has git; then
            info "Folder was downloaded with curl → converting to a git clone (keeps .menu.conf)"
            git -C "$DIR" init -q && git -C "$DIR" remote add origin "$REPO_URL.git" 2>/dev/null
            git -C "$DIR" fetch -q origin main && git -C "$DIR" reset -q --hard origin/main \
                && git -C "$DIR" checkout -q -B main --track origin/main 2>/dev/null \
                || { err "Converting to git failed"; return 1; }
            ok "Converted to git, version $(git -C "$DIR" rev-parse --short HEAD)"
            remote_refresh_after_update
            [ "${NONINTERACTIVE:-0}" = 0 ] && { info "Reopening the menu with the new version..."; sleep 1; exec bash "$SELF"; }
            return 0
        fi
        has curl || { err "git or curl is required to update"; return 1; }
        info "No git → downloading the new version with curl"
        curl -sfL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar xz --strip-components=1 -C "$DIR" \
            || { err "Download failed"; return 1; }
        ok "Downloaded the latest version"
        remote_refresh_after_update
        [ "${NONINTERACTIVE:-0}" = 0 ] && { info "Reopening the menu with the new version..."; sleep 1; exec bash "$SELF"; }
        return 0
    fi
    local before after out
    before=$(git -C "$DIR" rev-parse --short HEAD)
    # Ban cu cua menu 9 ghi de file dashboard trong repo -> git pull bi chan. Giu ban do
    # thanh dashboard-local.json (file menu 9 / 11 dung tu gio) roi tra file repo ve goc.
    if ! git -C "$DIR" diff --quiet -- "$DASH_REPO_JSON" 2>/dev/null; then
        if [ ! -f "$DASH_JSON" ]; then
            cp -p "$DASH_REPO_JSON" "$DASH_JSON" && info "Keeping the generated dashboard → ${W}$DASH_JSON${N}"
        else
            cp -p "$DASH_REPO_JSON" "$DASH_JSON.bak" && info "Old dashboard copy → $DASH_JSON.bak"
        fi
        git -C "$DIR" checkout -- "$DASH_REPO_JSON"
    fi
    if ! out=$(git -C "$DIR" pull --ff-only 2>&1); then
        echo "$out" | sub
        err "Update failed (still on ${W}$before${N})"
        git -C "$DIR" status --short | grep -v '^??' | sub
        info "Files above were edited by hand → save them elsewhere, then: git -C $DIR checkout -- <file> ; run menu 14 again"
        return 1
    fi
    echo "$out" | sub
    after=$(git -C "$DIR" rev-parse --short HEAD)
    if [ "$before" = "$after" ]; then
        ok "Already up to date (${W}$after${N})"; return 0
    fi
    ok "Updated ${W}$before → $after${N}:"
    git -C "$DIR" log --oneline "$before..$after" | sub
    if [ -f "$UNIT" ] && ! git -C "$DIR" diff --quiet "$before" "$after" -- exporter/; then
        warn "The exporter changed"
        confirm "Reinstall the new exporter (keep port $(current_port))?" && do_install "$(current_port)"
    fi
    git -C "$DIR" diff --quiet "$before" "$after" -- exporter/ || remote_refresh_after_update
    if [ "${NONINTERACTIVE:-0}" = 0 ]; then
        info "Reopening the menu with the new version..."; sleep 1
        exec bash "$SELF"
    fi
}

# Dat dia chi Prometheus / Grafana ma khong can import hay kiem tra target truoc.
ask_url() {  # ask_url "Cau hoi" "mac dinh" -> URL chuan (them http:// neu thieu), hoi lai neu sai scheme
    local u
    while :; do
        u=$(ask "$1" "$2"); u=${u%/}
        [ -z "$u" ] && { echo ""; return; }
        [[ "$u" == *://* ]] || u="http://$u"
        [[ "$u" =~ ^https?://[^/:]+(:[0-9]+)?(/.*)?$ ]] && { echo "$u"; return; }
        err "Invalid URL: '$u' → must look like http://IP:port or https://IP:port" >&2
    done
}

url_probe() {  # url_probe URL PATH GREP -> in URL dung duoc (thu ca http <-> https); rong neu khong
    local u="$1" alt x rc
    case "$u" in https://*) alt="http://${u#https://}" ;; *) alt="https://${u#http://}" ;; esac
    for x in "$u" "$alt"; do
        curl -sf --max-time 8 "$x$2" 2>/dev/null | grep -q "$3" && { echo "$x"; return 0; }
    done
    curl -s --max-time 8 -o /dev/null "$u$2" 2>/dev/null; rc=$?
    [ "$rc" = 60 ] && warn "TLS cert of $u is not trusted (self-signed?) → use http://, or install the CA on this host (update-ca-certificates)" >&2
    return 1
}

set_urls() {
    local u w
    u=$(ask_url "Prometheus URL (e.g. http://10.16.16.x:9090; Enter = keep)" "${PROM_URL:-}")
    if [ -n "$u" ]; then
        if w=$(url_probe "$u" "/-/ready" "Ready"); then
            [ "$w" != "$u" ] && warn "Using $w (not $u)"; u=$w; ok "Prometheus answers: $u"
        else warn "Cannot reach $u/-/ready → check IP/port, firewall of the Prometheus host (port 9090)"; fi
        save_conf PROM_URL "$u"; PROM_URL=$u
    fi
    u=$(ask_url "Grafana URL (e.g. http://10.16.16.x:3000; Enter = keep)" "${GRAFANA_URL:-}")
    if [ -n "$u" ]; then
        if w=$(url_probe "$u" "/api/health" '"database"'); then
            [ "$w" != "$u" ] && warn "Using $w (not $u)"; u=$w; ok "Grafana answers: $u"
        else warn "Cannot reach $u/api/health → check IP/port, firewall of the Grafana host (port 3000)"; fi
        save_conf GRAFANA_URL "$u"; GRAFANA_URL=$u
    fi
    info "Grafana token: entered in menu 11, can be saved once (.grafana-token, root-only)"
}

do_config() {
    title "SAVED CONFIG"
    if [ ! -s "$CONF" ]; then
        info "No saved config ($CONF)"
        confirm "Set the Prometheus / Grafana URLs now?" && set_urls
        return 0
    fi
    info "File: $CONF"; echo
    local k v
    while IFS= read -r l; do
        k=${l%%=*}; v=$(. "$CONF"; printf '%s' "${!k-}")
        printf '%s    %s%-14s%s %s\n' "$IND" "$C" "$k" "$N" "${v:-${D}<empty>${N}}"
    done < "$CONF"
    echo
    info "Edit: run ${W}S${N} again (current values prefilled) or edit the file above"
    if [ -s "$GRAFANA_TOKEN_FILE" ]; then
        info "Saved Grafana token: $GRAFANA_TOKEN_FILE"
        confirm "Delete the saved Grafana token (enter it again on next import)?" && { rm -f "$GRAFANA_TOKEN_FILE"; ok "Token deleted"; }
    fi
    if confirm "Set / change the Prometheus, Grafana URLs?"; then set_urls; return 0; fi
    if confirm "Delete all saved config?"; then
        rm -f "$CONF" "$GRAFANA_TOKEN_FILE"; ok "Deleted (Grafana token too) - the next run asks everything again"
        unset "${!DASH_@}" GRAFANA_URL GRAFANA_FOLDER PROM_URL PROM_JOB SETUP_ROLE 2>/dev/null || true
    fi
}

do_about() {
    echo
    box_top
    box_center "${W}${C}$TOOL_NAME${N}"
    box_center "${D}version $TOOL_VERSION${N}${D}$(tool_rev | sed 's/^/ · /')${N}"
    box_sep
    box_row "$(kv "Developer" "${W}FIX NHANH${N}")"
    box_row "$(kv "Repo" "${REPO_URL#https://}")"
    box_row "$(kv "Parts" "proxmox-ceph-monitor.sh · exporter · dashboard-grafana · prometheus · template-zabbix")"
    box_row "$(kv "Requires" "bash, python3 >= 3.5, curl")"
    box_row "$(kv "Modes" "local (on a Ceph node) · remote (API token)")"
    box_row "$(kv "License" "see the LICENSE file")"
    box_sep
    box_center "${Y}Copyright © 2026 FIX NHANH. All rights reserved.${N}"
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
    title "FULL SETUP"
    info "Answer the questions below (Enter = use the value in ${D}[ ]${N})."
    info "Answers are kept in .menu.conf for the next run (tokens are stored separately)."
    dash_defaults
    [ -n "${ENV_ROLE:-}" ] || detect_env
    local role port="" job="" cn gurl="" gfolder="" prom="" TOKEN="" flags=""
    local do_ex=0 do_dash=0 do_imp=0 do_chk=0

    echo; echo "${IND}  ${W}${M}[1/5] What is this host for?${N}"
    echo "${IND}     ${C}1${N}  Ceph node: install the exporter + generate/import the dashboard (full)"
    echo "${IND}     ${C}2${N}  Exporter only (Ceph node)"
    echo "${IND}     ${C}3${N}  Dashboard only (Grafana / admin host)"
    echo "${IND}     ${C}4${N}  Monitor host: watch clusters REMOTELY over the API (nothing installed on nodes) + dashboard"
    if [ "$ENV_CEPH" = 1 ]; then info "This host runs Ceph → suggested ${W}1${N}"
    else info "No Ceph on this host → suggested ${W}4${N} (remote) or ${W}3${N} (dashboard only)"; fi
    role=$(ask "Choice" "${SETUP_ROLE:-$ENV_ROLE}")
    case "$role" in
        1) do_ex=1; do_dash=1 ;;
        2) do_ex=1 ;;
        3) do_dash=1 ;;
        4) do_dash=1
           echo; echo "${IND}  ${W}${M}[2/5] Remote clusters${N}"
           while true; do
               do_remote_add || warn "That cluster was not added"
               confirm "Add another cluster?" || break
           done ;;
        *) err "Invalid choice: $role"; return 1 ;;
    esac
    if [ $do_ex = 1 ] && [ "$ENV_CEPH" != 1 ]; then
        warn "Exporter install chosen but 'ceph status' fails here → the check step will stop"
        confirm "Continue anyway?" || { info "Cancelled - run again and pick 3, or run on a Ceph node"; return 1; }
    fi

    if [ $do_ex = 1 ]; then
        need_root || return 1
        echo; echo "${IND}  ${W}${M}[2/5] Exporter${N}"
        port=$(ask "Exporter port" "$(current_port)")
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] \
            || { err "Invalid port: $port"; return 1; }
        info "Merged: the exporter re-serves ceph mgr + Proxmox (pvesh) metrics → Prometheus needs only 1 target"
        local allin; allin=$(ask "Serve all metrics on 1 port? (Y/n)" "$([ -z "$(current_flags)" ] && echo Y || echo n)")
        if [[ "$allin" =~ ^[Nn] ]]; then flags="--no-ceph-mgr --no-pve"; else flags=""; fi
        cn=$(detect_cluster_name)
        [ -n "$cn" ] && info "Proxmox cluster name (corosync): ${W}$cn${N}"
        job=$(ask "Prometheus job name for the cluster (must match the ceph mgr job)" "${PROM_JOB:-Proxmox-${cn:-CLUSTER}}")
    fi

    if [ $do_dash = 1 ]; then
        echo; echo "${IND}  ${W}${M}[3/5] Dashboard${N}"
        ask_dashboard
        echo; echo "${IND}  ${W}${M}[4/5] Grafana${N}"
        [ -n "${ENV_GRAFANA:-}" ] && info "Grafana found on this host: ${W}$ENV_GRAFANA${N}"
        gurl=$(ask "Grafana URL (empty = no import, JSON file only)" "${GRAFANA_URL:-${ENV_GRAFANA:-}}")
        if [ -n "$gurl" ]; then
            ask_token
            gfolder=$(ask "Folder UID (empty = General)" "${GRAFANA_FOLDER:-}")
            if [ -n "$TOKEN" ]; then do_imp=1; else warn "No token → JSON file only"; fi
        fi
    fi

    echo; echo "${IND}  ${W}${M}[5/5] Prometheus${N}"
    [ -n "${ENV_PROM:-}" ] && info "Prometheus found on this host: ${W}$ENV_PROM${N}"
    prom=$(ask "Prometheus URL to check after install (empty = skip)" "${PROM_URL:-${ENV_PROM:-}}")
    [ -n "$prom" ] && do_chk=1

    echo; box_top
    box_center "${W}${Y}SUMMARY${N}"
    box_sep
    if [ $do_ex = 1 ]; then
        box_row "$(kv "Exporter" "service $SERVICE · $(hostname) · port ${W}$port${N}")"
        box_row "$(kv "Mode" "$(mode_text "$flags")")"
        box_row "$(kv "Job Prom" "${W}$job${N} (target $(local_ip):$port)")"
    fi
    if [ $do_dash = 1 ]; then
        box_row "$(kv "Dashboard" "\"$DASH_TITLE\" · uid ${W}$DASH_UID${N}")"
        box_row "$(kv "Filter" "Site ${DASH_SITE:-<all>} · job $DASH_JOB")"
        box_row "$(kv "Size" "$DASH_NODES nodes · $DASH_POOLS pools · $DASH_CLASSES classes · $DASH_TIME")"
        box_row "$(kv "Latency" "$DASH_LAT")"
        box_row "$(kv "HA alias" "$(echo "${DASH_ALIASES:-<none>}" | sed 's/;;/ | /g' | cut -c1-55)")"
        if [ $do_imp = 1 ]; then box_row "$(kv "Grafana" "import → $gurl · folder ${gfolder:-General}")"
        else box_row "$(kv "Grafana" "no import (import the JSON file by hand)")"; fi
    fi
    [ "$role" = 4 ] && box_row "$(kv "Remote" "$(remote_names | paste -sd' ' | cut -c1-60)")"
    if [ $do_chk = 1 ]; then box_row "$(kv "Check" "$prom")"; else box_row "$(kv "Check" "skipped")"; fi
    box_bottom; echo
    confirm "Start?" || { info "Cancelled - nothing changed"; return 1; }

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
        next "Environment check"
        do_check || { err "Stopped: fix the errors above and run again (menu S)"; return 1; }
        next "Install exporter (port $port)"
        do_install "$port" "$flags" || return 1
        next "Prometheus config"
        prom_snippet "$job" "$port" "$flags"
    fi
    if [ $do_dash = 1 ]; then
        next "Generate dashboard"
        gen_dashboard || failed+=("generate dashboard")
    fi
    if [ $do_imp = 1 ]; then
        next "Import dashboard to Grafana"
        import_dashboard "$gurl" "$TOKEN" "$gfolder" || failed+=("import Grafana")
    fi
    if [ $do_chk = 1 ]; then
        next "Check Prometheus"
        prom_check "$prom" || failed+=("check Prometheus")
    fi

    echo; box_top
    if [ ${#failed[@]} = 0 ]; then box_center "${G}${W}✔ DONE, $total STEPS${N}"
    else box_center "${R}${W}✘ FAILED: ${failed[*]}${N}"; fi
    box_bottom
    [ $do_ex = 1 ] && [ $do_chk = 0 ] && \
        info "Remember to add the target to Prometheus, then run: proxmox-menu prom-check"
    [ $do_dash = 1 ] && [ $do_imp = 0 ] && \
        info "Manual import: Grafana → Dashboards → New → Import → $DASH_JSON"
    info "To change answers: run menu S again (current values prefilled), or menu 15"
    [ ${#failed[@]} = 0 ]
}

# =============================================================================
# Menu
# =============================================================================
show_help() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"   # khoi comment dau file
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

tool_rev() { git -C "$DIR" rev-parse --short HEAD 2>/dev/null; }   # ma commit dang chay

check_new_version() {  # hoi GitHub 1 lan / phien (toi da 5s) -> NEWVER = ma commit moi hon, rong neu khong
    [ -n "${NEWVER_DONE:-}" ] && return 0
    NEWVER_DONE=1; NEWVER=""
    [ -d "$DIR/.git" ] && has git && has timeout || return 0
    local r; r=$(GIT_TERMINAL_PROMPT=0 timeout 5 git -C "$DIR" ls-remote "$REPO_URL.git" refs/heads/main 2>/dev/null | cut -c1-40)
    [ -n "$r" ] && [ "$r" != "$(git -C "$DIR" rev-parse HEAD 2>/dev/null)" ] || return 0
    git -C "$DIR" merge-base --is-ancestor "$r" HEAD 2>/dev/null && return 0   # local da moi hon / bang
    NEWVER=${r:0:7}
}

header() {
    clear 2>/dev/null || true
    check_new_version
    setup_ui
    local st port ex grafana prom pve
    port=$(current_port)
    if [ -f "$UNIT" ]; then st=$(svc_state); else st="not installed"; fi
    case "$st" in active) ex="${G}${W}● running${N} :$port" ;; "not installed") ex="${D}○ not installed${N}" ;; *) ex="${R}● $st${N}" ;; esac
    # May monitor: khong cai local nhung co exporter tu xa -> dem so dang chay (systemd + docker)
    if [ "$st" = "not installed" ] && [ -n "$(remote_names)" ]; then
        local n run=0 tot=0
        for n in $(remote_names); do
            tot=$((tot + 1))
            { systemctl is-active -q "$SERVICE@$n" 2>/dev/null || { has docker && [ "$(container_state "$n")" = running ]; }; } && run=$((run + 1))
        done
        ex="$([ "$run" = "$tot" ] && echo "$G" || echo "$Y")${W}● $run/$tot remote running${N}"
    fi
    pve="${ENV_PVE:+${G}PVE $ENV_PVE${N}}"; pve="${pve:-${D}not a PVE node${N}}"
    grafana="${GRAFANA_URL:-${ENV_GRAFANA:-}}"; grafana="${grafana:-${D}not set (menu 15)${N}}"
    prom="${PROM_URL:-${ENV_PROM:-}}"; prom="${prom:-${D}not set (menu 15)${N}}"

    echo
    box_top
    banner
    box_center "${W}MONITOR PROXMOX + CEPH${N}  ${D}·${N}  ${B}Prometheus${N} ${D}→${N} ${O}Grafana${N}"
    local rev; rev=$(tool_rev)
    box_center "${D}version $TOOL_VERSION${rev:+ · $rev}${N}"
    [ -n "$NEWVER" ] && box_center "${Y}${W}▲ New version $NEWVER on GitHub → pick 14 to update${N}"
    box_title "HOST INFO" "$C"
    box_row2 "$(kv "Host" "${W}$(hostname)${N}")" "$(kv "IP" "$(local_ip)")"
    box_row2 "$(kv "Proxmox" "$pve")" "$(kv "Ceph" "$(ceph_health_short)")"
    box_row2 "$(kv "Exporter" "$ex")" "$(kv "OS" "$(echo "$ENV_OS" | cut -c1-24)")"
    box_row "$(kv "Grafana" "$grafana")"
    box_row "$(kv "Prometheus" "$prom")"
    local rn; rn=$(remote_names | wc -l)
    [ "$rn" -gt 0 ] && box_row "$(kv "Remote" "${W}$rn${N} clusters: $(remote_names | paste -sd' ' | cut -c1-55)")"
}

menu_body() {
    box_title "QUICK SETUP" "$G"
    box_row "$(mi S "${W}Full setup${N} ${D}- asks once, then runs every step below${N}" "$G")"
    box_title "EXPORTER  ${D}(runs on a Ceph node)${N}" "$M"
    box_row2 "$(mi 1 "Environment check" "$M")"   "$(mi 5 "View logs" "$M")"
    box_row2 "$(mi 2 "Install / update" "$M")"    "$(mi 6 "Restart" "$M")"
    box_row2 "$(mi 3 "Exporter status" "$M")"   "$(mi 7 "Change port" "$M")"
    box_row2 "$(mi 4 "Current metrics" "$M")"   "$(mi 8 "Uninstall" "$M")"
    box_title "DASHBOARD & PROMETHEUS" "$O"
    box_row2 "$(mi 9 "Generate dashboard" "$O")"   "$(mi 11 "Import to Grafana" "$O")"
    box_row2 "$(mi 10 "Prometheus config / push" "$O")"   "$(mi 12 "Check Prometheus" "$O")"
    box_row  "$(mi 13 "Full check (environment + exporter + Prometheus)" "$O")"
    box_title "REMOTE MONITORING  ${D}(over the API, nothing on the nodes)${N}" "$G"
    box_row2 "$(mi 17 "Add / edit cluster" "$G")"    "$(mi 19 "Test connection" "$G")"
    box_row2 "$(mi 18 "List clusters" "$G")"     "$(mi 20 "Remove cluster" "$G")"
    box_title "SYSTEM & DOCKER" "$Y"
    box_row2 "$(mi 21 "Install packages" "$Y")"     "$(mi 23 "Run clusters in Docker" "$Y")"
    box_row2 "$(mi 22 "Open firewall for Prometheus" "$Y")" "$(mi 24 "Manage containers" "$Y")"
    box_row2 "$(mi 25 "Change Docker IP range" "$Y")"        "$(mi 26 "Services & health, watchdog" "$Y")"
    box_title "ZABBIX" "$R"
    box_row  "$(mi 27 "Ceph via Zabbix agent 2 (agent config, API key, fallback template)" "$R")"
    box_title "TOOLS" "$B"
    box_row2 "$(mi 14 "Update tool (git pull)" "$B")" "$(mi 16 "About & license" "$B")"
    box_row2 "$(mi 15 "Saved config / URLs" "$B")"         "$(mi 0 "Exit" "$R")"
    box_sep
    box_center "${D}$COPYRIGHT${N}"
    box_bottom
}

menu() {
    detect_env
    while true; do
        header
        menu_body
        local c; echo; read -rp "${IND}  ${C}❯${N} ${W}Select:${N} " c
        case "$c" in
            1) do_check ;;      2) do_install ;;   3) do_status ;;
            4) do_metrics ;;    5) do_logs ;;      6) do_restart ;;
            7) do_port ;;       8) do_uninstall ;; 9) do_dashboard ;;
            10) do_prom ;;      11) do_import ;;   12) do_prom_check ;;
            13) do_doctor ;;    14) do_update ;;   15) do_config ;;
            16) do_about ;;
            17) do_remote_add ;; 18) do_remote_list ;; 19) do_remote_test ;; 20) do_remote_remove ;;
            21) do_deps ;; 22) do_firewall ;; 23) do_docker_run ;; 24) do_docker_manage ;; 25) do_docker_net ;; 26) do_services ;; 27) do_zabbix_ceph ;;
            s|S) do_setup ;;
            0|q|Q) echo; echo "${IND}  ${D}Bye! $COPYRIGHT${N}"; echo; exit 0 ;;
            "") continue ;;
            *) warn "Invalid choice: $c" ;;
        esac
        pause
    done
}

# Lenh ngan "proxmox-menu" (go o bat ky dau): file goi lai proxmox-ceph-monitor.sh cua thu muc nay.
# Tu cai / sua khi chay bang root; thu muc doi cho thi lan chay sau tu tro lai dung.
CMD_BIN=${CMD_BIN:-/usr/local/bin/proxmox-menu}
install_cmd() {
    [ "$(id -u)" = 0 ] && [ -d "$(dirname "$CMD_BIN")" ] || return 0
    grep -qF "\"$SELF\"" "$CMD_BIN" 2>/dev/null && return 0
    printf '#!/bin/bash\n# FIX NHANH - shortcut for the Monitor Proxmox + Ceph menu\nexec bash "%s" "$@"\n' "$SELF" > "$CMD_BIN" \
        && chmod 755 "$CMD_BIN" && [ -t 1 ] && ok "From now on type ${W}proxmox-menu${N} anywhere to open the menu"
    return 0
}
install_cmd

# ----------------------------------------------------------------- dong lenh
if [ $# -gt 0 ]; then
    NONINTERACTIVE=1
    cmd="$1"; shift
    case "$cmd" in
        setup) NONINTERACTIVE=0; detect_env; do_setup ;;
        check) do_check ;;           install) do_install "${1:-$(current_port)}" ;;
        status) do_status ;;         metrics) do_metrics ;;
        logs) do_logs ;;             restart) do_restart ;;
        port) [ -n "${1:-}" ] || { err "Usage: proxmox-menu port <number>"; exit 1; }; do_port "$1" ;;
        uninstall) do_uninstall ;;   dashboard) NONINTERACTIVE=0; detect_env; do_dashboard ;;
        import) NONINTERACTIVE=0; detect_env; do_import ;;
        prom) NONINTERACTIVE=0; do_prom ;;
        prom-check) NONINTERACTIVE=0; detect_env; do_prom_check ;;
        doctor) do_doctor ;;         update) do_update ;;
        about) do_about ;;
        remote-add) NONINTERACTIVE=0; do_remote_add "${1:-}" ;;
        remote-list) do_remote_list ;;
        prom-all) NONINTERACTIVE=0; title "PROMETHEUS: ALL CLUSTERS"; prom_all ;;
        urls) NONINTERACTIVE=0; title "PROMETHEUS / GRAFANA URL"; set_urls ;;
        prom-rules) NONINTERACTIVE=0; title "PUSH ALERT RULES TO PROMETHEUS"; prom_rules_push ;;
        prom-push) NONINTERACTIVE=0; title "PUSH SCRAPE FILE TO PROMETHEUS"; prom_push ;;
        remote-test) NONINTERACTIVE=0; do_remote_test ;;
        remote-remove) NONINTERACTIVE=0; do_remote_remove ;;
        deps) NONINTERACTIVE=0; detect_env; do_deps ;;
        firewall) NONINTERACTIVE=0; do_firewall ;;
        docker-run) NONINTERACTIVE=0; do_docker_run ;;
        docker-manage) NONINTERACTIVE=0; do_docker_manage ;;
        docker-net) NONINTERACTIVE=0; do_docker_net ;;
        services) NONINTERACTIVE=0; do_services ;;
        zabbix-ceph) NONINTERACTIVE=0; do_zabbix_ceph ;;
        refresh)  # tu git pull truoc, roi chay refresh bang code MOI vua keo ve
            if [ -z "${REFRESH_PULLED:-}" ] && [ -d "$DIR/.git" ]; then
                NONINTERACTIVE=1; do_update </dev/null || exit 1
                REFRESH_PULLED=1 exec bash "$SELF" refresh
            fi
            NONINTERACTIVE=1; detect_env; do_refresh ;;
        ha-sync) NONINTERACTIVE=1; detect_env; do_ha_sync ;;
        watchdog) NONINTERACTIVE=0; title "WATCHDOG EXPORTER"; need_root && do_watchdog ;;
        help|-h|--help) show_help ;;
        *) err "Unknown command: $cmd"; show_help; exit 1 ;;
    esac
    exit $?
fi

menu
