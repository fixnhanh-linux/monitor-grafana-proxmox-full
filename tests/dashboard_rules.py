# -*- coding: utf-8 -*-
"""Chuyen moi query PromQL cua dashboard thanh recording rule de CI chay
"promtool check rules" -> bat loi cu phap query truoc khi import vao Grafana.
Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.

    python3 tests/dashboard_rules.py dashboard-grafana/proxmox_ceph_dashboard.json > /tmp/dash-rules.yml
"""

import json
import re
import sys

# Bien Grafana -> gia tri hop le cho PromQL
VARS = {"__rate_interval": "5m", "__interval": "1m", "__range": "1h"}


def exprs(dash):
    for p in dash.get("panels", []):
        for t in p.get("targets", []):
            if t.get("expr"):
                yield "%s / %s" % (p.get("title", ""), t.get("refId", "")), t["expr"]


def fill(expr):
    # Chi bien bat dau bang chu / "_" -> giu "$1" cua label_replace
    return re.sub(r"\$\{?([A-Za-z_]\w*)\}?",lambda m: VARS.get(m.group(1), ".*"), expr)


def main(path):
    dash = json.load(open(path, encoding="utf-8"))
    out = ["groups:", "  - name: dashboard", "    rules:"]
    for i, (name, e) in enumerate(exprs(dash)):
        out += ["      # %s" % name.encode("ascii", "replace").decode(),
                "      - record: dashboard:q%d" % i,
                "        expr: %s" % json.dumps(fill(e))]
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1])
