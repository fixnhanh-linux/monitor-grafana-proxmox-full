# -*- coding: utf-8 -*-
"""Tao docs/so-do-kien-truc.vi.svg tu ban tieng Anh: thay chu hien thi, giu nguyen lenh / ten metric / ten panel.
Sua so do tieng Anh xong thi chay lai (them cau dich moi vao T neu co chu moi):

    python3 docs/make_vi_svg.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "so-do-kien-truc.svg")
DST = os.path.join(HERE, "so-do-kien-truc.vi.svg")

T = {
    "<title>Proxmox + Ceph monitoring: Prometheus / Grafana and Zabbix": "<title>Giám sát Proxmox + Ceph: Prometheus / Grafana và Zabbix",
    "<desc>Proxmox + Ceph clusters are read by pve_ceph_extra_exporter on a monitor host; Prometheus scrapes it and Grafana shows it, Zabbix reads the same exporter over HTTP and polls zabbix-agent2 on the nodes. Bottom: how to check each part on the servers and which values must match.":
        "<desc>Cluster Proxmox + Ceph được pve_ceph_extra_exporter trên máy monitor đọc; Prometheus thu thập, Grafana hiển thị, Zabbix đọc cùng exporter qua HTTP và hỏi zabbix-agent2 trên các node. Phía dưới: cách kiểm tra từng phần trên server và các giá trị phải khớp nhau.",
    ">Proxmox + Ceph monitoring  ·  Prometheus → Grafana  ·  Zabbix<": ">Giám sát Proxmox + Ceph  ·  Prometheus → Grafana  ·  Zabbix<",
    ">Moving arrows = data flow. Prometheus and Zabbix pull; the monitor host pushes config (SSH) and dashboards (Grafana API). Bottom: how to check it on the servers.<":
        ">Mũi tên chạy = chiều dữ liệu. Prometheus và Zabbix chủ động kéo; máy monitor đẩy cấu hình (SSH) và dashboard (Grafana API). Phía dưới: cách kiểm tra trên server.<",
    ">PROXMOX + CEPH CLUSTER<": ">CLUSTER PROXMOX + CEPH<",
    ">One per site (P1-XD, FPT01-FPT02, Deco ...)<": ">Mỗi site một cluster (P1-XD, FPT01-FPT02, Deco ...)<",
    ">Health · PG map · OSD · pools · latency<": ">Health · PG map · OSD · pool · độ trễ<",
    ">NVMe / SSD / HDD device classes<": ">Các device class NVMe / SSD / HDD<",
    ">Read-only token monitor@pve!exporter (PVEAuditor)<": ">Token chỉ đọc monitor@pve!exporter (PVEAuditor)<",
    ">Optional local mode (on a Ceph node)<": ">Chế độ local, tùy chọn (trên node Ceph)<",
    ">Service pve-ceph-extra-exporter :9830<": ">Dịch vụ pve-ceph-extra-exporter :9830<",
    ">Reads ceph status, pvesh, /etc/pve/ha<": ">Đọc ceph status, pvesh, /etc/pve/ha<",
    ">Remote mode: nothing is installed on the nodes,<": ">Chế độ từ xa: không cài gì lên các node,<",
    ">Only a read-only API token (menu 17)<": ">Chỉ cần một token API chỉ đọc (menu 17)<",
    ">API key zabbix-monitor · self-signed cert<": ">API key zabbix-monitor · cert tự ký<",
    ">Every node: zabbix-agent2  :10050<": ">Mọi node: zabbix-agent2  :10050<",
    ">Cron every minute: ceph health →<": ">Cron mỗi phút: ceph health →<",
    ">(Fallback, read with vfs.file.contents)<": ">(Dự phòng, đọc bằng vfs.file.contents)<",
    ">MONITOR HOST<": ">MÁY MONITOR<",
    ">Example 10.16.16.38 (Ubuntu) · git repo monitor-grafana-proxmox-full<": ">Ví dụ 10.16.16.38 (Ubuntu) · repo git monitor-grafana-proxmox-full<",
    ">One per cluster, every metric on one port:<": ">Mỗi cluster một exporter, mọi metric trên 1 port:<",
    ">Systemd @name  or  Docker fixnhanh-pve-&lt;name&gt;<": ">Systemd @tên  hoặc  Docker fixnhanh-pve-&lt;tên&gt;<",
    ">Mgr metrics + Proxmox + recovery % + HA groups<": ">Metric mgr + Proxmox + % recovery + nhóm HA<",
    ">Systemd timers<": ">Timer systemd<",
    ">Watchdog · 2 min: /health failing twice → restart<": ">Watchdog · 2 phút: /health lỗi 2 lần → khởi động lại<",
    ">HA colors · 5 min: new HA group → regenerate + import<": ">Màu HA · 5 phút: có nhóm HA mới → tạo lại + import<",
    ">Dashboards: dashboard-grafana/make_dashboard.py<": ">Dashboard: dashboard-grafana/make_dashboard.py<",
    ">HA Groups: one color per CPU type (.ha-colors.json)<": ">HA Groups: mỗi loại CPU một màu (.ha-colors.json)<",
    ">Internal / customer · saved args (fixnhanhArgs)<": ">Nội bộ / khách hàng · lưu tham số (fixnhanhArgs)<",
    ">Alerts: prometheus/pve-ceph-alerts.yml<": ">Cảnh báo: prometheus/pve-ceph-alerts.yml<",
    ">19 alert rules: exporter · Ceph · Proxmox<": ">19 luật cảnh báo: exporter · Ceph · Proxmox<",
    ">Menu 27: agent2 + cron + restful key on every node<": ">Menu 27: agent2 + cron + key restful trên mọi node<",
    ">Example 10.16.16.24:9090 · one per site<": ">Ví dụ 10.16.16.24:9090 · mỗi site một máy<",
    ">Job Proxmox-&lt;cluster&gt; → 1 target monitor:port<": ">Job Proxmox-&lt;cluster&gt; → 1 target máy-monitor:port<",
    ">Checked by promtool, restored on error<": ">promtool kiểm tra, lỗi thì trả lại file cũ<",
    ">One Prometheus datasource per site → variable $Site<": ">Mỗi site một datasource Prometheus → biến $Site<",
    ">Internal dashboard<": ">Dashboard nội bộ<",
    ">$Site · $job · $class · Exporter row · alarms<": ">$Site · $job · $class · hàng Exporter · cảnh báo<",
    ">Customer dashboards<": ">Dashboard khách hàng<",
    ">Locked job + datasource · read-only · own folder<": ">Khóa job + datasource · chỉ xem · folder riêng<",
    ">Total Health % · OSD · pools · latency · nodes · HA Groups<": ">Total Health % · OSD · pool · độ trễ · node · HA Groups<",
    ">Example 10.8.10.201 · Zabbix 6.0 / 6.2 / 7.0<": ">Ví dụ 10.8.10.201 · Zabbix 6.0 / 6.2 / 7.0<",
    ">HTTP, no agent · LLD nodes / OSDs / pools / collectors<": ">HTTP, không cần agent · tự tìm node / OSD / pool<",
    ">Ceph by Zabbix agent 2  +  health fallback<": ">Ceph by Zabbix agent 2  +  bản dự phòng health<",
    ">Pull<": ">Kéo<",
    ">SSH push<": ">Đẩy SSH<",
    ">Scrape<": ">Thu thập<",
    ">Zabbix polls zabbix-agent2 :10050 on every node<": ">Zabbix hỏi zabbix-agent2 :10050 trên mọi node<",
    ">WHAT EACH TOOL SHOWS<": ">MỖI CÔNG CỤ HIỂN THỊ GÌ<",
    ">Same exporter data, three views<": ">Cùng dữ liệu exporter, ba cách xem<",
    ">6 · Exporter (internal dashboard only)<": ">6 · Exporter (chỉ dashboard nội bộ)<",
    ">Prometheus alerts  ·  19 rules<": ">Cảnh báo Prometheus  ·  19 luật<",
    ">• Exporter down<": ">• Exporter không trả lời<",
    ">• Collector failed<": ">• Collector bị lỗi<",
    ">• Data stale (more than 3 minutes)<": ">• Dữ liệu cũ (quá 3 phút)<",
    ">• Health ERROR · Health WARNING<": ">• Health ERROR · Health WARNING<",
    ">• OSD near full 85% · OSD full 90%<": ">• OSD gần đầy 85% · OSD đầy 90%<",
    ">• Pool near full 80%<": ">• Pool gần đầy 80%<",
    ">• PG inconsistent · Unfound objects<": ">• PG inconsistent · Object unfound<",
    ">• Recovery too long · High latency<": ">• Recovery quá lâu · Độ trễ cao<",
    ">• Node down · Cluster not quorate<": ">• Node chết · Cluster mất quorum<",
    ">• HA node fenced / lost / gone<": ">• Node HA bị fence / lost / gone<",
    ">• High CPU 90% · High memory 90%<": ">• CPU cao 90% · RAM cao 90%<",
    ">→ Alertmanager → Telegram / email<": ">→ Alertmanager → Telegram / email<",
    ">Zabbix template (exporter by HTTP)<": ">Template Zabbix (exporter qua HTTP)<",
    ">Items<": ">Item<",
    ">• Exporter: version · mode · last collect<": ">• Exporter: version · chế độ · lần thu thập cuối<",
    ">• Ceph: health · recovery % / speed<": ">• Ceph: health · % / tốc độ recovery<",
    ">• Objects degraded / misplaced / unfound<": ">• Object degraded / misplaced / unfound<",
    ">• PGs not clean / inconsistent<": ">• PG chưa clean / inconsistent<",
    ">• OSDs up / in · quorum · nodes online<": ">• OSD up / in · quorum · node online<",
    ">Discovery (LLD)<": ">Tự tìm (LLD)<",
    ">• Nodes: up · CPU · RAM · uptime · HA<": ">• Node: up · CPU · RAM · uptime · HA<",
    ">• OSDs: up · in · latency · used %<": ">• OSD: up · in · độ trễ · % dùng<",
    ">• Pools: used % · stored · available<": ">• Pool: % dùng · đã lưu · còn trống<",
    ">• Collectors: up · last error<": ">• Collector: up · lỗi cuối<",
    ">Thresholds are macros, editable per host<": ">Ngưỡng là macro, sửa riêng từng host<",
    ">HOW TO CHECK IT ON THE SERVERS<": ">CÁCH KIỂM TRA TRÊN SERVER<",
    ">Top to bottom: a step fails → fix it before looking further<": ">Đi từ trên xuống: bước nào lỗi → sửa trước rồi mới xem tiếp<",
    ">Monitor host (ssh root)<": ">Máy monitor (ssh root)<",
    ">2 timers listed: watchdog + ha-colors<": ">Có 2 timer: watchdog + ha-colors<",
    ">Status → Targets: Proxmox-* all UP<": ">Status → Targets: mọi Proxmox-* UP<",
    ">Alerts tab: group pve-ceph loaded<": ">Tab Alerts: đã nạp nhóm pve-ceph<",
    ">Open /d/&lt;DASH_UID&gt; (UID in menu 15)<": ">Mở /d/&lt;DASH_UID&gt; (UID xem ở menu 15)<",
    ">Exporter row: every collector = 1<": ">Hàng Exporter: mọi collector = 1<",
    ">HA Groups: same CPU type = same color<": ">HA Groups: cùng loại CPU = cùng màu<",
    ">Node down → red  OFFLINE: &lt;group&gt;<": ">Node chết → đỏ  OFFLINE: &lt;nhóm&gt;<",
    ">New host → its color within 5 minutes<": ">Host mới → có màu trong 5 phút<",
    ">Old copy /d/pve-ceph-prom is not updated<": ">Bản cũ /d/pve-ceph-prom không được cập nhật<",
    ">Latest data → host → tag component<": ">Latest data → host → tag component<",
    ">Exporter: version + last collect fresh<": ">Exporter: có version, thu thập mới<",
    ">Discovery: nodes, OSDs, pools found<": ">Discovery: đã thấy node, OSD, pool<",
    ">Problems: same as Prometheus alerts<": ">Problems: giống cảnh báo Prometheus<",
    ">Run zabbix_get on Zabbix, cat on a node<": ">zabbix_get chạy trên Zabbix, cat trên node<",
    ">COMPARE: THE SAME VALUE IN EVERY PLACE<": ">SO SÁNH: CÙNG MỘT GIÁ TRỊ Ở MỌI NƠI<",
    ">Equal within ~1 minute; different → stale exporter, wrong job / port, or wrong Zabbix host<":
        ">Khớp nhau trong ~1 phút; lệch → exporter treo, sai job / port, hoặc host Zabbix sai port<",
    ">What<": ">Giá trị<",
    ">Grafana panel (Prometheus)<": ">Panel Grafana (Prometheus)<",
    ">Zabbix item (exporter by HTTP)<": ">Item Zabbix (exporter qua HTTP)<",
    ">On a Proxmox node (CLI)<": ">Trên node Proxmox (lệnh)<",
    ">Total Health gauge (100% when clean)<": ">Đồng hồ Total Health (100% khi sạch)<",
    ">OSDs up / in<": ">OSD up / in<",
    ">Nodes online / quorum<": ">Node online / quorum<",
    ">Resource Cluster table<": ">Bảng Resource Cluster<",
    ">HA state / HA groups<": ">Trạng thái HA / nhóm HA<",
    ">HA · HA Groups columns<": ">Cột HA · HA Groups<",
    '>Recovery: Grafana Recovery Speed = Zabbix "Ceph: recovery speed" = "recovery: … MiB/s" in ceph -s<':
        '>Recovery: Recovery Speed trên Grafana = Zabbix "Ceph: recovery speed" = "recovery: … MiB/s" trong ceph -s<',
    ">Reads data<": ">Đọc dữ liệu<",
    ">Pushes config / dashboards<": ">Đẩy cấu hình / dashboard<",
    ">Repo: proxmox-ceph-monitor.sh · exporter/ · dashboard-grafana/ · prometheus/ · template-zabbix/ · docs/ · tests/   ·   Update everything: proxmox-menu refresh<":
        ">Repo: proxmox-ceph-monitor.sh · exporter/ · dashboard-grafana/ · prometheus/ · template-zabbix/ · docs/ · tests/   ·   Cập nhật mọi thứ: proxmox-menu refresh<",
}


def translate(s):
    """Tra ve (svg tieng Viet, cac cau trong T khong con thay trong ban tieng Anh)."""
    miss = [k for k in T if k not in s]
    for k, v in T.items():
        s = s.replace(k, v)
    return s, miss


if __name__ == "__main__":
    with open(SRC, encoding="utf-8") as f:
        out, miss = translate(f.read())
    if miss:
        sys.exit("so-do-kien-truc.svg changed, update T in docs/make_vi_svg.py: %s" % miss)
    with open(DST, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("Wrote %s" % DST)
