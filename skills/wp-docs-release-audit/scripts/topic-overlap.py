#!/usr/bin/env python3
"""Count how often each topic appears in an issue's body and in its comments.

Usage: topic-overlap.py BODY.md COMMENTS.md TOPICS.tsv
  TOPICS.tsv   one topic per line: label<TAB>regex (case-insensitive)

Per topic it prints body hits, comment hits and the first matching line, so
you can tell "already an item" (body) from "already discussed" (comments) from
"not there" (0 and 0). Run it before writing, and again just before pasting,
because the issue keeps changing.
"""
import pathlib
import re
import sys


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    body, comments, topics = (pathlib.Path(a).read_text(encoding="utf-8") for a in sys.argv[1:])
    for raw in topics.splitlines():
        if not raw.strip() or raw.startswith("#"):
            continue
        label, _, pattern = raw.partition("\t")
        rx = re.compile(pattern.strip(), re.I)
        hits = [("body", l) for l in body.splitlines() if rx.search(l)]
        hits += [("comments", l) for l in comments.splitlines() if rx.search(l)]
        nb = sum(1 for w, _ in hits if w == "body")
        nc = len(hits) - nb
        first = hits[0][1].strip()[:90] if hits else ""
        status = "NOT THERE" if not hits else ("item" if nb else "discussed")
        print(f"{status:9} body={nb:<2} comments={nc:<2} {label:<28} {first}")


if __name__ == "__main__":
    main()
