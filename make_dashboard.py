#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sinh dashboard Grafana "Proxmox - Ceph" (Prometheus).
Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.

Khac ban dashboard tay cu:
  - OSD Used Class / Top 5 Latency lap theo bien $class (lay tu ceph_osd_metadata)
    -> chi hien class thuc su co OSD (ssd, hdd, nvme, hdd12t, ...), het o "No data".
  - Detailed Alarms hien "HEALTH_OK" khi khong co canh bao.
  - Bang HA Group loc theo $job (truoc day tron node cua moi cluster) + cot HA Groups.
  - Ceph Status / Total Health / Recovery Speed doc tu pve_ceph_extra_exporter,
    co gia tri mac dinh khi khong co recovery.

Vi du:
  python make_dashboard.py -o proxmox_ceph_dashboard.json
  python make_dashboard.py --title "Proxmox - Ceph DECO" --uid pve-ceph-deco \
      --site-regex "/^Prometheus (FPT HN|CMC-Q7)$/" --job-regex "/.*Proxmox-/"
"""

import argparse
import json

DS = {"type": "prometheus", "uid": "${Site}"}
J = 'job=~"$job"'


class Builder(object):
    def __init__(self):
        self.panels = []
        self.next_id = 1
        self.y = 0

    def add(self, panel, x, w, h, y=None):
        panel["id"] = self.next_id
        self.next_id += 1
        panel["gridPos"] = {"h": h, "w": w, "x": x, "y": self.y if y is None else y}
        self.panels.append(panel)
        return panel

    def row(self, title):
        self.add({"type": "row", "title": title, "collapsed": False, "panels": []}, 0, 24, 1)
        self.y += 1

    def line(self, h, *items):
        """items: (panel, width) dat lien tren 1 hang."""
        x = 0
        for panel, w in items:
            self.add(panel, x, w, h)
            x += w
        self.y += h


def tgt(expr, ref="A", legend=None, fmt=None, instant=True):
    t = {"datasource": DS, "expr": expr, "refId": ref, "range": not instant, "instant": instant}
    if legend:
        t["legendFormat"] = legend
    if fmt:
        t["format"] = fmt
    return t


def steps(*pairs):
    out = [{"color": pairs[0], "value": None}]
    for i in range(1, len(pairs), 2):
        out.append({"color": pairs[i + 1], "value": pairs[i]})
    return {"mode": "absolute", "steps": out}


def stat(title, targets, unit="none", th=None, color_mode="background", text_mode="value",
         mappings=None, decimals=None, no_value=None, fixed_color=None, desc=None, value_size=None):
    d = {"unit": unit, "thresholds": th or steps("green"), "mappings": mappings or [],
         "color": {"mode": "fixed", "fixedColor": fixed_color} if fixed_color else {"mode": "thresholds"}}
    if decimals is not None:
        d["decimals"] = decimals
    if no_value is not None:
        d["noValue"] = no_value
    p = {"type": "stat", "title": title, "datasource": DS, "targets": targets,
         "fieldConfig": {"defaults": d, "overrides": []},
         "options": {"colorMode": color_mode, "graphMode": "none", "justifyMode": "center",
                     "orientation": "auto", "textMode": text_mode, "wideLayout": True,
                     "showPercentChange": False,
                     "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}}
    if value_size:
        p["options"]["text"] = {"valueSize": value_size}
    if desc:
        p["description"] = desc
    return p


def table(title, targets, transforms, unit="none", th=None, decimals=None, overrides=None,
          cell="color-text", filterable=False, footer=None, desc=None, no_value=None):
    d = {"unit": unit, "thresholds": th or steps("green"), "mappings": [],
         "color": {"mode": "thresholds"},
         "custom": {"align": "center", "cellOptions": {"type": cell}, "inspect": False,
                    "filterable": filterable}}
    if decimals is not None:
        d["decimals"] = decimals
    if no_value is not None:
        d["noValue"] = no_value
    p = {"type": "table", "title": title, "datasource": DS, "targets": targets,
         "transformations": transforms,
         "fieldConfig": {"defaults": d, "overrides": overrides or []},
         "options": {"cellHeight": "sm", "showHeader": True,
                     "footer": {"show": bool(footer), "reducer": footer or ["sum"],
                                "fields": "", "countRows": False}}}
    if desc:
        p["description"] = desc
    return p


def organize(exclude=(), rename=None, order=None):
    return {"id": "organize", "options": {
        "excludeByName": {k: True for k in exclude},
        "renameByName": rename or {}, "indexByName": order or {}}}


def drop_extra_fields(pattern):
    """An cac cot Time/__name__/instance/job... (ke ca ban danh so 'Time 1')."""
    return {"id": "filterFieldsByName", "options": {"exclude": {"pattern": pattern}}}


def override(name, *props):
    return {"matcher": {"id": "byName", "options": name},
            "properties": [{"id": k, "value": v} for k, v in props]}


def repeat(panel, var="class", max_per_row=2):
    panel["repeat"] = var
    panel["repeatDirection"] = "h"
    panel["maxPerRow"] = max_per_row
    return panel


# --------------------------------------------------------------------------- queries
def osd_used_pct(fn):
    return ('%s(1,\n  max by (ceph_daemon) (ceph_osd_stat_bytes_used{%s})\n'
            '  / max by (ceph_daemon) (ceph_osd_stat_bytes{%s}) * 100\n'
            '  * on(ceph_daemon) group_left()\n'
            '  max by (ceph_daemon) (ceph_osd_metadata{device_class=~"$class", %s})\n)'
            % (fn, J, J, J))


def osd_latency_all():
    return ('sort_desc(\n  max by (ceph_daemon, hostname) (\n'
            '    ceph_osd_apply_latency_ms{%s}\n'
            '    * on(ceph_daemon) group_left(hostname)\n'
            '    max by (ceph_daemon, hostname) (ceph_osd_metadata{device_class=~"$class", %s})\n  )\n)'
            % (J, J))


def parse_lat_th(text):
    """'nvme=15:25,ssd=50:100,default=100:200' -> {'nvme': (15, 25), ...}"""
    out = {}
    for item in filter(None, (x.strip() for x in text.split(","))):
        cls, _, rng = item.partition("=")
        warn, _, crit = rng.partition(":")
        out[cls.strip()] = (float(warn), float(crit))
    return out


def parse_ha_alias(items):
    """['A,B=Text:purple', ...] -> mapping options cho cot HA Groups."""
    opts = {}
    for i, item in enumerate(items or []):
        raw, _, rest = item.rpartition("=")
        text, _, color = rest.partition(":")
        opts[raw] = {"text": text, "color": color or "blue", "index": i}
    return opts


def node_q(expr):
    # Chi giu nhan host: join nhieu query ma con nhan id/instance/... thi Grafana doi ten
    # nhan trung thanh "id 1", "id 2" ... -> loc cot an khong bat duoc, hien cot thua.
    return 'max by (host) (label_replace(%s, "host", "$1", "id", "node/(.*)"))' % expr


NO_ALARM = ('max by (severity, name, message) (ceph_health_detail{%s} > 0)\n'
            'or on() label_replace(label_replace(label_replace(vector(0),\n'
            '  "severity", "OK", "", ""), "name", "HEALTH_OK", "", ""),\n'
            '  "message", "Không có cảnh báo", "", "")' % J)

HIDE = "^(Time.*|__name__.*|instance.*|job.*|job_type.*|id( \\d+)?|state( \\d+)?|group( \\d+)?|Value #Group)$"


# --------------------------------------------------------------------------- dashboard
def build(args):
    b = Builder()

    # ---------------- Cluster State
    b.row("Cluster State")
    health_map = [{"type": "value", "options": {
        "0": {"text": "HEALTHY", "color": "green"},
        "1": {"text": "WARNING", "color": "orange"},
        "2": {"text": "ERROR", "color": "red"}}},
        {"type": "special", "options": {"match": "null", "result": {"text": "N/A", "color": "gray"}}}]
    alarms = table("Detailed Alarms", [tgt(NO_ALARM, fmt="table")],
                   [organize(["Time", "Value"],
                             {"severity": "LEVEL", "name": "ERROR CODE", "message": "DETAILED MESSAGE"},
                             {"severity": 0, "name": 1, "message": 2})],
                   cell="auto",
                   overrides=[override("LEVEL", ("custom.cellOptions", {"type": "color-text"}),
                                       ("mappings", [{"type": "value", "options": {
                                           "OK": {"color": "green"},
                                           "HEALTH_WARN": {"color": "orange"},
                                           "HEALTH_ERR": {"color": "red"}}}]))])
    b.line(5,
           (stat("Cluster Health Status", [tgt('max(ceph_health_status{%s})' % J)],
                 th=steps("green", 1, "orange", 2, "red"), mappings=health_map), 4),
           (alarms, 4),
           (stat("Cluster Capacity", [tgt('sum(ceph_cluster_total_bytes{%s})' % J)],
                 unit="decbytes", color_mode="value", fixed_color="green", value_size=60), 4),
           (stat("Used Capacity", [tgt('sum(ceph_cluster_total_used_bytes{%s})' % J)],
                 unit="decbytes", color_mode="value", fixed_color="green", value_size=60), 4),
           (stat("PG Inconsistent", [tgt('sum(ceph_pg_inconsistent{%s}) or vector(0)' % J)],
                 th=steps("green", 1, "red")), 4),
           (stat("Avg Apply Latency", [tgt('avg(ceph_osd_apply_latency_ms{%s})' % J)],
                 unit="ms", decimals=2, th=steps("green", 10, "orange", 50, "red")), 4))

    # ---------------- OSD State
    b.row("OSD State")
    pct_th = steps("green", 75, "orange", 85, "red")
    used_th = steps("green", 75, "#EAB839", 90, "red", 95, "dark-red")

    def osd_extreme(title, fn):
        p = stat(title, [tgt('%s(1, ceph_osd_stat_bytes_used{%s} / ceph_osd_stat_bytes{%s} * 100)'
                             % (fn, J, J), legend="{{ceph_daemon}}")],
                 unit="percent", decimals=2, th=pct_th, text_mode="value_and_name")
        p["options"]["text"] = {"titleSize": 24, "valueSize": 60}
        return p

    b.line(5,
           (stat("OSDs OUT", [tgt('count(ceph_osd_in{%s} == 0) or vector(0)' % J)],
                 th=steps("green", 1, "red")), 4),
           (stat("OSDs DOWN", [tgt('count(ceph_osd_up{%s} == 0) or vector(0)' % J)],
                 th=steps("green", 1, "red")), 4),
           (stat("OSDs UP", [tgt('count(ceph_osd_up{%s} == 1) or vector(0)' % J)],
                 color_mode="none"), 4),
           (stat("OSDs IN", [tgt('count(ceph_osd_in{%s} == 1) or vector(0)' % J)],
                 color_mode="none"), 4),
           (osd_extreme("OSD Low", "bottomk"), 4),
           (osd_extreme("OSD High", "topk"), 4))

    used = table("OSD Used Class $class",
                 [tgt(osd_used_pct("topk"), "High", fmt="table"),
                  tgt(osd_used_pct("bottomk"), "Low", fmt="table")],
                 [{"id": "merge", "options": {}},
                  drop_extra_fields("^(Time.*|job.*)$"),
                  organize(rename={"ceph_daemon": "OSD", "Value #High": "High", "Value #Low": "Low"},
                           order={"ceph_daemon": 0, "Value #High": 1, "Value #Low": 2})],
                 unit="percent", decimals=2, th=used_th,
                 desc="Lặp theo biến OSD Class: OSD dùng nhiều nhất / ít nhất của từng device class.")
    b.add(repeat(used), 0, 12, 5)
    b.y += 5

    # ---------------- Proxmox Resource - HA Group
    b.row("Proxmox Resource - HA Group")
    nj = 'id=~"node/.*", %s' % J
    ha = table("Resource Cluster with HA Groups",
               [tgt(node_q('pve_cpu_usage_ratio{%s} * 100' % nj), "CPU", fmt="table"),
                tgt(node_q('pve_memory_usage_bytes{%s} / pve_memory_size_bytes{%s} * 100' % (nj, nj)),
                    "RAM_Pct", fmt="table"),
                tgt(node_q('pve_memory_size_bytes{%s}' % nj), "RAM_Total", fmt="table"),
                tgt(node_q('pve_uptime_seconds{%s}' % nj), "Uptime", fmt="table"),
                # Cot HA / HA Groups chi co khi cluster co HA group: query rong -> cot tu an
                tgt('%s\nand on() count(pve_ha_groups_custom_info{%s})'
                    % (node_q('pve_ha_state{state="online", %s}' % nj), J), "HA", fmt="table"),
                tgt('max by (host, groups) (pve_ha_groups_custom_info{%s})' % J, "Group", fmt="table")],
               [{"id": "joinByField", "options": {"byField": "host", "mode": "outer"}},
                drop_extra_fields(HIDE),
                organize(rename={"host": "Node Proxmox", "groups": "HA Groups", "Value #HA": "HA",
                                 "Value #CPU": "CPU (%)", "Value #RAM_Pct": "RAM (%)",
                                 "Value #RAM_Total": "Tổng RAM", "Value #Uptime": "UPTIME"},
                         order={"host": 0, "groups": 1, "Value #HA": 2, "Value #CPU": 3,
                                "Value #RAM_Pct": 4, "Value #RAM_Total": 5, "Value #Uptime": 6}),
                {"id": "sortBy", "options": {"sort": [{"field": "Node Proxmox"}]}}],
               cell="auto", filterable=True,
               desc="Cột HA và HA Groups chỉ hiện khi cluster đang chọn có HA group / node-affinity rule (pve_ceph_extra_exporter đọc groups.cfg / rules.cfg).",
               overrides=[
                   override("HA", ("mappings", [
                       {"type": "value", "options": {
                           "1": {"text": "Online", "color": "green", "index": 0},
                           "0": {"text": "-", "color": "red", "index": 1}}},
                       {"type": "special", "options": {"match": "null",
                                                       "result": {"text": "-", "color": "text"}}}]),
                       ("custom.cellOptions", {"type": "color-text"})),
                   override("HA Groups", ("custom.width", 300),
                            ("custom.cellOptions", {"type": "color-text"}),
                            ("mappings", [
                                {"type": "value", "options": parse_ha_alias(args.ha_alias)},
                                {"type": "special", "options": {"match": "null",
                                                                "result": {"text": "No Group",
                                                                           "color": "gray"}}}])),
                   override("CPU (%)", ("unit", "percent"), ("decimals", 1),
                            ("thresholds", steps("green", 75, "orange", 90, "red")),
                            ("custom.cellOptions", {"type": "color-text"})),
                   override("RAM (%)", ("unit", "percent"), ("decimals", 1),
                            ("thresholds", steps("green", 80, "orange", 90, "red")),
                            ("custom.cellOptions", {"type": "color-text"})),
                   override("Tổng RAM", ("unit", "bytes"), ("decimals", 0)),
                   override("UPTIME", ("unit", "dtdhms"))])
    b.line(4 + 2 * args.nodes, (ha, 24))

    cls = table("OSD CLASS DETAILS",
                [tgt('sum by (device_class) (ceph_cluster_by_class_total_bytes{%s})' % J, "S", fmt="table"),
                 tgt('sum by (device_class) (ceph_cluster_by_class_total_bytes{%s})'
                     ' - sum by (device_class) (ceph_cluster_by_class_total_used_bytes{%s})' % (J, J),
                     "A", fmt="table"),
                 tgt('sum by (device_class) (ceph_cluster_by_class_total_used_bytes{%s})' % J, "R", fmt="table"),
                 tgt('sum by (device_class) (ceph_cluster_by_class_total_used_bytes{%s})'
                     ' / sum by (device_class) (ceph_cluster_by_class_total_bytes{%s}) * 100' % (J, J),
                     "B", fmt="table")],
                [{"id": "merge", "options": {}},
                 drop_extra_fields("^Time.*$"),
                 organize(rename={"device_class": "CLASS", "Value #S": "SIZE", "Value #A": "AVAIL",
                                  "Value #R": "RAW USED", "Value #B": "% RAW USED"},
                          order={"device_class": 0, "Value #S": 1, "Value #A": 2,
                                 "Value #R": 3, "Value #B": 4})],
                unit="bytes", decimals=2, cell="auto", footer=["sum"],
                overrides=[override("% RAW USED", ("unit", "percent"), ("min", 0), ("max", 100),
                                    ("thresholds", used_th),
                                    ("custom.cellOptions", {"type": "color-background",
                                                            "mode": "basic"}))])
    b.line(4 + 2 * args.classes, (cls, 24))

    pool_q = [("A", "ceph_pool_metadata"), ("C", "ceph_pg_total"), ("D", "ceph_pool_stored"),
              ("G", "ceph_pool_objects"), ("H", "ceph_pool_bytes_used"),
              ("K", "ceph_pool_percent_used"), ("L", "ceph_pool_max_avail"),
              ("Q", "ceph_pool_compress_under_bytes")]
    pool = table("CEPH POOL DETAILS",
                 [tgt('max by (pool_id%s) (%s{%s})' % (", name" if r == "A" else "", m, J), r, fmt="table")
                  for r, m in pool_q],
                 [{"id": "merge", "options": {}},
                  drop_extra_fields("^(Time.*|Value #A)$"),
                  organize(rename={"name": "POOL", "pool_id": "ID", "Value #C": "PGS",
                                   "Value #D": "STORED", "Value #G": "OBJECTS", "Value #H": "USED",
                                   "Value #K": "%USED", "Value #L": "MAX AVAIL",
                                   "Value #Q": "UNDER COMPR"},
                           order={"name": 0, "pool_id": 1, "Value #C": 2, "Value #D": 3, "Value #G": 4,
                                  "Value #H": 5, "Value #K": 6, "Value #L": 7, "Value #Q": 8}),
                  {"id": "sortBy", "options": {"sort": [{"field": "%USED", "desc": True}]}}],
                 unit="bytes", decimals=2, cell="auto",
                 overrides=[override("ID", ("unit", "none")), override("PGS", ("unit", "none")),
                            override("OBJECTS", ("unit", "short")),
                            override("%USED", ("unit", "percentunit"),
                                     ("thresholds", steps("green", 0.75, "#EAB839", 0.9, "red",
                                                          0.95, "dark-red")),
                                     ("custom.cellOptions", {"type": "color-background",
                                                             "mode": "basic"}))])
    b.line(4 + 2 * args.pools, (pool, 24))

    # ---------------- Latency
    b.row("Latency All OSD (High → Low)")
    ts = {"type": "timeseries", "title": "OSD Apply Latency", "datasource": DS,
          "targets": [tgt('ceph_osd_apply_latency_ms{%s}' % J, "A", legend="{{ceph_daemon}}",
                          instant=False)],
          "fieldConfig": {"defaults": {"unit": "ms", "min": 0, "color": {"mode": "palette-classic"},
                                       "custom": {"drawStyle": "line", "lineWidth": 1, "fillOpacity": 10,
                                                  "showPoints": "never", "spanNulls": False}},
                          "overrides": []},
          "options": {"legend": {"displayMode": "table", "placement": "right", "showLegend": True,
                                 "calcs": ["lastNotNull"], "sortBy": "Name", "sortDesc": False},
                      "tooltip": {"mode": "multi", "sort": "desc"}}}
    b.line(12, (ts, 24))

    # Cot gia tri doi ten thanh "<class> (ms)" (Grafana noi suy $class trong transformation)
    # de override nguong rieng tung class: nvme nhanh, hdd cham.
    lat_th = parse_lat_th(args.lat_th)
    dw, dc = lat_th.pop("default", (100, 200))
    col = "${class} (ms)"
    lat = table("All $class OSD Latency (High → Low)", [tgt(osd_latency_all(), fmt="table")],
                [drop_extra_fields("^(Time.*|job.*|instance.*)$"),
                 organize(rename={"hostname": "NODE", "ceph_daemon": "OSD ID", "Value": col},
                          order={"hostname": 0, "ceph_daemon": 1, "Value": 2}),
                 {"id": "sortBy", "options": {"sort": [{"field": col, "desc": True}]}}],
                unit="ms", decimals=0, th=steps("green", dw, "orange", dc, "red"), filterable=True,
                desc="Tất cả OSD của class, sắp xếp latency cao → thấp. Ngưỡng theo class: %s; class khác %g/%g ms."
                     % (", ".join("%s %g/%g" % (k, w, c) for k, (w, c) in sorted(lat_th.items())), dw, dc),
                overrides=[override("%s (ms)" % k, ("thresholds", steps("green", w, "orange", c, "red")))
                           for k, (w, c) in sorted(lat_th.items())])
    b.add(repeat(lat), 0, 12, 12)
    b.y += 12

    # ---------------- Recovery
    b.row("Ceph Recovery & Rebalance Operations")
    status = stat("Ceph Status", [tgt('max by (content) (ceph_custom_recovery_info{%s})' % J,
                                      legend="{{content}}")],
                  th=steps("green", 1, "orange", 2, "red"), text_mode="name",
                  no_value="Chưa có dữ liệu - kiểm tra pve_ceph_extra_exporter",
                  desc="Dòng trạng thái giống giao diện Proxmox (pve_ceph_extra_exporter).")
    status["fieldConfig"]["defaults"]["displayName"] = "${__field.labels.content}"
    status["options"]["reduceOptions"]["limit"] = 1
    b.line(3, (status, 24))

    gauge = {"type": "gauge", "title": "Total Health (%)", "datasource": DS,
             "targets": [tgt('min(ceph_custom_recovery_percent{%s})' % J, legend="Health")],
             "fieldConfig": {"defaults": {"unit": "percent", "min": 90, "max": 100, "decimals": 2,
                                          "color": {"mode": "thresholds"},
                                          "thresholds": steps("red", 95, "#EAB839", 99.9, "green")},
                             "overrides": []},
             "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                         "showThresholdLabels": False, "showThresholdMarkers": True}}
    speed = {"type": "timeseries", "title": "Recovery Speed (Tốc độ phục hồi)", "datasource": DS,
             "targets": [tgt('max(ceph_custom_recovery_speed_bytes{%s})' % J, "A",
                             legend="Recovery Speed", instant=False),
                         tgt('sum(ceph_custom_degraded_objects{%s})' % J, "B",
                             legend="Degraded objects", instant=False),
                         tgt('sum(ceph_custom_misplaced_objects{%s})' % J, "C",
                             legend="Misplaced objects", instant=False)],
             "fieldConfig": {"defaults": {"unit": "binBps", "color": {"mode": "palette-classic"},
                                          "custom": {"drawStyle": "line", "lineWidth": 2,
                                                     "fillOpacity": 15, "gradientMode": "opacity",
                                                     "showPoints": "never"}},
                             "overrides": [{"matcher": {"id": "byRegexp", "options": ".*objects"},
                                            "properties": [{"id": "unit", "value": "short"},
                                                           {"id": "custom.axisPlacement",
                                                            "value": "right"}]}]},
             "options": {"legend": {"displayMode": "table", "placement": "bottom", "showLegend": True,
                                    "calcs": ["mean", "max", "lastNotNull"]},
                         "tooltip": {"mode": "multi", "sort": "none"}}}
    b.line(8, (gauge, 5), (speed, 19))

    # ---------------- Exporter: collector nao loi, du lieu cu bao lau -> biet vi sao "No data"
    b.row("Exporter (pve_ceph_extra_exporter)")
    coll = table("Collector",
                 [tgt('max by (collector) (pve_ceph_extra_exporter_up{%s})' % J, "U", fmt="table"),
                  tgt('max by (collector) (pve_ceph_extra_exporter_collect_seconds{%s})' % J, "S",
                      fmt="table"),
                  tgt('max by (collector, error) (pve_ceph_extra_exporter_last_error{%s})' % J, "E",
                      fmt="table")],
                 [{"id": "joinByField", "options": {"byField": "collector", "mode": "outer"}},
                  drop_extra_fields("^(Time.*|Value #E)$"),
                  organize(rename={"collector": "COLLECTOR", "Value #U": "TRẠNG THÁI",
                                   "Value #S": "THỜI GIAN", "error": "LỖI GẦN NHẤT"},
                           order={"collector": 0, "Value #U": 1, "Value #S": 2, "error": 3}),
                  {"id": "sortBy", "options": {"sort": [{"field": "COLLECTOR"}]}}],
                 cell="auto", no_value="Không có metric exporter trong job này",
                 desc="ceph_mgr: phát lại /metrics của ceph mgr · pve: node Proxmox · ceph: Ceph Status / "
                      "Recovery · ha: HA Groups. Collector lỗi thì các ô dùng dữ liệu đó sẽ No data.",
                 overrides=[
                     override("TRẠNG THÁI", ("custom.width", 120),
                              ("custom.cellOptions", {"type": "color-background", "mode": "basic"}),
                              ("mappings", [{"type": "value", "options": {
                                  "1": {"text": "OK", "color": "green", "index": 0},
                                  "0": {"text": "LỖI", "color": "red", "index": 1}}}])),
                     override("THỜI GIAN", ("unit", "s"), ("decimals", 2), ("custom.width", 110),
                              ("thresholds", steps("green", 5, "orange", 15, "red")),
                              ("custom.cellOptions", {"type": "color-text"})),
                     override("LỖI GẦN NHẤT", ("custom.align", "left"),
                              ("custom.cellOptions", {"type": "color-text"}),
                              ("color", {"mode": "fixed", "fixedColor": "red"}))])
    age = stat("Dữ liệu cũ", [tgt('time() - max(pve_ceph_extra_exporter_last_collect_timestamp{%s})' % J)],
               unit="s", decimals=0, th=steps("green", 90, "orange", 180, "red"),
               no_value="Exporter không chạy",
               desc="Bao lâu từ lần thu thập gần nhất. Bình thường < INTERVAL (30s) + scrape_interval.")
    mode = stat("Chế độ", [tgt('max by (mode) (pve_ceph_extra_exporter_mode{%s})' % J,
                               legend="{{mode}}")],
                text_mode="name", color_mode="none", no_value="-")
    ver = stat("Phiên bản", [tgt('max by (version) (pve_ceph_extra_exporter_build_info{%s})' % J,
                                 legend="{{version}}")],
               text_mode="name", color_mode="none", no_value="-")
    for p, label in ((mode, "mode"), (ver, "version")):
        p["fieldConfig"]["defaults"]["displayName"] = "${__field.labels.%s}" % label
        p["options"]["reduceOptions"]["limit"] = 1
    b.line(6, (coll, 15), (age, 3), (mode, 3), (ver, 3))

    # ---------------- variables
    templating = {"list": [
        {"type": "datasource", "name": "Site", "label": "Site", "query": "prometheus",
         "regex": args.site_regex, "refresh": 1, "includeAll": False, "options": [], "current": {}},
        {"type": "query", "name": "job", "label": "Job / Cluster", "datasource": DS,
         "definition": "label_values(pve_cluster_info,job)",
         "query": {"qryType": 1, "query": "label_values(pve_cluster_info,job)",
                   "refId": "PrometheusVariableQueryEditor-VariableQuery"},
         "regex": args.job_regex, "refresh": 1, "includeAll": False, "multi": False,
         "options": [], "current": {}, "sort": 1},
        {"type": "query", "name": "class", "label": "OSD Class", "datasource": DS,
         "definition": 'label_values(ceph_osd_metadata{job=~"$job"},device_class)',
         "query": {"qryType": 1, "query": 'label_values(ceph_osd_metadata{job=~"$job"},device_class)',
                   "refId": "PrometheusVariableQueryEditor-VariableQuery"},
         "refresh": 2, "includeAll": True, "multi": True, "sort": 1,
         "options": [], "current": {"text": ["All"], "value": ["$__all"]}},
    ]}

    return {
        "title": args.title, "uid": args.uid, "editable": True, "graphTooltip": 0,
        "refresh": "30s", "schemaVersion": 41, "timezone": "Asia/Ho_Chi_Minh",
        "time": {"from": args.time_from, "to": "now"}, "tags": ["proxmox", "ceph"],
        "annotations": {"list": [{"builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"},
                                  "enable": True, "hide": True, "iconColor": "rgba(0, 211, 255, 1)",
                                  "name": "Annotations & Alerts", "type": "dashboard"}]},
        "templating": templating, "panels": b.panels, "links": [], "version": 1,
    }


def main():
    ap = argparse.ArgumentParser(description="Sinh dashboard Grafana Proxmox + Ceph")
    ap.add_argument("-o", "--out", default="proxmox_ceph_dashboard.json")
    ap.add_argument("--title", default="Proxmox - Ceph Prometheus")
    ap.add_argument("--uid", default="pve-ceph-prom")
    ap.add_argument("--site-regex", default="", help='loc datasource, vd "/^Prometheus (FPT HN|CMC-Q7)$/"')
    ap.add_argument("--job-regex", default="/.*Proxmox-/", help="loc job cua pve_cluster_info")
    ap.add_argument("--nodes", type=int, default=8, help="so node du kien (chieu cao bang HA)")
    ap.add_argument("--pools", type=int, default=8, help="so pool du kien (chieu cao bang pool)")
    ap.add_argument("--classes", type=int, default=3, help="so device class du kien")
    ap.add_argument("--lat-th", default="nvme=15:25,ssd=50:100,default=100:200",
                    help="nguong latency (ms) canh bao:nghiem trong theo class")
    ap.add_argument("--ha-alias", action="append", default=[], metavar="GROUPS=TEXT[:mau]",
                    help='ten ngan cho chuoi HA Groups, vd "Gold-6146,HIGH-FREQUENCY,P1-XD=Gold+HIGH+P1-XD:orange"')
    ap.add_argument("--time-from", default="now-15m", help="khoang thoi gian mac dinh")
    args = ap.parse_args()

    dash = build(args)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(dash, f, ensure_ascii=False, indent=2)
    print("Da ghi %s (%d panel)" % (args.out, len(dash["panels"])))


if __name__ == "__main__":
    main()
