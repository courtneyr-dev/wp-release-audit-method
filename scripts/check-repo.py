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
def shell_scripts():
    """Every shell script in the repo, vendored trees excluded.

    Recursive and rooted at the repo, not at scripts/: a non-recursive glob
    silently skipped every driver in scripts/env/ while CONTRIBUTING told driver
    authors CI enforced these checks, and a scripts/-only glob still missed
    examples/chains/ and skills/. One helper, because this gap opened in the
    first place by two callers each carrying their own copy of the pattern.
    """
    skip = {".git", "node_modules", "vendor"}
    return sorted(p for p in ROOT.rglob("*.sh") if not skip & set(p.parts))


def check_shell():
    scripts = shell_scripts()
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
    sec = ROOT / "data" / "security-releases.csv"
    if sec.exists():
        lines = sec.read_text(encoding="utf-8").strip().splitlines()
        expected = ["release", "date", "cve", "cvss", "summary", "fixed_in",
                    "diff_prev", "backport_floor", "branches_patched", "source_url"]
        if lines[0].split(",") != expected:
            bad.append(f"security-releases.csv header is {lines[0].split(',')}, expected {expected}")
        for i, line in enumerate(lines[1:], 2):
            if line.count(",") < len(expected) - 1:
                bad.append(f"security-releases.csv:{i} too few columns")
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
        # Render the way GITHUB does, not the way mermaid-cli does by default.
        #
        # This mattered: every diagram in README.md passed this check while GitHub
        # refused all five with "Cannot read properties of undefined (reading
        # 'render')". mermaid-cli defaults to htmlLabels:true, so <b>/<i> inside node
        # labels sail through locally; GitHub disables HTML labels for security and
        # renders those diagrams differently or not at all. A check that is more
        # permissive than the thing it stands in for reports a pass that means nothing
        # — which is the same failure this repo warns about everywhere else.
        cfg = Path(td) / "github.json"
        cfg.write_text(
            '{"securityLevel":"strict","htmlLabels":false,'
            '"flowchart":{"htmlLabels":false}}', encoding="utf-8"
        )
        # mermaid-cli drives headless Chrome through Puppeteer, and Chrome's sandbox
        # cannot start as root inside a CI container. Without this every diagram
        # "fails" identically with a ChildProcess error that has nothing to do with
        # the diagram.
        pcfg = Path(td) / "puppeteer.json"
        pcfg.write_text('{"args":["--no-sandbox","--disable-setuid-sandbox"]}',
                        encoding="utf-8")

        launch_failed = 0
        for path, idx, body in blocks:
            src = Path(td) / f"d{len(bad)}_{idx}.mmd"
            src.write_text(body, encoding="utf-8")
            out = src.with_suffix(".svg")
            r = subprocess.run(
                ["npx", "-y", "-p", "@mermaid-js/mermaid-cli@11", "mmdc",
                 "--configFile", str(cfg), "--puppeteerConfigFile", str(pcfg),
                 "-i", str(src), "-o", str(out)],
                capture_output=True, text=True,
            )
            if not out.exists():
                err = r.stderr.strip()
                # Tell "the renderer would not start" apart from "this diagram is
                # broken". Reporting the first as the second is how this check spent
                # its life red on main while saying nothing true about the diagrams.
                if re.search(r"Failed to launch|Could not find (Chrome|browser)|"
                             r"ChildProcess|ENOENT|spawn", err):
                    launch_failed += 1
                    continue
                bad.append(f"{path} diagram {idx}: {err.splitlines()[-1] if err else 'render failed'}")
                continue
            # Rendering is necessary but not sufficient. With htmlLabels off, an <b> in
            # a label does not error — it renders as the literal text "&lt;b&gt;", so
            # the diagram silently displays its own markup. Catch that too.
            svg = out.read_text(encoding="utf-8", errors="replace")
            if "&lt;b&gt;" in svg or "&lt;i&gt;" in svg:
                bad.append(
                    f"{path} diagram {idx}: HTML tags in labels render as literal text "
                    f"on GitHub — remove <b>/<i> (<br/> is fine)"
                )

    if launch_failed and not bad:
        # Nothing was actually checked. Say so instead of claiming a pass.
        SKIPPED.append(f"mermaid render — headless Chrome would not start ({launch_failed} diagrams unchecked)")
        print(f"ok    mermaid diagrams found ({len(blocks)}) — renderer unavailable, not checked")
        return
    report(f"mermaid renders as GitHub renders it ({len(blocks)} diagrams)", bad)


# ── 9. Scripts have a shebang and a description ──────────────────────────────
def check_scripts_meta():
    bad = []
    for s in shell_scripts():
        rel = s.relative_to(ROOT)
        text = s.read_text(encoding="utf-8")
        if not text.startswith("#!"):
            bad.append(f"{rel}: no shebang")
        if not re.search(r"^#\s*\S", text.split("\n", 1)[1] if "\n" in text else "", re.M):
            bad.append(f"{rel}: no description comment")
    report("scripts have shebang and description", bad)


# ── 10. Release detector calibration ─────────────────────────────────────────
def check_detector_calibration():
    """Controls before readings, applied to the repo's own newest instrument.

    A detector whose only test is "it worked live once" is the confident shrug
    the README warns about. Three cells against a captured feed snapshot, no
    network: the known answer, the no-cycle negative control (same feed, stable
    pinned past the prerelease), and garbage in / no version out.
    """
    script = ROOT / "scripts" / "check-latest-release.sh"
    feed = ROOT / "fixtures" / "feeds" / "releases-2026-08-13.xml"
    bad = []
    if not feed.exists():
        report("detector calibration", [f"missing fixture {feed.relative_to(ROOT)}"])
        return

    def run(feed_path, stable, probe=None):
        env = {**os.environ, "WP_AUDIT_FEED_FILE": str(feed_path),
               "WP_AUDIT_STABLE": stable}
        if probe is None:
            env["WP_AUDIT_SKIP_PACKAGE_CHECK"] = "1"
        else:
            env["WP_AUDIT_PROBE_LIST"] = probe
        return subprocess.run(["bash", str(script)], capture_output=True, text=True, env=env)

    r = run(feed, "7.0.3")
    if r.returncode != 0 or r.stdout.strip() != "7.1-RC2":
        bad.append(f"known answer: want 7.1-RC2/exit 0, got '{r.stdout.strip()}'/exit {r.returncode}")
    r = run(feed, "7.1")
    if r.returncode != 2:
        bad.append(f"negative control: want exit 2 (no cycle), got exit {r.returncode}")
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False) as f:
        f.write("<rss>this feed mentions no builds at all</rss>")
        garbage = f.name
    try:
        r = run(garbage, "7.0.3")
        if r.returncode == 0 or r.stdout.strip():
            bad.append(f"garbage feed: produced '{r.stdout.strip()}'/exit {r.returncode}, want no version")
    finally:
        os.unlink(garbage)

    # The forward walk past the feeds. Cells 4-6 exist because on 2026-08-13 the feeds'
    # newest 7.1 mention was RC2 while RC3 had been downloadable for a day — the walk is
    # what closes that, so it needs its own controls rather than riding on the parser's.
    for name, probe, want in (
        ("walk finds a build the feeds never announced", "7.1-RC2 7.1-RC3", "7.1-RC3"),
        ("walk stops when nothing newer exists", "7.1-RC2", "7.1-RC2"),
        ("walk does not jump a gap", "7.1-RC2 7.1-RC3 7.1-RC5", "7.1-RC3"),
    ):
        r = run(feed, "7.0.3", probe=probe)
        if r.stdout.strip() != want:
            bad.append(f"{name}: want {want}, got '{r.stdout.strip()}'")
    report("detector calibration (6 cells)", bad)


# ── 11. Referenced run-root paths resolve in the repo ────────────────────────
def check_runroot_paths():
    """Every $WP_AUDIT_ROOT/<path> and bare pilots/learning/methods/deliverables
    reference in the Markdown resolves relative to the repo root.

    For a year of commits these references pointed at files that existed only on
    one machine — a fresh clone broke at step 2 of wp-release-party, and nothing
    here could see it, because the machine the checks ran on had the files. The
    schemas now ship in-repo; this is the check that keeps them shipped.

    The allowlist is for references that are ABOUT the private run root rather
    than into the repo. Every entry carries its reason; an entry without one is
    a dangling path with a hall pass.
    """
    allow = {
        # Per-release run data: evidence, verdicts, build manifests. Private by
        # design — .gitignore draws the same boundary.
        "pilots/wp71-rc1/",
        # Preserved prompt bodies cite the run root's old deliverables/ layout;
        # their headers carry a path note pointing at prompts/. The bodies stay
        # byte-for-byte because audit records cite them as run.
        "deliverables/codex-feature-chain-test-generation-prompt.md",
    }
    pat = re.compile(
        r"(?:\$WP_AUDIT_ROOT/|(?<![\w/.$-]))"
        r"((?:pilots|learning|methods|deliverables)/[A-Za-z0-9_<>./-]*[A-Za-z0-9_>/-])"
    )
    bad, count = [], 0
    for p in md_files():
        text = p.read_text(encoding="utf-8")
        rel = p.relative_to(ROOT)
        for m in pat.finditer(text):
            path = m.group(1).split("#")[0].rstrip(".,")
            count += 1
            if path in allow or "<" in path:  # templated segments are per-release
                continue
            target = ROOT / path
            ok = target.is_dir() if path.endswith("/") else target.exists()
            if not ok:
                line = text[: m.start()].count("\n") + 1
                bad.append(f"{rel}:{line} {path}")
    report(f"run-root paths resolve in the repo ({count} checked)", sorted(set(bad)))


# ── 12. Environment drivers honour the driver contract ───────────────────────
def check_driver_conformance():
    """Every driver, against the contract in scripts/env/README.md.

    Syntax-clean is not the failure that matters for a driver. One that swallows
    WP-CLI's exit status is valid shell that turns every failure into a silent
    PASS — three of the first six shipped with exactly that bug. This runs the
    conformance harness, which needs no WordPress and no container.
    """
    harness = ROOT / "scripts" / "env" / "conformance.sh"
    if not harness.exists():
        SKIPPED.append("driver conformance (no harness)")
        return
    r = subprocess.run(["bash", str(harness)], capture_output=True, text=True)
    bad = [l.strip() for l in r.stdout.splitlines() if l.strip().startswith("FAIL")]
    report("environment drivers honour the contract", bad)


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
    check_detector_calibration()
    check_runroot_paths()
    check_driver_conformance()

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
