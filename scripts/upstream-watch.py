#!/usr/bin/env python3
"""Watch the third-party sources this repo adapts technique from, and report drift.

This repo borrows. `scripts/check-latest-release.sh` is adapted from Chris Reynolds's
wpnext-test; `method/preflight-core-probe.md` is documented from Austin Ginder's
CaptainCore. Borrowing once is a citation. Borrowing and then never looking again is how
an attribution goes stale, a technique's honest limits shift underneath the write-up, and
a directory of 58 operational scripts sits unread because one of them was interesting in
August.

The register is `sources/upstream-watch.csv`. Each row names an upstream path, the license
it carries, what here was adapted from it, and the commit we last reviewed. This script
asks GitHub what has landed since — and `--update` moves the baseline forward once a human
has actually looked.

  python3 scripts/upstream-watch.py                      # report drift, human-readable
  python3 scripts/upstream-watch.py --format=markdown    # the issue body CI posts
  python3 scripts/upstream-watch.py --id=CC-REMOTE-SCRIPTS
  python3 scripts/upstream-watch.py --update             # AFTER review: baselines to HEAD
  python3 scripts/upstream-watch.py --control            # self-test, offline

Exit codes, mirroring check-latest-release.sh:
  0  no drift — every active row is current
  3  drift found (this is a result, not an error; CI branches on it)
  2  nothing to check — no active rows
  1  error (register unreadable, gh missing or unauthenticated, API failure)

Test seam: WP_AUDIT_UPSTREAM_FIXTURE=<dir> reads <dir>/<watch_id>.json instead of calling
gh, so the controls below run offline in CI. A detector whose controls need the network is
a detector that stops being checked the first week the network is flaky.
"""

import csv
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTER = ROOT / "sources" / "upstream-watch.csv"
FIXTURES = ROOT / "fixtures" / "upstream"
PAGE_SIZE = 100

FIELDS = [
    "watch_id", "upstream", "path", "license", "author", "why_we_watch",
    "integrated_into", "baseline_sha", "baseline_date", "status", "notes",
]


class WatchError(Exception):
    pass


def read_register(path=REGISTER):
    if not path.exists():
        raise WatchError(f"register not found: {path}")
    with path.open(encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise WatchError(f"register has no rows: {path}")
    missing = [f for f in FIELDS if f not in rows[0]]
    if missing:
        raise WatchError(f"register is missing columns: {', '.join(missing)}")
    return rows


def fetch_commits(row):
    """Newest-first commits touching this row's path. Fixture wins when set."""
    fixture_dir = os.environ.get("WP_AUDIT_UPSTREAM_FIXTURE")
    if fixture_dir:
        f = Path(fixture_dir) / f"{row['watch_id']}.json"
        if not f.exists():
            raise WatchError(f"fixture not found: {f}")
        return json.loads(f.read_text(encoding="utf-8"))

    endpoint = f"repos/{row['upstream']}/commits?per_page={PAGE_SIZE}"
    if row["path"]:
        endpoint += f"&path={row['path']}"
    proc = subprocess.run(
        ["gh", "api", endpoint, "--jq",
         "[.[] | {sha, commit: {author: {name: .commit.author.name, "
         "date: .commit.author.date}, message: .commit.message}, html_url}]"],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        err = (proc.stderr or "").strip().splitlines()
        raise WatchError(f"gh api failed for {row['watch_id']}: {err[-1] if err else 'no output'}")
    try:
        return json.loads(proc.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise WatchError(f"unparseable gh output for {row['watch_id']}: {exc}") from exc


def drift_for(row, commits):
    """Commits newer than the baseline.

    Returns (new_commits, truncated). `truncated` means the baseline was not found in
    the page we fetched — the drift is real but its size is a floor, not a count. That
    distinction matters: an unfound baseline can also mean a force-push rewrote history,
    and reporting "100 new commits" for a rebase would be a lie the register then carries.
    """
    baseline = (row["baseline_sha"] or "").strip()
    if not baseline:
        return commits, True
    new = []
    for c in commits:
        if c["sha"] == baseline:
            return new, False
        new.append(c)
    return new, True


def subject(commit):
    return commit["commit"]["message"].split("\n")[0].strip()


def render_text(results):
    out = []
    for row, new, truncated in results:
        head = f"{row['watch_id']}  ({row['upstream']}"
        head += f"/{row['path']})" if row["path"] else ")"
        if not new:
            out.append(f"ok    {head} — current at {row['baseline_sha'][:8]}")
            continue
        count = f"{len(new)}+" if truncated else str(len(new))
        out.append(f"DRIFT {head} — {count} new commit(s) since {row['baseline_sha'][:8]} ({row['baseline_date']})")
        for c in new[:10]:
            out.append(f"        {c['sha'][:8]}  {c['commit']['author']['date'][:10]}  {subject(c)}")
        if len(new) > 10:
            out.append(f"        … and {len(new) - 10} more")
        if truncated:
            out.append("        ! baseline not found in the fetched page — count is a floor, "
                       "and history may have been rewritten")
        out.append(f"        integrated into: {row['integrated_into'] or '(nothing yet)'}")
        out.append(f"        license: {row['license']} — {row['author']}")
    return "\n".join(out)


def render_markdown(results):
    drifted = [r for r in results if r[1]]
    if not drifted:
        return "Every watched upstream is current. Nothing to review."
    out = ["The upstream watch found new commits in sources this repo adapts technique from.",
           "", "Review each, then move the baseline forward with:", "",
           "```bash", "python3 scripts/upstream-watch.py --update", "```", ""]
    for row, new, truncated in drifted:
        loc = f"`{row['upstream']}/{row['path']}`" if row["path"] else f"`{row['upstream']}`"
        count = f"{len(new)}+" if truncated else str(len(new))
        out.append(f"### {row['watch_id']} — {loc}")
        out.append("")
        out.append(f"{count} new commit(s) since `{row['baseline_sha'][:8]}` ({row['baseline_date']}). "
                   f"{row['license']}, {row['author']}.")
        out.append("")
        for c in new[:20]:
            out.append(f"- [`{c['sha'][:8]}`]({c['html_url']}) {c['commit']['author']['date'][:10]} — {subject(c)}")
        if len(new) > 20:
            out.append(f"- … and {len(new) - 20} more")
        if truncated:
            out.append("")
            out.append("> The baseline commit was not in the fetched page. The count above is a "
                       "floor, and upstream history may have been rewritten — check before trusting it.")
        out.append("")
        out.append(f"**Already integrated here:** {row['integrated_into'] or '_nothing yet_'}")
        out.append("")
        out.append("**The review question is not \"is this new code good.\"** It is: does anything "
                   "here change a limit this repo has written down, contradict an attribution, or "
                   "cover a lane we left blocked? A commit that changes nothing for us still gets "
                   "the baseline moved — that is the register recording that someone looked.")
        out.append("")
    return "\n".join(out)


def write_register(rows, path=REGISTER):
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in FIELDS})


def run_control():
    """Positive and negative control, offline, against the captured fixture.

    A watch that has never reported drift on a known-drifted input is not a detector.
    Both controls run in one pass, per this repo's rule that a probe run without its
    controls passing is not a reading.
    """
    fixture = FIXTURES / "CONTROL-FIXTURE.json"
    if not fixture.exists():
        print(f"FAIL  control fixture missing: {fixture}")
        return 4
    commits = json.loads(fixture.read_text(encoding="utf-8"))
    if len(commits) < 3:
        print(f"FAIL  control fixture needs 3+ commits, has {len(commits)}")
        return 4

    problems = []

    # Positive: a baseline three commits back MUST report exactly three new.
    stale = {"watch_id": "CTL", "upstream": "x/y", "path": "", "baseline_sha": commits[3]["sha"],
             "baseline_date": "", "license": "", "author": "", "integrated_into": ""}
    new, truncated = drift_for(stale, commits)
    if len(new) != 3 or truncated:
        problems.append(f"positive control: expected 3 new and truncated=False, "
                        f"got {len(new)} and truncated={truncated}")

    # Negative: a baseline at HEAD MUST report none.
    current = dict(stale, baseline_sha=commits[0]["sha"])
    new, truncated = drift_for(current, commits)
    if new or truncated:
        problems.append(f"negative control: expected 0 new and truncated=False, "
                        f"got {len(new)} and truncated={truncated}")

    # Unknown baseline MUST be flagged truncated, not silently reported as full drift.
    unknown = dict(stale, baseline_sha="0" * 40)
    new, truncated = drift_for(unknown, commits)
    if not truncated:
        problems.append("unknown-baseline control: expected truncated=True, got False")

    # The register itself must parse and every active row must carry a baseline.
    try:
        rows = read_register()
    except WatchError as exc:
        problems.append(f"register: {exc}")
        rows = []
    for r in rows:
        if r["status"] == "active" and not (r["baseline_sha"] or "").strip():
            problems.append(f"register: active row {r['watch_id']} has no baseline_sha")

    if problems:
        print(f"FAIL  upstream-watch controls ({len(problems)})")
        for p in problems:
            print(f"        {p}")
        return 4
    print("ok    upstream-watch controls (positive, negative, unknown-baseline, register)")
    return 0


def main(argv):
    fmt, only, update = "text", None, False
    for a in argv:
        if a == "--control":
            return run_control()
        elif a == "--update":
            update = True
        elif a.startswith("--format="):
            fmt = a.split("=", 1)[1]
            if fmt not in ("text", "markdown"):
                print(f"upstream-watch: unknown format '{fmt}'", file=sys.stderr)
                return 1
        elif a.startswith("--id="):
            only = a.split("=", 1)[1]
        else:
            print(f"upstream-watch: unknown argument '{a}'", file=sys.stderr)
            return 1

    try:
        rows = read_register()
    except WatchError as exc:
        print(f"upstream-watch: {exc}", file=sys.stderr)
        return 1

    active = [r for r in rows if r["status"] == "active" and (only is None or r["watch_id"] == only)]
    if not active:
        print("upstream-watch: no active rows to check.", file=sys.stderr)
        return 2

    results = []
    for row in active:
        try:
            commits = fetch_commits(row)
        except WatchError as exc:
            print(f"upstream-watch: {exc}", file=sys.stderr)
            return 1
        results.append((row, *drift_for(row, commits)))

    print(render_markdown(results) if fmt == "markdown" else render_text(results))

    drifted = {r[0]["watch_id"]: r for r in results if r[1]}
    if update and drifted:
        for row in rows:
            hit = drifted.get(row["watch_id"])
            if hit:
                newest = hit[1][0]
                row["baseline_sha"] = newest["sha"]
                row["baseline_date"] = newest["commit"]["author"]["date"][:10]
        write_register(rows)
        print(f"\nBaselines moved forward for: {', '.join(sorted(drifted))}")
        print("Commit sources/upstream-watch.csv — the register is the record that a human looked.")
        return 0

    return 3 if drifted else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
