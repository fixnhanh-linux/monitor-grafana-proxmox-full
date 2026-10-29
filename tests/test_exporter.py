# -*- coding: utf-8 -*-
"""Kiem tra phan xu ly du lieu cua pve_ceph_extra_exporter (khong can Ceph / Proxmox that).
Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.

    python3 -m unittest discover -s tests
"""

import os
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "exporter"))
import pve_ceph_extra_exporter as ex  # noqa: E402


def pgmap(**kw):
    base = {"num_pgs": 128, "pgs_by_state": [{"state_name": "active+clean", "count": 128}]}
    base.update(kw)
    return base


class CephStatus(unittest.TestCase):
    def test_ok(self):
        r = ex.parse_ceph_status({"health": {"status": "HEALTH_OK"}, "pgmap": pgmap()})
        self.assertEqual((r["state"], r["code"], r["percent"]), ("ok", 0, 100.0))

    def test_recovery(self):
        r = ex.parse_ceph_status({"health": {"status": "HEALTH_WARN"}, "pgmap": pgmap(
            degraded_objects=25, degraded_total=100, recovering_bytes_per_sec=2 * 1024 ** 2)})
        self.assertEqual((r["state"], r["code"]), ("recovering", 1))
        self.assertAlmostEqual(r["percent"], 75.0)
        self.assertIn("2.0 MiB/s", r["content"])

    def test_unfound_is_error(self):
        r = ex.parse_ceph_status({"health": {"status": "HEALTH_ERR"}, "pgmap": pgmap(
            unfound_objects=3, degraded_total=10)})
        self.assertEqual(r["code"], 2)

    def test_metrics_escape(self):
        r = ex.parse_ceph_status({"health": {"status": "HEALTH_OK"}, "pgmap": pgmap()})
        r["progress"] = {'Rebalancing "pool"': 50.0}
        text = "\n".join(ex.ceph_metrics(r))
        self.assertIn('event="Rebalancing \\"pool\\""', text)


class HaCfg(unittest.TestCase):
    def test_groups_and_rules(self):
        groups = "group: Gold\n\tnodes pve1:2,pve2\n\trestricted 1\n\ngroup: Silver\n\tnodes pve2\n"
        rules = "node-affinity: ha-rule-1\n\tnodes pve3\n\tresources vm:100\n"
        self.assertEqual(ex.parse_ha_cfg(groups, ("group",)), {"Gold": ["pve1", "pve2"], "Silver": ["pve2"]})
        self.assertEqual(ex.parse_ha_cfg(rules, ("node-affinity",)), {"ha-rule-1": ["pve3"]})


class PveMetrics(unittest.TestCase):
    def test_cluster_and_nodes(self):
        status = [{"type": "cluster", "name": "proxmox-1", "nodes": 2, "quorate": 1, "version": 4}]
        res = [{"type": "node", "id": "node/pve1", "status": "online", "cpu": 0.25, "maxcpu": 8,
                "mem": 1, "maxmem": 2, "uptime": 10},
               {"type": "node", "id": "node/pve2", "status": "offline"}]
        ha = {"manager_status": {"node_status": {"pve1": "online"}}}
        text = "\n".join(ex.pve_metrics(status, res, ha))
        self.assertIn('pve_cluster_info{id="cluster/proxmox-1",nodes="2",quorate="1",version="4"} 1', text)
        self.assertIn('pve_up{id="node/pve2"} 0', text)
        self.assertIn('pve_cpu_usage_ratio{id="node/pve1"} 0.25', text)
        self.assertIn('pve_ha_state{id="node/pve1",state="online"} 1', text)


class MgrFailover(unittest.TestCase):
    """Mgr standby tra /metrics rong -> phai bo qua, lay o mgr active."""

    def serve(self, body):
        class H(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *a):
                pass
        srv = HTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.addCleanup(srv.server_close)
        self.addCleanup(srv.shutdown)  # chay truoc server_close (LIFO)
        return "127.0.0.1:%d" % srv.server_port

    def test_skip_standby(self):
        standby, active = self.serve(b""), self.serve(b"ceph_health_status 0\n")
        lines, idx = ex.remote_mgr_metrics([standby, active], 3)
        self.assertEqual((lines, idx), (["ceph_health_status 0"], 1))

    def test_all_standby_names_host(self):
        standby = self.serve(b"")
        with self.assertRaises(RuntimeError) as cm:
            ex.remote_mgr_metrics([standby], 3)
        self.assertIn(standby, str(cm.exception))


class Health(unittest.TestCase):
    def test_stale(self):
        args = type("A", (), {"remote": False, "interval": 30})()
        c = ex.Collector(args)
        self.assertIsNone(c.age())
        c.last_ts = ex.time.time() - 10
        self.assertLess(c.age(), 60)


if __name__ == "__main__":
    unittest.main()
