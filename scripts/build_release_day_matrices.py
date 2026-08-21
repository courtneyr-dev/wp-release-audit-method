#!/usr/bin/env python3
"""Deterministic regenerator for the release-day matrices.

Writes pilots/release-day/sweep-matrix.csv and pilots/release-day/upgrade-ladder.csv
from the entity x operation x interface x environment model in the README and the
release-day sweep playbook. Regenerate rather than hand-editing the CSVs — the model
lives here, where a count that drifts from the documented one is an error instead of
a silent lie.

  python3 scripts/build_release_day_matrices.py
  python3 scripts/build_release_day_matrices.py --browser-t1 media,plugins,posts,navigation-block-menu,themes
  python3 scripts/build_release_day_matrices.py --target https://wordpress.org/wordpress-7.2-RC1.zip

Two things are deliberately NOT baked in:

  * BROWSER_T1 — which entities get browser cells at tier 1 — is re-derived per
    release from that release's change ledger and never carried forward. With no
    --browser-t1 the script regenerates the recorded 7.1 set (media, plugins, posts,
    navigation-block-menu, themes) and says so loudly: that set is a historical
    record of the 7.1 cycle, not a default for yours.
  * The target build. With no --target the target_build column is left empty, to be
    filled at run start — a suite never picks its own target.

The generated rows carry empty verdict/observed/evidence columns. Those get filled in
your run root copy, never in the repo copy — see pilots/README.md.
"""

import argparse
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The 7.1 change-ledger browser set, kept as the recorded example. 7.1 touched the
# upload path, the library UI, the plugin-card buttons, the editor chrome, and the
# iframe — hence these five. Re-derive for any other release.
BROWSER_T1_71 = ["media", "plugins", "posts", "navigation-block-menu", "themes"]

# ── The sweep model ──────────────────────────────────────────────────────────
# One tuple per CLI cell: (entity, operation, environment). The counts at the
# bottom are load-bearing: the skills and playbooks say "51 wp-cli + 10 browser"
# and this script refuses to emit anything else without the docs changing too.

CLI_CELLS = [
    # entity, operation, environment
    ("post", "create", "single"),
    ("post", "update", "single"),
    ("post", "delete", "single"),
    ("post", "trash-restore", "single"),
    ("post", "revision-restore", "single"),
    ("post", "schedule-publish", "single"),
    ("post", "create", "multisite-subsite"),
    ("page", "create", "single"),
    ("page", "update", "single"),
    ("page", "delete", "single"),
    ("custom-post-type", "create", "single"),
    ("custom-post-type", "update", "single"),
    ("custom-post-type", "delete", "single"),
    ("comment", "create", "single"),
    ("comment", "update", "single"),       # includes reparenting — the beta4 class
    ("comment", "delete", "single"),
    ("category-tag", "create", "single"),
    ("category-tag", "delete", "single"),
    ("custom-taxonomy-term", "create", "single"),
    ("custom-taxonomy-term", "delete", "single"),
    ("media", "create", "single"),
    ("media", "update", "single"),
    ("media", "delete", "single"),
    ("media", "create", "multisite-subsite"),  # upload against the subsite quota
    ("user", "create", "single"),
    ("user", "update", "single"),
    ("user", "delete", "single"),
    ("user", "application-password", "single"),
    ("user", "create", "multisite-network"),
    ("role-capability", "update", "single"),
    ("role-capability", "read-list", "multisite-network"),  # super-admin asymmetry
    ("theme", "create", "single"),          # install
    ("theme", "update", "single"),
    ("theme", "delete", "single"),
    ("plugin", "create", "single"),         # install
    ("plugin", "update", "single"),
    ("plugin", "delete", "single"),
    ("plugin", "create", "multisite-network"),   # network activate
    ("plugin", "create", "multisite-subsite"),   # site activate
    ("option-setting", "update", "single"),
    ("permalink", "update", "single"),      # save structure + front-end route answers
    ("content", "wxr-round-trip", "single"),
    # Post-upgrade assertions on the primary hop (current stable -> target).
    # Each is its own cell: one hop, six individually recorded observations —
    # a single hop verdict painting six checklist lines is the exact
    # by-association failure the renderer exists to prevent.
    ("upgrade", "version-db-correct", "single"),
    ("upgrade", "no-new-fatals", "single"),
    ("upgrade", "admin-loads", "single"),
    ("upgrade", "front-loads", "single"),
    ("upgrade", "tree-vs-clean-install", "single"),
    ("upgrade", "rollback", "single"),
    # Multisite lifecycle — the held-back-denominator class (FM-03, FM-15).
    ("site", "lifecycle", "multisite-network"),  # create, archive, spam, delete
    ("site", "held-back-denominator", "multisite-network"),
    ("site", "subsite-loads", "multisite-subsite"),
]

# Ecosystem cells — the lane the WP Rocket 7.1 outage exposed (see
# method/ecosystem-compatibility-lane.md). Three parties: a core change, a
# plugin assumption, a third plugin supplying the trigger. Single-plugin
# matrices test pairs; this block is what reaches toward the triples.
ECOSYSTEM_CELLS = [
    # operation, command hint
    ("co-installed-pairs-upgrade",
     "pair fixture per plugin-theme-authors/co-installed-plugins.md; upgrade across the "
     "boundary; assert no new fatals in debug.log, admin and front answer 200. Premium "
     "plugins the tester cannot supply read BLOCKED(premium-license), never SKIP"),
    ("closure-trigger-probe",
     "scripts/hook-key-type-probe.sh --control positive; --control negative; then the "
     "plain reading. Controls must pass before the reading counts"),
    ("fleet-tracker-triage",
     "for each fleet plugin: search its public tracker for issues naming the target core "
     "version. An open issue with a proposed fix is an imported finding"),
]

# Browser cells: two per ledger-selected entity. The checks name what only a
# browser can see — the beta4 plugin-dependency defect was invisible to WP-CLI.
BROWSER_CHECKS = {
    "media": ["library grid: upload, infinite scroll, per-user opt-out",
              "media editor modal: crop, rotate, flip"],
    "plugins": ["plugin-card install and activate buttons", "dependencies affordance (Requires Plugins)"],
    "posts": ["editor loads and publishes", "quick edit and bulk edit"],
    "navigation-block-menu": ["create and edit in the editor", "front-end render"],
    "themes": ["switch theme from the admin", "site editor opens a template"],
    # Entities not in this release's ledger demote to T2 — same two checks shape.
    "page": ["editor loads and publishes", "quick edit and bulk edit"],
    "comment": ["moderation screen actions", "reply from the admin"],
    "user": ["profile screen saves", "role change from the users screen"],
    "classic-nav-menu": ["Appearance > Menus edit", "front-end render"],
    "block-widget": ["widgets screen edit", "front-end render"],
    "template-template-part": ["edit in the site editor", "revert to theme default"],
    "option-setting": ["General settings save", "Reading settings save"],
    "site": ["network admin: add and archive a site", "per-site admin loads"],
}

# ── The ladder model ─────────────────────────────────────────────────────────
# 22 source series x {single, multisite} x {core-updater, wp-cli-updater} = 88.
# T1 is the 9-cell subset the party runs; see the sweep playbook for the tiering
# rationale (oldest source, block-editor boundary, PHP-floor boundaries, stable).

SERIES = (
    ["4.9"]
    + [f"5.{i}" for i in range(10)]
    + [f"6.{i}" for i in range(10)]
    + ["7.0.2"]
)
T1_SINGLE = ["4.9", "5.0", "6.2", "6.3", "6.6", "6.9", "7.0.2"]
T1_MULTI = ["4.9", "7.0.2"]


def ladder_tier(series, env, lane):
    if lane == "wp-cli-updater":
        return "T3"
    if env == "single":
        return "T1" if series in T1_SINGLE else "T2"
    return "T1" if series in T1_MULTI else "T3"


def build(browser_t1, target):
    sweep = []
    n = 0
    for entity, op, env in CLI_CELLS:
        n += 1
        sweep.append({
            "cell_id": f"T1-{n:02d}",
            "entity": entity, "operation": op, "interface": "wp-cli",
            "environment": env, "tier": "T1",
            "expected": f"{op} succeeds and cleanup restores the fixture",
            "observed": "", "verdict": "",
            "command": "scripts/crud-suite.sh (see per-entity cell in output)",
            "evidence_path": "", "fixture_hash": "", "cleanup_verified": "",
            "notes": "",
        })
    for op, hint in ECOSYSTEM_CELLS:
        n += 1
        sweep.append({
            "cell_id": f"T1-{n:02d}",
            "entity": "ecosystem", "operation": op, "interface": "ecosystem",
            "environment": "single", "tier": "T1",
            "expected": "no new fatals attributable to the release boundary",
            "observed": "", "verdict": "",
            "command": hint,
            "evidence_path": "", "fixture_hash": "", "cleanup_verified": "",
            "notes": "ecosystem lane — method/ecosystem-compatibility-lane.md",
        })
    for entity, checks in BROWSER_CHECKS.items():
        tier = "T1" if entity in browser_t1 else "T2"
        for check in checks:
            n += 1
            sweep.append({
                "cell_id": f"{tier}-{n:02d}",
                "entity": entity, "operation": check, "interface": "browser",
                "environment": "single", "tier": tier,
                "expected": "behaves as on the prior stable; no console errors",
                "observed": "", "verdict": "",
                "command": "manual (ledger-selected browser cell)",
                "evidence_path": "", "fixture_hash": "", "cleanup_verified": "",
                "notes": "browser tier from this release's change ledger"
                         if tier == "T1" else "demoted: not on this release's ledger",
            })

    cli_t1 = sum(1 for c in sweep if c["interface"] == "wp-cli" and c["tier"] == "T1")
    br_t1 = sum(1 for c in sweep if c["interface"] == "browser" and c["tier"] == "T1")
    eco_t1 = sum(1 for c in sweep if c["interface"] == "ecosystem")
    # The documented shape. If you change the model, change the docs that promise
    # these numbers (README, wp-release-party, the sweep playbook) in the same commit.
    assert cli_t1 == 51, f"CLI T1 cells: {cli_t1}, docs promise 51"
    assert br_t1 == 2 * len(browser_t1), f"browser T1 cells: {br_t1}"
    assert eco_t1 == 3, f"ecosystem T1 cells: {eco_t1}, docs promise 3"

    ladder = []
    n = 0
    for lane in ("core-updater", "wp-cli-updater"):
        for env in ("single", "multisite"):
            for series in SERIES:
                n += 1
                ladder.append({
                    "cell_id": f"L1-{n:02d}",
                    "source_version": series,
                    # Populated per release from the official requirements/compat
                    # tables when the ladder runs — not carried forward from here.
                    "source_php_support": "",
                    "fixture_php": "7.4",
                    "env": env, "updater_lane": lane,
                    "tier": ladder_tier(series, env, lane),
                    "target_build": target,
                    "pre_assert": "version, db_version, site inventory + flags, content counts, fixture hash",
                    "post_assert": "version, db_version, counts, tree vs clean install, admin 200, front 200, no new fatals",
                    "verdict": "", "evidence_path": "", "cleanup_verified": "",
                    "notes": "PHP 7.4 pinned: the only band where 4.9 and the target both run",
                })

    assert len(ladder) == 88, f"ladder cells: {len(ladder)}, docs promise 88"
    t1 = sum(1 for c in ladder if c["tier"] == "T1")
    assert t1 == 9, f"ladder T1 cells: {t1}, docs promise 9"
    return sweep, ladder


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--browser-t1", help="comma-separated ledger entities for THIS release")
    ap.add_argument("--target", default="", help="target build zip URL (else left blank)")
    ap.add_argument("--out-dir", default=str(ROOT / "pilots" / "release-day"))
    args = ap.parse_args()

    if args.browser_t1:
        browser_t1 = [e.strip() for e in args.browser_t1.split(",") if e.strip()]
        unknown = [e for e in browser_t1 if e not in BROWSER_CHECKS]
        if unknown:
            sys.exit(f"unknown browser entities {unknown}; known: {sorted(BROWSER_CHECKS)}")
    else:
        browser_t1 = BROWSER_T1_71
        print("NOTE: no --browser-t1 given — regenerating with the RECORDED 7.1 ledger set:")
        print(f"      {', '.join(browser_t1)}")
        print("      That set is a historical record. Re-derive it from YOUR release's")
        print("      change ledger before a party; it is the one input that must never")
        print("      carry forward.")

    sweep, ladder = build(browser_t1, args.target)
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    for name, rows in (("sweep-matrix.csv", sweep), ("upgrade-ladder.csv", ladder)):
        path = out / name
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {path} ({len(rows)} cells)")

    cli_t1 = sum(1 for c in sweep if c["interface"] == "wp-cli" and c["tier"] == "T1")
    br_t1 = sum(1 for c in sweep if c["interface"] == "browser" and c["tier"] == "T1")
    eco = sum(1 for c in sweep if c['interface'] == 'ecosystem')
    print(f"sweep T1: {cli_t1} wp-cli + {br_t1} browser + {eco} ecosystem · ladder T1: "
          f"{sum(1 for c in ladder if c['tier'] == 'T1')} of {len(ladder)}")


if __name__ == "__main__":
    main()
