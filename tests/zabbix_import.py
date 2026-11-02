# -*- coding: utf-8 -*-
"""CI: import template-zabbix/*.yaml vao Zabbix that (docker) qua API, roi gan vao 1 host
-> bat loi ma test tinh khong thay (cu phap trigger, preprocessing, formula ...).
Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.

    python3 tests/zabbix_import.py http://127.0.0.1:8080 template-zabbix/*.yaml
"""

import json
import sys
import time
import urllib.request


class Api:
    def __init__(self, url):
        self.url = url.rstrip("/") + "/api_jsonrpc.php"
        self.auth = None

    def call(self, method, params):
        body = {"jsonrpc": "2.0", "method": method, "params": params, "id": 1}
        if self.auth and method not in ("apiinfo.version", "user.login"):
            body["auth"] = self.auth  # 6.0 chi nhan "auth" trong body; 7.0 van nhan (toi 7.2)
        req = urllib.request.Request(self.url, json.dumps(body).encode(),
                                     {"Content-Type": "application/json-rpc"})
        with urllib.request.urlopen(req, timeout=30) as r:
            res = json.load(r)
        if "error" in res:
            raise RuntimeError("%s: %s" % (method, res["error"].get("data") or res["error"]))
        return res["result"]


def main(url, files):
    api = Api(url)
    deadline = time.time() + 600
    while True:  # doi web + DB schema (zabbix-server tao schema luc khoi dong)
        try:
            ver = api.call("apiinfo.version", {})
            api.auth = api.call("user.login", {"username": "Admin", "password": "zabbix"})
            break
        except Exception as e:  # noqa: BLE001
            if time.time() > deadline:
                print("::error::Zabbix API not ready: %s" % e)
                sys.exit(1)
            time.sleep(5)
    print("Zabbix %s" % ver)
    major = tuple(int(x) for x in ver.split(".")[:2])
    grp = "template_groups" if major >= (6, 2) else "groups"
    rule = {"createMissing": True, "updateExisting": True}
    rules = {grp: {"createMissing": True}, "templates": dict(rule), "items": dict(rule, deleteMissing=True),
             "triggers": dict(rule, deleteMissing=True), "discoveryRules": dict(rule, deleteMissing=True),
             "valueMaps": dict(rule, deleteMissing=True), "templateLinkage": {"createMissing": True}}
    names, bad = [], []
    for f in files:
        with open(f, encoding="utf-8") as fh:
            src = fh.read()
        try:
            api.call("configuration.import", {"format": "yaml", "rules": rules, "source": src})
            print("imported %s" % f)
        except RuntimeError as e:
            # ::error:: -> hien o trang tom tat GitHub Actions (khong can dang nhap de xem)
            print("::error file=%s::Zabbix %s import: %s" % (f, ver, e))
            bad.append(f)
    if bad:
        sys.exit("import failed: %s" % " ".join(bad))
    tpls = api.call("template.get", {"output": ["templateid", "host"], "selectItems": "count",
                                      "selectTriggers": "count", "selectDiscoveries": "count"})
    tpls = [t for t in tpls if "FIX NHANH" in t["host"] or "fallback" in t["host"]]
    for t in tpls:
        print("  %s: %s items, %s triggers, %s discovery rules"
              % (t["host"], t["items"], t["triggers"], t["discoveries"]))
        names.append(t["host"])
    if len(tpls) != len(files):
        print("::error::expected %d templates, found %s" % (len(files), names))
        sys.exit(1)
    # Gan vao 1 host: kiem tra item / trigger / LLD prototype tao duoc tren host that
    try:
        link(api, tpls)
    except RuntimeError as e:
        print("::error::Zabbix %s link to host: %s" % (ver, e))
        sys.exit(1)
    print("linked to host ci-proxmox-ceph: OK")


def link(api, tpls):
    gid = api.call("hostgroup.create", {"name": "CI FIX NHANH"})["groupids"][0]
    api.call("host.create", {"host": "ci-proxmox-ceph", "groups": [{"groupid": gid}],
                             "interfaces": [{"type": 1, "main": 1, "useip": 1, "ip": "127.0.0.1",
                                             "dns": "", "port": "10050"}],
                             "templates": [{"templateid": t["templateid"]} for t in tpls]})


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
