#!/bin/bash
# =============================================================================
#  FIX NHANH - Monitor Proxmox + Ceph
#    - pve_ceph_extra_exporter (Ceph recovery + HA groups)
#    - Dashboard Grafana (make_dashboard.py)
#
#  Chạy menu:        bash menu.sh
#  Cài trọn gói:     bash menu.sh setup   (hỏi 1 lần, tự làm hết)
#  Chạy 1 lệnh:      bash menu.sh <lệnh>
#      setup | check | install | status | metrics | logs | restart | port <số> |
#      uninstall | dashboard | import | prom | prom-check | doctor | update | about | help
#
#  Bản quyền © 2026 FIX NHANH. Bảo lưu mọi quyền.
# =============================================================================
set -uo pipefail

TOOL_NAME="FIX NHANH · Monitor Proxmox + Ceph"
TOOL_VERSION="2026.10.29"
REPO_URL="https://github.com/fixnhanh-linux/monitor-grafana-proxmox-full"
COPYRIGHT="© 2026 FIX NHANH · Bảo lưu mọi quyền"

DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORTER_SRC="$DIR/exporter/pve_ceph_extra_exporter.py"
INSTALLER="$DIR/exporter/install_exporter.sh"
MAKE_DASH="$DIR/make_dashboard.py"
DASH_JSON="$DIR/proxmox_ceph_dashboard.json"

SERVICE=pve-ceph-extra-exporter
BIN=/usr/local/bin/pve_ceph_extra_exporter.py
UNIT=/etc/systemd/system/$SERVICE.service
CONF="$DIR/.menu.conf"          # nhớ Grafana URL, Prometheus URL, ... giữa các lần chạy
DEFAULT_PORT=9284

# =============================================================================
# Giao diện: màu, khung căn giữa
# =============================================================================
# ${#chuoi} đếm đúng ký tự tiếng Việt / khung chỉ khi locale là UTF-8
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

vis_len() {  # độ dài hiển thị (bỏ mã màu)
    local s; s=$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'); echo ${#s}
}
hline() { local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }

box_top()    { echo "${IND}${BC}╭$(hline ─ $((BOXW - 2)))╮${N}"; }
box_sep()    { echo "${IND}${BC}├$(hline ─ $((BOXW - 2)))┤${N}"; }
box_bottom() { echo "${IND}${BC}╰$(hline ─ $((BOXW - 2)))╯${N}"; }
box_row() {  # dòng căn trái trong khung
    local t="$1" pad; pad=$((BOXW - 4 - $(vis_len "$t"))); [ $pad -lt 0 ] && pad=0
    printf '%s%s│%s %s%*s %s│%s\n' "$IND" "$BC" "$N" "$t" "$pad" '' "$BC" "$N"
}
box_center() {  # dòng căn giữa trong khung
    local t="$1" len l r; len=$(vis_len "$t")
    l=$(((BOXW - 2 - len) / 2)); [ $l -lt 0 ] && l=0; r=$((BOXW - 2 - len - l)); [ $r -lt 0 ] && r=0
    printf '%s%s│%s%*s%s%*s%s│%s\n' "$IND" "$BC" "$N" "$l" '' "$t" "$r" '' "$BC" "$N"
}
box_title() {  # ├─ TIÊU ĐỀ ──────┤
    local t=" $1 " len; len=$(vis_len "$t")
    echo "${IND}${BC}├─${N}${W}${2:-$Y}${t}${N}${BC}$(hline ─ $((BOXW - 3 - len)))┤${N}"
}
box_row2() {  # 2 cột
    local a="$1" b="$2" cw pad; cw=$(((BOXW - 4) / 2))
    pad=$((cw - $(vis_len "$a"))); [ $pad -lt 1 ] && pad=1
    box_row "$a$(printf '%*s' $pad '')$b"
}
mi() { printf '%s%s%3s%s  %s' "${3:-$C}" "$W" "$1" "$N" "$2"; }   # mục menu: phím, chữ, màu
kv() {  # nhãn: giá trị (tự đệm theo số ký tự, printf %-Ns đếm byte với chữ có dấu)
    local p=$((12 - ${#1})); [ $p -lt 1 ] && p=1
    printf '%s%s%s%*s%s' "$D" "$1" "$N" "$p" '' "$2"
}

ok()   { echo "${IND}  ${G}✔${N}  $*"; }
warn() { echo "${IND}  ${Y}▲${N}  $*"; }
err()  { echo "${IND}  ${R}✘${N}  $*"; }
info() { echo "${IND}  ${C}●${N}  $*"; }
sub()  { sed "s/^/${IND}      /"; }   # thụt lề output lệnh
title() {
    local t=" $* " len l; len=$(vis_len "$t"); l=$(((BOXW - len) / 2)); [ $l -lt 2 ] && l=2
    echo; echo "${IND}${BC}$(hline ━ $l)${N}${W}${C}${t}${N}${BC}$(hline ━ $((BOXW - len - l)))${N}"
}
pause() {
    [ -t 0 ] && [ "${NONINTERACTIVE:-0}" = 0 ] || return 0
    echo; read -rp "${IND}  ${D}Nhấn Enter để quay lại menu...${N}" _
}

ask() {  # ask "Câu hỏi" "mặc định" -> in giá trị
    local q="$1" def="${2:-}" ans
    if [ -n "$def" ]; then read -rp "${IND}  ${C}❯${N} $q ${D}[$def]${N}: " ans
    else read -rp "${IND}  ${C}❯${N} $q: " ans; fi
    echo "${ans:-$def}"
}
confirm() {  # confirm "Câu hỏi" -> 0 nếu đồng ý
    local ans; read -rp "${IND}  ${Y}?${N} $1 ${D}(y/N)${N}: " ans
    [[ "$ans" =~ ^[YyCc]$ ]]
}

need_root() {
    [ "$(id -u)" = 0 ] && return 0
    err "Cần chạy bằng root (sudo bash menu.sh)"; return 1
}
has() { command -v "$1" >/dev/null 2>&1; }

# =============================================================================
# Cấu hình lưu
# =============================================================================
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
# Nhận diện máy (chạy 1 lần khi mở menu)
# =============================================================================
detect_env() {
    ENV_OS=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-?}")
    ENV_PVE=""; has pveversion && ENV_PVE=$(pveversion 2>/dev/null | sed -n 's|^pve-manager/\([^/ ]*\).*|\1|p')
    ENV_CEPH=0
    has ceph && timeout 8 ceph status >/dev/null 2>&1 && ENV_CEPH=1
    ENV_GRAFANA=""; ENV_PROM=""
    if has curl; then
        curl -sf --max-time 2 http://127.0.0.1:3000/api/health >/dev/null 2>&1 && ENV_GRAFANA="http://127.0.0.1:3000"
        curl -sf --max-time 2 http://127.0.0.1:9090/-/ready >/dev/null 2>&1 && ENV_PROM="http://127.0.0.1:9090"
    fi
    if [ $ENV_CEPH = 1 ]; then ENV_ROLE=1; else ENV_ROLE=3; fi
}

ceph_health_short() {
    [ "${ENV_CEPH:-0}" = 1 ] || { echo "${D}không có trên máy này${N}"; return; }
    local h; h=$(timeout 8 ceph health 2>/dev/null | awk '{print $1}')
    case "$h" in
        HEALTH_OK)   echo "${G}${W}HEALTH_OK${N}" ;;
        HEALTH_WARN) echo "${Y}${W}HEALTH_WARN${N}" ;;
        HEALTH_ERR)  echo "${R}${W}HEALTH_ERR${N}" ;;
        *)           echo "${R}không đọc được${N}" ;;
    esac
}

# =============================================================================
# 1. Kiểm tra môi trường
# =============================================================================
do_check() {
    title "KIỂM TRA MÔI TRƯỜNG"
    local bad=0

    if [ -f /etc/pve/.version ] || has pveversion; then
        ok "Proxmox VE: $(pveversion 2>/dev/null | head -1)"
    else
        warn "Không thấy Proxmox VE (vẫn chạy được trên node Ceph thường)"
    fi

    if has python3; then
        local pv; pv=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')
        if python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,5) else 1)'; then
            ok "python3 $pv"
        else
            err "python3 $pv quá cũ (cần >= 3.5)"; bad=1
        fi
    else
        err "Thiếu python3 (apt install python3)"; bad=1
    fi

    if has ceph; then
        ok "Lệnh ceph: $(ceph --version 2>/dev/null | awk '{print $3, $5}')"
        if timeout 15 ceph status --format json >/dev/null 2>&1; then
            ok "ceph status chạy được: $(timeout 15 ceph health 2>/dev/null)"
        else
            err "Không chạy được 'ceph status' (thiếu /etc/ceph/ceph.client.admin.keyring hoặc không kết nối được mon)"; bad=1
        fi
    else
        err "Máy này không có lệnh ceph → cài exporter trên 1 node Ceph của cluster"; bad=1
    fi

    if [ -f /etc/pve/ha/groups.cfg ] || [ -f /etc/pve/ha/rules.cfg ]; then
        ok "Có cấu hình HA: $(ls /etc/pve/ha/groups.cfg /etc/pve/ha/rules.cfg 2>/dev/null | xargs)"
    else
        info "Chưa có HA group/rule → cột HA Groups sẽ trống (bình thường)"
    fi

    local port; port=$(current_port)
    if has ss && ss -ltnp 2>/dev/null | grep -q ":$port "; then
        if ss -ltnp 2>/dev/null | grep ":$port " | grep -q python3; then
            ok "Port $port đang được exporter sử dụng"
        else
            err "Port $port bị chương trình khác chiếm: $(ss -ltnp | grep ":$port " | awk '{print $NF}')"; bad=1
        fi
    else
        ok "Port $port còn trống"
    fi

    if has pve-firewall && pve-firewall status 2>/dev/null | grep -q "enabled/running"; then
        warn "PVE firewall đang bật → mở port $port cho IP Prometheus:"
        echo "Datacenter/Node → Firewall → Add: IN ACCEPT tcp dport $port source <IP Prometheus>" | sub
    fi

    has curl || warn "Thiếu curl (apt install curl) - cần cho xem metric / import Grafana"

    if [ "$bad" = 0 ]; then ok "${G}${W}Môi trường sẵn sàng${N}"; else err "${R}${W}Cần xử lý các lỗi trên trước khi cài${N}"; fi
    return $bad
}

# =============================================================================
# 2. Cài / cập nhật exporter
# =============================================================================
do_install() {
    title "CÀI / CẬP NHẬT EXPORTER"
    need_root || return 1
    [ -f "$EXPORTER_SRC" ] || { err "Không thấy $EXPORTER_SRC"; return 1; }
    local port="${1:-}"
    [ -n "$port" ] || port=$(ask "Port exporter" "$(current_port)")
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] \
        || { err "Port không hợp lệ: $port"; return 1; }

    if [ -f "$BIN" ]; then
        local old new
        old=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$BIN")
        new=$(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$EXPORTER_SRC")
        info "Bản đang cài: ${old:-?}  →  bản mới: ${new:-?}"
    fi

    if PORT="$port" bash "$INSTALLER" 2>&1 | sub; then
        ok "Đã cài service ${W}$SERVICE${N} port ${W}$port${N}"
        info "Bước tiếp theo: thêm target $(local_ip):$port vào Prometheus (menu 10)"
    else
        err "Cài exporter lỗi"; return 1
    fi
}

# =============================================================================
# 3. Trạng thái
# =============================================================================
do_status() {
    title "TRẠNG THÁI EXPORTER"
    if [ ! -f "$UNIT" ]; then
        warn "Chưa cài exporter trên máy này (menu 2 hoặc S)"; return 1
    fi
    local st port; st=$(svc_state); port=$(current_port)
    if [ "$st" = active ]; then ok "Service $SERVICE: ${G}${W}$st${N}"; else err "Service $SERVICE: ${R}$st${N}"; fi
    info "Port: ${W}$port${N}   ·   Bản: $(sed -n 's/^VERSION = "\(.*\)"/\1/p' "$BIN" 2>/dev/null)"
    info "Tự khởi động: $(systemctl is-enabled "$SERVICE" 2>/dev/null)"
    systemctl show "$SERVICE" -p ActiveEnterTimestamp -p NRestarts -p MemoryCurrent 2>/dev/null | sub

    if has curl; then
        local m line; m=$(curl -sf --max-time 20 "http://127.0.0.1:$port/metrics") || { err "Không gọi được /metrics"; return 1; }
        echo
        while read -r l; do
            [ -n "$l" ] || continue
            if [[ "$l" == *" 1" ]]; then ok "$l"; else err "$l"; fi
        done <<< "$(echo "$m" | grep '^pve_ceph_extra_exporter_up')"
        line=$(echo "$m" | grep '^ceph_custom_recovery_info')
        [ -n "$line" ] && info "Ceph: ${W}$(echo "$line" | sed 's/.*content="\([^"]*\)".*/\1/')${N}"
        info "Total Health: ${W}$(echo "$m" | awk '/^ceph_custom_recovery_percent /{print $2}') %${N}"
        info "HA groups: $(echo "$m" | grep -c '^pve_ha_groups_custom_info') node"
    fi
}

# =============================================================================
# 4. Xem metric
# =============================================================================
do_metrics() {
    title "METRIC HIỆN TẠI"
    local port; port=$(current_port)
    if [ "$(svc_state)" = active ] && has curl; then
        curl -sf --max-time 20 "http://127.0.0.1:$port/metrics" | grep -v '^#' | sub
    elif has python3 && [ -f "$EXPORTER_SRC" ]; then
        info "Service chưa chạy → chạy thử 1 lần từ file nguồn:"
        python3 "$EXPORTER_SRC" --once | grep -v '^#' | sub
    else
        err "Không lấy được metric"
    fi
}

# =============================================================================
# 5. Log / 6. Restart / 7. Đổi port / 8. Gỡ cài
# =============================================================================
do_logs() {
    title "LOG 50 DÒNG GẦN NHẤT"
    journalctl -u "$SERVICE" -n 50 --no-pager 2>/dev/null | sub || err "Không đọc được journal"
}

do_restart() {
    title "KHỞI ĐỘNG LẠI EXPORTER"
    need_root || return 1
    systemctl restart "$SERVICE" && sleep 2
    if [ "$(svc_state)" = active ]; then ok "Đã khởi động lại"; else err "Khởi động lại lỗi"; do_logs; fi
}

do_port() {
    title "ĐỔI PORT EXPORTER"
    need_root || return 1
    local p="${1:-}"
    [ -n "$p" ] || p=$(ask "Port mới" "$(current_port)")
    do_install "$p" && warn "Nhớ sửa target trong prometheus.yml sang port $p"
}

do_uninstall() {
    title "GỠ EXPORTER"
    need_root || return 1
    if [ "${NONINTERACTIVE:-0}" = 1 ] || confirm "Gỡ service $SERVICE khỏi máy này?"; then
        bash "$INSTALLER" uninstall 2>&1 | sub
    else
        info "Huỷ"
    fi
}

# =============================================================================
# Hàm dùng chung (menu lẻ + cài đặt trọn gói)
# =============================================================================
detect_cluster_name() {
    sed -n 's/^[[:space:]]*cluster_name:[[:space:]]*\([^[:space:]]*\).*/\1/p' /etc/pve/corosync.conf 2>/dev/null | head -1
}

detect_sizes() {  # đặt DN DP DC (số node / pool / device class) từ Ceph
    DN=8; DP=8; DC=3
    has ceph && has python3 && timeout 10 ceph status >/dev/null 2>&1 || return 1
    DN=$(timeout 10 ceph osd tree -f json 2>/dev/null | python3 -c \
        'import json,sys;print(sum(1 for x in json.load(sys.stdin)["nodes"] if x["type"]=="host"))' 2>/dev/null || echo 8)
    DP=$(timeout 10 ceph osd pool ls 2>/dev/null | wc -l)
    DC=$(timeout 10 ceph osd crush class ls -f json 2>/dev/null | python3 -c \
        'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 3)
}

detect_ha_groups() {  # mỗi chuỗi HA Groups khác nhau 1 dòng (dùng đúng code của exporter)
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

alias_of() {  # tên ngắn đã lưu cho 1 chuỗi HA Groups
    local x
    while IFS= read -r x; do
        [ "${x%=*}" = "$1" ] && { echo "${x##*=}"; return; }
    done <<< "${DASH_ALIASES//;;/$'\n'}"
}

ask_aliases() {  # hỏi tên ngắn cho từng chuỗi HA Groups đang có -> DASH_ALIASES
    local groups g t out=""
    groups=$(detect_ha_groups)
    if [ -z "$groups" ]; then
        info "Không đọc được HA groups trên máy này → giữ tên ngắn đã lưu (nếu có)"
        return 0
    fi
    info "Nhập tên ngắn, thêm :màu nếu muốn (vd ${W}Gold+HIGH:orange${N}). Enter trống = giữ tên gốc."
    while IFS= read -r g <&3; do
        t=$(ask "$g" "$(alias_of "$g")")
        [ -n "$t" ] && out+="${out:+;;}$g=$t"
    done 3<<< "$groups"
    DASH_ALIASES="$out"
}

gen_dashboard() {  # sinh $DASH_JSON từ các biến DASH_*
    has python3 || { err "Thiếu python3"; return 1; }
    dash_defaults
    local a args=(-o "$DASH_JSON" --title "$DASH_TITLE" --uid "$DASH_UID" --site-regex "$DASH_SITE"
                  --job-regex "$DASH_JOB" --nodes "$DASH_NODES" --pools "$DASH_POOLS"
                  --classes "$DASH_CLASSES" --lat-th "$DASH_LAT" --time-from "$DASH_TIME")
    while IFS= read -r a; do
        [ -n "$a" ] && args+=(--ha-alias "$a")
    done <<< "${DASH_ALIASES//;;/$'\n'}"
    python3 "$MAKE_DASH" "${args[@]}" >/dev/null || { err "Sinh dashboard lỗi"; return 1; }
    ok "Đã tạo ${W}$DASH_JSON${N}"
}

import_dashboard() {  # import_dashboard URL TOKEN FOLDER
    local url="${1%/}" token="$2" folder="$3" payload resp
    has curl && has python3 || { err "Cần curl và python3"; return 1; }
    [ -f "$DASH_JSON" ] || { err "Chưa có $DASH_JSON"; return 1; }
    if ! curl -sf --max-time 10 -H "Authorization: Bearer $token" "$url/api/health" >/dev/null; then
        err "Không kết nối được $url"; return 1
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
        ok "Import thành công: ${W}$url$(echo "$resp" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')${N}"
        save_conf GRAFANA_URL "$url"; save_conf GRAFANA_FOLDER "$folder"
    else
        err "Import lỗi: $resp"; return 1
    fi
}

prom_snippet() {  # prom_snippet JOB PORT -> in + lưu file mẫu prometheus.yml
    local job="$1" port="$2" ip f
    ip=$(local_ip); f="$DIR/prometheus-target-$job.yml"
    cat > "$f" <<EOF
# Thêm vào scrape_configs của prometheus.yml (CÙNG job với ceph mgr / pve exporter)
  - job_name: $job
    static_configs:
      - targets:
          - $ip:9283   # ceph mgr prometheus (đã có)
          - $ip:$port   # pve_ceph_extra_exporter (mới)
EOF
    info "Thêm target ${W}$ip:$port${N} vào ${W}CÙNG job '$job'${N} với ceph mgr / pve exporter:"
    echo; sed -n '2,$p' "$f" | sed "s/^/${IND}    ${O}/; s/$/${N}/"; echo
    info "Đã lưu mẫu: $f"
    info "Nếu job đã tồn tại thì chỉ thêm dòng '$ip:$port' vào danh sách targets."
    info "Trên máy Prometheus:"
    printf '%s\n' "promtool check config /etc/prometheus/prometheus.yml" \
        "systemctl reload prometheus      # hoặc: curl -X POST http://<prom>:9090/-/reload" | sub
}

prom_q() {  # prom_q URL QUERY -> in kết quả dạng "{labels} value"
    curl -sfG --max-time 15 "$1/api/v1/query" --data-urlencode "query=$2" | python3 -c '
import json, sys
r = json.load(sys.stdin)["data"]["result"]
for s in r:
    m = s["metric"]
    lab = ",".join("%s=%s" % (k, v) for k, v in sorted(m.items()) if k != "__name__")
    print("{%s} %s" % (lab, s["value"][1]))
'
}

prom_check() {  # prom_check URL -> 0 nếu exporter được scrape và job khớp
    local url="${1%/}" port out cj ej j rc=0
    has curl && has python3 || { err "Cần curl và python3"; return 1; }
    curl -sf --max-time 10 "$url/-/ready" >/dev/null || { err "Không kết nối được $url"; return 1; }
    save_conf PROM_URL "$url"
    port=$(current_port)

    echo; info "Target exporter (up{instance=~\".*:$port\"}):"
    out=$(prom_q "$url" "up{instance=~\".*:$port\"}")
    if [ -z "$out" ]; then
        err "Prometheus chưa scrape exporter → thêm target (menu 10) rồi reload Prometheus"; rc=1
    else
        while read -r l; do
            if [[ "$l" == *" 1" ]]; then ok "$l"; else err "$l (target down)"; rc=1; fi
        done <<< "$out"
    fi

    echo; info "Các job cluster (pve_cluster_info):"
    prom_q "$url" 'count by (job) (pve_cluster_info)' | sub

    echo; info "So sánh job: ceph mgr ↔ exporter:"
    cj=$(prom_q "$url" 'count by (job) (ceph_health_status)' | sed 's/{job=\(.*\)} .*/\1/')
    ej=$(prom_q "$url" 'count by (job) (ceph_custom_recovery_info)' | sed 's/{job=\(.*\)} .*/\1/')
    printf '%s\n' "ceph mgr : $(echo ${cj:-'<không có>'})" "exporter : $(echo ${ej:-'<không có>'})" | sub
    for j in $ej; do
        if echo "$cj" | grep -qx "$j"; then ok "job '$j' khớp"
        else err "job '$j' của exporter không có ceph mgr → dashboard sẽ không hiện Recovery"; rc=1; fi
    done

    echo; info "Trạng thái recovery từng cluster:"
    prom_q "$url" 'ceph_custom_recovery_info' | sub
    echo; info "OSD device class:"
    prom_q "$url" 'count by (job, device_class) (ceph_osd_metadata)' | sub
    return $rc
}

# =============================================================================
# 9. Sinh dashboard
# =============================================================================
ask_dashboard() {  # hỏi các tuỳ chọn dashboard -> biến DASH_*
    dash_defaults
    DASH_TITLE=$(ask "Tiêu đề dashboard" "$DASH_TITLE")
    DASH_UID=$(ask "UID (không dấu, không cách; trùng UID sẽ ghi đè)" "$DASH_UID")
    DASH_SITE=$(ask "Regex lọc datasource Site (bỏ trống = tất cả Prometheus)" "$DASH_SITE")
    DASH_JOB=$(ask "Regex lọc job cluster" "$DASH_JOB")
    if detect_sizes; then
        info "Đọc từ Ceph: ${W}$DN${N} node, ${W}$DP${N} pool, ${W}$DC${N} device class"
    else
        DN=$DASH_NODES; DP=$DASH_POOLS; DC=$DASH_CLASSES
    fi
    DASH_NODES=$(ask "Số node (chiều cao bảng HA)" "$DN")
    DASH_POOLS=$(ask "Số pool (chiều cao bảng pool)" "$DP")
    DASH_CLASSES=$(ask "Số device class" "$DC")
    DASH_LAT=$(ask "Ngưỡng latency ms theo class (cảnh báo:nghiêm trọng)" "$DASH_LAT")
    DASH_TIME=$(ask "Khoảng thời gian mặc định" "$DASH_TIME")
    if confirm "Đặt tên ngắn + màu cho HA Groups?"; then ask_aliases; fi
}

do_dashboard() {
    title "SINH DASHBOARD GRAFANA"
    ask_dashboard
    DASH_JSON=$(ask "File xuất" "$DASH_JSON")
    gen_dashboard || return 1
    save_dash_conf
    info "Import: Grafana → Dashboards → New → Import → Upload JSON, hoặc dùng menu 11"
}

# =============================================================================
# 11. Import dashboard qua Grafana API
# =============================================================================
ask_token() {
    info "Tạo token: Grafana → Administration → Service accounts → Add token (role Editor)"
    read -rsp "${IND}  ${C}❯${N} Service account token ${D}(không hiện khi gõ)${N}: " TOKEN; echo
}

do_import() {
    title "IMPORT DASHBOARD LÊN GRAFANA"
    [ -f "$DASH_JSON" ] || { warn "Chưa có $DASH_JSON → sinh trước"; do_dashboard || return 1; }
    local url folder
    url=$(ask "Grafana URL" "${GRAFANA_URL:-${ENV_GRAFANA:-http://127.0.0.1:3000}}")
    ask_token
    [ -n "$TOKEN" ] || { err "Chưa nhập token"; return 1; }
    folder=$(ask "Folder UID (bỏ trống = General)" "${GRAFANA_FOLDER:-}")
    import_dashboard "$url" "$TOKEN" "$folder"
}

# =============================================================================
# 10. Cấu hình Prometheus
# =============================================================================
do_prom() {
    title "CẤU HÌNH PROMETHEUS"
    local job cn
    cn=$(detect_cluster_name)
    job=$(ask "Tên job của cluster này trong Prometheus (giống job của ceph mgr)" "${PROM_JOB:-Proxmox-${cn:-CLUSTER}}")
    save_conf PROM_JOB "$job"
    prom_snippet "$job" "$(current_port)"
}

# =============================================================================
# 12. Kiểm tra phía Prometheus
# =============================================================================
do_prom_check() {
    title "KIỂM TRA DỮ LIỆU TRÊN PROMETHEUS"
    prom_check "$(ask "Prometheus URL" "${PROM_URL:-${ENV_PROM:-http://127.0.0.1:9090}}")"
}

# =============================================================================
# 13. Kiểm tra tổng thể
# =============================================================================
do_doctor() {
    do_check
    if [ -f "$UNIT" ]; then do_status; else warn "Exporter chưa cài trên máy này"; fi
    if [ -n "${PROM_URL:-}" ] && [ "${NONINTERACTIVE:-0}" = 0 ]; then
        confirm "Kiểm tra thêm Prometheus $PROM_URL?" && prom_check "$PROM_URL"
    fi
}

# =============================================================================
# 14. Cập nhật tool / 15. Cấu hình đã lưu / 16. Giới thiệu & bản quyền
# =============================================================================
do_update() {
    title "CẬP NHẬT TOOL"
    has git || { err "Thiếu git (apt install git)"; return 1; }
    [ -d "$DIR/.git" ] || { err "Thư mục không phải bản git clone → tải lại từ $REPO_URL"; return 1; }
    local before after
    before=$(git -C "$DIR" rev-parse --short HEAD)
    git -C "$DIR" pull --ff-only 2>&1 | sub
    after=$(git -C "$DIR" rev-parse --short HEAD)
    if [ "$before" = "$after" ]; then
        ok "Đang là bản mới nhất (${W}$after${N})"; return 0
    fi
    ok "Đã cập nhật ${W}$before → $after${N}:"
    git -C "$DIR" log --oneline "$before..$after" | sub
    if [ -f "$UNIT" ] && ! git -C "$DIR" diff --quiet "$before" "$after" -- exporter/; then
        warn "Exporter có thay đổi"
        confirm "Cài lại exporter bản mới (giữ port $(current_port))?" && do_install "$(current_port)"
    fi
    if [ "${NONINTERACTIVE:-0}" = 0 ]; then
        info "Mở lại menu với bản mới..."; sleep 1
        exec bash "$DIR/menu.sh"
    fi
}

do_config() {
    title "CẤU HÌNH ĐÃ LƯU"
    if [ ! -s "$CONF" ]; then
        info "Chưa có cấu hình đã lưu ($CONF)"; return 0
    fi
    info "File: $CONF"; echo
    local k v
    while IFS= read -r l; do
        k=${l%%=*}; v=$(. "$CONF"; printf '%s' "${!k-}")
        printf '%s    %s%-14s%s %s\n' "$IND" "$C" "$k" "$N" "${v:-${D}<trống>${N}}"
    done < "$CONF"
    echo
    info "Sửa: chạy lại ${W}S${N} (giá trị cũ hiện sẵn) hoặc sửa trực tiếp file trên"
    if confirm "Xoá toàn bộ cấu hình đã lưu?"; then
        rm -f "$CONF"; ok "Đã xoá - lần chạy sau sẽ hỏi lại từ đầu"
        unset "${!DASH_@}" GRAFANA_URL GRAFANA_FOLDER PROM_URL PROM_JOB SETUP_ROLE 2>/dev/null || true
    fi
}

do_about() {
    echo
    box_top
    box_center "${W}${C}$TOOL_NAME${N}"
    box_center "${D}phiên bản $TOOL_VERSION${N}"
    box_sep
    box_row "$(kv "Phát triển" "${W}FIX NHANH${N}")"
    box_row "$(kv "Repo" "${REPO_URL#https://}")"
    box_row "$(kv "Thành phần" "menu.sh · make_dashboard.py · pve_ceph_extra_exporter")"
    box_row "$(kv "Yêu cầu" "bash, python3 >= 3.5, curl; node Ceph cho exporter")"
    box_row "$(kv "Giấy phép" "xem file LICENSE")"
    box_sep
    box_center "${Y}Bản quyền © 2026 FIX NHANH. Bảo lưu mọi quyền.${N}"
    box_bottom
}

# =============================================================================
# S. Cài đặt trọn gói: hỏi hết 1 lần, xác nhận, rồi tự làm từng bước
# =============================================================================
progress() {  # progress STEP TOTAL -> thanh tiến độ
    local w=24 f; f=$(($1 * w / $2))
    printf '%s%s%s%s' "$G" "$(hline █ $f)" "$D" "$(hline ░ $((w - f)))"; printf '%s' "$N"
}

do_setup() {
    title "CÀI ĐẶT TRỌN GÓI"
    info "Trả lời các câu hỏi bên dưới (Enter = dùng giá trị trong ${D}[ ]${N})."
    info "Câu trả lời được nhớ trong .menu.conf cho lần chạy sau (không lưu token)."
    dash_defaults
    [ -n "${ENV_ROLE:-}" ] || detect_env
    local role port="" job="" cn gurl="" gfolder="" prom="" TOKEN=""
    local do_ex=0 do_dash=0 do_imp=0 do_chk=0

    echo; echo "${IND}  ${W}${M}[1/5] Máy này làm gì?${N}"
    echo "${IND}     ${C}1${N}  Node Ceph: cài exporter + sinh/import dashboard (đầy đủ)"
    echo "${IND}     ${C}2${N}  Chỉ cài exporter (node Ceph)"
    echo "${IND}     ${C}3${N}  Chỉ sinh / import dashboard (máy Grafana / máy quản trị)"
    if [ "$ENV_CEPH" = 1 ]; then info "Máy này có Ceph → gợi ý ${W}1${N}"
    else info "Máy này không có Ceph → gợi ý ${W}3${N} (exporter cài trên node Ceph)"; fi
    role=$(ask "Chọn" "${SETUP_ROLE:-$ENV_ROLE}")
    case "$role" in
        1) do_ex=1; do_dash=1 ;;
        2) do_ex=1 ;;
        3) do_dash=1 ;;
        *) err "Lựa chọn không hợp lệ: $role"; return 1 ;;
    esac
    if [ $do_ex = 1 ] && [ "$ENV_CEPH" != 1 ]; then
        warn "Chọn cài exporter nhưng máy này không chạy được 'ceph status' → bước kiểm tra sẽ dừng lại"
        confirm "Vẫn tiếp tục?" || { info "Huỷ - chạy lại và chọn 3, hoặc chạy trên node Ceph"; return 1; }
    fi

    if [ $do_ex = 1 ]; then
        need_root || return 1
        echo; echo "${IND}  ${W}${M}[2/5] Exporter${N}"
        port=$(ask "Port exporter" "$(current_port)")
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] \
            || { err "Port không hợp lệ: $port"; return 1; }
        cn=$(detect_cluster_name)
        [ -n "$cn" ] && info "Tên cluster Proxmox (corosync): ${W}$cn${N}"
        job=$(ask "Tên job Prometheus của cluster (phải trùng job của ceph mgr)" "${PROM_JOB:-Proxmox-${cn:-CLUSTER}}")
    fi

    if [ $do_dash = 1 ]; then
        echo; echo "${IND}  ${W}${M}[3/5] Dashboard${N}"
        ask_dashboard
        echo; echo "${IND}  ${W}${M}[4/5] Grafana${N}"
        [ -n "${ENV_GRAFANA:-}" ] && info "Phát hiện Grafana trên máy này: ${W}$ENV_GRAFANA${N}"
        gurl=$(ask "Grafana URL (bỏ trống = không import, chỉ xuất file JSON)" "${GRAFANA_URL:-${ENV_GRAFANA:-}}")
        if [ -n "$gurl" ]; then
            ask_token
            gfolder=$(ask "Folder UID (bỏ trống = General)" "${GRAFANA_FOLDER:-}")
            if [ -n "$TOKEN" ]; then do_imp=1; else warn "Không có token → chỉ xuất file JSON"; fi
        fi
    fi

    echo; echo "${IND}  ${W}${M}[5/5] Prometheus${N}"
    [ -n "${ENV_PROM:-}" ] && info "Phát hiện Prometheus trên máy này: ${W}$ENV_PROM${N}"
    prom=$(ask "Prometheus URL để kiểm tra sau khi cài (bỏ trống = bỏ qua)" "${PROM_URL:-${ENV_PROM:-}}")
    [ -n "$prom" ] && do_chk=1

    echo; box_top
    box_center "${W}${Y}TÓM TẮT${N}"
    box_sep
    if [ $do_ex = 1 ]; then
        box_row "$(kv "Exporter" "service $SERVICE · $(hostname) · port ${W}$port${N}")"
        box_row "$(kv "Job Prom" "${W}$job${N} (target $(local_ip):$port)")"
    fi
    if [ $do_dash = 1 ]; then
        box_row "$(kv "Dashboard" "\"$DASH_TITLE\" · uid ${W}$DASH_UID${N}")"
        box_row "$(kv "Lọc" "Site ${DASH_SITE:-<tất cả>} · job $DASH_JOB")"
        box_row "$(kv "Kích thước" "$DASH_NODES node · $DASH_POOLS pool · $DASH_CLASSES class · $DASH_TIME")"
        box_row "$(kv "Latency" "$DASH_LAT")"
        box_row "$(kv "HA alias" "$(echo "${DASH_ALIASES:-<không>}" | sed 's/;;/ | /g' | cut -c1-55)")"
        if [ $do_imp = 1 ]; then box_row "$(kv "Grafana" "import → $gurl · folder ${gfolder:-General}")"
        else box_row "$(kv "Grafana" "không import (import tay file JSON)")"; fi
    fi
    if [ $do_chk = 1 ]; then box_row "$(kv "Kiểm tra" "$prom")"; else box_row "$(kv "Kiểm tra" "bỏ qua")"; fi
    box_bottom; echo
    confirm "Bắt đầu thực hiện?" || { info "Huỷ - chưa thay đổi gì"; return 1; }

    save_conf SETUP_ROLE "$role"
    [ -n "$job" ] && save_conf PROM_JOB "$job"
    [ $do_dash = 1 ] && save_dash_conf
    [ -n "$prom" ] && save_conf PROM_URL "${prom%/}"

    local step=0 total=$((do_ex * 3 + do_dash + do_imp + do_chk)) failed=()
    next() {
        step=$((step + 1))
        echo; echo "${IND}${W}${C}▶ [$step/$total]${N} $(progress $step $total) ${W}$1${N}"
    }

    if [ $do_ex = 1 ]; then
        next "Kiểm tra môi trường"
        do_check || { err "Dừng lại: sửa các lỗi trên rồi chạy lại (menu S)"; return 1; }
        next "Cài exporter (port $port)"
        do_install "$port" || return 1
        next "Cấu hình Prometheus"
        prom_snippet "$job" "$port"
    fi
    if [ $do_dash = 1 ]; then
        next "Sinh dashboard"
        gen_dashboard || failed+=("sinh dashboard")
    fi
    if [ $do_imp = 1 ]; then
        next "Import dashboard lên Grafana"
        import_dashboard "$gurl" "$TOKEN" "$gfolder" || failed+=("import Grafana")
    fi
    if [ $do_chk = 1 ]; then
        next "Kiểm tra Prometheus"
        prom_check "$prom" || failed+=("kiểm tra Prometheus")
    fi

    echo; box_top
    if [ ${#failed[@]} = 0 ]; then box_center "${G}${W}✔ HOÀN TẤT $total BƯỚC${N}"
    else box_center "${R}${W}✘ LỖI Ở: ${failed[*]}${N}"; fi
    box_bottom
    [ $do_ex = 1 ] && [ $do_chk = 0 ] && \
        info "Nhớ thêm target vào Prometheus rồi chạy: bash menu.sh prom-check"
    [ $do_dash = 1 ] && [ $do_imp = 0 ] && \
        info "Import tay: Grafana → Dashboards → New → Import → $DASH_JSON"
    info "Muốn đổi câu trả lời: chạy lại menu S (giá trị cũ hiện sẵn), hoặc menu 15"
    [ ${#failed[@]} = 0 ]
}

# =============================================================================
# Menu
# =============================================================================
show_help() {
    sed -n '2,14p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
}

banner() {
    # chữ FIX NHANH kiểu ANSI Shadow, mỗi dòng 1 màu (gradient)
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
    if [ -f "$UNIT" ]; then st=$(svc_state); else st="chưa cài"; fi
    case "$st" in active) ex="${G}${W}● đang chạy${N} :$port" ;; "chưa cài") ex="${D}○ chưa cài${N}" ;; *) ex="${R}● $st${N}" ;; esac
    pve="${ENV_PVE:+${G}PVE $ENV_PVE${N}}"; pve="${pve:-${D}không phải node PVE${N}}"
    grafana="${GRAFANA_URL:-${ENV_GRAFANA:-}}"; grafana="${grafana:-${D}chưa cấu hình${N}}"
    prom="${PROM_URL:-${ENV_PROM:-}}"; prom="${prom:-${D}chưa cấu hình${N}}"

    echo
    box_top
    banner
    box_center "${W}MONITOR PROXMOX + CEPH${N}  ${D}·${N}  ${B}Prometheus${N} ${D}→${N} ${O}Grafana${N}"
    box_center "${D}phiên bản $TOOL_VERSION${N}"
    box_title "THÔNG TIN MÁY" "$C"
    box_row2 "$(kv "Máy" "${W}$(hostname)${N}")" "$(kv "IP" "$(local_ip)")"
    box_row2 "$(kv "Proxmox" "$pve")" "$(kv "Ceph" "$(ceph_health_short)")"
    box_row2 "$(kv "Exporter" "$ex")" "$(kv "Hệ điều hành" "$(echo "$ENV_OS" | cut -c1-24)")"
    box_row "$(kv "Grafana" "$grafana")"
    box_row "$(kv "Prometheus" "$prom")"
}

menu_body() {
    box_title "CÀI ĐẶT NHANH" "$G"
    box_row "$(mi S "${W}Cài đặt trọn gói${N} ${D}- hỏi 1 lần, tự làm hết các bước bên dưới${N}" "$G")"
    box_title "EXPORTER  ${D}(chạy trên node Ceph)${N}" "$M"
    box_row2 "$(mi 1 "Kiểm tra môi trường" "$M")"   "$(mi 5 "Xem log" "$M")"
    box_row2 "$(mi 2 "Cài đặt / cập nhật" "$M")"    "$(mi 6 "Khởi động lại" "$M")"
    box_row2 "$(mi 3 "Trạng thái exporter" "$M")"   "$(mi 7 "Đổi port" "$M")"
    box_row2 "$(mi 4 "Xem metric hiện tại" "$M")"   "$(mi 8 "Gỡ cài đặt" "$M")"
    box_title "DASHBOARD & PROMETHEUS" "$O"
    box_row2 "$(mi 9 "Sinh dashboard JSON" "$O")"   "$(mi 11 "Import lên Grafana" "$O")"
    box_row2 "$(mi 10 "Mẫu prometheus.yml" "$O")"   "$(mi 12 "Kiểm tra Prometheus" "$O")"
    box_row  "$(mi 13 "Kiểm tra tổng thể (môi trường + exporter + Prometheus)" "$O")"
    box_title "TIỆN ÍCH" "$B"
    box_row2 "$(mi 14 "Cập nhật tool (git pull)" "$B")" "$(mi 16 "Giới thiệu & bản quyền" "$B")"
    box_row2 "$(mi 15 "Cấu hình đã lưu" "$B")"         "$(mi 0 "Thoát" "$R")"
    box_sep
    box_center "${D}$COPYRIGHT${N}"
    box_bottom
}

menu() {
    detect_env
    while true; do
        header
        menu_body
        local c; echo; read -rp "${IND}  ${C}❯${N} ${W}Chọn chức năng:${N} " c
        case "$c" in
            1) do_check ;;      2) do_install ;;   3) do_status ;;
            4) do_metrics ;;    5) do_logs ;;      6) do_restart ;;
            7) do_port ;;       8) do_uninstall ;; 9) do_dashboard ;;
            10) do_prom ;;      11) do_import ;;   12) do_prom_check ;;
            13) do_doctor ;;    14) do_update ;;   15) do_config ;;
            16) do_about ;;
            s|S) do_setup ;;
            0|q|Q) echo; echo "${IND}  ${D}Tạm biệt! $COPYRIGHT${N}"; echo; exit 0 ;;
            "") continue ;;
            *) warn "Lựa chọn không hợp lệ: $c" ;;
        esac
        pause
    done
}

# ----------------------------------------------------------------- dòng lệnh
if [ $# -gt 0 ]; then
    NONINTERACTIVE=1
    cmd="$1"; shift
    case "$cmd" in
        setup) NONINTERACTIVE=0; detect_env; do_setup ;;
        check) do_check ;;           install) do_install "${1:-$(current_port)}" ;;
        status) do_status ;;         metrics) do_metrics ;;
        logs) do_logs ;;             restart) do_restart ;;
        port) [ -n "${1:-}" ] || { err "Dùng: menu.sh port <số>"; exit 1; }; do_port "$1" ;;
        uninstall) do_uninstall ;;   dashboard) NONINTERACTIVE=0; detect_env; do_dashboard ;;
        import) NONINTERACTIVE=0; detect_env; do_import ;;
        prom) NONINTERACTIVE=0; do_prom ;;
        prom-check) NONINTERACTIVE=0; detect_env; do_prom_check ;;
        doctor) do_doctor ;;         update) do_update ;;
        about) do_about ;;
        help|-h|--help) show_help ;;
        *) err "Lệnh không rõ: $cmd"; show_help; exit 1 ;;
    esac
    exit $?
fi

menu
