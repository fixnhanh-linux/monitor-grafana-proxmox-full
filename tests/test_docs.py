# -*- coding: utf-8 -*-
"""Kiem tra tai lieu: so do tieng Viet khop ban tieng Anh, README 2 ngon ngu tro dung file.
Ban quyen (c) 2026 FIX NHANH. Bao luu moi quyen.

    python3 -m unittest discover -s tests
"""

import os
import re
import sys
import unittest

ROOT = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(ROOT, "docs"))
import make_vi_svg as vi  # noqa: E402


def read(*p):
    with open(os.path.join(ROOT, *p), encoding="utf-8") as f:
        return f.read()


class Docs(unittest.TestCase):
    def test_vi_diagram_up_to_date(self):
        out, miss = vi.translate(read("docs", "so-do-kien-truc.svg"))
        self.assertEqual(miss, [], "update T in docs/make_vi_svg.py")
        self.assertEqual(out, read("docs", "so-do-kien-truc.vi.svg"),
                         "run: python3 docs/make_vi_svg.py")

    def test_readme_links(self):
        en, vn = read("README.md"), read("README.vi.md")
        self.assertIn("docs/so-do-kien-truc.svg", en)
        self.assertIn("docs/so-do-kien-truc.vi.svg", vn)
        self.assertIn("(README.vi.md)", en)
        self.assertIn("(README.md)", vn)
        # cung so muc lon (## ...) -> ban tieng Viet khong bi thieu phan
        h = lambda s: len(re.findall(r"^## ", s, re.M))  # noqa: E731
        self.assertEqual(h(en), h(vn))


if __name__ == "__main__":
    unittest.main()
