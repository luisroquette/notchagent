#!/usr/bin/env python3
# REGRESSÃO (22/08): this used to validate a full standalone site (H1,
# recorder tabs, panel) that docs/index.html hasn't been since "docs: GitHub
# Pages vira redirect para notchagent.app" (20/08) turned it into a plain
# redirect stub to the real product site — the script was never updated to
# match, so CI has been red on every push since (found during a full audit,
# unrelated to the day's Codex fixes).
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
CANONICAL_URL = "https://notchagent.app/"


class RedirectStubParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.meta_refresh_target = None
        self.canonical_href = None
        self.refs = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "meta" and values.get("http-equiv", "").lower() == "refresh":
            content = values.get("content", "")
            if ";" in content:
                self.meta_refresh_target = content.split(";", 1)[1].strip().removeprefix("url=")
        if tag == "link" and values.get("rel") == "canonical":
            self.canonical_href = values.get("href")
        for key in ("href", "src"):
            value = values.get(key, "")
            if value and not value.startswith(("#", "http://", "https://", "data:", "mailto:")):
                self.refs.append(value.split("?", 1)[0])


parser = RedirectStubParser()
parser.feed((DOCS / "index.html").read_text())
assert parser.meta_refresh_target == CANONICAL_URL, \
    f"Expected meta-refresh to {CANONICAL_URL}, found {parser.meta_refresh_target!r}"
assert parser.canonical_href == CANONICAL_URL, \
    f"Expected canonical link to {CANONICAL_URL}, found {parser.canonical_href!r}"
missing = [ref for ref in parser.refs if not (DOCS / ref).exists()]
assert not missing, f"Missing local references: {missing}"
print(f"Site validation passed: redirect stub points to {CANONICAL_URL}, no missing assets")
