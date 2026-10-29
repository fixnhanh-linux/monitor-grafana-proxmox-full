# Nhật ký thay đổi

Mới nhất ở trên. Mã commit đang chạy hiện ở đầu menu (`phien ban 2026.10.30 · <commit>`); cập nhật bằng menu **14**.

## Chưa phát hành

- **Menu 11 với Grafana cert tự ký**: tool lấy cert, in SHA-256 để so với trình duyệt, bạn đồng ý thì **ghim** cert đó (`.grafana-cert.pem`, chỉ dùng khi gọi Grafana) — vẫn kiểm tra TLS, không tắt. Cert ghi tên khác IP trong URL thì tool gọi bằng tên trong cert và trỏ về IP thật. Token thiếu quyền (Viewer) thì báo cần role Editor.
- **Menu 11**: không gọi được Grafana thì nói rõ lý do (cert tự ký, nhầm http/https, bị từ chối, hết giờ chờ, DNS) kèm cách sửa, và tự thử dạng URL còn lại.
- **Menu 9** ghi dashboard ra `dashboard-local.json` (không nằm trong git) thay vì ghi đè `proxmox_ceph_dashboard.json` — trước đây làm `git pull` ở menu 14 bị chặn.
- **Menu 14**: tự giữ dashboard đã sinh bằng bản cũ sang `dashboard-local.json` rồi mới pull; pull lỗi thì báo lỗi và file bị sửa, không còn báo nhầm "Đang là bản mới nhất".
- **Dashboard**: ô **Cluster Proxmox** đầu hàng *Proxmox Resource* hiện tên cluster thật, số node, quorate của job đang chọn — 2 job cùng tên cluster thì bảng node giống nhau là đúng; 1 job ra nhiều ô là job đang trộn nhiều cluster.
- **Dashboard**: bảng *Resource Cluster with HA Groups* hết các cột thừa `id 1 … id 5` (mỗi truy vấn chỉ giữ nhãn `host`); cột HA Groups rộng hơn.
- **Menu 10**: cảnh báo khi IP nhập không phải của máy monitor (target sẽ trỏ sai máy); không nhận thư mục / glob làm file cấu hình chính; SSH chỉ hỏi mật khẩu 1 lần, đề nghị tạo key + `ssh-copy-id`.
- **Menu 12**: target down vì trỏ tới máy khác thì chỉ ra cách sửa.
- Tên job mặc định không còn bị lặp `Proxmox-Proxmox-…` khi tên cluster đã bắt đầu bằng `Proxmox-`.
- **Menu 11** kiểm tra datasource Prometheus trên Grafana trước khi import: báo khi Grafana chưa có datasource nào, khi regex Site không khớp datasource nào, và chỉ ra datasource trỏ tới Prometheus đã cấu hình.
- **Exporter 2026.10.30-6**: thêm `/health` (503 khi vòng thu thập treo quá `3 × INTERVAL`, tối thiểu 120 s); Docker image có `HEALTHCHECK` → `docker ps` hiện `unhealthy`.
- **Unit test** exporter (`tests/`) và **CI GitHub Actions**: `bash -n`, `shellcheck`, unit test, sinh lại dashboard so với file trong repo, `promtool check rules`.

## 2026-10-29

### Prometheus / Grafana
- Đầu menu hiện mã commit, báo khi GitHub có bản mới.
- Menu **10** gộp mọi cluster thành `prometheus-scrape-all.yml`: kiểm tra từng exporter, bỏ job trùng (giữ cái đang OK), báo 2 cấu hình cùng 1 cluster.
- Đẩy file scrape qua SSH (`prom-push`) vào thư mục `scrape_config_files` dưới tên `proxmox-ceph-<máy>.yml`; dừng khi trùng `job_name`, `promtool` lỗi thì trả lại file cũ.
- Đẩy alert rules qua SSH (`prom-rules`), tự thêm `rule_files` nếu thiếu.
- Menu **15** / `urls`: đặt Prometheus, Grafana URL trực tiếp; bắt URL gõ sai, tự thử http / https.
- Menu **18**: cột cluster thật, tô đỏ cấu hình trùng cluster / trùng job.
- Dashboard thêm hàng **Exporter** (trạng thái collector, lỗi gần nhất, dữ liệu cũ, phiên bản); file `alerts/pve-ceph-alerts.yml` 19 rule.

### Theo dõi từ xa (menu 17)
- Tự tìm mgr active trên mọi node của cluster (`CEPH_MGR` trống), mgr standby bị bỏ qua.
- Nhận lỗi cert tự ký và đề nghị tắt kiểm tra TLS rồi chạy thử lại; tách lỗi port đóng khỏi lỗi firewall.
- Cảnh báo node đã có ở cluster khác, token `root@pam`, port 9283 / 9221; đổi Token ID thì bắt nhập secret mới.
- Menu 21–24: cài gói theo distro, mở firewall cho Prometheus, chạy cluster bằng Docker.

### Exporter
- Chế độ remote qua API Proxmox (token chỉ đọc) + ceph mgr, mỗi cluster 1 service `@<tên>`.
- Gộp mọi metric ra 1 port (ceph mgr + Proxmox + bổ sung), port mặc định 9830.
- Thu thập nền 30 s, giới hạn CPU / RAM / IO bằng systemd.
