#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pve_ceph_extra_exporter - bo sung metric cho dashboard Proxmox + Ceph.
Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.

Chay tren 1 node Proxmox co Ceph (can quyen doc `ceph status` va /etc/pve).
Chi dung thu vien chuan Python 3 (co san tren Proxmox 7/8/9).

Mac dinh GOP TAT CA metric ra 1 port (Prometheus chi can 1 target):
  - phat lai /metrics cua ceph mgr dang active (tat bang --no-ceph-mgr)
  - metric Proxmox lay tu pvesh, ten giong prometheus-pve-exporter (tat bang --no-pve):
      pve_cluster_info, pve_up, pve_cpu_usage_ratio, pve_memory_*, pve_disk_*,
      pve_uptime_seconds, pve_ha_state{state}
  - cac metric bo sung ben duoi

Metric bo sung:
  ceph_custom_recovery_info{content,state}   trang thai 1 dong giong GUI Proxmox
                                             value: 0=OK, 1=recovery/rebalance, 2=loi
  ceph_custom_recovery_percent               % du lieu da on dinh (100 = khong co recovery)
  ceph_custom_recovery_speed_bytes           toc do recovery (bytes/s), 0 khi khong recovery
  ceph_custom_recovery_objects_per_sec       so object recovery / giay
  ceph_custom_degraded_objects               object degraded
  ceph_custom_misplaced_objects              object misplaced
  ceph_custom_unfound_objects                object unfound
  ceph_custom_pgs_not_clean                  so PG khong active+clean
  ceph_custom_progress_percent{event}        tien do tung su kien (ceph progress)
  pve_ha_groups_custom_info{host,groups}     HA group / node-affinity rule cua tung node
  pve_ceph_extra_exporter_up{collector}      1 = thu thap OK
"""

import argparse
import json
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

VERSION = "2026.10.30-2"

HA_GROUPS_CFG = "/etc/pve/ha/groups.cfg"
HA_RULES_CFG = "/etc/pve/ha/rules.cfg"  # PVE 9: HA group -> node-affinity rule


def esc(v):
    return str(v).replace("\\", "\\\\").replace("\n", " ").replace('"', '\\"')


def fmt_bytes(n):
    n = float(n)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024 or unit == "TiB":
            return "%.1f %s" % (n, unit) if unit != "B" else "%d B" % n
        n /= 1024.0


# ---------------------------------------------------------------- Ceph
def run_ceph_status(ceph_bin, timeout):
    out = subprocess.check_output(
        [ceph_bin, "status", "--format", "json"],
        stderr=subprocess.DEVNULL, timeout=timeout)
    return json.loads(out.decode("utf-8", "replace"))


def parse_ceph_status(st):
    """Tra ve dict cac gia tri recovery tu output `ceph status -f json`."""
    health = (st.get("health") or {}).get("status", "HEALTH_UNKNOWN")
    pgmap = st.get("pgmap") or {}

    num_pgs = int(pgmap.get("num_pgs") or 0)
    clean = 0
    for s in pgmap.get("pgs_by_state") or []:
        if s.get("state_name") == "active+clean":
            clean += int(s.get("count") or 0)
    not_clean = max(num_pgs - clean, 0)

    degraded = int(pgmap.get("degraded_objects") or 0)
    misplaced = int(pgmap.get("misplaced_objects") or 0)
    unfound = int(pgmap.get("unfound_objects") or 0)
    total = max(int(pgmap.get("degraded_total") or 0),
                int(pgmap.get("misplaced_total") or 0))
    speed = float(pgmap.get("recovering_bytes_per_sec") or 0)
    obj_speed = float(pgmap.get("recovering_objects_per_sec") or 0)

    bad = degraded + misplaced + unfound
    if total > 0:
        percent = max(0.0, 100.0 * (1.0 - float(bad) / total))
    elif num_pgs > 0:
        percent = 100.0 * clean / num_pgs
    else:
        percent = 100.0

    progress = {}
    for ev in (st.get("progress_events") or {}).values():
        msg = (ev.get("message") or "").strip()
        if msg:
            progress[msg] = float(ev.get("progress") or 0) * 100.0

    if bad > 0 or speed > 0 or progress:
        state, code = ("recovering" if degraded or unfound else "rebalancing"), 1
        parts = []
        if degraded:
            parts.append("degraded %d/%d" % (degraded, total))
        if misplaced:
            parts.append("misplaced %d/%d" % (misplaced, total))
        if unfound:
            parts.append("unfound %d" % unfound)
        content = "%s - Recovery/Rebalance: %.2f%% (%s)" % (
            health, percent, ", ".join(parts) or "đang xử lý")
        if speed > 0:
            content += " - %s/s" % fmt_bytes(speed)
        if unfound:
            code = 2
    elif health == "HEALTH_ERR":
        state, code = "error", 2
        content = "HEALTH_ERR - %d/%d PG active+clean" % (clean, num_pgs)
    else:
        state, code = ("warn", 1) if health == "HEALTH_WARN" else ("ok", 0)
        if not_clean:
            content = "%s - %d/%d PG active+clean" % (health, clean, num_pgs)
        else:
            content = "%s - Tất cả %d PG active+clean, không có recovery" % (
                health, num_pgs)

    return {
        "health": health, "state": state, "code": code, "content": content,
        "percent": round(percent, 3), "speed": speed, "obj_speed": obj_speed,
        "degraded": degraded, "misplaced": misplaced, "unfound": unfound,
        "not_clean": not_clean, "progress": progress,
    }


def ceph_metrics(r):
    lines = [
        "# HELP ceph_custom_recovery_info Trang thai recovery 1 dong (0=OK,1=recovery,2=loi).",
        "# TYPE ceph_custom_recovery_info gauge",
        'ceph_custom_recovery_info{content="%s",state="%s"} %d'
        % (esc(r["content"]), r["state"], r["code"]),
        "# TYPE ceph_custom_recovery_percent gauge",
        "ceph_custom_recovery_percent %s" % r["percent"],
        "# TYPE ceph_custom_recovery_speed_bytes gauge",
        "ceph_custom_recovery_speed_bytes %s" % r["speed"],
        "# TYPE ceph_custom_recovery_objects_per_sec gauge",
        "ceph_custom_recovery_objects_per_sec %s" % r["obj_speed"],
        "# TYPE ceph_custom_degraded_objects gauge",
        "ceph_custom_degraded_objects %d" % r["degraded"],
        "# TYPE ceph_custom_misplaced_objects gauge",
        "ceph_custom_misplaced_objects %d" % r["misplaced"],
        "# TYPE ceph_custom_unfound_objects gauge",
        "ceph_custom_unfound_objects %d" % r["unfound"],
        "# TYPE ceph_custom_pgs_not_clean gauge",
        "ceph_custom_pgs_not_clean %d" % r["not_clean"],
        "# TYPE ceph_custom_progress_percent gauge",
    ]
    for msg, pct in sorted(r["progress"].items()):
        lines.append('ceph_custom_progress_percent{event="%s"} %.2f' % (esc(msg), pct))
    return lines


# ---------------------------------------------------------------- HA groups
def parse_ha_cfg(text, section_types):
    """Doc file cau hinh dang section cua PVE, tra ve {ten: [node,...]}."""
    result, cur = {}, None
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^(\S+):\s*(\S+)", line)
        if m and not raw[0].isspace():
            cur = m.group(2) if m.group(1) in section_types else None
            if cur is not None:
                result.setdefault(cur, [])
            continue
        if cur is None:
            continue
        kv = line.strip().split(None, 1)
        if len(kv) == 2 and kv[0] == "nodes":
            for n in kv[1].split(","):
                n = n.strip().split(":")[0]  # bo priority "pve1:2"
                if n:
                    result[cur].append(n)
    return result


def ha_groups_by_host():
    groups = {}
    for path, types in ((HA_GROUPS_CFG, ("group",)),
                        (HA_RULES_CFG, ("node-affinity",))):
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as f:
                for name, nodes in parse_ha_cfg(f.read(), types).items():
                    for n in nodes:
                        groups.setdefault(n, set()).add(name)
    return {h: ",".join(sorted(g)) for h, g in groups.items()}


def ha_metrics(by_host):
    lines = ["# HELP pve_ha_groups_custom_info HA group / node-affinity rule cua node.",
             "# TYPE pve_ha_groups_custom_info gauge"]
    for host, g in sorted(by_host.items()):
        lines.append('pve_ha_groups_custom_info{host="%s",groups="%s"} 1' % (esc(host), esc(g)))
    return lines


# ---------------------------------------------------------------- ceph mgr (gop 1 port)
def ceph_mgr_url(ceph_bin, timeout):
    """URL module prometheus cua mgr dang active (`ceph mgr services`)."""
    out = subprocess.check_output([ceph_bin, "mgr", "services", "--format", "json"],
                                  stderr=subprocess.DEVNULL, timeout=timeout)
    url = json.loads(out.decode("utf-8", "replace")).get("prometheus")
    if not url:
        raise RuntimeError("chua bat module prometheus: ceph mgr module enable prometheus")
    return url


def ceph_mgr_metrics(url, timeout):
    """Lay nguyen van /metrics cua ceph mgr de phat lai tren cung port."""
    from urllib.request import urlopen
    with urlopen(url.rstrip("/") + "/metrics", timeout=timeout) as resp:
        text = resp.read().decode("utf-8", "replace")
    if "ceph_health_status" not in text:
        raise RuntimeError("mgr tra ve rong (standby?)")
    return text.rstrip("\n").splitlines()


# ---------------------------------------------------------------- Proxmox (gop 1 port)
# Ten metric giong prometheus-pve-exporter de dashboard dung chung query.
PVE_HA_STATES = ("online", "maintenance", "unknown", "fence", "gone", "lost")


def pvesh(pvesh_bin, path, timeout):
    out = subprocess.check_output([pvesh_bin, "get", path, "--output-format", "json"],
                                  stderr=subprocess.DEVNULL, timeout=timeout)
    return json.loads(out.decode("utf-8", "replace"))


def pve_metrics(status, resources, ha_manager):
    """status=/cluster/status, resources=/cluster/resources?type=node,
    ha_manager=/cluster/ha/status/manager_status."""
    lines = ["# TYPE pve_cluster_info gauge"]
    cluster = [x for x in status if x.get("type") == "cluster"]
    if cluster:
        c = cluster[0]
        lines.append('pve_cluster_info{id="cluster/%s",nodes="%s",quorate="%s",version="%s"} 1'
                     % (esc(c.get("name", "")), c.get("nodes", ""), c.get("quorate", ""),
                        c.get("version", "")))
    else:  # node le, khong join cluster
        n = [x for x in status if x.get("type") == "node"]
        name = n[0].get("name", "standalone") if n else "standalone"
        lines.append('pve_cluster_info{id="cluster/%s",nodes="1",quorate="1",version=""} 1' % esc(name))

    gauges = (("pve_up", None), ("pve_cpu_usage_ratio", "cpu"), ("pve_cpu_usage_limit", "maxcpu"),
              ("pve_memory_usage_bytes", "mem"), ("pve_memory_size_bytes", "maxmem"),
              ("pve_disk_usage_bytes", "disk"), ("pve_disk_size_bytes", "maxdisk"),
              ("pve_uptime_seconds", "uptime"))
    nodes = sorted((x for x in resources if x.get("type") == "node"), key=lambda x: x.get("id", ""))
    for metric, key in gauges:
        lines.append("# TYPE %s gauge" % metric)
        for n in nodes:
            if key is None:
                val = 1 if n.get("status") == "online" else 0
            else:
                val = n.get(key) or 0
            lines.append('%s{id="%s"} %s' % (metric, esc(n.get("id", "")), val))

    node_status = ((ha_manager or {}).get("manager_status") or {}).get("node_status") or {}
    lines.append("# TYPE pve_ha_state gauge")
    for node, st in sorted(node_status.items()):
        for s in PVE_HA_STATES:
            lines.append('pve_ha_state{id="node/%s",state="%s"} %d' % (esc(node), s, 1 if st == s else 0))
    return lines


PVE_MEMBERS = "/etc/pve/.members"            # pmxcfs: ten cluster, node online (doc file, khong ton CPU)
PVE_HA_MANAGER = "/etc/pve/ha/manager_status"  # pmxcfs: trang thai HA tung node


def read_json(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return json.load(f)


def members_to_status(m):
    """/etc/pve/.members -> dang list giong `pvesh get /cluster/status`."""
    out = []
    c = m.get("cluster")
    if c and c.get("name"):
        out.append({"type": "cluster", "name": c.get("name"), "nodes": c.get("nodes", ""),
                    "quorate": c.get("quorate", ""), "version": c.get("version", "")})
    out.append({"type": "node", "name": m.get("nodename", "standalone")})
    return out


def collect_pve(pvesh_bin, timeout):
    # Chi 1 lan goi pvesh (perl, ton CPU nhat); cluster + HA doc thang tu pmxcfs.
    try:
        status = members_to_status(read_json(PVE_MEMBERS))
    except Exception:
        status = pvesh(pvesh_bin, "/cluster/status", timeout)
    out = subprocess.check_output([pvesh_bin, "get", "/cluster/resources", "--type", "node",
                                   "--output-format", "json"],
                                  stderr=subprocess.DEVNULL, timeout=timeout)
    resources = json.loads(out.decode("utf-8", "replace"))
    try:
        ha = {"manager_status": read_json(PVE_HA_MANAGER)}
    except Exception:
        ha = {}
    return pve_metrics(status, resources, ha)


# ---------------------------------------------------------------- server
class Collector(object):
    """Thu thap o luong nen moi --interval giay; HTTP chi tra ket qua san co.
    -> tai len server co dinh, khong phu thuoc so lan / so Prometheus scrape."""

    def __init__(self, args):
        self.args = args
        self.lock = threading.Lock()
        self.ready = threading.Event()
        self.cache = ""
        self.mgr_url, self.mgr_url_ts = "", 0.0

    def _mgr_url(self):
        a = self.args
        if a.ceph_mgr_url:
            return a.ceph_mgr_url
        if not self.mgr_url or time.time() - self.mgr_url_ts > 300:  # hoi lai mgr active moi 5 phut
            self.mgr_url = ceph_mgr_url(a.ceph_bin, a.timeout)
            self.mgr_url_ts = time.time()
        return self.mgr_url

    def collect(self):
        a = self.args
        up, took, lines = {}, {}, []

        def run(name, fn):
            t0 = time.time()
            try:
                lines.extend(fn())
                up[name] = 1
            except Exception:
                up[name] = 0
                if name == "ceph_mgr":
                    self.mgr_url = ""  # mgr co the da chuyen node
            took[name] = time.time() - t0

        if not a.no_ceph_mgr:
            run("ceph_mgr", lambda: ceph_mgr_metrics(self._mgr_url(), a.timeout))
        if not a.no_pve:
            run("pve", lambda: collect_pve(a.pvesh_bin, a.timeout))
        run("ceph", lambda: ceph_metrics(parse_ceph_status(run_ceph_status(a.ceph_bin, a.timeout))))
        run("ha", lambda: ha_metrics(ha_groups_by_host()))

        lines.append("# TYPE pve_ceph_extra_exporter_up gauge")
        for k, v in sorted(up.items()):
            lines.append('pve_ceph_extra_exporter_up{collector="%s"} %d' % (k, v))
        lines.append("# TYPE pve_ceph_extra_exporter_collect_seconds gauge")
        for k, v in sorted(took.items()):
            lines.append('pve_ceph_extra_exporter_collect_seconds{collector="%s"} %.3f' % (k, v))
        lines.append("# TYPE pve_ceph_extra_exporter_last_collect_timestamp gauge")
        lines.append("pve_ceph_extra_exporter_last_collect_timestamp %d" % time.time())
        lines.append('pve_ceph_extra_exporter_build_info{version="%s"} 1' % VERSION)
        return "\n".join(lines) + "\n"

    def loop(self):
        while True:
            t0 = time.time()
            text = self.collect()
            with self.lock:
                self.cache = text
            self.ready.set()
            time.sleep(max(1.0, self.args.interval - (time.time() - t0)))

    def start(self):
        threading.Thread(target=self.loop, daemon=True).start()

    def get(self):
        self.ready.wait(120)
        with self.lock:
            return self.cache


def make_handler(collector):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path.split("?")[0] == "/metrics":
                body = collector.get().encode("utf-8")
                ctype = "text/plain; version=0.0.4; charset=utf-8"
            else:
                body = b"<a href='/metrics'>/metrics</a>\n"
                ctype = "text/html"
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *a):
            pass
    return Handler


class Server(ThreadingMixIn, HTTPServer):
    daemon_threads = True


def main():
    ap = argparse.ArgumentParser(description="Exporter bo sung Ceph recovery + HA groups cho Proxmox")
    ap.add_argument("--listen", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=9830)
    ap.add_argument("--ceph-bin", default="ceph")
    ap.add_argument("--pvesh-bin", default="pvesh")
    ap.add_argument("--ceph-mgr-url", default="", help="mac dinh lay tu `ceph mgr services`")
    ap.add_argument("--no-ceph-mgr", action="store_true",
                    help="khong phat lai metric ceph mgr (Prometheus scrape :9283 rieng)")
    ap.add_argument("--no-pve", action="store_true",
                    help="khong xuat metric Proxmox (da co prometheus-pve-exporter rieng)")
    ap.add_argument("--timeout", type=int, default=10, help="timeout lenh ceph (giay)")
    ap.add_argument("--interval", type=int, default=30,
                    help="chu ky thu thap nen (giay); scrape chi doc ket qua san co")
    ap.add_argument("--once", action="store_true", help="in metric ra stdout roi thoat")
    args = ap.parse_args()

    collector = Collector(args)
    if args.once:
        print(collector.collect(), end="")
        return
    collector.start()
    Server((args.listen, args.port), make_handler(collector)).serve_forever()


if __name__ == "__main__":
    main()
