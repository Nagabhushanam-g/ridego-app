#!/usr/bin/env python3
"""Offline checks for RideGo's static development-preview website.

Run: python3 website/check_site.py
No external dependencies or network calls.
"""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
PAGES = sorted(ROOT.glob("*.html"))
ERRORS = []


class PageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.links = []
        self.images = []
        self.has_title = False
        self.has_viewport = False
        self.has_main = False
        self.has_h1 = False
        self.has_lang = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if a.get("id"):
            self.ids.add(a["id"])
        if tag == "html" and a.get("lang"):
            self.has_lang = True
        if tag == "title":
            self.has_title = True
        if tag == "meta" and a.get("name") == "viewport":
            self.has_viewport = True
        if tag == "main":
            self.has_main = True
        if tag == "h1":
            self.has_h1 = True
        if tag == "a" and "href" in a:
            self.links.append(a["href"])
        if tag == "link" and a.get("href"):
            self.links.append(a["href"])
        if tag == "script" and a.get("src"):
            self.links.append(a["src"])
        if tag == "img":
            self.images.append(a)


parsed = {}
for page in PAGES:
    parser = PageParser()
    parser.feed(page.read_text(encoding="utf-8"))
    parsed[page.name] = parser
    for label, ok in [
        ("html lang", parser.has_lang),
        ("title", parser.has_title),
        ("viewport meta", parser.has_viewport),
        ("main landmark", parser.has_main),
        ("h1 heading", parser.has_h1),
    ]:
        if not ok:
            ERRORS.append(f"{page.name}: missing {label}")
    for image in parser.images:
        if "alt" not in image:
            ERRORS.append(f"{page.name}: image missing alt: {image.get('src', '?')}")
        elif not image.get("src"):
            ERRORS.append(f"{page.name}: image missing src")
        else:
            parser.links.append(image["src"])

for page in PAGES:
    parser = parsed[page.name]
    for href in parser.links:
        url = urlsplit(href)
        if url.scheme or url.netloc or href.startswith(("mailto:", "tel:", "javascript:")):
            continue
        target_name = url.path or page.name
        target = (page.parent / target_name).resolve()
        if not target.is_relative_to(ROOT.resolve()) or not target.is_file():
            ERRORS.append(f"{page.name}: broken local link {href}")
            continue
        if url.fragment and target.suffix == ".html":
            destination = parsed.get(target.name)
            if destination is None:
                destination = PageParser()
                destination.feed(target.read_text(encoding="utf-8"))
            if url.fragment not in destination.ids:
                ERRORS.append(f"{page.name}: missing anchor {href}")

if not PAGES:
    ERRORS.append("No HTML pages found")
if ERRORS:
    print("Website checks FAILED:")
    for error in ERRORS:
        print(" -", error)
    raise SystemExit(1)
print(f"Website checks PASSED: {len(PAGES)} HTML pages; local assets, links, anchors and basic accessibility checked.")
