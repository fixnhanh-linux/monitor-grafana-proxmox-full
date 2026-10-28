# Monitor Proxmox + Ceph (Prometheus / Grafana)

Bộ tool dựng dashboard **Proxmox - Ceph Prometheus** và lấp các ô đang báo `No data`.

| File | Việc |
|---|---|
| `menu.sh` | **Menu quản lý tất cả**: kiểm tra, cài, trạng thái, log, sinh/import dashboard, kiểm tra Prometheus |
| `make_dashboard.py` | Sinh JSON dashboard Grafana, import thẳng vào Grafana |
| `exporter/pve_ceph_extra_exporter.py` | Exporter bổ sung: trạng thái recovery/rebalance, Total Health %, Recovery Speed, HA Groups |
| `exporter/install_exporter.sh` | Cài exporter thành service systemd trên 1 node Proxmox |

## Vì sao dashboard cũ có ô "No data"

| Ô | Nguyên nhân | Bản mới |
|---|---|---|
| OSD Used Class Nvme / HDD / HDD12T, Top 5 NVME/HDD/HDD12T Latency | Cluster không có OSD class đó, panel bị cố định theo tên class | Panel lặp theo biến `$class` (lấy từ `ceph_osd_metadata`), chỉ hiện class có OSD |
| Detailed Alarms | Cluster HEALTH_OK nên `ceph_health_detail` rỗng | Hiện dòng `OK / HEALTH_OK / Không có cảnh báo` |
| Ceph Status, Total Health, Recovery Speed | Không có nguồn cho `ceph_custom_recovery_*` | `pve_ceph_extra_exporter` luôn xuất metric (100% / 0 B/s khi không recovery) |
| Cột HA Groups | Thiếu `pve_ha_groups_custom_info` | Exporter đọc `/etc/pve/ha/groups.cfg` và `rules.cfg` (PVE 9) |

Sửa thêm các lỗi query của bản cũ:
- Bảng **Resource Cluster with HA Groups** không lọc `job` → trộn node của mọi cluster trên cùng Prometheus.
- **OSDs OUT** tính `count(up) - count(in)` luôn ra 0; nay đếm `ceph_osd_in == 0`.
- **OSD Used Class HDD12T** cột Low lấy nhầm class `hdd`.

## Cách nhanh: dùng menu

Copy cả thư mục lên 1 node Ceph của mỗi cluster rồi chạy menu:

```bash
scp -r Monitor-Proxmox-Total root@<node-proxmox>:/root/
```

```bash
bash /root/Monitor-Proxmox-Total/menu.sh
```

| Mục | Việc |
|---|---|
| 1 | Kiểm tra python3, lệnh `ceph`, keyring, HA config, port trống, PVE firewall |
| 2 | Cài / cập nhật exporter (hỏi port, mặc định 9284) |
| 3 | Trạng thái service, collector OK/lỗi, dòng Ceph Status, Total Health |
| 4 | Xem metric (nếu chưa cài thì chạy thử 1 lần từ file nguồn) |
| 5 / 6 / 7 / 8 | Log, restart, đổi port, gỡ cài |
| 9 | Sinh dashboard JSON — tự đọc số node / pool / device class từ Ceph |
| 10 | In đoạn `prometheus.yml` mẫu cho node này |
| 11 | Import dashboard lên Grafana qua API (service account token, role Editor) |
| 12 | Hỏi Prometheus: target exporter có `up`, job của exporter có khớp job ceph mgr, device class từng cluster |
| 13 | Kiểm tra tổng thể (1 + 3 + 12) |

Chạy 1 lệnh không qua menu: `bash menu.sh check | install [port] | status | metrics | logs | restart | port <số> | uninstall | dashboard | import | prom | prom-check | doctor`.

Menu nhớ Grafana URL, Prometheus URL, tiêu đề/UID dashboard trong `.menu.conf` (không lưu token).

## 1. Cài exporter thủ công (trên 1 node Ceph của mỗi cluster)

```bash
scp -r exporter root@<node-proxmox>:/root/
```

```bash
bash /root/exporter/install_exporter.sh
```

Kiểm tra nhanh không cần cài: `python3 pve_ceph_extra_exporter.py --once`

## 2. Thêm vào Prometheus

Target phải nằm **cùng job** với ceph mgr / pve exporter của cluster đó (dashboard lọc theo `job=~"$job"`):

```yaml
  - job_name: Proxmox-DECO
    static_configs:
      - targets:
          - 10.0.0.11:9283   # ceph mgr prometheus (đã có)
          - 10.0.0.11:9284   # pve_ceph_extra_exporter (mới)
```

## 3. Sinh và import dashboard

```bash
python make_dashboard.py -o proxmox_ceph_dashboard.json
```

Tuỳ chọn:

```bash
python make_dashboard.py --title "Proxmox - Ceph DECO" --uid pve-ceph-deco --site-regex "/^Prometheus (FPT HN|CMC-Q7)$/" --nodes 5 --pools 4 --classes 1
```

- `--site-regex`: lọc datasource Prometheus cho biến **Site**
- `--job-regex`: lọc job của `pve_cluster_info` (mặc định `/.*Proxmox-/`)
- `--nodes / --pools / --classes`: chỉnh chiều cao các bảng cho vừa số dòng
- `--lat-th`: ngưỡng latency (ms) cảnh báo:nghiêm trọng theo class, mặc định `nvme=15:25,ssd=50:100,default=100:200`
- `--ha-alias "GROUPS=TEXT[:màu]"` (lặp được): tên ngắn và màu cho chuỗi HA Groups, vd `--ha-alias "Gold-6146,HIGH-FREQUENCY,P1-XD=Gold+HIGH+P1-XD:orange"`
- `--time-from`: khoảng thời gian mặc định, vd `now-5m`

Ví dụ dựng lại dashboard CMC Q7 / FPT HCM / VIETTEL HCM / CMC HN:

```bash
python make_dashboard.py -o cmc.json --title "Proxmox - Ceph Prometheus CMC Q7 - FPT HCM - VIETTEL HCM - CMC HN" --uid fix --time-from now-5m --site-regex "/^(Prometheus FPT HCM|Prometheus FPT HN|Prometheus CMC-Q7|Prometheus VIETTEL HCM|Prometheus CMC HN)$/" --job-regex "/^(?!.*Proxmox-Cluster-DMS|.*Test|.*Deco).*Proxmox-/" --ha-alias "BASIC-COMPUTING,INTEL-HIGH-CPU,P1-XD=BASIC+INTEL+P1-XD:purple" --ha-alias "Gold-6146,HIGH-FREQUENCY,P1-XD=Gold+HIGH+P1-XD:orange" --ha-alias "Gold-8260,INTEL-HIGH-CPU,Platinum-8260=Gold+INTEL+Platinum:blue" --ha-alias "Gold-8260,INTEL-HIGH-CPU,P1-XD,Platinum-8260=Gold+INTEL+P1+Platinum:green"
```

Lưu ý: import với `--uid fix` sẽ ghi đè dashboard đang có uid `fix`.

Grafana → Dashboards → New → Import → chọn file JSON.

## Metric của exporter

| Metric | Ý nghĩa |
|---|---|
| `ceph_custom_recovery_info{content,state}` | Dòng trạng thái; giá trị 0 = OK, 1 = recovery/rebalance, 2 = lỗi |
| `ceph_custom_recovery_percent` | % dữ liệu ổn định (100 khi không có degraded/misplaced) |
| `ceph_custom_recovery_speed_bytes` | Tốc độ recovery (bytes/s) |
| `ceph_custom_recovery_objects_per_sec` | Object recovery / giây |
| `ceph_custom_degraded_objects`, `_misplaced_objects`, `_unfound_objects` | Số object bất thường |
| `ceph_custom_pgs_not_clean` | Số PG không active+clean |
| `ceph_custom_progress_percent{event}` | Tiến độ các sự kiện `ceph progress` |
| `pve_ha_groups_custom_info{host,groups}` | HA group / node-affinity rule của node |
| `pve_ceph_extra_exporter_up{collector}` | 1 = thu thập OK (`ceph`, `ha`) |
