# Nhat ky thay doi

Moi nhat o tren. Ma commit dang chay hien o dau menu (`phien ban 2026.10.30 · <commit>`); cap nhat bang menu **14**.

## Chua phat hanh

- **Dashboard**: cot HA Groups can giua (ca dau `-` khi node khong co nhom), thang hang voi cac cot khac.
- **Nhieu dashboard**: file dashboard luu tham so sinh (`fixnhanhArgs`), `make_dashboard.py --regen FILE`; `refresh` sinh lai + import moi `dashboard-*.json`; import giu folder hien tai cua dashboard tren Grafana (khong tu chuyen ve General); menu 11 chon duoc moi file.
- **Toan bo chu hien thi khong dau**: dashboard (tieu de cot, mo ta, chu khi chua co du lieu), exporter 2026.10.30-8 (dong trang thai Ceph) — dong bo voi menu.sh; doc duoc tren moi terminal / font.
- **Dashboard**: cot HA / HA Groups luon hien; node khong thuoc nhom nao ghi `-` (thay cho an ca cot / "No Group").
- **Exporter 2026.10.30-7 — HA rule PVE 9**: bo rule node-affinity bao trum **moi node** (vd `ha-rule-7fa207ce-7b43` — khong phai nhom) va rule dang tat; rule co `comment` thi hien comment thay cho ma `ha-rule-…`. Cluster khong con rule co y nghia thi cot HA / HA Groups tren dashboard tu an.
- **Alert `PveCephExporterDown`** chi bao target cua exporter nay (da tung xuat `pve_ceph_extra_exporter_build_info` trong 1 ngay) — khong con bao sai mgr standby / pve exporter cu cua cac job scrape thang.
- **Lenh tat `proxmox-menu`**: tu tao `/usr/local/bin/proxmox-menu` khi chay bang root, go o bat ky dau; doi thu muc tool thi tu tro lai.
- **`proxmox-menu refresh`** tu `git pull` truoc roi chay bang code moi — khong can `cd` + `git pull` nua.
- **Menu 10 chuyen job cu sang exporter**: job tren Prometheus trung ten hoac trung target voi exporter thi de nghi **thay the** — sao luu ca thu muc scrape (`/root/prom-bak-<gio>`), go dung cac block job do (file khong con job thi bo), day job exporter, `promtool` loi thi tra lai toan bo.
- **`refresh`** gio cap nhat luon cluster chay Docker: build image theo phien ban exporter (co roi thi bo qua), tao lai container cung port, kiem tra tra metric; container da dung phien ban thi de nguyen.
- **`bash menu.sh refresh`**: cap nhat toan bo khong hoi — cai lai exporter, sinh + import dashboard bang cau hinh / token da luu, bang dich vu, kiem tra Prometheus.
- Payload import Grafana gui dang ASCII, khong hong khi may chay locale khong phai UTF-8.
- **Dashboard**: cot HA Groups khong con bi cat chu — xuong dong trong o, rong 380, can trai, bam o de xem day du.
- **Menu 26 / `services`**: bang moi dich vu (exporter local, `@cluster`, container, Docker, watchdog) — trang thai, `/health`, port, chay khi khoi dong may; khoi dong lai / dung / chay tung cai hoac tat ca roi tu kiem tra active + `/health`, loi thi in log; restart Docker thi kiem tra container chay lai.
- **Watchdog** (`w` trong menu 26 / `watchdog`): systemd timer 2 phut / lan, `/health` loi 2 lan lien tiep thi khoi dong lai dung exporter do; log `journalctl -t pve-ceph-watchdog`.
- **Menu 25 / `docker-net`**: doi dai IP Docker (`bip`, `default-address-pools`) — canh bao dai public (vd `192.20.0.0`) va dai trung route dang co, sao luu `daemon.json`, restart Docker; exporter chay systemd khong bi anh huong, container tat vai giay roi tool kiem tra / khoi dong lai cai nao chua len; Docker khong len voi cau hinh moi thi tra file cu.
- **Dashboard khach hang** (menu 9 → 2, `make_dashboard.py --customer-job`): khoa 1 job + 1 datasource, an Site / Job, bo Detailed Alarms, HA Groups, hang Exporter, khong cho sua; menu 11 chon file nao de import (vao folder rieng cua khach).
- UID gop dau `-` lien tiep: `Proxmox - Ceph Prometheus` → `Proxmox-Ceph-Prometheus` (khop dashboard da co, khong tao ban trung).
- Menu 17: khong nhan so port o cau Ceph mgr; loi 403 in san lenh cap `PVEAuditor` dung token (ke ca token privsep).
- **UID dashboard** tu chuan hoa ve `[A-Za-z0-9_-]`, toi da 40 ky tu (menu 9, `make_dashboard.py`, va ngay truoc khi import) — het loi Grafana `uid contains illegal characters`.
- **Token Grafana go 1 lan**: chon luu thi nam rieng o `.grafana-token` (chi root doc, khong vao git); token sai / het han tu xoa va hoi lai; xoa tay o menu 15.
- **Menu 11 voi Grafana cert tu ky**: tool lay cert, in SHA-256 de so voi trinh duyet, ban dong y thi **ghim** cert do (`.grafana-cert.pem`, chi dung khi goi Grafana) — van kiem tra TLS, khong tat. Cert ghi ten khac IP trong URL thi tool goi bang ten trong cert va tro ve IP that. Token thieu quyen (Viewer) thi bao can role Editor.
- **Menu 11**: khong goi duoc Grafana thi noi ro ly do (cert tu ky, nham http/https, bi tu choi, het gio cho, DNS) kem cach sua, va tu thu dang URL con lai.
- **Menu 9** ghi dashboard ra `dashboard-local.json` (khong nam trong git) thay vi ghi de `proxmox_ceph_dashboard.json` — truoc day lam `git pull` o menu 14 bi chan.
- **Menu 14**: tu giu dashboard da sinh bang ban cu sang `dashboard-local.json` roi moi pull; pull loi thi bao loi va file bi sua, khong con bao nham "Dang la ban moi nhat".
- **Dashboard**: o **Cluster Proxmox** dau hang *Proxmox Resource* hien ten cluster that, so node, quorate cua job dang chon — 2 job cung ten cluster thi bang node giong nhau la dung; 1 job ra nhieu o la job dang tron nhieu cluster.
- **Dashboard**: bang *Resource Cluster with HA Groups* het cac cot thua `id 1 … id 5` (moi truy van chi giu nhan `host`); cot HA Groups rong hon.
- **Menu 10**: canh bao khi IP nhap khong phai cua may monitor (target se tro sai may); khong nhan thu muc / glob lam file cau hinh chinh; SSH chi hoi mat khau 1 lan, de nghi tao key + `ssh-copy-id`.
- **Menu 12**: target down vi tro toi may khac thi chi ra cach sua.
- Ten job mac dinh khong con bi lap `Proxmox-Proxmox-…` khi ten cluster da bat dau bang `Proxmox-`.
- **Menu 11** kiem tra datasource Prometheus tren Grafana truoc khi import: bao khi Grafana chua co datasource nao, khi regex Site khong khop datasource nao, va chi ra datasource tro toi Prometheus da cau hinh.
- **Exporter 2026.10.30-6**: them `/health` (503 khi vong thu thap treo qua `3 × INTERVAL`, toi thieu 120 s); Docker image co `HEALTHCHECK` → `docker ps` hien `unhealthy`.
- **Unit test** exporter (`tests/`) va **CI GitHub Actions**: `bash -n`, `shellcheck`, unit test, sinh lai dashboard so voi file trong repo, `promtool check rules`.

## 2026-10-29

### Prometheus / Grafana
- Dau menu hien ma commit, bao khi GitHub co ban moi.
- Menu **10** gop moi cluster thanh `prometheus-scrape-all.yml`: kiem tra tung exporter, bo job trung (giu cai dang OK), bao 2 cau hinh cung 1 cluster.
- Day file scrape qua SSH (`prom-push`) vao thu muc `scrape_config_files` duoi ten `proxmox-ceph-<may>.yml`; dung khi trung `job_name`, `promtool` loi thi tra lai file cu.
- Day alert rules qua SSH (`prom-rules`), tu them `rule_files` neu thieu.
- Menu **15** / `urls`: dat Prometheus, Grafana URL truc tiep; bat URL go sai, tu thu http / https.
- Menu **18**: cot cluster that, to do cau hinh trung cluster / trung job.
- Dashboard them hang **Exporter** (trang thai collector, loi gan nhat, du lieu cu, phien ban); file `alerts/pve-ceph-alerts.yml` 19 rule.

### Theo doi tu xa (menu 17)
- Tu tim mgr active tren moi node cua cluster (`CEPH_MGR` trong), mgr standby bi bo qua.
- Nhan loi cert tu ky va de nghi tat kiem tra TLS roi chay thu lai; tach loi port dong khoi loi firewall.
- Canh bao node da co o cluster khac, token `root@pam`, port 9283 / 9221; doi Token ID thi bat nhap secret moi.
- Menu 21–24: cai goi theo distro, mo firewall cho Prometheus, chay cluster bang Docker.

### Exporter
- Che do remote qua API Proxmox (token chi doc) + ceph mgr, moi cluster 1 service `@<ten>`.
- Gop moi metric ra 1 port (ceph mgr + Proxmox + bo sung), port mac dinh 9830.
- Thu thap nen 30 s, gioi han CPU / RAM / IO bang systemd.
