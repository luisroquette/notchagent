#!/usr/bin/env python3
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"


class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.h1 = 0
        self.ids = []
        self.refs = []
        self.tabs = 0

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "h1":
            self.h1 += 1
        if values.get("id"):
            self.ids.append(values["id"])
        if values.get("role") == "tab":
            self.tabs += 1
        for key in ("href", "src"):
            value = values.get(key, "")
            if value and not value.startswith(("#", "http://", "https://", "data:", "mailto:")):
                self.refs.append(value.split("?", 1)[0])


parser = SiteParser()
parser.feed((DOCS / "index.html").read_text())
assert parser.h1 == 1, f"Expected one H1, found {parser.h1}"
assert len(parser.ids) == len(set(parser.ids)), "Duplicate IDs found"
assert parser.tabs == 3, f"Expected three recorder tabs, found {parser.tabs}"
assert "recorder-panel" in parser.ids, "Recorder panel is missing"
missing = [ref for ref in parser.refs if not (DOCS / ref).exists()]
assert not missing, f"Missing local references: {missing}"
print(f"Site validation passed: one H1, {len(parser.ids)} unique IDs, three recorder tabs, no missing assets")
