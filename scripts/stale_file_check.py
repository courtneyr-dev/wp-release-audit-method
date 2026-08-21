#!/usr/bin/env python3
"""Offline stale-file detector: which deleted files will the Core updater orphan?

WordPress keeps an internal list of files an upgrade should delete
($_old_files in wp-admin/includes/update-core.php). Files removed from the
codebase but never added to that list stay on upgraded sites forever — 243 of
them did in the 7.1 cycle (detector D-05). This predicts that answer from two
extracted trees, before any fixture exists.

  python3 scripts/stale_file_check.py <prior_tree> <target_tree>

Each tree is an extracted release — either the wordpress/ directory itself or a
directory containing one. This is the canonical implementation; fast-triage.sh's
STATIC GATE 2 calls it rather than carrying a second copy that could disagree.

Exit codes:
  0  every deleted file is declared in $_old_files (or nothing was deleted)
  1  deleted-but-undeclared files found — these orphan on upgrade
  2  setup error (tree missing, update-core.php unreadable)

Calibration (run.sh in examples/chains/C-02 does this before trusting a verdict):
positive control 7.0.2 -> 7.1-beta4 must exit 1; negative control, a tree against
itself, must exit 0.
"""

import re
import sys
from collections import Counter
from pathlib import Path


def wp_root(path):
    p = Path(path)
    if (p / "wordpress").is_dir():
        p = p / "wordpress"
    if not (p / "wp-includes").is_dir():
        sys.exit(f"ERROR: {path} does not look like an extracted WordPress tree")
    return p


def core_files(root):
    """Same file population C-02 compares: wp-admin, wp-includes, root *.php."""
    out = set()
    for sub in ("wp-admin", "wp-includes"):
        base = root / sub
        if base.is_dir():
            out |= {str(f.relative_to(root)) for f in base.rglob("*") if f.is_file()}
    out |= {f.name for f in root.glob("*.php")}
    return out


def old_files_list(root):
    src = root / "wp-admin" / "includes" / "update-core.php"
    try:
        text = src.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        sys.exit(f"ERROR: cannot read {src}: {e}")
    m = re.search(r"\$_old_files\s*=\s*array\((.*?)\n\);", text, re.S)
    return set(re.findall(r"'([^']+)'", m.group(1))) if m else set()


def declared(path, listed):
    return path in listed or any(
        path.startswith(entry.rstrip("/") + "/") for entry in listed
    )


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[0]
                 + "\nusage: stale_file_check.py <prior_tree> <target_tree>")
    prior = wp_root(sys.argv[1])
    target = wp_root(sys.argv[2])

    deleted = sorted(core_files(prior) - core_files(target))
    listed = old_files_list(target)
    missing = [d for d in deleted if not declared(d, listed)]

    print(f"deleted since prior: {len(deleted)}   listed in $_old_files: {len(listed)}")
    if not deleted:
        print("no files deleted between these trees")
        return 0
    if missing:
        print(f"*** FAIL — {len(missing)} deleted files NOT in $_old_files (orphaned on upgrade):")
        for prefix, n in Counter(
            "/".join(p.split("/")[:3]) for p in missing
        ).most_common(10):
            print(f"    {n:5}  {prefix}/")
        return 1
    print("PASS — every deleted file is accounted for")
    return 0


if __name__ == "__main__":
    sys.exit(main())
