# Monitor Proxmox + Ceph (Prometheus / Grafana)

![Sơ đồ giám sát Proxmox + Ceph](docs/so-do-kien-truc.svg)

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

## Cài trọn gói: một lệnh, hỏi một lần

Clone repo lên 1 node Ceph của mỗi cluster rồi chạy:

```bash
git clone https://github.com/fixnhanh-linux/monitor-grafana-proxmox-full.git /root/monitor-grafana-proxmox-full
```

```bash
bash /root/monitor-grafana-proxmox-full/menu.sh setup
```

(hoặc mở `menu.sh` rồi chọn **S**). Tool hỏi hết các câu dưới đây, in **TÓM TẮT**, hỏi `Bắt đầu thực hiện? (y/N)`, rồi tự chạy từng bước `>>> [1/6] ...` và báo **KẾT QUẢ**.

| # | Câu hỏi | Mặc định / tự dò | Dùng để |
|---|---|---|---|
| 1 | Máy này làm gì: `1` node Ceph đầy đủ · `2` chỉ exporter · `3` chỉ dashboard | `1` | Chọn các bước sẽ chạy |
| 2 | Port exporter | `9830` | Cổng `/metrics` của service |
| 2 | Gộp tất cả metric ra 1 port? | `Y` | `Y`: Prometheus chỉ cần 1 target; `n`: giữ target ceph mgr / pve exporter riêng |
| 2 | Tên job Prometheus của cluster | `Proxmox-<cluster_name>` đọc từ `/etc/pve/corosync.conf` | File mẫu `prometheus-target-<job>.yml` |
| 3 | Tiêu đề, UID dashboard | `Proxmox - Ceph Prometheus`, `pve-ceph-prom` | UID trùng sẽ ghi đè dashboard cũ |
| 3 | Regex lọc datasource Site, regex lọc job | trống (tất cả), `/.*Proxmox-/` | Biến `$Site`, `$job` |
| 3 | Số node / pool / device class | đọc từ `ceph osd tree`, `ceph osd pool ls`, `ceph osd crush class ls` | Chiều cao các bảng |
| 3 | Ngưỡng latency theo class | `nvme=15:25,ssd=50:100,default=100:200` | Màu bảng Latency All OSD |
| 3 | Khoảng thời gian mặc định | `now-15m` | Time picker |
| 3 | Đặt tên ngắn + màu cho HA Groups? | đọc các chuỗi group đang có trong `/etc/pve/ha/` | Cột HA Groups, vd `Gold+HIGH:orange` |
| 4 | Grafana URL, token, folder UID | URL trống = chỉ xuất file JSON | Import qua API |
| 5 | Prometheus URL | trống = bỏ qua | Kiểm tra target `up` và job khớp ceph mgr |

Các bước tool tự làm (tuỳ lựa chọn ở câu 1):

1. Kiểm tra môi trường — có lỗi thì dừng, chưa cài gì
2. Cài / cập nhật service `pve-ceph-extra-exporter`
3. In và lưu đoạn `prometheus.yml` mẫu (`prometheus-target-<job>.yml`)
4. Sinh `proxmox_ceph_dashboard.json`
5. Import lên Grafana
6. Kiểm tra Prometheus

### Điều chỉnh sau khi cài

| Muốn đổi | Cách |
|---|---|
| Bất kỳ câu trả lời nào | Chạy lại `menu.sh setup` — giá trị cũ hiện sẵn trong `[ ]`, chỉ sửa câu cần đổi, Enter các câu khác |
| Sửa nhanh không qua câu hỏi | Sửa `.menu.conf` (dòng `DASH_TITLE=`, `DASH_LAT=`, `DASH_ALIASES=` ...) rồi chạy `menu.sh setup` và Enter liên tục |
| Chỉ port exporter | `bash menu.sh port 9300`, rồi sửa target trong `prometheus.yml` |
| Chỉ dashboard | Menu **9** (sinh lại) rồi **11** (import, UID giống nhau sẽ ghi đè) |
| Tên ngắn HA Groups | Menu **9** → trả lời `y` ở câu HA Groups; `DASH_ALIASES` lưu dạng `chuoi=Ten:mau;;chuoi2=Ten2` |
| Gỡ exporter | Menu **8** hoặc `bash menu.sh uninstall` |

Token Grafana không bao giờ được lưu, mỗi lần import phải nhập lại.

## Menu từng mục

```bash
bash /root/monitor-grafana-proxmox-full/menu.sh
```

| Mục | Việc |
|---|---|
| S | Cài trọn gói (như trên) |
| 1 | Kiểm tra python3, lệnh `ceph`, keyring, HA config, port trống, PVE firewall |
| 2 | Cài / cập nhật exporter (hỏi port, mặc định 9830) |
| 3 | Trạng thái service, collector OK/lỗi, dòng Ceph Status, Total Health |
| 4 | Xem metric (nếu chưa cài thì chạy thử 1 lần từ file nguồn) |
| 5 / 6 / 7 / 8 | Log, restart, đổi port, gỡ cài |
| 9 | Sinh dashboard JSON — tự đọc số node / pool / device class từ Ceph |
| 10 | In đoạn `prometheus.yml` mẫu cho node này |
| 11 | Import dashboard lên Grafana qua API (service account token, role Editor) |
| 12 | Hỏi Prometheus: target exporter có `up`, job của exporter có khớp job ceph mgr, device class từng cluster |
| 13 | Kiểm tra tổng thể (1 + 3 + 12) |
| 14 | Cập nhật tool (`git pull`), tự hỏi cài lại exporter nếu exporter có thay đổi |
| 15 | Xem / xoá cấu hình đã lưu (`.menu.conf`) |
| 16 | Giới thiệu & bản quyền FIX NHANH |

Chạy 1 lệnh không qua menu: `bash menu.sh setup | check | install [port] | status | metrics | logs | restart | port <số> | uninstall | dashboard | import | prom | prom-check | doctor | update | about`.

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

### Mặc định: gộp tất cả metric ra 1 port

Exporter phát lại `/metrics` của ceph mgr đang active (lấy địa chỉ qua `ceph mgr services`) và tự xuất metric Proxmox từ `pvesh` (tên giống `prometheus-pve-exporter`: `pve_cluster_info`, `pve_up`, `pve_cpu_usage_ratio`, `pve_memory_*`, `pve_disk_*`, `pve_uptime_seconds`, `pve_ha_state`). Mỗi cluster chỉ cần **1 target**:

```yaml
  - job_name: Proxmox-DECO
    scrape_interval: 30s
    scrape_timeout: 25s
    static_configs:
      - targets:
          - 10.0.0.11:9830   # pve_ceph_extra_exporter (tất cả metric)
```

Điều kiện: đã bật module prometheus của ceph mgr (`ceph mgr module enable prometheus`), menu **1** sẽ kiểm tra.

**Phải xoá** target `:9283` (ceph mgr) và `:9221` (pve exporter) cũ của cluster đó khỏi job, nếu không mọi số liệu bị nhân đôi. Menu **12** báo `Trùng` khi một job có 2 target cùng xuất metric ceph hoặc Proxmox.

### Không gộp (giữ target cũ)

Chọn `n` ở câu gộp (service chạy với `--no-ceph-mgr --no-pve`). Target exporter phải nằm **cùng job** với ceph mgr / pve exporter của cluster đó (dashboard lọc theo `job=~"$job"`):

```yaml
  - job_name: Proxmox-DECO
    static_configs:
      - targets:
          - 10.0.0.11:9283   # ceph mgr prometheus (đã có)
          - 10.0.0.11:9830   # pve_ceph_extra_exporter (mới)
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

Cột **HA** và **HA Groups** trong bảng *Resource Cluster* chỉ hiện khi cluster đang chọn ở biến `$job` có HA group / node-affinity rule; cluster không có HA thì hai cột này tự ẩn.
| `pve_ceph_extra_exporter_up{collector}` | 1 = thu thập OK (`ceph`, `ha`) |

---

Bản quyền © 2026 **FIX NHANH**. Bảo lưu mọi quyền — xem [LICENSE](LICENSE).
