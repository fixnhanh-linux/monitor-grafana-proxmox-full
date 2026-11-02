# -*- coding: utf-8 -*-
"""Kiem tra template Zabbix (template-zabbix/*.yaml): uuid, key, trigger, macro, master item.
Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.

    python3 -m unittest discover -s tests
"""

import glob
import os
import re
import unittest

try:
    import yaml
except ImportError:  # may khong co PyYAML -> bo qua (CI ubuntu co san python3-yaml)
    yaml = None

DIR = os.path.join(os.path.dirname(__file__), "..", "template-zabbix")
EXPORTER = os.path.join(os.path.dirname(__file__), "..", "exporter", "pve_ceph_extra_exporter.py")
# Metric cua ceph mgr (module prometheus) ma template dung, exporter phat lai nguyen van
CEPH_MGR = {"ceph_health_status", "ceph_pg_inconsistent", "ceph_osd_up", "ceph_osd_in",
            "ceph_osd_apply_latency_ms", "ceph_osd_stat_bytes_used", "ceph_osd_stat_bytes",
            "ceph_pool_metadata", "ceph_pool_percent_used", "ceph_pool_stored", "ceph_pool_max_avail"}


def walk(t):
    """Moi item / item prototype / discovery rule trong template."""
    for it in t.get("items", []):
        yield it
    for d in t.get("discovery_rules", []):
        yield d
        for it in d.get("item_prototypes", []):
            yield it


def triggers(t):
    for it in walk(t):
        for tr in it.get("triggers", []) + it.get("trigger_prototypes", []):
            yield tr
    for tr in t.get("triggers", []):
        yield tr


@unittest.skipIf(yaml is None, "PyYAML missing")
class ZabbixTemplates(unittest.TestCase):
    def setUp(self):
        self.files = sorted(glob.glob(os.path.join(DIR, "*.yaml")))
        self.assertGreaterEqual(len(self.files), 2)

    def load(self, f):
        with open(f, encoding="utf-8") as fh:
            return yaml.safe_load(fh)["zabbix_export"]

    def test_structure(self):
        uuids = []
        for f in self.files:
            ex = self.load(f)
            self.assertEqual(ex["version"], "6.0", f)
            uuids += [g["uuid"] for g in ex.get("groups", []) if g["name"] != "Templates/Applications"]
            for t in ex["templates"]:
                name = t["template"]
                uuids.append(t["uuid"])
                keys = {it["key"] for it in walk(t)}
                macros = {m["macro"] for m in t.get("macros", [])}
                vmaps = {v["name"] for v in t.get("valuemaps", [])}
                uuids += [v["uuid"] for v in t.get("valuemaps", [])]
                for it in walk(t):
                    uuids.append(it["uuid"])
                    if it.get("type") == "DEPENDENT":
                        self.assertIn(it["master_item"]["key"], keys, it["key"])
                    if "valuemap" in it:
                        self.assertIn(it["valuemap"]["name"], vmaps, it["key"])
                    for m in re.findall(r"\{\$[A-Z0-9_.]+\}", str(it)):
                        self.assertIn(m, macros, it["key"])
                    for p in it.get("preprocessing", []):
                        if p["type"] == "PROMETHEUS_PATTERN":
                            self.assertEqual(len(p["parameters"]), 3, it["key"])
                for tr in triggers(t):
                    uuids.append(tr["uuid"])
                    refs = re.findall(r"\(/([^/]+)/([^,)]+(?:\[[^\]]*\])?)", tr["expression"])
                    self.assertTrue(refs, tr["name"])
                    for tpl, key in refs:
                        self.assertEqual(tpl, name, tr["name"])
                        self.assertIn(key, keys, tr["name"])
                    for m in re.findall(r"\{\$[A-Z0-9_.]+\}", tr["expression"] + tr["name"]):
                        self.assertIn(m, macros, tr["name"])
        for u in uuids:
            self.assertRegex(u, r"^[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$")  # Zabbix doi UUIDv4
        self.assertEqual(len(uuids), len(set(uuids)), "duplicate uuid")

    def test_metrics_exist(self):
        # Moi metric template doc phai do exporter phat ra (hoac ceph mgr phat lai)
        with open(EXPORTER, encoding="utf-8") as fh:
            src = fh.read()
        ex = self.load(os.path.join(DIR, "pve-ceph-exporter-by-http.yaml"))
        for it in walk(ex["templates"][0]):
            for p in it.get("preprocessing", []):
                if p["type"] in ("PROMETHEUS_PATTERN", "PROMETHEUS_TO_JSON"):
                    m = re.match(r"[a-z_]+", p["parameters"][0]).group(0)
                    self.assertTrue(m in CEPH_MGR or m in src, "%s: %s not exported" % (it["key"], m))


if __name__ == "__main__":
    unittest.main()
