# -*- coding: utf-8 -*-
"""Kiem tra make_dashboard.py: ban noi bo va ban khach hang (khoa job, an phan noi bo).
Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.

    python3 -m unittest discover -s tests
"""

import os
import sys
import unittest
from types import SimpleNamespace

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import make_dashboard as md  # noqa: E402


def args(**kw):
    a = dict(title="T", uid="u", site_regex="", job_regex="/.*Proxmox-/", nodes=8, pools=8,
             classes=3, lat_th="nvme=15:25,default=100:200", ha_alias=[], time_from="now-15m",
             customer_job="")
    a.update(kw)
    return SimpleNamespace(**a)


def titles(d):
    return [p["title"] for p in d["panels"]]


class Dashboard(unittest.TestCase):
    def test_internal(self):
        d = md.build(args())
        self.assertTrue(d["editable"])
        self.assertIn("Detailed Alarms", titles(d))
        self.assertIn("Exporter (pve_ceph_extra_exporter)", titles(d))
        job = [v for v in d["templating"]["list"] if v["name"] == "job"][0]
        self.assertEqual(job["type"], "query")

    def test_customer_locked(self):
        d = md.build(args(customer_job="Proxmox-P1-XD", site_regex="/^Prometheus FPT HCM$/"))
        self.assertFalse(d["editable"])
        self.assertIn("khach-hang", d["tags"])
        for t in ("Detailed Alarms", "Exporter (pve_ceph_extra_exporter)", "Collector"):
            self.assertNotIn(t, titles(d))
        v = {x["name"]: x for x in d["templating"]["list"]}
        self.assertEqual((v["job"]["type"], v["job"]["query"], v["job"]["hide"]), ("constant", "Proxmox-P1-XD", 2))
        self.assertEqual(v["Site"]["hide"], 2)
        res = [p for p in d["panels"] if p["title"] == "Resource Cluster"][0]
        self.assertEqual([t["refId"] for t in res["targets"]], ["CPU", "RAM_Pct", "RAM_Total", "Uptime"])
        # khong panel nao chong nhau
        g = [p["gridPos"] for p in d["panels"] if "repeat" not in p]
        for i, a in enumerate(g):
            for b in g[i + 1:]:
                self.assertFalse(a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"]
                                 and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"])

    def test_safe_uid(self):
        self.assertEqual(md.safe_uid("Proxmox - Ceph Prometheus"), "Proxmox-Ceph-Prometheus")
        self.assertEqual(len(md.safe_uid("x" * 60)), 40)


if __name__ == "__main__":
    unittest.main()
