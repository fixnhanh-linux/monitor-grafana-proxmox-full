#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pve_ceph_extra_exporter - bo sung metric cho dashboard Proxmox + Ceph.
Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.

2 che do chay, chi dung thu vien chuan Python 3:
  * local  : chay tren 1 node Proxmox co Ceph (doc `ceph`, `pvesh`, /etc/pve).
  * remote : (--remote) chay tren may monitor bat ky, KHONG cai gi len node:
             lay du lieu qua API Proxmox (token chi doc, role PVEAuditor) va
             /metrics cua ceph mgr (:9283). Cau hinh qua bien moi truong:
               PVE_API        node1,node2,...   (hoac https://node1:8006,...)
               PVE_TOKEN      monitor@pve!exporter=<secret>
               PVE_VERIFY_TLS 0 (mac dinh, cert tu ky) / 1
               CEPH_MGR       node1:9283,node2:9283 (trong = cac node PVE_API + IP moi node
                              lay tu /cluster/status, tu tim mgr active)
               PORT, INTERVAL

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
import ssl
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from urllib.error import HTTPError
from urllib.request import Request, urlopen

VERSION = "2026.10.30-6"

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


# ---------------------------------------------------------------- remote (API Proxmox)
def split_list(s):
    return [x.strip() for x in (s or "").split(",") if x.strip()]


def parse_nodes(s):
    """'pve1:2,pve2' -> ['pve1', 'pve2'] (bo priority)."""
    return [n.split(":")[0] for n in split_list(s)]


class PveApi(object):
    """Goi API Proxmox bang API token, tu chuyen sang node khac neu node dang dung loi."""

    def __init__(self, hosts, token, verify_tls, timeout):
        self.urls = [h.rstrip("/") if h.startswith("http")
                     else "https://%s" % h if re.search(r":\d+$", h)  # host:port
                     else "https://%s:8006" % h for h in hosts]
        self.token = token
        self.timeout = timeout
        self.good = 0
        self.ctx = ssl.create_default_context()
        if not verify_tls:  # Proxmox mac dinh dung cert tu ky
            self.ctx.check_hostname = False
            self.ctx.verify_mode = ssl.CERT_NONE

    def get(self, path):
        last = RuntimeError("chua cau hinh PVE_API")
        for i in [(self.good + k) % len(self.urls) for k in range(len(self.urls))]:
            req = Request(self.urls[i] + "/api2/json" + path,
                          headers={"Authorization": "PVEAPIToken=" + self.token})
            try:
                with urlopen(req, timeout=self.timeout, context=self.ctx) as resp:
                    data = json.loads(resp.read().decode("utf-8", "replace")).get("data")
                self.good = i
                return data
            except HTTPError as e:
                if e.code in (401, 403):  # sai token / thieu quyen: node khac cung vay
                    raise
                last = e
            except Exception as e:
                last = e
        raise last


def remote_pve_metrics(api):
    status = api.get("/cluster/status") or []
    resources = api.get("/cluster/resources?type=node") or []
    try:
        ha = api.get("/cluster/ha/status/manager_status") or {}
    except Exception:
        ha = {}
    return pve_metrics(status, resources, ha)


def remote_ceph_status(api):
    try:
        return api.get("/cluster/ceph/status")
    except HTTPError as e:
        if e.code in (401, 403):
            raise
    # PVE cu: hoi qua 1 node dang online
    for n in api.get("/cluster/status") or []:
        if n.get("type") == "node" and n.get("online"):
            return api.get("/nodes/%s/ceph/status" % n.get("name"))
    raise RuntimeError("khong co node online")


def remote_ha_groups(api):
    groups, ok, last = {}, False, None
    for path, kind, key in (("/cluster/ha/groups", None, "group"),
                            ("/cluster/ha/rules", "node-affinity", "rule")):  # PVE 9
        try:
            items = api.get(path) or []
            ok = True
        except Exception as e:
            last = e
            continue
        for it in items:
            if kind and it.get("type") != kind:
                continue
            for n in parse_nodes(it.get("nodes")):
                groups.setdefault(n, set()).add(it.get(key, "?"))
    if not ok:
        raise RuntimeError("khong doc duoc HA groups / rules: %s" % last)
    return {h: ",".join(sorted(g)) for h, g in groups.items()}


def remote_mgr_metrics(mgr_hosts, timeout, start=0):
    """Thu lan luot cac mgr, mgr standby tra rong -> bo qua. Tra (lines, index mgr tot)."""
    errs = []
    for k in range(len(mgr_hosts)):
        i = (start + k) % len(mgr_hosts)
        h = mgr_hosts[i]
        url = h if h.startswith("http") else "http://%s" % (h if ":" in h else h + ":9283")
        try:
            return ceph_mgr_metrics(url, timeout), i
        except Exception as e:
            errs.append("%s: %s" % (h, e))
    raise RuntimeError("; ".join(errs) or "chua cau hinh CEPH_MGR")


# ---------------------------------------------------------------- server
class Collector(object):
    """Thu thap o luong nen moi --interval giay; HTTP chi tra ket qua san co.
    -> tai len server co dinh, khong phu thuoc so lan / so Prometheus scrape."""

    def __init__(self, args):
        self.args = args
        self.lock = threading.Lock()
        self.ready = threading.Event()
        self.cache = ""
        self.last_ts = 0.0
        self.mgr_url, self.mgr_url_ts = "", 0.0
        self.mgr_good = 0
        self.api = None
        if args.remote:
            self.api = PveApi(split_list(args.pve_api), args.pve_token, args.verify_tls, args.timeout)
            self.mgr_auto = not split_list(args.ceph_mgr)  # trong -> tu do moi node cua cluster
            self.mgr_hosts = split_list(args.ceph_mgr) or [
                h.split("//")[-1].split(":")[0] + ":9283" for h in split_list(args.pve_api)]
            self.mgr_hosts_ts = 0.0

    def _remote_mgr(self):
        # Mgr active co the nam o node khong khai bao trong PVE_API (node do la standby,
        # /metrics rong) -> lay IP tat ca node tu /cluster/status, hoi lai moi 5 phut.
        if self.mgr_auto and time.time() - self.mgr_hosts_ts > 300:
            try:
                ips = [n["ip"] + ":9283" for n in self.api.get("/cluster/status") or []
                       if n.get("type") == "node" and n.get("ip")]
                self.mgr_hosts = self.mgr_hosts + [h for h in ips if h not in self.mgr_hosts]
                self.mgr_hosts_ts = time.time()
            except Exception:
                pass
        lines, self.mgr_good = remote_mgr_metrics(self.mgr_hosts, self.args.timeout, self.mgr_good)
        return lines

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
        up, took, errs, lines = {}, {}, {}, []

        def run(name, fn):
            t0 = time.time()
            try:
                lines.extend(fn())
                up[name] = 1
            except Exception as e:
                up[name] = 0
                errs[name] = str(e)[:200]
                if name == "ceph_mgr":
                    self.mgr_url = ""  # mgr co the da chuyen node
            took[name] = time.time() - t0

        if a.remote:
            api = self.api
            if not a.no_ceph_mgr:
                run("ceph_mgr", self._remote_mgr)
            if not a.no_pve:
                run("pve", lambda: remote_pve_metrics(api))
            run("ceph", lambda: ceph_metrics(parse_ceph_status(remote_ceph_status(api))))
            run("ha", lambda: ha_metrics(remote_ha_groups(api)))
        else:
            if not a.no_ceph_mgr:
                run("ceph_mgr", lambda: ceph_mgr_metrics(self._mgr_url(), a.timeout))
            if not a.no_pve:
                run("pve", lambda: collect_pve(a.pvesh_bin, a.timeout))
            run("ceph", lambda: ceph_metrics(parse_ceph_status(run_ceph_status(a.ceph_bin, a.timeout))))
            run("ha", lambda: ha_metrics(ha_groups_by_host()))

        lines.append("# TYPE pve_ceph_extra_exporter_up gauge")
        for k, v in sorted(up.items()):
            lines.append('pve_ceph_extra_exporter_up{collector="%s"} %d' % (k, v))
        lines.append("# TYPE pve_ceph_extra_exporter_last_error gauge")
        for k, v in sorted(errs.items()):
            lines.append('pve_ceph_extra_exporter_last_error{collector="%s",error="%s"} 1' % (k, esc(v)))
        lines.append('pve_ceph_extra_exporter_mode{mode="%s"} 1' % ("remote" if a.remote else "local"))
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
                self.last_ts = time.time()
            self.ready.set()
            time.sleep(max(1.0, self.args.interval - (time.time() - t0)))

    def start(self):
        threading.Thread(target=self.loop, daemon=True).start()

    def get(self):
        self.ready.wait(120)
        with self.lock:
            return self.cache

    def age(self):
        """Giay tu lan thu thap xong gan nhat (None = chua thu thap lan nao)."""
        with self.lock:
            return time.time() - self.last_ts if self.last_ts else None


def make_handler(collector):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path, code = self.path.split("?")[0], 200
            if path == "/metrics":
                body = collector.get().encode("utf-8")
                ctype = "text/plain; version=0.0.4; charset=utf-8"
            elif path == "/health":
                # 503 khi vong thu thap nen bi treo (lenh ceph / API khong tra loi) -> Docker / systemd biet
                age, limit = collector.age(), max(3 * collector.args.interval, 120)
                if age is not None and age <= limit:
                    body = ("ok %ds\n" % age).encode()
                else:
                    code = 503
                    body = ("stale %s\n" % ("chua thu thap" if age is None else "%ds" % age)).encode()
                ctype = "text/plain"
            else:
                body = b"<a href='/metrics'>/metrics</a> <a href='/health'>/health</a>\n"
                ctype = "text/html"
            self.send_response(code)
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
    env = os.environ.get
    ap = argparse.ArgumentParser(description="Exporter Proxmox + Ceph (local tren node / remote qua API)")
    ap.add_argument("--listen", default=env("LISTEN", "0.0.0.0"))
    ap.add_argument("--port", type=int, default=int(env("PORT", "9830")))
    ap.add_argument("--remote", action="store_true", default=env("REMOTE", "") == "1",
                    help="lay du lieu qua API Proxmox + ceph mgr, khong can chay tren node")
    ap.add_argument("--pve-api", default=env("PVE_API", ""), help="node1,node2 hoac https://node1:8006,...")
    ap.add_argument("--pve-token", default=env("PVE_TOKEN", ""),
                    help="USER@REALM!TOKENID=SECRET (nen dat qua bien moi truong PVE_TOKEN)")
    ap.add_argument("--verify-tls", action="store_true", default=env("PVE_VERIFY_TLS", "0") == "1")
    ap.add_argument("--ceph-mgr", default=env("CEPH_MGR", ""), help="host:9283,... (remote)")
    ap.add_argument("--ceph-bin", default="ceph")
    ap.add_argument("--pvesh-bin", default="pvesh")
    ap.add_argument("--ceph-mgr-url", default="", help="mac dinh lay tu `ceph mgr services`")
    ap.add_argument("--no-ceph-mgr", action="store_true",
                    help="khong phat lai metric ceph mgr (Prometheus scrape :9283 rieng)")
    ap.add_argument("--no-pve", action="store_true",
                    help="khong xuat metric Proxmox (da co prometheus-pve-exporter rieng)")
    ap.add_argument("--timeout", type=int, default=10, help="timeout lenh ceph (giay)")
    ap.add_argument("--interval", type=int, default=int(env("INTERVAL", "30")),
                    help="chu ky thu thap nen (giay); scrape chi doc ket qua san co")
    ap.add_argument("--once", action="store_true", help="in metric ra stdout roi thoat")
    args = ap.parse_args()
    if args.remote and not (args.pve_api and args.pve_token):
        ap.error("--remote can PVE_API va PVE_TOKEN")

    collector = Collector(args)
    if args.once:
        print(collector.collect(), end="")
        return
    collector.start()
    Server((args.listen, args.port), make_handler(collector)).serve_forever()


if __name__ == "__main__":
    main()
