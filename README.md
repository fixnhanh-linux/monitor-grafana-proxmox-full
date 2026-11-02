# Monitor Proxmox + Ceph (Prometheus / Grafana)

![So do giam sat Proxmox + Ceph](docs/so-do-kien-truc.svg)

Bo tool dung dashboard **Proxmox - Ceph Prometheus** va lap cac o dang bao `No data`.

| File | Viec |
|---|---|
| `menu.sh` | **Menu quan ly tat ca**: kiem tra, cai, trang thai, log, sinh/import dashboard, kiem tra Prometheus |
| `make_dashboard.py` | Sinh JSON dashboard Grafana, import thang vao Grafana |
| `exporter/pve_ceph_extra_exporter.py` | Exporter bo sung: trang thai recovery/rebalance, Total Health %, Recovery Speed, HA Groups |
| `exporter/install_exporter.sh` | Cai exporter thanh service systemd tren 1 node Proxmox |
| `alerts/pve-ceph-alerts.yml` | Alert rules Prometheus: exporter, Ceph, Proxmox |
| `tests/` | Unit test exporter (`python3 -m unittest discover -s tests`), chay tu dong tren GitHub Actions |
| `CHANGELOG.md` | Nhat ky thay doi |

## Vi sao dashboard cu co o "No data"

| O | Nguyen nhan | Ban moi |
|---|---|---|
| OSD Used Class Nvme / HDD / HDD12T, Top 5 NVME/HDD/HDD12T Latency | Cluster khong co OSD class do, panel bi co dinh theo ten class | Panel lap theo bien `$class` (lay tu `ceph_osd_metadata`), chi hien class co OSD |
| Detailed Alarms | Cluster HEALTH_OK nen `ceph_health_detail` rong | Hien dong `OK / HEALTH_OK / Khong co canh bao` |
| Ceph Status, Total Health, Recovery Speed | Khong co nguon cho `ceph_custom_recovery_*` | `pve_ceph_extra_exporter` luon xuat metric (100% / 0 B/s khi khong recovery) |
| Cot HA Groups | Thieu `pve_ha_groups_custom_info` | Exporter doc `/etc/pve/ha/groups.cfg` va `rules.cfg` (PVE 9) |

Sua them cac loi query cua ban cu:
- Bang **Resource Cluster with HA Groups** khong loc `job` → tron node cua moi cluster tren cung Prometheus.
- **OSDs OUT** tinh `count(up) - count(in)` luon ra 0; nay dem `ceph_osd_in == 0`.
- **OSD Used Class HDD12T** cot Low lay nham class `hdd`.

## Cai tron goi: mot lenh, hoi mot lan

Clone repo len 1 node Ceph cua moi cluster roi chay:

```bash
git clone https://github.com/fixnhanh-linux/monitor-grafana-proxmox-full.git /root/monitor-grafana-proxmox-full
```

```bash
bash /root/monitor-grafana-proxmox-full/menu.sh setup
```

(hoac mo `menu.sh` roi chon **S**). Tool hoi het cac cau duoi day, in **TOM TAT**, hoi `Bat dau thuc hien? (y/N)`, roi tu chay tung buoc `>>> [1/6] ...` va bao **KET QUA**.

| # | Cau hoi | Mac dinh / tu do | Dung de |
|---|---|---|---|
| 1 | May nay lam gi: `1` node Ceph day du · `2` chi exporter · `3` chi dashboard | `1` | Chon cac buoc se chay |
| 2 | Port exporter | `9830` | Cong `/metrics` cua service |
| 2 | Gop tat ca metric ra 1 port? | `Y` | `Y`: Prometheus chi can 1 target; `n`: giu target ceph mgr / pve exporter rieng |
| 2 | Ten job Prometheus cua cluster | `Proxmox-<cluster_name>` doc tu `/etc/pve/corosync.conf` | File mau `prometheus-target-<job>.yml` |
| 3 | Tieu de, UID dashboard | `Proxmox - Ceph Prometheus`, `pve-ceph-prom` | UID trung se ghi de dashboard cu |
| 3 | Regex loc datasource Site, regex loc job | trong (tat ca), `/.*Proxmox-/` | Bien `$Site`, `$job` |
| 3 | So node / pool / device class | doc tu `ceph osd tree`, `ceph osd pool ls`, `ceph osd crush class ls` | Chieu cao cac bang |
| 3 | Nguong latency theo class | `nvme=15:25,ssd=50:100,default=100:200` | Mau bang Latency All OSD |
| 3 | Khoang thoi gian mac dinh | `now-15m` | Time picker |
| 3 | Dat ten ngan + mau cho HA Groups? | doc cac chuoi group dang co trong `/etc/pve/ha/` | Cot HA Groups, vd `Gold+HIGH:orange` |
| 4 | Grafana URL, token, folder UID | URL trong = chi xuat file JSON | Import qua API |
| 5 | Prometheus URL | trong = bo qua | Kiem tra target `up` va job khop ceph mgr |

Cac buoc tool tu lam (tuy lua chon o cau 1):

1. Kiem tra moi truong — co loi thi dung, chua cai gi
2. Cai / cap nhat service `pve-ceph-extra-exporter`
3. In va luu doan `prometheus.yml` mau (`prometheus-target-<job>.yml`)
4. Sinh `dashboard-local.json` (file rieng, khong nam trong git nen menu 14 cap nhat khong bi chan)
5. Import len Grafana
6. Kiem tra Prometheus

### Dieu chinh sau khi cai

| Muon doi | Cach |
|---|---|
| Bat ky cau tra loi nao | Chay lai `menu.sh setup` — gia tri cu hien san trong `[ ]`, chi sua cau can doi, Enter cac cau khac |
| Sua nhanh khong qua cau hoi | Sua `.menu.conf` (dong `DASH_TITLE=`, `DASH_LAT=`, `DASH_ALIASES=` ...) roi chay `menu.sh setup` va Enter lien tuc |
| Chi port exporter | `bash menu.sh port 9300`, roi sua target trong `prometheus.yml` |
| Chi dashboard | Menu **9** (sinh lai) roi **11** (import, UID giong nhau se ghi de) |
| Ten ngan HA Groups | Menu **9** → tra loi `y` o cau HA Groups; `DASH_ALIASES` luu dang `chuoi=Ten:mau;;chuoi2=Ten2` |
| Go exporter | Menu **8** hoac `bash menu.sh uninstall` |

Token Grafana: go 1 lan o menu 11, chon luu thi nam rieng trong `.grafana-token` (chi root doc, khong vao git, khong nam trong `.menu.conf`). Token sai / het han thi tool tu xoa va hoi lai; xoa tay o menu 15.

## Cap nhat toan bo: 1 lenh, khong hoi

```bash
proxmox-menu refresh
```

Tu `git pull` roi chay bang code moi, dung cau hinh da luu: cai lai exporter (local + moi cluster tu xa) va khoi dong lai, sinh lai dashboard tu `.menu.conf` roi import len Grafana (can Grafana URL + token da luu o menu 11), in bang dich vu, kiem tra Prometheus. Cuoi cung bao `Xong, khong co loi` hoac liet ke buoc can xem lai.

## Lenh tat `proxmox-menu`

Lan dau chay `bash /root/monitor-grafana-proxmox-full/menu.sh` bang root, tool tu tao lenh `/usr/local/bin/proxmox-menu`. Tu do go o bat ky thu muc nao:

| Lenh | Viec |
|---|---|
| `proxmox-menu` | Mo menu |
| `proxmox-menu refresh` | Cap nhat toan bo (git pull + exporter + dashboard + kiem tra) |
| `proxmox-menu services` | Bang dich vu, khoi dong lai / dung / log |
| `proxmox-menu <lenh>` | Moi lenh ben duoi (`remote-list`, `prom-push`, `docker-net` ...) |

Chuyen thu muc tool di cho khac thi chay `bash <thu-muc-moi>/menu.sh` mot lan, lenh tat tu tro lai.

## Menu tung muc

```bash
bash /root/monitor-grafana-proxmox-full/menu.sh
```

| Muc | Viec |
|---|---|
| S | Cai tron goi (nhu tren) |
| 1 | Kiem tra python3, lenh `ceph`, keyring, HA config, port trong, PVE firewall |
| 2 | Cai / cap nhat exporter (hoi port, mac dinh 9830) |
| 3 | Trang thai service, collector OK/loi, dong Ceph Status, Total Health |
| 4 | Xem metric (neu chua cai thi chay thu 1 lan tu file nguon) |
| 5 / 6 / 7 / 8 | Log, restart, doi port, go cai |
| 9 | Sinh dashboard JSON — tu doc so node / pool / device class tu Ceph. Chon **1 Noi bo** (moi cluster) hoac **2 Khach hang** (xem duoi) |
| 10 | In doan `prometheus.yml` mau cho node nay; may co cluster tu xa thi gop **tat ca cluster** vao `prometheus-scrape-all.yml` (kiem tra tung exporter, bo job trung, bao 2 cau hinh cung 1 cluster), roi tuy chon day qua SSH len may Prometheus, kem alert rules (xem duoi) |
| 11 | Import dashboard len Grafana qua API (service account token, role **Editor**); kiem tra truoc Grafana co datasource Prometheus khop bien Site; Grafana dung cert tu ky thi de nghi **ghim cert** (so SHA-256 voi trinh duyet), khong tat kiem tra TLS |
| 12 | Hoi Prometheus: target exporter co `up`, job cua exporter co khop job ceph mgr, device class tung cluster |
| 13 | Kiem tra tong the (1 + 3 + 12) |
| 14 | Cap nhat tool (`git pull`), tu hoi cai lai exporter neu exporter co thay doi |
| 15 | Xem / xoa cau hinh da luu (`.menu.conf`), **dat Prometheus / Grafana URL** (kiem tra ket noi) |
| 16 | Gioi thieu & ban quyen FIX NHANH |
| 17 | Them / sua cluster theo doi tu xa (API token) |
| 18 | Danh sach cluster tu xa: port, service, cluster that doc duoc, trang thai tung phan; to do khi 2 cau hinh cung 1 cluster hoac trung job |
| 19 | Kiem tra ket noi 1 cluster (bao ro 401 / 403 / firewall) |
| 20 | Xoa cluster tu xa (dung service / container, xoa token) |
| 21 | Cai goi can thiet — tu nhan `apt` / `dnf` / `yum` / `zypper` / `pacman` / `apk` |
| 22 | Mo firewall cho IP Prometheus — tu nhan `ufw` / `firewalld` / `pve-firewall` |
| 23 | Chay cluster (da them o 17) bang Docker: build image, chuyen tu systemd sang container cung port |
| 24 | Quan ly container: xem trang thai, log, khoi dong lai, xoa (quay ve systemd) |
| 25 | Doi dai IP Docker (`docker0` + dai cho mang moi): kiem tra dai noi bo / trung route, sao luu `daemon.json`, restart Docker, kiem tra container chay lai; Docker khong len thi tra file cu |
| 26 | **Dich vu & suc khoe**: bang moi exporter (local, `@cluster`, container) + Docker + watchdog voi trang thai, `/health`, port, chay khi khoi dong may; `r`/`s`/`t` khoi dong lai / dung / chay (1 cai hoac `a` = tat ca) roi **tu kiem tra** active + `/health` trong 40 s, loi thi in log; `l` log; `b`/`B` bat / tat chay khi khoi dong may; `w` watchdog |

Chay 1 lenh khong qua menu: `proxmox-menu setup | check | install [port] | status | metrics | logs | restart | port <so> | uninstall | dashboard | import | prom | prom-check | doctor | update | about | remote-add [ten] | remote-list | prom-all | prom-push | prom-rules | urls | refresh | remote-test | remote-remove | deps | firewall | docker-run | docker-manage | docker-net | services | watchdog`.

Menu nho Grafana URL, Prometheus URL, tieu de/UID dashboard trong `.menu.conf`; token Grafana (neu chon luu) nam rieng o `.grafana-token`.

## Theo doi tu xa: khong cai gi len node Proxmox

Exporter chay tren **may monitor** (vi du 10.16.16.38, Ubuntu), lay du lieu qua **API Proxmox** bang token chi doc va `/metrics` cua ceph mgr. Mot may monitor theo doi duoc nhieu cluster, moi cluster la 1 service `pve-ceph-extra-exporter@<ten>` voi 1 port rieng (9830, 9831, ...). Ten metric giong het che do local nen **dashboard khong can sua**.

| Du lieu | Che do local (tren node) | Che do remote (may monitor) |
|---|---|---|
| Metric Ceph (OSD, pool, latency) | `ceph mgr services` → mgr:9283 | Thu lan luot `CEPH_MGR`; de trong thi tu lay IP moi node tu `/cluster/status` (mgr standby tra rong → bo qua, tim toi mgr active) |
| Node, CPU, RAM, uptime, HA | `pvesh`, `/etc/pve` | API `/cluster/status`, `/cluster/resources`, `/cluster/ha/status/manager_status` |
| Ceph Status / Recovery | `ceph status` | API `/cluster/ceph/status` |
| HA Groups | `/etc/pve/ha/*.cfg` | API `/cluster/ha/groups`, `/cluster/ha/rules` (PVE 9) |

### Buoc 1: tren 1 node bat ky cua moi cluster (1 lan)

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

`PVEAuditor` chi co quyen **xem**. Lenh tao token in ra `value` (secret) **chi mot lan** — luu lai.

### Buoc 2: tren may monitor

```bash
bash /root/monitor-grafana-proxmox-full/menu.sh remote-add
```

(hoac menu **17**, hoac cai tron goi **S → 4**). Tool hoi:

| Cau hoi | Vi du / mac dinh |
|---|---|
| Ten cluster | `FPT-HCM` |
| IP cac node Proxmox | `10.16.16.60,10.16.16.61,10.16.16.62` — node dau chet tu chuyen node sau |
| Token ID / secret | `monitor@pve!exporter` / secret (go khong hien) |
| Kiem tra chung chi TLS | `N` (Proxmox mac dinh cert tu ky) |
| Ceph mgr | Enter = tu tim mgr active tren moi node cua cluster (`:9283`) |
| Ten job Prometheus | `Proxmox-FPT-HCM` (phai chua `Proxmox-`) |
| Port | port trong ke tiep tu 9830 |

Tool **chay thu ket noi** va bao tung phan ✔ / ✘ (401 = sai token, 403 = thieu quyen, refused/timeout = firewall), sau do luu `/etc/pve-ceph-extra-exporter/<ten>.env` (chmod 600, chi root doc), bat service va in mau `prometheus.yml` (1 target `IP-may-monitor:port`).

May monitor can di toi duoc **node:8006** va **mgr:9283**.

### An toan & tai

- Service chay bang **user tam** (`DynamicUser`), khong phai root; he thong file chi doc (`ProtectSystem=strict`); gioi han `CPUQuota=25%`, `MemoryMax=256M`.
- Token chi nam trong file `.env` quyen 600, khong xuat hien tren dong lenh / `ps`.
- Moi 30 giay: 5–6 request API + 1 request mgr cho moi cluster. Phia Proxmox gan nhu khong ton gi.

### Chay tren server khong phai Ubuntu

| He dieu hanh | Ghi chu |
|---|---|
| Debian, Ubuntu, Rocky / Alma / RHEL 8+, Fedora, openSUSE, Arch | Day du: menu **21** cai goi, **17** them cluster |
| CentOS 7 / RHEL 7 | Chay duoc; systemd cu bo qua `DynamicUser` nen service chay bang root |
| Alpine, may khong co systemd, Windows (Docker Desktop / WSL2) | Dung Docker: menu **17** roi **23** |

Firewall (ufw / firewalld / pve-firewall): menu **22**, nhap IP Prometheus la mo du cac port exporter tren may.

### Docker

Them cluster o menu **17** (de co file cau hinh), roi menu **23**: tool build image `fixnhanh/pve-ceph-exporter:<version>`, dung service systemd cua cluster do va chay container `fixnhanh-pve-<ten>` cung port (gioi han 256 MB / 0.25 CPU, read-only, bo moi capability). Target Prometheus giu nguyen. Menu **24** xem log / khoi dong lai / xoa container (tu quay ve systemd).

Chay tay khong qua menu:

```bash
docker build -t fixnhanh/pve-ceph-exporter exporter/
```

```bash
docker run -d --name fixnhanh-pve-FPT-HCM --restart unless-stopped -p 9830:9830 --env-file /etc/pve-ceph-extra-exporter/FPT-HCM.env fixnhanh/pve-ceph-exporter
```

## 1. Cai exporter thu cong (tren 1 node Ceph cua moi cluster)

```bash
scp -r exporter root@<node-proxmox>:/root/
```

```bash
bash /root/exporter/install_exporter.sh
```

Kiem tra nhanh khong can cai: `python3 pve_ceph_extra_exporter.py --once`

## 2. Them vao Prometheus

### Mac dinh: gop tat ca metric ra 1 port

Exporter phat lai `/metrics` cua ceph mgr dang active (lay dia chi qua `ceph mgr services`) va tu xuat metric Proxmox tu `pvesh` (ten giong `prometheus-pve-exporter`: `pve_cluster_info`, `pve_up`, `pve_cpu_usage_ratio`, `pve_memory_*`, `pve_disk_*`, `pve_uptime_seconds`, `pve_ha_state`). Moi cluster chi can **1 target**:

```yaml
  - job_name: Proxmox-DECO
    scrape_interval: 30s
    scrape_timeout: 25s
    static_configs:
      - targets:
          - 10.0.0.11:9830   # pve_ceph_extra_exporter (tat ca metric)
```

Dieu kien: da bat module prometheus cua ceph mgr (`ceph mgr module enable prometheus`), menu **1** se kiem tra.

**Phai xoa** target `:9283` (ceph mgr) va `:9221` (pve exporter) cu cua cluster do khoi job, neu khong moi so lieu bi nhan doi. Menu **12** bao `Trung` khi mot job co 2 target cung xuat metric ceph hoac Proxmox.

### Nhieu cluster tren 1 may monitor

Menu **10** (hoac `bash menu.sh prom-all`) gop moi cluster thanh `prometheus-scrape-all.yml`, file da co san dong `scrape_configs:`.

| Prometheus cua ban | Cach dua vao |
|---|---|
| Tach file: `prometheus.yml` co `scrape_config_files: [/etc/prometheus/scrape_configs/*.yml]` | Chep **nguyen file** vao thu muc do, vd `proxmox-ceph-<ten-may-monitor>.yml` |
| 1 file (mac dinh) | Dan cac khoi `- job_name:` vao duoi `scrape_configs:` cua `prometheus.yml` |

Voi kieu tach file, tra loi `y` o cau *Day file len may Prometheus qua SSH* (hoac `bash menu.sh prom-push`). Tool tu lam:

1. SSH vao may Prometheus (can dang nhap bang key: `ssh-copy-id root@<prometheus>`), kiem tra thu muc va `scrape_config_files`.
2. **Dung** neu `job_name` da co o file khac — Prometheus khong cho trung job giua cac file.
3. Liet ke target `:9283` / `:9221` cu de ban xoa neu la cung cluster (tranh nhan doi so lieu).
4. Chep file, chay `promtool check config`; loi thi **tra lai file cu**, Prometheus khong bi anh huong; OK thi reload.

May SSH, file cau hinh, thu muc duoc nho trong `.menu.conf` cho lan sau.

**Chuyen job cu sang exporter:** neu Prometheus da co job cung ten (vd `Proxmox-P1-XD` dang scrape thang `:9283` / pve exporter) hoac job khac tro cung target exporter, tool liet ke tung block (file, job, dong, ly do) va hoi **thay the**: sao luu toan bo thu muc vao `/root/prom-bak-<gio>` tren may Prometheus, go dung cac block do, day job exporter cung ten (dashboard giu nguyen ten job), `promtool` loi thi tra lai tat ca.

Sau khi day file scrape, tool hoi day luon **alert rules** (hoac `bash menu.sh prom-rules`): chep `alerts/pve-ceph-alerts.yml` vao thu muc `rule_files` dang dung (mac dinh lay tu `prometheus.yml`, vd `/etc/prometheus/rules/`). Neu `prometheus.yml` chua nap thu muc do, tool them dong vao `rule_files` (giu ban sao `.bak`). `promtool check rules` + `check config` loi thi tra lai ca 2 file.

Dau menu hien ma commit dang chay (vd `2026.10.30 · de76e86`); GitHub co ban moi hon thi hien dong **Co ban moi → chon 14**.

### Khong gop (giu target cu)

Chon `n` o cau gop (service chay voi `--no-ceph-mgr --no-pve`). Target exporter phai nam **cung job** voi ceph mgr / pve exporter cua cluster do (dashboard loc theo `job=~"$job"`):

```yaml
  - job_name: Proxmox-DECO
    static_configs:
      - targets:
          - 10.0.0.11:9283   # ceph mgr prometheus (da co)
          - 10.0.0.11:9830   # pve_ceph_extra_exporter (moi)
```

### Canh bao (alert rules)

File `alerts/pve-ceph-alerts.yml` co san cac rule, chi ap cho job chua `Proxmox-`:

| Nhom | Alert | Khi nao |
|---|---|---|
| Exporter | `PveCephExporterDown` | Target khong scrape duoc 2 phut |
| | `PveCephExporterCollectorFailed` | Mot collector loi 5 phut (o dashboard tuong ung se No data) |
| | `PveCephExporterStale` | Khong thu thap moi qua 3 phut (lenh ceph / API treo) |
| Ceph | `CephHealthError` / `CephHealthWarning` | HEALTH_ERR 1 phut / HEALTH_WARN 15 phut |
| | `CephOsdDown` / `CephOsdOut` | OSD down 5 phut / out 15 phut |
| | `CephOsdNearFull` / `CephOsdFull` | OSD dung > 85% / > 90% |
| | `CephPoolNearFull` | Pool dung > 80% |
| | `CephPgInconsistent`, `CephUnfoundObjects` | Co PG inconsistent / object unfound |
| | `CephRecoveryTooLong` | Recovery / rebalance qua 6 gio |
| | `CephOsdHighLatency` | Apply latency > 200 ms trong 10 phut |
| Proxmox | `PveNodeDown`, `PveClusterNotQuorate`, `PveHaNodeFenced` | Node offline, mat quorum, HA fence / lost |
| | `PveNodeHighCpu` / `PveNodeHighMemory` | CPU / RAM > 90% trong 15 phut |

Chep file len may Prometheus roi them vao `prometheus.yml`:

```yaml
rule_files:
  - /etc/prometheus/rules/pve-ceph-alerts.yml
```

```bash
promtool check rules /etc/prometheus/rules/pve-ceph-alerts.yml
```

Sau do reload Prometheus. Gui canh bao di (Telegram, email ...) cau hinh o Alertmanager. Nguong va thoi gian `for:` sua thang trong file.

## 3. Sinh va import dashboard

```bash
python make_dashboard.py -o proxmox_ceph_dashboard.json
```

Tuy chon:

```bash
python make_dashboard.py --title "Proxmox - Ceph DECO" --uid pve-ceph-deco --site-regex "/^Prometheus (FPT HN|CMC-Q7)$/" --nodes 5 --pools 4 --classes 1
```

- `--site-regex`: loc datasource Prometheus cho bien **Site**
- `--job-regex`: loc job cua `pve_cluster_info` (mac dinh `/.*Proxmox-/`)
- `--nodes / --pools / --classes`: chinh chieu cao cac bang cho vua so dong
- `--lat-th`: nguong latency (ms) canh bao:nghiem trong theo class, mac dinh `nvme=15:25,ssd=50:100,default=100:200`
- `--ha-alias "GROUPS=TEXT[:mau]"` (lap duoc): ten ngan va mau cho chuoi HA Groups, vd `--ha-alias "Gold-6146,HIGH-FREQUENCY,P1-XD=Gold+HIGH+P1-XD:orange"`
- `--time-from`: khoang thoi gian mac dinh, vd `now-5m`

Vi du dung lai dashboard CMC Q7 / FPT HCM / VIETTEL HCM / CMC HN:

```bash
python make_dashboard.py -o cmc.json --title "Proxmox - Ceph Prometheus CMC Q7 - FPT HCM - VIETTEL HCM - CMC HN" --uid fix --time-from now-5m --site-regex "/^(Prometheus FPT HCM|Prometheus FPT HN|Prometheus CMC-Q7|Prometheus VIETTEL HCM|Prometheus CMC HN)$/" --job-regex "/^(?!.*Proxmox-Cluster-DMS|.*Test|.*Deco).*Proxmox-/" --ha-alias "BASIC-COMPUTING,INTEL-HIGH-CPU,P1-XD=BASIC+INTEL+P1-XD:purple" --ha-alias "Gold-6146,HIGH-FREQUENCY,P1-XD=Gold+HIGH+P1-XD:orange" --ha-alias "Gold-8260,INTEL-HIGH-CPU,Platinum-8260=Gold+INTEL+Platinum:blue" --ha-alias "Gold-8260,INTEL-HIGH-CPU,P1-XD,Platinum-8260=Gold+INTEL+P1+Platinum:green"
```

Luu y: import voi `--uid fix` se ghi de dashboard dang co uid `fix`.

Grafana → Dashboards → New → Import → chon file JSON.

## Watchdog: tu khoi dong lai exporter bi treo

Menu **26** → `w` (hoac `bash menu.sh watchdog`) cai systemd timer `pve-ceph-exporter-watchdog` chay **2 phut / lan**: goi `/health` cua tung exporter **dang chay** (local, `@cluster`, container `fixnhanh-pve-*`); treo (`503`) hoac khong tra loi **2 lan lien tiep** thi khoi dong lai dung cai do. Dich vu ban chu dong dung khong bi bat lai. Xem lich su: `journalctl -t pve-ceph-watchdog`. Chay lai `w` de tat va go.

## Dashboard khach hang

Menu **9** → `2` sinh `dashboard-kh-<job>.json` cho **1 khach**:

| | Noi bo | Khach hang |
|---|---|---|
| Site / Job | Chon duoc moi datasource, moi cluster | **An**, khoa cung 1 datasource + 1 job |
| Health, dung luong, OSD, pool, latency, recovery | ✔ | ✔ |
| CPU / RAM / uptime node | ✔ | ✔ |
| Detailed Alarms (thong diep loi Ceph goc) | ✔ | ✘ |
| Cot HA / HA Groups | ✔ | ✘ |
| Hang Exporter (collector, loi, phien ban) | ✔ | ✘ |
| Sua dashboard | Duoc | Khoa (`editable: false`) |

Tool hoi job cua khach (liet ke san tu Prometheus), ten khach, **ten datasource** trong Grafana (khop dung ten do), tieu de, UID `kh-<job>`. Phan quyen trong Grafana: tao **folder rieng** cho khach → import dashboard vao folder do (menu 11 hoi file nao, nhap Folder UID) → cap quyen **Viewer** cho user / team cua khach **tren folder**, khong cap o cap to chuc. Bien an chi giau giao dien — muon khach tuyet doi khong truy van duoc cluster khac thi khach can Grafana org rieng co datasource rieng.

```bash
python make_dashboard.py --customer-job Proxmox-P1-XD --site-regex "/^Prometheus FPT HCM$/" --title "Khach P1-XD - Proxmox Ceph" --uid kh-p1-xd -o dashboard-kh-p1-xd.json
```

## Metric cua exporter

| Metric | Y nghia |
|---|---|
| `ceph_custom_recovery_info{content,state}` | Dong trang thai; gia tri 0 = OK, 1 = recovery/rebalance, 2 = loi |
| `ceph_custom_recovery_percent` | % du lieu on dinh (100 khi khong co degraded/misplaced) |
| `ceph_custom_recovery_speed_bytes` | Toc do recovery (bytes/s) |
| `ceph_custom_recovery_objects_per_sec` | Object recovery / giay |
| `ceph_custom_degraded_objects`, `_misplaced_objects`, `_unfound_objects` | So object bat thuong |
| `ceph_custom_pgs_not_clean` | So PG khong active+clean |
| `ceph_custom_progress_percent{event}` | Tien do cac su kien `ceph progress` |
| `pve_ha_groups_custom_info{host,groups}` | HA group / node-affinity rule cua node |

Cot **HA** va **HA Groups** trong bang *Resource Cluster* chi hien khi cluster dang chon o bien `$job` co HA group / node-affinity rule; cluster khong co HA thi hai cot nay tu an.

Metric tu giam sat cua exporter (hang **Exporter** cuoi dashboard):

| Metric | Y nghia |
|---|---|
| `pve_ceph_extra_exporter_up{collector}` | 1 = thu thap OK. Collector: `ceph_mgr`, `pve`, `ceph`, `ha` (`ceph_mgr` / `pve` khong co khi chay `--no-ceph-mgr` / `--no-pve`) |
| `pve_ceph_extra_exporter_last_error{collector,error}` | Loi gan nhat cua collector dang hong (401, timeout, mgr standby ...) |
| `pve_ceph_extra_exporter_collect_seconds{collector}` | Thoi gian thu thap lan gan nhat (giay) |
| `pve_ceph_extra_exporter_last_collect_timestamp` | Thoi diem thu thap gan nhat (unix) — dung de phat hien du lieu cu |
| `pve_ceph_extra_exporter_mode{mode}` | `local` / `remote` |
| `pve_ceph_extra_exporter_build_info{version}` | Phien ban exporter |

Ngoai `/metrics`, exporter co `/health`: `200 ok` khi lan thu thap gan nhat con moi, `503 stale` khi vong thu thap treo qua `3 × INTERVAL` (toi thieu 120 s). Docker image dung no cho `HEALTHCHECK`, nen container treo hien `unhealthy` trong `docker ps`.

---

Ban quyen © 2026 **FIX NHANH**. Bao luu moi quyen — xem [LICENSE](LICENSE).
