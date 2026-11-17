#!/usr/bin/env python3
"""Check a Markdown draft against the checkable rules of the WordPress Documentation Style Guide.

Usage:
  check-draft.py DRAFT [DRAFT...] [--kind helphub|handbook|devhub]
  check-draft.py --list-rules

FAIL is a stated rule with a mechanical test. WARN needs a human look: the test
is a heuristic, or the sources disagree (see references/style-rules.md).
Exit status is the number of FAIL findings, capped at 125, so 0 means no FAILs, not "correct".
It cannot judge voice, accuracy, structure or screenshots; a person still reads the draft.
The first H1, on the first non-blank line, is read as the page title.
"""
import argparse
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

RULES = {
    "h1-extra": ("FAIL", "Only the title line is an H1; article sections start at H2"),
    "heading-skip": ("FAIL", "Heading levels go in order, with no skipped level"),
    "heading-empty": ("FAIL", "A heading has content before the next heading of the same or higher level"),
    "heading-period": ("FAIL", "A heading has no ending period"),
    "heading-link": ("FAIL", "No links inside headings"),
    "heading-case": ("WARN", "Headings use sentence case"),
    "heading-symbol": ("WARN", "No ampersands in headings"),
    "intro-missing": ("WARN", "The article opens with an introductory paragraph, not a heading"),
    "changelog-missing": ("WARN", "A HelpHub or handbook article ends with a Changelog section"),
    "long-paragraph": ("WARN", "Short paragraphs: one main point each (over 120 words)"),
    "single-item-list": ("WARN", "A list has at least two items"),
    "excl": ("FAIL", "No exclamation points in prose"),
    "latin-abbrev": ("FAIL", "No e.g., i.e., etc., et al. or aka"),
    "and-or": ("FAIL", "No and/or"),
    "noninclusive": ("FAIL", "Use blocklist/allowlist and primary/secondary, not the older terms"),
    "master-term": ("WARN", "Check 'master': use main, primary or a specific term"),
    "menu-arrow": ("WARN", "Write menu paths as Pages > Add New (an arrow in a non-menu example is fine)"),
    "link-text": ("FAIL", "Link text names the destination, not 'here' or 'this page'"),
    "link-url-text": ("FAIL", "A raw URL is not link text"),
    "external-link": ("WARN", "External links need the allow-list and no new ones are added right now"),
    "alt-missing": ("FAIL", "Every image has alt text (empty only if decorative)"),
    "alt-prefix": ("FAIL", "Alt text does not start with 'Image of', 'Photo of' or 'Picture of'"),
    "alt-screenshot": ("WARN", "Alt text does not start with 'Screenshot of'; say what it shows"),
    "alt-long": ("FAIL", "Alt text is 155 characters or fewer"),
    "alt-over-50": ("WARN", "The Accessibility page caps alt text at 50 characters; keep it short"),
    "image-host": ("FAIL", "Images are uploaded to the page's own media library, never hotlinked"),
    "image-name": ("WARN", "Image filenames are lowercase ASCII words joined by hyphens"),
    "image-format": ("WARN", "Use PNG (or SVG for diagrams); video, not an autoplaying GIF"),
    "we-voice": ("WARN", "Address the reader as 'you'; no we, us, our or let's"),
    "i-voice": ("WARN", "No first-person 'I' narration"),
    "please": ("WARN", "'Please' only where the reader must do something inconvenient"),
    "must-click": ("WARN", "Steps are bare imperatives: 'Click Publish.'"),
    "click-on": ("WARN", "Write 'Click Publish', not 'click on' or 'click the Publish button'"),
    "future-will": ("WARN", "Present tense; 'will' only when needed"),
    "filler-words": ("WARN", "Avoid simple, simply, easy, easily, just, very and latest"),
    "allows-you": ("WARN", "Use 'lets you', not 'allows you to'"),
    "avoid-words": ("WARN", "Word-list words: abort, leverage, legacy, launch, native, navigate to"),
    "brit-spelling": ("WARN", "American English spelling"),
    "gendered-pronoun": ("WARN", "No he, she, his or her for people in general; use you or singular they"),
    "directional": ("WARN", "No above, below, left or right to locate things; name the element"),
    "ordinal-date": ("WARN", "Dates read 'August 16, 2020': no ordinals"),
    "numeric-date": ("WARN", "Avoid all-numeric dates; use ISO 8601 if unavoidable"),
    "term-forms": ("WARN", "Fixed forms: website, webpage, email, multisite, permalink, WordPress"),
}

KNOWN_PHRASES = [
    "Media Library", "Site Editor", "Block Editor", "Classic Editor", "Block Directory",
    "Application Passwords", "Twenty Twenty-Five", "Twenty Twenty-Four", "Twenty Twenty-Three",
    "Site Health", "Screen Options", "Command Palette", "Query Loop", "Page List",
]
KNOWN_WORDS = {
    "WordPress", "Gutenberg", "HelpHub", "DevHub", "GitHub", "Playground", "JavaScript", "PHP",
    "CSS", "HTML", "MySQL", "WooCommerce", "BuddyPress", "bbPress", "Ajax", "Markdown", "Linux",
    "Windows", "Mac", "macOS", "Chrome", "Firefox", "Safari", "Edge", "Google", "Gravatar",
    "Ipsum", "Trac", "Slack", "InstaWP", "Awesome", "Screenshot",
}
HOTLINK_OK = ("wordpress.org", "w.org")
EXTERNAL_OK = ("wordpress.org",)
GENERIC_LINK = {"here", "click here", "this link", "this page", "this document", "link", "read more", "more", "learn more", "this article"}
MONTHS = "January|February|March|April|May|June|July|August|September|October|November|December"
LIST_RE = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+")
HEAD_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
LINK_RE = re.compile(r'(?<!!)\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
IMG_RE = re.compile(r'!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
HTML_IMG_RE = re.compile(r"<img\b[^>]*>", re.I)


def host_ok(url, allowed):
    host = (urlparse(url).hostname or "").lower()
    return any(host == a or host.endswith("." + a) for a in allowed)


def strip_code(line):
    line = re.sub(r"`[^`]*`", " ", line)
    line = re.sub(r"\]\([^)]*\)", "]", line)
    return re.sub(r"https?://\S+", " ", line)


def sentence_case_extra(text):
    text = re.sub(r"`[^`]*`", "", text)
    for phrase in KNOWN_PHRASES:
        text = text.replace(phrase, "")
    caps = []
    for seg in text.split(":"):
        words = re.findall(r"[A-Za-z][A-Za-z'’-]*", seg)[1:]
        caps += [w for w in words if w[0].isupper() and not (w.isupper() and len(w) <= 6) and w not in KNOWN_WORDS]
    return caps


PROSE_RULES = [
    ("we-voice", re.compile(r"\b(we|We|our|Our|ours|us|let's|Let's|let’s)\b")),
    ("i-voice", re.compile(r"\bI\b(?!\.)")),
    ("please", re.compile(r"\bplease\b", re.I)),
    ("must-click", re.compile(r"\byou (must|need to|have to) (click|select|choose|enter|type|press)\b", re.I)),
    ("click-on", re.compile(r"\bclick on\b|\bclick the [A-Z][\w ]*? button\b", re.I)),
    ("future-will", re.compile(r"\bwill\b", re.I)),
    ("filler-words", re.compile(r"\b(simple|simply|easy|easily|just|very|latest)\b", re.I)),
    ("allows-you", re.compile(r"\ballows? you to\b", re.I)),
    ("avoid-words", re.compile(r"\b(abort|leverage|legacy|launch|native|navigate to)\b", re.I)),
    ("brit-spelling", re.compile(r"\b(colour\w*|behaviour\w*|favourite\w*|organis\w+|customis\w+|centre\w*|grey|licence|analyse\w*|catalogue\w*|cancelled|labelled|optimis\w+|recognis\w+)\b", re.I)),
    ("gendered-pronoun", re.compile(r"\b(he|she|his|hers|her|him)\b", re.I)),
    ("directional", re.compile(r"\b(above|below)\b|\b(left|right)[- ]hand\b|\bon the (left|right)\b|\b(upper|lower|top|bottom)[- ](left|right)\b", re.I)),
    ("ordinal-date", re.compile(r"\b(" + MONTHS + r")\s+\d{1,2}(st|nd|rd|th)\b")),
    ("numeric-date", re.compile(r"\b\d{1,2}/\d{1,2}/\d{2,4}\b")),
    ("term-forms", re.compile(r"\b(log-in|e-mail|web site|web page|multi-site|perma-link|login to|Wordpress|wordpress)\b")),
    ("latin-abbrev", re.compile(r"(?<!\w)(e\.g\.|i\.e\.|etc\.?|et al\.?|a\.k\.a\.|aka)(?!\w)", re.I)),
    ("and-or", re.compile(r"\band/or\b", re.I)),
    ("noninclusive", re.compile(r"\b(blacklist\w*|whitelist\w*|slave\w*|master/slave)\b", re.I)),
    ("master-term", re.compile(r"\bmaster\b", re.I)),
    ("menu-arrow", re.compile(r"[A-Za-z]\s*(->|→|»)\s*[A-Za-z]")),
    ("excl", re.compile(r"(?<!\[)!(?=\s|$)")),
]


def analyze(text, kind):
    out = []

    def add(n, slug, msg=None):
        out.append((n, slug, msg or RULES[slug][1]))

    lines = text.splitlines()
    in_code = False
    heads = []
    para, para_start = [], 0
    items = []
    seen_title = False
    first_block = None
    list_group = 0
    in_list = False
    in_changelog = False

    def flush_para():
        nonlocal para
        if para and len(" ".join(para).split()) > 120:
            add(para_start, "long-paragraph")
        para = []

    for n, raw in enumerate(lines, 1):
        if raw.strip().startswith("```"):
            in_code = not in_code
            flush_para()
            continue
        if in_code:
            continue
        line = raw.rstrip()
        if not line.strip():
            flush_para()
            continue
        h = HEAD_RE.match(line)
        li = LIST_RE.match(line)
        if h:
            flush_para()
            level, title = len(h.group(1)), h.group(2)
            if level == 1 and first_block is None and not seen_title:
                seen_title = True
                continue
            first_block = first_block or "heading"
            heads.append((n, level, title))
            if in_list and list_group == 1 and not in_changelog:
                add(items[-1], "single-item-list")
            in_changelog = bool(re.match(r"change ?log", title, re.I))
            in_list, list_group = False, 0
            continue
        first_block = first_block or "other"
        if li and len(li.group(1)) == 0:
            if in_list:
                list_group += 1
            else:
                in_list, list_group = True, 1
            items.append(n)
        elif in_list and raw.startswith((" ", "\t")):
            pass
        else:
            if in_list and list_group == 1 and not in_changelog:
                add(items[-1], "single-item-list")
            in_list, list_group = False, 0
            if not li and not raw.startswith(("    ", "\t", "|", ">")):
                if not para:
                    para_start = n
                para.append(line)
        for m in LINK_RE.finditer(line):
            text_, url = m.group(1).strip(), m.group(2)
            if text_.lower().strip(" .") in GENERIC_LINK:
                add(n, "link-text", f"link text '{text_}' does not name the destination")
            if re.match(r"https?://", text_):
                add(n, "link-url-text", "a raw URL is link text")
            if url.startswith("http") and not host_ok(url, EXTERNAL_OK):
                add(n, "external-link", f"external link to {urlparse(url).hostname}")
        for m in IMG_RE.finditer(line):
            check_image(n, m.group(1), m.group(2), add)
        for m in HTML_IMG_RE.finditer(line):
            alt = re.search(r'alt\s*=\s*"([^"]*)"', m.group(0))
            src = re.search(r'src\s*=\s*"([^"]*)"', m.group(0))
            check_image(n, alt.group(1) if alt else None, src.group(1) if src else "", add)
        prose = strip_code(line)
        for slug, rx in PROSE_RULES:
            if rx.search(prose):
                m = rx.search(prose)
                add(n, slug, f"{RULES[slug][1]} (found '{m.group(0).strip()}')")
    flush_para()

    if in_list and list_group == 1 and not in_changelog:
        add(items[-1], "single-item-list")

    prev_level = 1 if seen_title else 0
    for i, (n, level, title) in enumerate(heads):
        if level == 1:
            add(n, "h1-extra")
        if prev_level and level > prev_level + 1:
            add(n, "heading-skip", f"H{prev_level} jumps to H{level}")
        prev_level = level
        if title.rstrip().endswith("."):
            add(n, "heading-period")
        if any(not m.group(2).startswith("#") for m in LINK_RE.finditer(title)):
            add(n, "heading-link", "no links in headings (same-page anchors are ignored: HelpHub adds them to every heading)")
        if "&" in title:
            add(n, "heading-symbol")
        caps = sentence_case_extra(LINK_RE.sub(r"\1", title))
        if len(caps) >= 2:
            add(n, "heading-case", f"not sentence case: {', '.join(caps[:3])}")
        nxt = heads[i + 1] if i + 1 < len(heads) else None
        end = nxt[0] if nxt else len(lines) + 1
        body = [l for l in lines[n:end - 1] if l.strip()]
        if not body and (not nxt or nxt[1] <= level):
            add(n, "heading-empty")
    if first_block == "heading" and heads:
        add(heads[0][0], "intro-missing")
    if kind in ("helphub", "handbook"):
        if not any(re.match(r"change ?log", t, re.I) for _, _, t in heads):
            add(len(lines) or 1, "changelog-missing")
    return sorted(out)


def check_image(n, alt, src, add):
    if alt is None or not alt.strip():
        add(n, "alt-missing", f"image {Path(src).name or src} has no alt text")
    else:
        a = alt.strip()
        if re.match(r"(image|photo|picture) of\b", a, re.I):
            add(n, "alt-prefix")
        elif re.match(r"screenshot of\b", a, re.I):
            add(n, "alt-screenshot")
        if len(a) > 155:
            add(n, "alt-long", f"alt text is {len(a)} characters")
        elif len(a) > 50:
            add(n, "alt-over-50", f"alt text is {len(a)} characters")
    if re.match(r"https?://", src):
        if not host_ok(src, HOTLINK_OK):
            add(n, "image-host", f"image hosted on {urlparse(src).hostname}")
    name = Path(urlparse(src).path).name
    if name:
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*\.[a-z0-9]+", name):
            add(n, "image-name", f"filename '{name}' is not lowercase words joined by hyphens")
        ext = name.rsplit(".", 1)[-1].lower()
        if ext in ("gif", "jpg", "jpeg", "webp", "bmp"):
            add(n, "image-format", f".{ext} image '{name}'")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--kind", choices=["helphub", "handbook", "devhub"], default="helphub")
    ap.add_argument("--list-rules", action="store_true")
    args = ap.parse_args()
    if args.list_rules:
        for slug, (sev, desc) in RULES.items():
            print(f"{sev} {slug}: {desc}")
        return 0
    if not args.files:
        ap.error("give at least one draft file")
    fails = warns = 0
    for f in args.files:
        for n, slug, msg in analyze(Path(f).read_text(encoding="utf-8"), args.kind):
            sev = RULES[slug][0]
            fails += sev == "FAIL"
            warns += sev == "WARN"
            print(f"{sev} {f}:{n} [{slug}] {msg}")
    print(f"--- {fails} FAIL, {warns} WARN ---")
    return min(fails, 125)


if __name__ == "__main__":
    sys.exit(main())
