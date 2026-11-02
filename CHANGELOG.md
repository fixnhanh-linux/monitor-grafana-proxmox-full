# Changelog

Newest first. The running commit is shown in the menu header (`version 2026.10.30 · <commit>`); update with `proxmox-menu refresh` or menu **14**.

## Unreleased

- **Dashboard**: HA Groups color = node state: green OK, orange `MAINTENANCE` / `HA UNKNOWN`, red `OFFLINE` / `FENCE` (prefix in the cell). `--ha-alias` keeps the short names; its `:color` is ignored.
- **Repo layout**: `exporter/`, `grafana/` (`make_dashboard.py`, default dashboard), `prometheus/` (alert rules), `zabbix/`, `docs/`, `tests/`; `menu.sh` stays at the root. Old local leftovers removed.
- **Zabbix merged in** (from `huong-dan-monitor-ceph-proxmox-zabbix`): `zabbix/setup_ceph_zabbix.sh` (menu 27 / `zabbix-ceph`) configures zabbix-agent2 for Ceph on every node over SSH (key first, password once via `sshpass -e`), cron fallback file, restful API key + macros; new template `zabbix/templates/ceph-health-fallback.yaml` reads the fallback file with `vfs.file.contents` — `AllowKey=system.run[*]` and `docfile.sh` are no longer used.
- **Architecture diagram** redrawn: cluster, monitor host, Prometheus, Grafana and Zabbix with every data flow.
- **English UI**: every message of the menu, exporter (2026.10.30-9), dashboards and alert rules is now in English; code comments stay in Vietnamese (unaccented). README / CHANGELOG / LICENSE in English.
- **Dashboard**: HA Groups column centered (including `-` for nodes without a group).
- **Multiple dashboards**: dashboard files store their generation arguments (`fixnhanhArgs`), `make_dashboard.py --regen FILE`; `refresh` regenerates + imports every `dashboard-*.json`; imports keep the dashboard's current Grafana folder (no move to General); menu 11 can pick any file.
- **Dashboard**: HA / HA Groups columns always shown; nodes without a group show `-` (instead of hiding the column / "No Group").
- **Exporter 2026.10.30-7 — PVE 9 HA rules**: node-affinity rules covering **every node** (e.g. `ha-rule-7fa207ce-7b43` — not a group) and disabled rules are ignored; a rule `comment` is shown instead of the `ha-rule-…` id.
- **Alert `PveCephExporterDown`** only fires for this exporter's targets (exported `pve_ceph_extra_exporter_build_info` within 1 day) — no more false alarms for standby mgrs / old pve exporters of direct-scrape jobs.
- **`proxmox-menu` shortcut**: `/usr/local/bin/proxmox-menu` is created when run as root, usable from anywhere; follows the tool folder if it moves.
- **`proxmox-menu refresh`** runs `git pull` first and restarts on the new code.
- **Menu 10 migrates old jobs to the exporter**: Prometheus jobs with the same name or target as the exporter can be **replaced** — backs up the whole scrape directory (`/root/prom-bak-<time>`), removes exactly those job blocks (drops files left without jobs), pushes the exporter jobs, restores everything if `promtool` fails.
- **`refresh`** also updates Docker clusters: builds the image for the exporter version (skipped if present), recreates containers on the same port, checks metrics; containers already on that version are left alone.
- **`refresh`**: update everything without questions — reinstall exporters, generate + import dashboards with the saved config / token, service table, Prometheus check.
- Grafana import payload is sent as ASCII, independent of the host locale.
- **Dashboard**: HA Groups column wraps instead of truncating (width 380, click a cell for the full value).
- **Menu 26 / `services`**: table of every service (local exporter, `@cluster`, containers, Docker, watchdog) — state, `/health`, port, start on boot; restart / stop / start one or all, then verify active + `/health` and print logs on failure; restarting Docker checks containers come back.
- **Watchdog** (`w` in menu 26 / `watchdog`): systemd timer every 2 minutes, `/health` failing twice in a row restarts that exporter; log in `journalctl -t pve-ceph-watchdog`.
- **Menu 25 / `docker-net`**: change the Docker IP range (`bip`, `default-address-pools`) — warns on public ranges (e.g. `192.20.0.0`) and overlaps with existing routes, backs up `daemon.json`, restarts Docker; systemd exporters are unaffected, containers stop for a few seconds and are checked / restarted; the old file is restored if Docker fails to start.
- **Customer dashboards** (menu 9 → 2, `make_dashboard.py --customer-job`): locked to 1 job + 1 datasource, hides Site / Job, drops Detailed Alarms, HA Groups and the Exporter row, read-only; menu 11 picks the file to import (into the customer's folder).
- UID collapses repeated `-`: `Proxmox - Ceph Prometheus` → `Proxmox-Ceph-Prometheus` (matches the existing dashboard, no duplicate).
- Menu 17: port numbers are rejected at the Ceph mgr question; a 403 prints the exact `pveum` command granting `PVEAuditor` to the token in use (privsep tokens included).
- **Dashboard UID** normalized to `[A-Za-z0-9_-]`, max 40 characters (menu 9, `make_dashboard.py`, and right before import) — fixes Grafana `uid contains illegal characters`.
- **Grafana token entered once**: optionally saved in `.grafana-token` (root-only, not in git); invalid / expired tokens are deleted and asked again; delete by hand in menu 15.
- **Menu 11 with a self-signed Grafana cert**: fetches the cert, shows its SHA-256 to compare with the browser and, if accepted, **pins** it (`.grafana-cert.pem`, only for Grafana calls) — TLS is still verified. If the cert does not list the URL's IP, the tool calls by the cert name and points it at the real IP. A Viewer-only token is reported as needing the Editor role.
- **Menu 11**: explains why Grafana cannot be reached (self-signed cert, http/https mix-up, refused, timeout, DNS) with the fix, and tries the other URL scheme.
- **Menu 9** writes `dashboard-local.json` (not tracked by git) instead of overwriting `proxmox_ceph_dashboard.json`, which used to block `git pull` in menu 14.
- **Menu 14**: moves a dashboard generated by an old version into `dashboard-local.json` before pulling; a failed pull is reported with the edited files instead of "already up to date".
- **Dashboard**: **Proxmox Cluster** tile at the top of *Proxmox Resource* shows the real cluster name, node count and quorum of the selected job.
- **Dashboard**: *Resource Cluster with HA Groups* no longer shows stray `id 1 … id 5` columns (each query keeps only `host`).
- **Menu 10**: warns when the entered IP is not this monitor host; rejects directories / globs as the main config file; SSH asks for the password once and offers to create a key + `ssh-copy-id`.
- **Menu 12**: a target down because it points to another host is explained with the fix.
- Default job names are no longer doubled (`Proxmox-Proxmox-…`) when the cluster name already starts with `Proxmox-`.
- **Menu 11** checks the Prometheus datasources on Grafana before importing.
- **Exporter 2026.10.30-6**: `/health` (503 when the collection loop is hung for over `3 × INTERVAL`, at least 120 s); Docker image `HEALTHCHECK` → `docker ps` shows `unhealthy`.
- **Unit tests** (`tests/`) and **GitHub Actions CI**: `bash -n`, `shellcheck`, unit tests, regenerated dashboard compared with the repo file, `promtool check rules`.

## 2026-10-29

### Prometheus / Grafana
- Menu header shows the running commit and announces newer versions on GitHub.
- Menu **10** merges every cluster into `prometheus-scrape-all.yml`: checks each exporter, skips duplicate jobs (keeps the healthy one), flags two configs for the same cluster.
- Push the scrape file over SSH (`prom-push`) into the `scrape_config_files` directory as `proxmox-ceph-<host>.yml`; restores the old file if `promtool` fails.
- Push alert rules over SSH (`prom-rules`), adding `rule_files` if missing.
- Menu **15** / `urls`: set the Prometheus and Grafana URLs directly; catches mistyped URLs, tries http / https.
- Menu **18**: real cluster column, red rows for configs sharing a cluster / job.
- Dashboard **Exporter** row (collector state, last error, data age, version); `alerts/pve-ceph-alerts.yml` with 19 rules.

### Remote monitoring (menu 17)
- Finds the active mgr on every node of the cluster (`CEPH_MGR` empty), standby mgrs are skipped.
- Detects self-signed certs and offers to disable TLS verification and retest; refused ports are reported separately from firewall timeouts.
- Warns on nodes already in another cluster, `root@pam` tokens, ports 9283 / 9221; changing the Token ID requires a new secret.
- Menus 21–24: packages per distro, firewall for Prometheus, clusters in Docker.

### Exporter
- Remote mode over the Proxmox API (read-only token) + ceph mgr, one `@<name>` service per cluster.
- All metrics merged on one port (ceph mgr + Proxmox + extras), default port 9830.
- Background collection every 30 s, CPU / RAM / IO limits via systemd.
