# Nhật ký thay đổi

Mới nhất ở trên. Mã commit đang chạy hiện ở đầu menu (`phien ban 2026.10.30 · <commit>`); cập nhật bằng menu **14**.

## Chưa phát hành

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
