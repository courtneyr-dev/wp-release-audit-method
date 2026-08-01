#!/usr/bin/env python3
"""Self-test for this repository.

A repository about testing that isn't tested is an easy thing to dismiss. This
runs the checks that were previously done by hand, and is what CI runs.

  python3 scripts/check-repo.py           # all checks
  python3 scripts/check-repo.py --quick   # skip the slow external ones

Exit code is the number of failing checks.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUICK = "--quick" in sys.argv
FAILURES = []
SKIPPED = []


def report(name, problems, detail_limit=12):
    if problems:
        FAILURES.append(name)
        print(f"FAIL  {name} ({len(problems)})")
        for p in problems[:detail_limit]:
            print(f"        {p}")
        if len(problems) > detail_limit:
            print(f"        … and {len(problems) - detail_limit} more")
    else:
        print(f"ok    {name}")


def have(cmd):
    return subprocess.run(["which", cmd], capture_output=True).returncode == 0


def md_files():
    return [p for p in ROOT.rglob("*.md") if ".git" not in p.parts]


def slugs(text):
    """GitHub's heading-anchor slugification, near enough for our purposes."""
    out = set()
    for h in re.findall(r"^#+ (.+)$", text, re.M):
        h = re.sub(r"`([^`]*)`", r"\1", h)
        out.add(re.sub(r"[^a-z0-9 -]", "", h.lower()).replace(" ", "-"))
    return out


# ── 1. Internal links and anchors ────────────────────────────────────────────
def check_links():
    bad, count = [], 0
    for p in md_files():
        text = p.read_text(encoding="utf-8")
        rel = p.relative_to(ROOT)
        for m in re.finditer(r"\[([^\]]*)\]\(([^)]*)#([^)]+)\)", text):
            target, anchor = m.group(2), m.group(3)
            count += 1
            if target.startswith(("http", "mailto:", "$")):
                continue
            f = (p.parent / target).resolve() if target else p.resolve()
            if f.is_dir():
                f = f / "README.md"
            if not f.exists():
                bad.append(f"{rel}: missing {target}")
            elif anchor not in slugs(f.read_text(encoding="utf-8")):
                bad.append(f"{rel} -> {target}#{anchor}")
        for m in re.finditer(r"\[([^\]]*)\]\(([^)#][^)]*)\)", text):
            target = m.group(2).split("#")[0]
            count += 1
            if target.startswith(("http", "mailto:", "$")):
                continue
            if not (p.parent / target).resolve().exists():
                bad.append(f"{rel}: {target}")
    report(f"internal links and anchors ({count} checked)", bad)


# ── 2. Code fences ───────────────────────────────────────────────────────────
def check_fences():
    bad = [
        str(p.relative_to(ROOT))
        for p in md_files()
        if p.read_text(encoding="utf-8").count("```") % 2
    ]
    report("balanced code fences", bad)


# ── 3. No personal paths or names ────────────────────────────────────────────
def check_no_personal_data():
    patterns = [
        (r"/Users/[a-z]", "absolute home path"),
        (r"/home/[a-z]+/", "absolute home path"),
        (r"\[\[[^\]]+\]\]", "Obsidian wikilink"),
        (r"gh[pousr]_[A-Za-z0-9]{20,}", "GitHub token"),
        (r"sk-[A-Za-z0-9]{20,}", "API key"),
        (r"AKIA[0-9A-Z]{16}", "AWS key"),
    ]
    bad = []
    self_path = Path(__file__).resolve()
    for p in ROOT.rglob("*"):
        if not p.is_file() or ".git" in p.parts:
            continue
        # This file contains the patterns themselves.
        if p.resolve() == self_path:
            continue
        if p.suffix not in (".md", ".sh", ".py", ".js", ".php", ".yml", ".csv", ".json"):
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for pat, label in patterns:
            for m in re.finditer(pat, text):
                # Bash [[ ]] tests and JS array literals are not wikilinks.
                if label == "Obsidian wikilink" and p.suffix in (".sh", ".js", ".py"):
                    continue
                line = text[: m.start()].count("\n") + 1
                bad.append(f"{p.relative_to(ROOT)}:{line} {label}")
    report("no personal paths, wikilinks, or secrets", bad)


# ── 4. Shell scripts ─────────────────────────────────────────────────────────
def check_shell():
    scripts = sorted((ROOT / "scripts").glob("*.sh")) + sorted(
        ROOT.rglob("plugin-theme-authors/**/*.sh")
    )
    bad = []
    for s in scripts:
        r = subprocess.run(["bash", "-n", str(s)], capture_output=True, text=True)
        if r.returncode:
            bad.append(f"{s.relative_to(ROOT)}: {r.stderr.strip().splitlines()[0]}")
    report(f"shell syntax ({len(scripts)} scripts)", bad)

    if QUICK or not have("shellcheck"):
        SKIPPED.append("shellcheck")
        return
    warn = []
    for s in scripts:
        r = subprocess.run(
            ["shellcheck", "-S", "error", "-f", "gcc", str(s)],
            capture_output=True, text=True,
        )
        if r.returncode:
            warn += [l for l in r.stdout.strip().splitlines() if l][:3]
    report("shellcheck (errors only)", warn)


# ── 5. PHP and JS ────────────────────────────────────────────────────────────
def check_php_js():
    php = list(ROOT.rglob("*.php"))
    if php and have("php"):
        bad = []
        for f in php:
            r = subprocess.run(["php", "-l", str(f)], capture_output=True, text=True)
            if r.returncode:
                bad.append(f"{f.relative_to(ROOT)}: {r.stdout.strip().splitlines()[0]}")
        report(f"PHP syntax ({len(php)} files)", bad)
    else:
        SKIPPED.append("php lint")

    js = [p for p in ROOT.rglob("*.js") if "node_modules" not in p.parts]
    if js and have("node"):
        bad = []
        for f in js:
            r = subprocess.run(["node", "--check", str(f)], capture_output=True, text=True)
            if r.returncode:
                bad.append(f"{f.relative_to(ROOT)}: {r.stderr.strip().splitlines()[0]}")
        report(f"JS syntax ({len(js)} files)", bad)
    else:
        SKIPPED.append("js check")


# ── 6. YAML ──────────────────────────────────────────────────────────────────
def check_yaml():
    try:
        import yaml
    except ImportError:
        SKIPPED.append("yaml (pyyaml not installed)")
        return
    files = [p for p in ROOT.rglob("*.yml") if ".git" not in p.parts]
    bad = []
    for f in files:
        try:
            yaml.safe_load(f.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001 - we want the message
            bad.append(f"{f.relative_to(ROOT)}: {str(e).splitlines()[0]}")
    report(f"YAML parses ({len(files)} files)", bad)


# ── 7. Data files ────────────────────────────────────────────────────────────
def check_data():
    bad = []
    dep = ROOT / "data" / "deprecations.csv"
    if not dep.exists():
        bad.append("data/deprecations.csv missing")
    else:
        lines = dep.read_text(encoding="utf-8").strip().splitlines()
        header = lines[0].split(",")
        expected = ["symbol", "type", "deprecated_in", "replacement", "notes"]
        if header != expected:
            bad.append(f"deprecations.csv header is {header}, expected {expected}")
        for i, line in enumerate(lines[1:], 2):
            if line.count(",") < 4:
                bad.append(f"deprecations.csv:{i} too few columns")
    for csv in ROOT.rglob("examples/**/*.csv"):
        if not csv.read_text(encoding="utf-8").strip():
            bad.append(f"{csv.relative_to(ROOT)} is empty")
    report("data files well-formed", bad)


# ── 8. Mermaid ───────────────────────────────────────────────────────────────
def check_mermaid():
    blocks = []
    for p in md_files():
        for i, b in enumerate(
            re.findall(r"```mermaid\n(.*?)```", p.read_text(encoding="utf-8"), re.S), 1
        ):
            blocks.append((p.relative_to(ROOT), i, b))
    if not blocks:
        report("mermaid diagrams", [])
        return
    if QUICK or not have("npx"):
        SKIPPED.append(f"mermaid render ({len(blocks)} diagrams)")
        print(f"ok    mermaid diagrams found ({len(blocks)}) — render skipped")
        return

    import tempfile

    bad = []
    with tempfile.TemporaryDirectory() as td:
        for path, idx, body in blocks:
            src = Path(td) / f"d{len(bad)}_{idx}.mmd"
            src.write_text(body, encoding="utf-8")
            out = src.with_suffix(".svg")
            r = subprocess.run(
                ["npx", "-y", "@mermaid-js/mermaid-cli@latest", "-i", str(src), "-o", str(out)],
                capture_output=True, text=True,
            )
            if not out.exists():
                bad.append(f"{path} diagram {idx}: {r.stderr.strip().splitlines()[-1] if r.stderr else 'render failed'}")
    report(f"mermaid renders ({len(blocks)} diagrams)", bad)


# ── 9. Scripts are executable and documented ─────────────────────────────────
def check_scripts_meta():
    bad = []
    for s in sorted((ROOT / "scripts").glob("*.sh")):
        text = s.read_text(encoding="utf-8")
        if not text.startswith("#!"):
            bad.append(f"{s.name}: no shebang")
        if not re.search(r"^#\s*\S", text.split("\n", 1)[1] if "\n" in text else "", re.M):
            bad.append(f"{s.name}: no description comment")
    report("scripts have shebang and description", bad)


def main():
    print(f"Checking {ROOT.name}{' (quick)' if QUICK else ''}\n")
    check_links()
    check_fences()
    check_no_personal_data()
    check_shell()
    check_php_js()
    check_yaml()
    check_data()
    check_mermaid()
    check_scripts_meta()

    print()
    if SKIPPED:
        print("skipped: " + ", ".join(SKIPPED))
    if FAILURES:
        print(f"\n{len(FAILURES)} check(s) failed: {', '.join(FAILURES)}")
        return len(FAILURES)
    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
