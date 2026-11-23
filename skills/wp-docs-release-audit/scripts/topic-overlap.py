#!/usr/bin/env python3
"""Count how often each topic appears in an issue's body, its comments and any extra files.

Usage: topic-overlap.py BODY.md COMMENTS.md TOPICS.tsv [EXTRA.md ...]
  TOPICS.tsv   one topic per line: label<TAB>regex (case-insensitive)
  EXTRA.md     more text to search, for example the issues the team created, saved with one
               "### #N [state] title" header each so a hit names its issue

Per topic it prints a status, a hit count per file and the first matching line:
  item       in the issue body: already a checklist item
  discussed  only in the comments
  elsewhere  only in an extra file (the line starts with the issue number)
  NOT THERE  nowhere
Run it before writing, and again just before pasting, because the issue keeps changing.
Use exact names (a filter, a constant, a ticket number), not headings: a loose pattern
matches unrelated lines, so read the printed line.
"""
import pathlib
import re
import sys


def hits(text, rx):
    out, head = [], ""
    for line in text.splitlines():
        if line.startswith("### #"):
            head = line.split(" ", 2)[1] + " "
        if rx.search(line):
            out.append(head + line.strip())
    return out


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    paths = sys.argv[1:3] + sys.argv[4:]
    names = ["body", "comments"] + [pathlib.Path(p).stem for p in sys.argv[4:]]
    texts = [pathlib.Path(p).read_text(encoding="utf-8") for p in paths]
    for raw in pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.startswith("#"):
            continue
        label, _, pattern = raw.partition("\t")
        rx = re.compile(pattern.strip(), re.I)
        per = [hits(t, rx) for t in texts]
        counts = " ".join(f"{n}={len(h)}" for n, h in zip(names, per))
        first = next((h[0] for h in per if h), "")[:80]
        status = ("NOT THERE" if not any(per) else "item" if per[0]
                  else "discussed" if per[1] else "elsewhere")
        print(f"{status:9} {counts:<38} {label:<26} {first}")


if __name__ == "__main__":
    main()
