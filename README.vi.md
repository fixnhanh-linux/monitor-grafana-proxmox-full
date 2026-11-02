# Giám sát Proxmox + Ceph (Prometheus / Grafana / Zabbix)

[English](README.md) · **Tiếng Việt**

![Sơ đồ giám sát Proxmox + Ceph](docs/so-do-kien-truc.vi.svg)

Bộ công cụ dựng dashboard Grafana **Proxmox - Ceph Prometheus** và lấp đầy mọi panel trước đây hiện `No data`.

| Đường dẫn | Công dụng |
|---|---|
| `menu.sh` | **Menu quản lý mọi thứ** (`proxmox-menu`): kiểm tra, cài đặt, trạng thái, log, dashboard, Prometheus, Zabbix, Docker, dịch vụ |
| `exporter/` | `pve_ceph_extra_exporter.py` (recovery / rebalance, Total Health %, Recovery Speed, HA Groups; phát lại metric ceph mgr + Proxmox trên cùng 1 port), `install_exporter.sh`, unit systemd `pve-ceph-extra-exporter@.service`, `Dockerfile` |
| `dashboard-grafana/` | `make_dashboard.py` (tạo dashboard) và `proxmox_ceph_dashboard.json` (dashboard mặc định, import được ngay) |
| `prometheus/` | `pve-ceph-alerts.yml` — luật cảnh báo Prometheus: exporter, Ceph, Proxmox |
| `template-zabbix/` | Template Zabbix (6.0+): `pve-ceph-exporter-by-http.yaml` (đọc exporter qua HTTP, không cần agent), `ceph-health-fallback.yaml`; `setup_ceph_zabbix.sh` (cài Zabbix Agent 2 cho Ceph trên mọi node qua SSH) |
| `docs/` | Sơ đồ kiến trúc tiếng Anh và tiếng Việt (`make_vi_svg.py` tạo bản tiếng Việt từ bản tiếng Anh) |
| `tests/` | Unit test (`python3 -m unittest discover -s tests`), chạy trên GitHub Actions; CI còn import template Zabbix vào Zabbix 6.0, 6.2 và 7.0 thật |
| `CHANGELOG.md` | Nhật ký thay đổi |

Sinh ra trên máy (không nằm trong git): `dashboard-local.json`, `dashboard-<tên>.json`, `prometheus-scrape-all.yml`, `.menu.conf`, `.grafana-token`, `.grafana-cert.pem`, `.ha-colors.json`, `.ha-groups.seen`.

## Vì sao dashboard cũ hiện "No data"

| Panel | Nguyên nhân | Bản mới |
|---|---|---|
| OSD Used Class Nvme / HDD / HDD12T, Top 5 NVME/HDD/HDD12T Latency | Cluster không có OSD thuộc class đó, panel bị viết cứng theo từng class | Panel lặp theo biến `$class` (lấy từ `ceph_osd_metadata`), chỉ hiện class đang có |
| Detailed Alarms | Cluster HEALTH_OK nên `ceph_health_detail` rỗng | Hiện `OK / HEALTH_OK / No alarms` |
| Ceph Status, Total Health, Recovery Speed | Không có gì xuất `ceph_custom_recovery_*` | `pve_ceph_extra_exporter` luôn xuất (100% / 0 B/s khi không recovery) |
| Cột HA Groups | Thiếu `pve_ha_groups_custom_info` | Exporter đọc `/etc/pve/ha/groups.cfg` và `rules.cfg` (PVE 9) |

Các lỗi query đã sửa so với dashboard cũ:
- **Resource Cluster with HA Groups** không lọc theo `job` → node của mọi cluster trên cùng Prometheus bị trộn lẫn.
- **OSDs OUT** tính `count(up) - count(in)`, luôn ra 0; nay đếm `ceph_osd_in == 0`.
- **OSD Used Class HDD12T** lấy cột Low từ class `hdd`.

## Kiểm tra trên server

Đi từ trên xuống; bước nào lỗi thì sửa bước đó trước khi xem tiếp (giống phần cuối sơ đồ).

| Ở đâu | Lệnh / chỗ xem | Kết quả đúng |
|---|---|---|
| Máy monitor | `proxmox-menu doctor` | mọi dòng ✔ |
| Máy monitor | `proxmox-menu services` | mọi exporter `active`, `/health ok` |
| Máy monitor | `curl -s http://127.0.0.1:9830/health` (port từng cluster: `proxmox-menu remote-list`) | `ok` |
| Máy monitor | `systemctl list-timers 'pve-ceph*'` · `journalctl -t pve-ceph-ha-colors -n 20` | có timer watchdog + ha-colors; dòng "No new HA groups" hoặc các dòng tạo lại dashboard |
| Prometheus | `proxmox-menu prom-check`, hoặc **Status → Targets** | mọi target `Proxmox-*` UP, job khớp với job ceph mgr |
| Prometheus | query `ceph_custom_recovery_percent`, `pve_ha_groups_custom_info` | mỗi cluster / node một series |
| Prometheus | tab **Alerts**, `promtool check rules /etc/prometheus/rules/pve-ceph-alerts.yml` | đã nạp nhóm `pve-ceph`, `SUCCESS` |
| Grafana | `/d/<DASH_UID>` (UID xem ở menu 15) | Total Health `100%`, Ceph Status OK, hàng Exporter toàn `1`; cùng loại CPU = cùng màu HA Groups; node chết hiện đỏ `OFFLINE: …` |
| Zabbix | **Monitoring → Latest data** → host, tag `component` | có version exporter + "last collect" mới; đã tìm thấy node / OSD / pool |
| Zabbix | `zabbix_get -s <node> -k agent.ping` (trên Zabbix server) · `cat /etc/zabbix/cephstatus.txt` (trên node) | `1` · `HEALTH_OK` |

**So sánh cùng một giá trị ở mọi nơi** (giống nhau trong khoảng 1 phút; lệch nhau nghĩa là exporter bị treo, sai job / port, hoặc host Zabbix trỏ sai port):

| Giá trị | Grafana | Zabbix (exporter qua HTTP) | Trên node Proxmox |
|---|---|---|---|
| Ceph health | Ceph Status | `Ceph: health` | `ceph health` |
| Total Health % | Total Health | `Ceph: total health (data stable)` | `ceph -s` (% degraded / misplaced) |
| OSD up / in | OSDs UP / IN / DOWN | `Ceph: OSDs up`, `Ceph: OSDs in` | `ceph osd stat` |
| Node online / quorum | Resource Cluster | `Proxmox: nodes online`, `Proxmox: cluster quorate` | `pvecm status` |
| Trạng thái HA / nhóm HA | HA, HA Groups | `Proxmox: node <tên> HA state / HA groups` | `ha-manager status`, `/etc/pve/ha/` |
| Tốc độ recovery | Recovery Speed | `Ceph: recovery speed` | `recovery: … MiB/s` trong `ceph -s` |

## Cài đặt: một lệnh, hỏi một lần

Clone repo lên một node Ceph của mỗi cluster (hoặc lên một máy monitor riêng, xem *Giám sát từ xa*) rồi chạy:

```bash
git clone https://github.com/fixnhanh-linux/monitor-grafana-proxmox-full.git /root/monitor-grafana-proxmox-full
```

```bash
bash /root/monitor-grafana-proxmox-full/menu.sh setup
```

(hoặc mở menu và chọn **S**). Công cụ hỏi hết các câu dưới đây, in **SUMMARY**, hỏi `Start? (y/N)`, rồi chạy từng bước và báo kết quả.

| # | Câu hỏi | Mặc định / tự nhận | Dùng cho |
|---|---|---|---|
| 1 | Máy này dùng để: `1` node Ceph đầy đủ · `2` chỉ exporter · `3` chỉ dashboard · `4` máy monitor từ xa | `1` | Chạy những bước nào |
| 2 | Port exporter | `9830` | Port `/metrics` của dịch vụ |
| 2 | Gộp mọi metric vào 1 port? | `Y` | `Y`: Prometheus chỉ cần 1 target; `n`: giữ target ceph mgr / pve exporter riêng |
| 2 | Tên job Prometheus | `Proxmox-<tên_cluster>` lấy từ `/etc/pve/corosync.conf` | File mẫu `prometheus-target-<job>.yml` |
| 3 | Tiêu đề, UID dashboard | `Proxmox - Ceph Prometheus`, `pve-ceph-prom` | Cùng UID thì ghi đè dashboard cũ |
| 3 | Regex datasource Site, regex job | rỗng (tất cả), `/.*Proxmox-/` | Biến `$Site`, `$job` |
| 3 | Số node / pool / device class | lấy từ `ceph osd tree`, `ceph osd pool ls`, `ceph osd crush class ls` | Chiều cao các bảng |
| 3 | Ngưỡng latency theo class | `nvme=15:25,ssd=50:100,default=100:200` | Màu bảng latency OSD |
| 3 | Khoảng thời gian mặc định | `now-15m` | Bộ chọn thời gian |
| 3 | Tên ngắn + màu cho HA Groups? | các chuỗi nhóm có trong `/etc/pve/ha/` | Cột HA Groups, vd `Gold+HIGH:purple` |
| 4 | URL Grafana, token, UID folder | URL rỗng = chỉ tạo file JSON | Import qua API |
| 5 | URL Prometheus | rỗng = bỏ qua | Kiểm tra target `up` và job khớp ceph mgr |

Các bước công cụ chạy (tùy câu trả lời 1):

1. Kiểm tra môi trường — dừng nếu lỗi, chưa cài gì
2. Cài / cập nhật dịch vụ `pve-ceph-extra-exporter`
3. In và lưu đoạn `prometheus.yml` mẫu (`prometheus-target-<job>.yml`)
4. Tạo `dashboard-local.json` (git không theo dõi, nên cập nhật không bao giờ bị chặn)
5. Import vào Grafana
6. Kiểm tra Prometheus

### Đổi cấu hình sau này

| Muốn đổi | Cách làm |
|---|---|
| Bất kỳ câu trả lời nào | Chạy lại `proxmox-menu setup` — giá trị hiện tại điền sẵn trong `[ ]`, Enter để giữ |
| Sửa nhanh không cần hỏi | Sửa `.menu.conf` (`DASH_TITLE=`, `DASH_LAT=`, `DASH_ALIASES=` ...) rồi chạy `proxmox-menu refresh` |
| Chỉ port exporter | `proxmox-menu port 9300`, rồi sửa target trong Prometheus |
| Chỉ dashboard | Menu **9** (tạo) rồi **11** (import; cùng UID thì ghi đè) |
| Tên ngắn HA Groups | Menu **9** → trả lời `y` ở câu HA Groups; `DASH_ALIASES` lưu dạng `chuỗi=Tên:màu;;chuỗi2=Tên2` |
| Gỡ exporter | Menu **8** hoặc `proxmox-menu uninstall` |

Token Grafana: nhập một lần ở menu 11; nếu chọn lưu thì nằm trong `.grafana-token` (chỉ root đọc, không vào git, không nằm trong `.menu.conf`). Token sai / hết hạn tự bị xóa và hỏi lại; xóa tay ở menu 15.

## Cập nhật mọi thứ: một lệnh, không hỏi gì

```bash
proxmox-menu refresh
```

Chạy `git pull`, tự khởi động lại bằng code mới, rồi dùng cấu hình đã lưu để: cài lại exporter (local + mọi cluster từ xa, systemd hoặc Docker) và khởi động lại, tạo lại mọi file dashboard và import vào Grafana (cần URL + token Grafana đã lưu ở menu 11), in bảng dịch vụ và kiểm tra Prometheus. Kết thúc bằng `Done, no errors` hoặc danh sách bước cần xem lại.

## Lệnh tắt `proxmox-menu`

Lần đầu chạy `bash /root/monitor-grafana-proxmox-full/menu.sh` bằng root, công cụ tạo `/usr/local/bin/proxmox-menu`. Từ đó gõ ở thư mục nào cũng được:

| Lệnh | Công dụng |
|---|---|
| `proxmox-menu` | Mở menu |
| `proxmox-menu refresh` | Cập nhật mọi thứ (git pull + exporter + dashboard + kiểm tra) |
| `proxmox-menu services` | Bảng dịch vụ: khởi động lại / dừng / log |
| `proxmox-menu <lệnh>` | Bất kỳ lệnh nào bên dưới (`remote-list`, `prom-push`, `docker-net` ...) |

Nếu chuyển thư mục công cụ đi chỗ khác, chạy `bash <thư-mục-mới>/menu.sh` một lần là lệnh tắt tự trỏ theo.

## Các mục menu

| Mục | Công dụng |
|---|---|
| S | Cài đặt đầy đủ (ở trên) |
| 1 | Kiểm tra python3, `ceph`, keyring, cấu hình HA, port trống, firewall PVE |
| 2 | Cài / cập nhật exporter (hỏi port, mặc định 9830) |
| 3 | Trạng thái dịch vụ, collector OK / lỗi, dòng Ceph Status, Total Health |
| 4 | Xem metric (chạy thử 1 lần từ mã nguồn nếu chưa cài) |
| 5 / 6 / 7 / 8 | Log, khởi động lại, đổi port, gỡ cài đặt |
| 9 | Tạo dashboard — số node / pool / device class đọc từ Ceph. Chọn **1 Nội bộ** (mọi cluster) hoặc **2 Khách hàng** (xem bên dưới) |
| 10 | `prometheus.yml` mẫu cho node này; khi có cluster từ xa thì gộp **mọi cluster** vào `prometheus-scrape-all.yml` (kiểm tra từng exporter, bỏ job trùng, báo khi 2 cấu hình đọc cùng 1 cluster), rồi tùy chọn đẩy lên máy Prometheus qua SSH, kèm luật cảnh báo (xem bên dưới) |
| 11 | Import dashboard vào Grafana qua API (token service account, quyền **Editor**); kiểm tra trước Grafana có datasource Prometheus khớp biến Site; với cert Grafana tự ký thì đề nghị **ghim cert** (so SHA-256 với trình duyệt) thay vì tắt kiểm tra TLS; giữ nguyên folder hiện tại của dashboard |
| 12 | Hỏi Prometheus: target exporter `up`, job exporter khớp job ceph mgr, device class từng cluster |
| 13 | Kiểm tra đầy đủ (1 + 3 + 12) |
| 14 | Cập nhật công cụ (`git pull`), đề nghị cài lại exporter nếu exporter có thay đổi |
| 15 | Xem / xóa cấu hình đã lưu (`.menu.conf`), **đặt URL Prometheus / Grafana** (có kiểm tra kết nối) |
| 16 | Giới thiệu & bản quyền |
| 17 | Thêm / sửa một cluster giám sát từ xa (token API) |
| 18 | Các cluster từ xa: port, dịch vụ, cluster thực đọc được, trạng thái từng phần; đỏ khi 2 cấu hình đọc cùng 1 cluster hoặc trùng job |
| 19 | Thử kết nối 1 cluster (giải thích 401 / 403 / firewall) |
| 20 | Xóa một cluster từ xa (dừng dịch vụ / container, xóa token) |
| 21 | Cài các gói cần thiết — tự nhận `apt` / `dnf` / `yum` / `zypper` / `pacman` / `apk` |
| 22 | Mở firewall cho IP Prometheus — tự nhận `ufw` / `firewalld` / `pve-firewall` |
| 23 | Chạy các cluster (đã thêm ở 17) bằng Docker: build image, chuyển từ systemd sang container cùng port |
| 24 | Quản lý container: trạng thái, log, khởi động lại, xóa (quay lại systemd) |
| 25 | Đổi dải IP Docker (`docker0` + dải cho mạng mới): kiểm tra dải private / trùng route, sao lưu `daemon.json`, khởi động lại Docker, kiểm tra container chạy lại; Docker lỗi thì trả lại file cũ |
| 26 | **Dịch vụ & sức khỏe**: bảng mọi exporter (local, `@cluster`, container) + Docker + watchdog với trạng thái, `/health`, port, tự chạy khi khởi động; `r`/`s`/`t` khởi động lại / dừng / chạy (một cái hoặc `a` = tất cả) rồi **kiểm tra** active + `/health` trong 40 giây, lỗi thì in log; `l` log; `b`/`B` bật / tắt tự chạy khi khởi động; `w` watchdog |
| 27 | **Zabbix: Ceph qua Zabbix Agent 2** — chạy `template-zabbix/setup_ceph_zabbix.sh` (xem *Zabbix* bên dưới) |

Chạy một lệnh không cần mở menu: `proxmox-menu setup | check | install [port] | status | metrics | logs | restart | port <số> | uninstall | dashboard | import | prom | prom-check | doctor | update | refresh | about | remote-add [tên] | remote-list | remote-test | remote-remove | prom-all | prom-push | prom-rules | urls | deps | firewall | docker-run | docker-manage | docker-net | services | watchdog | zabbix-ceph | ha-sync`.

Menu nhớ URL Grafana, URL Prometheus, tiêu đề / UID dashboard trong `.menu.conf`; token Grafana (nếu lưu) nằm riêng trong `.grafana-token`.

## Giám sát từ xa: không cài gì lên node Proxmox

Exporter chạy trên một **máy monitor** (vd 10.16.16.38, Ubuntu) và lấy dữ liệu qua **Proxmox API** bằng token chỉ đọc, cộng với `/metrics` của ceph mgr. Một máy monitor theo dõi được nhiều cluster, mỗi cluster là một dịch vụ `pve-ceph-extra-exporter@<tên>` trên port riêng (9830, 9831, ...). Tên metric giống hệt chế độ local, nên **dashboard không phải đổi**.

| Dữ liệu | Chế độ local (trên node) | Chế độ từ xa (máy monitor) |
|---|---|---|
| Metric Ceph (OSD, pool, latency) | `ceph mgr services` → mgr:9283 | Thử lần lượt `CEPH_MGR`; rỗng = mọi IP node lấy từ `/cluster/status` (mgr standby không trả dữ liệu → bỏ qua tới mgr active) |
| Node, CPU, RAM, uptime, HA | `pvesh`, `/etc/pve` | API `/cluster/status`, `/cluster/resources`, `/cluster/ha/status/manager_status` |
| Ceph Status / Recovery | `ceph status` | API `/cluster/ceph/status` |
| HA Groups | `/etc/pve/ha/*.cfg` | API `/cluster/ha/groups`, `/cluster/ha/rules` (PVE 9) |

### Bước 1: trên một node bất kỳ của mỗi cluster (một lần)

```bash
pveum user add monitor@pve --comment "FIX NHANH monitor"
```

```bash
pveum acl modify / --users monitor@pve --roles PVEAuditor
```

```bash
pveum user token add monitor@pve exporter --privsep 0
```

```bash
ceph mgr module enable prometheus
```

`PVEAuditor` chỉ được **đọc**. Lệnh tạo token in `value` (mã bí mật) **đúng một lần** — hãy lưu lại.

### Bước 2: trên máy monitor

```bash
proxmox-menu remote-add
```

(hoặc menu **17**, hoặc cài đầy đủ **S → 4**). Công cụ hỏi:

| Câu hỏi | Ví dụ / mặc định |
|---|---|
| Tên cluster | `FPT-HCM` |
| IP các node Proxmox | `10.16.16.60,10.16.16.61,10.16.16.62` — node này chết thì chuyển sang node kế |
| Token ID / secret | `monitor@pve!exporter` / secret (ẩn khi gõ) |
| Proxmox có cert hợp lệ không? | `N` (Proxmox mặc định dùng cert tự ký) |
| Ceph mgr | Enter = tự tìm mgr active trên mọi node (`:9283`) |
| Tên job Prometheus | `Proxmox-FPT-HCM` (phải chứa `Proxmox-`) |
| Port | port trống kế tiếp từ 9830 |

Công cụ **thử kết nối** và báo từng phần ✔ / ✘ (401 = sai token, 403 = thiếu quyền kèm đúng lệnh `pveum` để sửa, refused / timeout = firewall), rồi lưu `/etc/pve-ceph-extra-exporter/<tên>.env` (chmod 600, chỉ root), khởi động dịch vụ và in đoạn Prometheus mẫu (1 target `IP-máy-monitor:port`).

Máy monitor phải tới được **node:8006** và **mgr:9283**.

### Bảo mật & tải

- Dịch vụ chạy bằng **user tạm** (`DynamicUser`), không phải root; hệ thống file chỉ đọc (`ProtectSystem=strict`); giới hạn `CPUQuota=25%`, `MemoryMax=256M`.
- Token chỉ nằm trong file `.env` quyền 600, không bao giờ xuất hiện trên dòng lệnh / trong `ps`.
- Mỗi 30 giây: 5–6 request API + 1 request mgr cho mỗi cluster. Tải lên Proxmox không đáng kể.

### Server không phải Ubuntu

| Hệ điều hành | Ghi chú |
|---|---|
| Debian, Ubuntu, Rocky / Alma / RHEL 8+, Fedora, openSUSE, Arch | Hỗ trợ đầy đủ: menu **21** cài gói, **17** thêm cluster |
| CentOS 7 / RHEL 7 | Chạy được; systemd cũ bỏ qua `DynamicUser` nên dịch vụ chạy bằng root |
| Alpine, máy không có systemd, Windows (Docker Desktop / WSL2) | Dùng Docker: menu **17** rồi **23** |

Firewall (ufw / firewalld / pve-firewall): menu **22**, nhập IP Prometheus là mọi port exporter trên máy được mở.

### Docker

Thêm cluster ở menu **17** (để có file cấu hình), rồi menu **23**: công cụ build `fixnhanh/pve-ceph-exporter:<version>`, dừng dịch vụ systemd của cluster đó và chạy container `fixnhanh-pve-<tên>` trên cùng port (256 MB / 0.25 CPU, chỉ đọc, bỏ mọi capability). Target Prometheus không đổi. Menu **24** xem log / khởi động lại / xóa container (quay lại systemd). `proxmox-menu refresh` build lại image và tạo lại container khi version exporter thay đổi.

Chạy tay không qua menu:

```bash
docker build -t fixnhanh/pve-ceph-exporter exporter/
```

```bash
docker run -d --name fixnhanh-pve-FPT-HCM --restart unless-stopped -p 9830:9830 --env-file /etc/pve-ceph-extra-exporter/FPT-HCM.env fixnhanh/pve-ceph-exporter
```

## 1. Cài exporter bằng tay (trên một node Ceph của mỗi cluster)

```bash
scp -r exporter root@<node-proxmox>:/root/
```

```bash
bash /root/exporter/install_exporter.sh
```

Thử nhanh không cần cài: `python3 pve_ceph_extra_exporter.py --once`

## 2. Thêm vào Prometheus

### Mặc định: mọi metric trên một port

Exporter phát lại `/metrics` của ceph mgr đang active (địa chỉ lấy từ `ceph mgr services`) và xuất metric Proxmox từ `pvesh` (cùng tên với `prometheus-pve-exporter`: `pve_cluster_info`, `pve_up`, `pve_cpu_usage_ratio`, `pve_memory_*`, `pve_disk_*`, `pve_uptime_seconds`, `pve_ha_state`). Mỗi cluster chỉ cần **một target**:

```yaml
  - job_name: Proxmox-DECO
    scrape_interval: 30s
    scrape_timeout: 25s
    static_configs:
      - targets:
          - 10.0.0.11:9830   # pve_ceph_extra_exporter (all metrics)
```

Yêu cầu: đã bật module prometheus của ceph mgr (`ceph mgr module enable prometheus`); menu **1** có kiểm tra.

**Xóa** các target cũ `:9283` (ceph mgr) và `:9221` (pve exporter) của cluster khỏi job, nếu không mọi giá trị bị nhân đôi. Menu **12** báo trùng khi một job có 2 target cùng xuất metric ceph hoặc Proxmox.

### Nhiều cluster trên một máy monitor

Menu **10** (hoặc `proxmox-menu prom-all`) gộp mọi cluster vào `prometheus-scrape-all.yml`, file này đã bắt đầu bằng `scrape_configs:`.

| Prometheus của bạn | Cách thêm |
|---|---|
| Tách file: `prometheus.yml` có `scrape_config_files: [/etc/prometheus/scrape_configs/*.yml]` | Chép **nguyên file** vào thư mục đó, vd `proxmox-ceph-<máy-monitor>.yml` |
| Một file (mặc định) | Dán các khối `- job_name:` dưới `scrape_configs:` trong `prometheus.yml` |

Với kiểu tách file, trả lời `y` ở câu *Push the file to the Prometheus host over SSH* (hoặc `proxmox-menu prom-push`). Công cụ:

1. SSH vào máy Prometheus (đề nghị tạo key + `ssh-copy-id`; nếu không thì hỏi mật khẩu một lần mỗi lần chạy), kiểm tra thư mục và `scrape_config_files`.
2. Liệt kê các job đang có **cùng tên** hoặc **cùng target** với exporter và đề nghị **thay thế**: sao lưu cả thư mục vào `/root/prom-bak-<thời-gian>` trên máy Prometheus, xóa đúng các khối job đó, thêm job exporter dưới cùng tên (dashboard giữ nguyên tên job).
3. Liệt kê các target `:9283` / `:9221` khác để bạn xóa nếu chúng là cùng cluster.
4. Chép file và chạy `promtool check config`; lỗi thì **trả lại mọi thứ** và Prometheus không bị ảnh hưởng; không lỗi thì reload.

Host SSH, file cấu hình và thư mục được nhớ trong `.menu.conf`.

Sau file scrape, công cụ đề nghị đẩy luôn **luật cảnh báo** (hoặc `proxmox-menu prom-rules`): chép `prometheus/pve-ceph-alerts.yml` vào thư mục `rule_files` đang dùng (đọc từ `prometheus.yml`, vd `/etc/prometheus/rules/`). Nếu `prometheus.yml` chưa nạp thư mục đó, công cụ thêm vào `rule_files` (giữ bản `.bak`). Nếu `promtool check rules` + `check config` lỗi thì trả lại cả hai file.

Đầu menu hiện commit đang chạy (vd `2026.10.30 · de76e86`); khi GitHub có bản mới hơn thì hiện **New version → pick 14**.

### Không gộp (giữ target cũ)

Trả lời `n` ở câu hỏi gộp (dịch vụ chạy với `--no-ceph-mgr --no-pve`). Target exporter phải nằm **cùng job** với ceph mgr / pve exporter của cluster (dashboard lọc theo `job=~"$job"`):

```yaml
  - job_name: Proxmox-DECO
    static_configs:
      - targets:
          - 10.0.0.11:9283   # ceph mgr prometheus (existing)
          - 10.0.0.11:9830   # pve_ceph_extra_exporter (new)
```

### Luật cảnh báo

`prometheus/pve-ceph-alerts.yml` có các luật sau, áp dụng cho job chứa `Proxmox-`:

| Nhóm | Cảnh báo | Khi nào |
|---|---|---|
| Exporter | `PveCephExporterDown` | Không scrape được target exporter trong 2 phút (chỉ target của exporter này, không tính mgr standby) |
| | `PveCephExporterCollectorFailed` | Một collector lỗi 5 phút (panel tương ứng hiện No data) |
| | `PveCephExporterStale` | Không thu thập mới trong 3 phút (lệnh ceph / API bị treo) |
| Ceph | `CephHealthError` / `CephHealthWarning` | HEALTH_ERR 1 phút / HEALTH_WARN 15 phút |
| | `CephOsdDown` / `CephOsdOut` | OSD down 5 phút / out 15 phút |
| | `CephOsdNearFull` / `CephOsdFull` | OSD dùng > 85% / > 90% |
| | `CephPoolNearFull` | Pool dùng > 80% |
| | `CephPgInconsistent`, `CephUnfoundObjects` | PG inconsistent / object unfound |
| | `CephRecoveryTooLong` | Recovery / rebalance quá 6 giờ |
| | `CephOsdHighLatency` | Apply latency > 200 ms trong 10 phút |
| Proxmox | `PveNodeDown`, `PveClusterNotQuorate`, `PveHaNodeFenced` | Node offline, mất quorum, HA fence / lost |
| | `PveNodeHighCpu` / `PveNodeHighMemory` | CPU / RAM > 90% trong 15 phút |

Thêm bằng tay: chép file lên máy Prometheus và thêm vào `prometheus.yml`:

```yaml
rule_files:
  - /etc/prometheus/rules/pve-ceph-alerts.yml
```

```bash
promtool check rules /etc/prometheus/rules/pve-ceph-alerts.yml
```

Rồi reload Prometheus. Việc gửi tin (Telegram, email ...) cấu hình trong Alertmanager. Ngưỡng và thời gian `for:` sửa thẳng trong file.

## 3. Tạo và import dashboard

```bash
python3 dashboard-grafana/make_dashboard.py -o dashboard-grafana/proxmox_ceph_dashboard.json
```

Tùy chọn:

```bash
python3 dashboard-grafana/make_dashboard.py --title "Proxmox - Ceph DECO" --uid pve-ceph-deco --site-regex "/^Prometheus (FPT HN|CMC-Q7)$/" --nodes 5 --pools 4 --classes 1
```

- `--site-regex`: lọc datasource Prometheus cho biến **Site**
- `--job-regex`: lọc job trên `pve_cluster_info` (mặc định `/.*Proxmox-/`)
- `--nodes / --pools / --classes`: chiều cao các bảng
- `--lat-th`: ngưỡng latency (ms) cảnh báo:nghiêm trọng theo class, mặc định `nvme=15:25,ssd=50:100,default=100:200`
- `--ha-alias "NHÓM=TÊN[:màu]"` (lặp được): tên ngắn và màu cho một chuỗi HA Groups, vd `--ha-alias "Gold-6146,HIGH-FREQUENCY,P1-XD=Gold+HIGH+P1-XD:purple"`; node có sự cố luôn chuyển đỏ / cam bất kể màu nhóm
- `--prom-url URL` / `--ha-group NHÓM`: nhóm không có `--ha-alias` được tự gán màu (không bao giờ đỏ / cam), **mỗi loại CPU một màu**: tên model trong chuỗi nhóm (một từ + số model từ 3 chữ số, vd `Gold-8260`, `Platinum-8260`, `EPYC-7543`) được tự nhận, nên `Gold-8260,HIGH-MEMORY,...,Platinum-8260` và `Gold-8260,...,Platinum-8260` cùng màu; nhóm không có tên model thì xếp theo nhóm đầu tiên (vd `BASIC-COMPUTING`); với `--prom-url` danh sách nhóm được đọc từ Prometheus mỗi lần tạo dashboard. Menu 9 / `refresh` tự truyền URL Prometheus đã lưu
- `--color-state FILE`: nhớ màu của từng loại CPU (menu dùng `.ha-colors.json`, dùng chung cho mọi dashboard): loại cũ giữ màu, loại mới lấy một màu chưa dùng
- **Host / nhóm mới tự lên màu**: `refresh` cài timer systemd `pve-ceph-ha-colors` (cần root + URL / token Grafana đã lưu). Cứ 5 phút chạy `proxmox-menu ha-sync`: khi xuất hiện chuỗi HA Groups mới (host mới, nhóm mới, site mới) thì tạo lại và import lại mọi dashboard. Log: `journalctl -t pve-ceph-ha-colors`
- `--time-from`: khoảng thời gian mặc định, vd `now-5m`
- `--customer-job JOB`: dashboard khách hàng (xem bên dưới)
- `--regen FILE`: tạo lại FILE bằng tham số đã lưu bên trong nó

Import: Grafana → Dashboards → New → Import → tải file JSON lên, hoặc menu 11. Import với UID đã có sẽ ghi đè dashboard đó.

## Nhiều dashboard (mỗi nhóm Site một dashboard)

Mỗi `dashboard-<tên>.json` trong thư mục công cụ lưu sẵn tham số đã dùng để tạo nó (`fixnhanhArgs`). `proxmox-menu refresh` tạo lại và import **tất cả**, giữ nguyên folder Grafana hiện tại của từng dashboard. Menu 11 cho chọn file nào để import.

Tạo một lần (lấy UID từ URL dashboard đang có `/d/<uid>/...`; cùng UID thì ghi đè dashboard đó):

```bash
cd /root/monitor-grafana-proxmox-full && python3 dashboard-grafana/make_dashboard.py -o dashboard-cmc.json --title "Proxmox - Ceph Prometheus CMC Q7 - FPT HCM - VIETTEL HCM - CMC HN" --uid fix --time-from now-5m --site-regex "/^(Prometheus FPT HCM|Prometheus FPT HN|Prometheus CMC-Q7|Prometheus VIETTEL HCM|Prometheus CMC HN)$/" --job-regex "/^(?!.*Proxmox-Cluster-DMS|.*Test|.*Deco).*Proxmox-/" --nodes 15 --pools 6 --ha-alias "BASIC-COMPUTING,INTEL-HIGH-CPU,P1-XD=BASIC+INTEL+P1-XD:purple" --ha-alias "Gold-6146,HIGH-FREQUENCY,P1-XD=Gold+HIGH+P1-XD:orange" --ha-alias "Gold-8260,INTEL-HIGH-CPU,P1-XD,Platinum-8260=Gold+INTEL+P1+Platinum:green" --ha-alias "Gold-8260,INTEL-HIGH-CPU,Platinum-8260=Gold+INTEL+Platinum:blue"
```

Tạo lại một file bằng tham số đã lưu: `python3 dashboard-grafana/make_dashboard.py --regen dashboard-cmc.json`.

## Dashboard khách hàng

Menu **9** → `2` tạo `dashboard-kh-<job>.json` cho **một khách hàng**:

| | Nội bộ | Khách hàng |
|---|---|---|
| Site / Job | Mọi datasource, mọi cluster | **Ẩn**, khóa vào 1 datasource + 1 job |
| Health, dung lượng, OSD, pool, latency, recovery | ✔ | ✔ |
| CPU / RAM / uptime node | ✔ | ✔ |
| Detailed Alarms (thông báo Ceph thô) | ✔ | ✘ |
| Cột HA / HA Groups | ✔ | ✘ |
| Hàng Exporter (collector, lỗi, version) | ✔ | ✘ |
| Chỉnh sửa | Cho phép | Khóa (`editable: false`) |

Công cụ hỏi job của khách (liệt kê từ Prometheus), tên khách, **tên datasource Grafana** (khớp chính xác), tiêu đề và UID `kh-<job>`. Phân quyền Grafana: tạo một **folder** cho khách → import dashboard vào đó (menu 11 hỏi file nào và UID folder) → cấp cho user / team của khách quyền **Viewer trên folder đó**, không cấp ở mức organization. Biến ẩn chỉ ẩn trên giao diện — nếu khách tuyệt đối không được query cluster khác, hãy cho họ một organization Grafana riêng với datasource riêng.

```bash
python3 dashboard-grafana/make_dashboard.py --customer-job Proxmox-P1-XD --site-regex "/^Prometheus FPT HCM$/" --title "Customer P1-XD - Proxmox Ceph" --uid kh-p1-xd -o dashboard-kh-p1-xd.json
```

## Watchdog: tự khởi động lại exporter bị treo

Menu **26** → `w` (hoặc `proxmox-menu watchdog`) cài timer systemd `pve-ceph-exporter-watchdog`, chạy **mỗi 2 phút**: gọi `/health` của mọi exporter **đang chạy** (local, `@cluster`, container `fixnhanh-pve-*`); treo (`503`) hoặc không trả lời **2 lần liên tiếp** thì khởi động lại đúng exporter đó. Dịch vụ bạn chủ động dừng sẽ không bị bật lại. Lịch sử: `journalctl -t pve-ceph-watchdog`. Chạy `w` lần nữa để tắt và gỡ.

## Zabbix: template đọc exporter qua HTTP

`template-zabbix/pve-ceph-exporter-by-http.yaml` cho Zabbix cùng dữ liệu với dashboard Grafana và cảnh báo Prometheus, **không cần zabbix-agent**: mỗi phút một request HTTP tới `/metrics` của exporter, mọi item khác tính từ đó.

1. Zabbix web → **Data collection → Templates → Import** → chọn file (Zabbix 6.0+; CI đã thử trên 6.0, 6.2 và 7.0).
2. **Data collection → Hosts → Create host**: interface = IP máy chạy exporter (máy monitor ở chế độ từ xa, hoặc node), gán template `Proxmox Ceph by FIX NHANH exporter`.
3. Chế độ từ xa (nhiều cluster trên một máy monitor): mỗi cluster một host Zabbix, cùng IP, macro `{$PVE.EXPORTER.PORT}` = port của cluster đó (`proxmox-menu remote-list`).

| Phần | Item | Trigger |
|---|---|---|
| Exporter | version, mode, lần thu thập cuối; mỗi collector (LLD): up, lỗi cuối | không trả lời 5 phút (high), dữ liệu cũ hơn 3 phút, collector lỗi 5 phút |
| Ceph | health, trạng thái / dòng trạng thái / % recovery, tốc độ recovery, objects/s, object degraded / misplaced / unfound, PG chưa clean, PG inconsistent, tổng / up / in OSD | HEALTH_ERR (high), HEALTH_WARN 15 phút, object unfound (high), PG inconsistent (high), recovery lâu hơn `{$CEPH.RECOVERY.MAX.TIME}` (6h) |
| Ceph OSD (LLD) | up, in, apply latency, byte đã dùng / tổng, % dùng | down 5 phút (high), out 15 phút, latency > `{$CEPH.OSD.LATENCY.MAX}` ms, dùng > 85 % / 90 % |
| Ceph pool (LLD) | % dùng, đã lưu, còn trống tối đa | dùng > `{$CEPH.POOL.USED.MAX}` % (80) trong 15 phút |
| Proxmox | tên cluster, quorum, node online / tổng | mất quorum (disaster) |
| Node Proxmox (LLD) | up, % CPU, RAM dùng / tổng / %, uptime, trạng thái HA, nhóm HA | offline (high), HA fence / lost / gone / unknown (high), HA maintenance (info), CPU / RAM > 90 % trong 15 phút |

Item Ceph cần metric ceph mgr được gộp trên cùng port (mặc định, không dùng `--no-ceph-mgr`); item Proxmox cần collector pve (mặc định, không dùng `--no-pve`). Ngưỡng là macro của template, sửa riêng được cho từng host.

## Zabbix: Ceph qua Zabbix Agent 2

Độc lập với Prometheus / Grafana: Zabbix hỏi **zabbix-agent2** trên mọi node Proxmox, plugin Ceph có sẵn của agent đọc **ceph-mgr restful API** (`:8003`). Mỗi node còn có cron ghi `ceph health` vào `/etc/zabbix/cephstatus.txt` mỗi phút, để dự phòng khi API chết.

Chạy từ máy nào SSH được tới các node (vd máy monitor):

```bash
proxmox-menu zabbix-ceph
```

(menu **27**, hoặc `bash template-zabbix/setup_ceph_zabbix.sh <ip-zabbix> <node1> <node2> ...`). Công cụ hỏi IP Zabbix server / proxy và IP các node; có SSH key thì dùng key, không thì hỏi mật khẩu root một lần (`sshpass`, không bao giờ hiện trong `ps`). Trên mỗi node nó:

1. Cài `zabbix-agent2` nếu chưa có (cần repo gói Zabbix) và đặt `Server` / `ServerActive`, `Plugins.Ceph.InsecureSkipVerify=true` (giữ `zabbix_agent2.conf.bak`).
2. Cài `/etc/zabbix/cephstatus.sh` + cron mỗi phút → `/etc/zabbix/cephstatus.txt`.
3. Khởi động lại và bật agent.

Trên node đầu tiên nó bật module mgr `restful`, tạo API key `zabbix-monitor` và cert tự ký, rồi in ba macro:

```text
{$CEPH.API.KEY} = <key>
{$CEPH.USER}    = zabbix-monitor
{$CEPH.API.URL} = https://<active-mgr>:8003
```

Trên Zabbix web (**Data collection → Hosts → host**):

| Template | Cách làm |
|---|---|
| `Ceph by Zabbix agent 2` | Có sẵn trong Zabbix. Gán vào host và đặt ba macro ở trên (**Macros → Inherited and host macros**) |
| `Ceph health fallback by Zabbix agent 2` | Import `template-zabbix/ceph-health-fallback.yaml` một lần (**Data collection → Templates → Import**, Zabbix 6.0+), rồi gán. Item: `vfs.file.contents[/etc/zabbix/cephstatus.txt]` (trigger: không phải `HEALTH_OK`), `vfs.file.time[...]` (trigger: 5 phút không cập nhật) |

Bản dự phòng dùng `vfs.file.contents`, nên không cần `AllowKey=system.run[*]` và `docfile.sh` của script cũ nữa (script tự xóa `docfile.sh`). Nếu bản Ceph của bạn không có module restful, script sẽ báo — khi đó dùng đường Prometheus / Grafana.

## Metric của exporter

| Metric | Ý nghĩa |
|---|---|
| `ceph_custom_recovery_info{content,state}` | Dòng trạng thái; giá trị 0 = OK, 1 = recovery / rebalance, 2 = lỗi |
| `ceph_custom_recovery_percent` | % dữ liệu ổn định (100 khi không có degraded / misplaced) |
| `ceph_custom_recovery_speed_bytes` | Tốc độ recovery (byte/giây) |
| `ceph_custom_recovery_objects_per_sec` | Số object recovery mỗi giây |
| `ceph_custom_degraded_objects`, `_misplaced_objects`, `_unfound_objects` | Số object bất thường |
| `ceph_custom_pgs_not_clean` | Số PG chưa active+clean |
| `ceph_custom_progress_percent{event}` | Tiến độ các sự kiện `ceph progress` |
| `pve_ha_groups_custom_info{host,groups}` | Nhóm HA / luật node-affinity của node (bỏ qua luật phủ mọi node hoặc luật bị tắt; hiện `comment` của luật thay cho id `ha-rule-…`) |

Cột **HA Groups** của *Resource Cluster* luôn hiện; node không thuộc nhóm nào hiện `-`. Node bình thường giữ màu nhóm; khi có sự cố thì màu sự cố đè lên:

| Màu | Ô hiện | Khi nào |
|---|---|---|
| Màu nhóm: `--ha-alias ...:màu`, không có thì tự gán màu theo nhóm | tên nhóm (hoặc tên ngắn) | node up, HA online |
| Cam | `MAINTENANCE: ...`, `HA UNKNOWN: ...` | HA đang bảo trì / không rõ trạng thái HA |
| Đỏ | `OFFLINE: ...`, `FENCE: ...` | node chết (`pve_up = 0`) / HA fence, lost, gone |
| Xám | `-` | node không thuộc nhóm nào |

Metric tự giám sát của exporter (hàng **Exporter** cuối dashboard):

| Metric | Ý nghĩa |
|---|---|
| `pve_ceph_extra_exporter_up{collector}` | 1 = thu thập OK. Các collector: `ceph_mgr`, `pve`, `ceph`, `ha` (không có `ceph_mgr` / `pve` khi dùng `--no-ceph-mgr` / `--no-pve`) |
| `pve_ceph_extra_exporter_last_error{collector,error}` | Lỗi cuối của collector đang lỗi (401, timeout, mgr standby ...) |
| `pve_ceph_extra_exporter_collect_seconds{collector}` | Thời gian lần thu thập cuối (giây) |
| `pve_ceph_extra_exporter_last_collect_timestamp` | Thời điểm thu thập cuối (unix) — phát hiện dữ liệu cũ |
| `pve_ceph_extra_exporter_mode{mode}` | `local` / `remote` |
| `pve_ceph_extra_exporter_build_info{version}` | Version exporter |

Ngoài `/metrics`, exporter còn có `/health`: trả `200 ok` khi lần thu thập cuối còn mới, `503 stale` khi vòng thu thập bị treo quá `3 × INTERVAL` (ít nhất 120 giây). Image Docker dùng nó cho `HEALTHCHECK`, nên container bị treo hiện `unhealthy` trong `docker ps`.

---

Bản quyền © 2026 **FIX NHANH**. Bảo lưu mọi quyền — xem [LICENSE](LICENSE).
