#!/usr/bin/env python3
"""Render the Slack test-report checklist from recorded cell verdicts.

  python3 scripts/render_slack_checklist.py --from-results --tier T1 \\
    --source "7.0.2" --target "7.1-RC4" --method "Beta Tester plugin" \\
    --env "single-site" --php "8.4" --theme "Twenty Twenty-Five" --browser "Chrome" \\
    --site-mode single

Reads verdicts from pilots/release-day/sweep-matrix.csv and upgrade-ladder.csv
(--results-dir, defaulting to $WP_AUDIT_ROOT/pilots/release-day and falling back to
the repo copies, whose verdict columns are blank by design). Without --from-results
it renders the blank form.

THE ONE RULE THIS SCRIPT EXISTS TO ENFORCE

Each checklist line owns an explicit list of cells, and renders the worst verdict
among ITS OWN verdicted cells — nothing else. Lines are never filled by entity-name
association. The first auto-renderer did exactly that, and at the 7.1-RC1 party one
BLOCKED media cell painted all seven Media lines blocked while untested WooCommerce
lines inherited green from the "plugin" entity — a checklist lying in both
directions at once. Ownership here is written as fully-qualified selectors
(entity/operation/environment, or a ladder hop) that must resolve to EXACTLY ONE
cell in the matrix; zero or several is an error, not a guess.

Lines with no cells in the committed model say so in UNMAPPED_LINES, with the
reason. Cells no line owns are in UNMAPPED_CELLS, with the reason. --strict turns
any verdicted cell outside both sets into an error instead of a silently dropped
result.
"""

import argparse
import csv
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

EMOJI = {
    "PASS": ":white_check_mark:",
    "FAIL": ":x:",
    "PARTIAL": ":warning:",
    "BLOCKED": ":no_entry_sign:",
    "SKIP": ":heavy_minus_sign:",
    "INVALID": ":recycle:",
}
# Worst wins within a line. FAIL outranks everything; INVALID outranks BLOCKED
# because an invalid batch means the line's evidence is contaminated, not merely
# missing; SKIP is barely a result at all.
SEVERITY = {"FAIL": 6, "INVALID": 5, "BLOCKED": 4, "PARTIAL": 3, "SKIP": 2, "PASS": 1}

LEGEND = (":white_check_mark: pass  ·  :x: fail  ·  :warning: partial or unexpected"
          "  ·  :no_entry_sign: blocked  ·  :heavy_minus_sign: not tested"
          "  ·  :recycle: invalid batch, rerun needed")


def sel(entity, op, env):
    return f"sweep:{entity}/{op}/{env}"


def lad(source, env):
    return f"ladder:{source}/{env}/core-updater"


# ── Line ownership ───────────────────────────────────────────────────────────
# (section, [(label, [selectors])]). A selector resolves to exactly one cell.
SECTIONS = [
    ("Upgrade", [
        ("Upgrade completed without error", [lad("7.0.2", "single")]),
        ("Version and db_version correct after upgrade", [sel("upgrade", "version-db-correct", "single")]),
        ("No PHP fatals or new deprecations in debug.log", [sel("upgrade", "no-new-fatals", "single")]),
        ("wp-admin loads (dashboard + all core screens)", [sel("upgrade", "admin-loads", "single")]),
        ("Front end loads", [sel("upgrade", "front-loads", "single")]),
        ("File tree matches a clean install of the same build", [sel("upgrade", "tree-vs-clean-install", "single")]),
        ("Rollback / reactivate previous version", [sel("upgrade", "rollback", "single")]),
    ]),
    ("Content", [
        ("Create, update, and delete Posts",
         [sel("post", "create", "single"), sel("post", "update", "single"), sel("post", "delete", "single")]),
        ("Create, update, and delete Pages",
         [sel("page", "create", "single"), sel("page", "update", "single"), sel("page", "delete", "single")]),
        ("Trash and restore Posts", [sel("post", "trash-restore", "single")]),
        ("Post revisions save and restore", [sel("post", "revision-restore", "single")]),
        ("Create, update, and delete Custom Post Types",
         [sel("custom-post-type", "create", "single"), sel("custom-post-type", "update", "single"),
          sel("custom-post-type", "delete", "single")]),
        ("Add and delete Comments on Posts",
         [sel("comment", "create", "single"), sel("comment", "delete", "single")]),
        ("Edit comment parent", [sel("comment", "update", "single")]),
        ("Add and remove Categories and Tags",
         [sel("category-tag", "create", "single"), sel("category-tag", "delete", "single")]),
        ("Add and remove custom taxonomy terms",
         [sel("custom-taxonomy-term", "create", "single"), sel("custom-taxonomy-term", "delete", "single")]),
        ("Bulk edit and quick edit", ["browser:posts/quick edit and bulk edit"]),
        ("Scheduled post publishes", [sel("post", "schedule-publish", "single")]),
    ]),
    ("Media", [
        ("Upload, edit, and delete media (JPEG/PNG)",
         [sel("media", "create", "single"), sel("media", "update", "single"), sel("media", "delete", "single")]),
        ("Upload HEIC / AVIF / WebP", []),
        ("Media Editor Modal: crop, rotate, flip", ["browser:media/media editor modal: crop, rotate, flip"]),
        ("Media Library infinite scroll and per-user opt-out",
         ["browser:media/library grid: upload, infinite scroll, per-user opt-out"]),
        ("Gallery block: attached-images inserter", []),
        ("Regenerate thumbnails / subsizes", []),
        ("Alt text and 'mark as decorative'", []),
    ]),
    ("Editor", [
        ("Block editor loads (iframed)", ["browser:posts/editor loads and publishes"]),
        ("Persistent toolbar in Post Editor and Site Editor", []),
        ("Distraction Free and Fullscreen toggles", []),
        ("Notes: add, @mention, resolve, delete", []),
        ("Responsive per-breakpoint styling", []),
        ("Interactive (hover/focus) state styling", []),
        ("Command palette", []),
        ("Patterns and reusable blocks", []),
        ("Copy/paste and undo/redo across blocks", []),
    ]),
    ("Themes and Site Editor", [
        ("Switch between block themes", ["browser:themes/switch theme from the admin"]),
        ("Switch block theme to classic theme and back", []),
        ("Install, update, and delete themes",
         [sel("theme", "create", "single"), sel("theme", "delete", "single")]),
        ("Edit and revert templates and template parts",
         ["browser:themes/site editor opens a template",
          "browser:template-template-part/edit in the site editor",
          "browser:template-template-part/revert to theme default"]),
        ("Global Styles: edit and restore a revision", []),
        ("theme.json viewport breakpoints", []),
        ("Classic and Navigation-block menus",
         ["browser:navigation-block-menu/create and edit in the editor",
          "browser:navigation-block-menu/front-end render",
          "browser:classic-nav-menu/Appearance > Menus edit",
          "browser:classic-nav-menu/front-end render"]),
    ]),
    ("Plugins", [
        ("Install plugin", [sel("plugin", "create", "single")]),
        ("Activate, deactivate, and delete plugin",
         [sel("plugin", "delete", "single"), "browser:plugins/plugin-card install and activate buttons"]),
        ("Update plugins and themes",
         [sel("plugin", "update", "single"), sel("theme", "update", "single")]),
        ("Auto-update toggle", []),
        ("Plugin dependencies (Requires Plugins header)",
         ["browser:plugins/dependencies affordance (Requires Plugins)"]),
        ("WooCommerce: create, update, delete Products", []),
        ("WooCommerce: cart and checkout smoke", []),
    ]),
    ("Users and roles", [
        ("Create, update, and delete Users",
         [sel("user", "create", "single"), sel("user", "update", "single"), sel("user", "delete", "single")]),
        ("Change user role", [sel("role-capability", "update", "single")]),
        ("Login, logout, and password reset", []),
        ("Application passwords", [sel("user", "application-password", "single")]),
        ("Personal data export and erase", []),
    ]),
    ("Settings and tools", [
        ("Save General / Reading / Writing / Discussion settings", [sel("option-setting", "update", "single")]),
        ("Save permalinks and verify front-end routing", [sel("permalink", "update", "single")]),
        ("Export and import (WXR) round-trip", [sel("content", "wxr-round-trip", "single")]),
        ("Site Health reports no new critical issues", []),
        ("Widgets screen",
         ["browser:block-widget/widgets screen edit", "browser:block-widget/front-end render"]),
    ]),
    ("Multisite", [
        ("Network upgrade completes; report the full site count", [lad("7.0.2", "multisite")]),
        ("Create, archive, spam, and delete a site", [sel("site", "lifecycle", "multisite-network")]),
        ("Held-back sites report correctly (archived/spam/deleted)",
         [sel("site", "held-back-denominator", "multisite-network")]),
        ("Network-activate and site-activate a plugin",
         [sel("plugin", "create", "multisite-network"), sel("plugin", "create", "multisite-subsite")]),
        ("Per-site admin and front end load", [sel("site", "subsite-loads", "multisite-subsite")]),
        ("Network user vs site user management",
         [sel("user", "create", "multisite-network"), sel("role-capability", "read-list", "multisite-network")]),
    ]),
]

# Lines with an empty selector list above, and why. The reason is the contract:
# an unmapped line renders "not tested" until someone adds the cell — it never
# inherits a verdict from a neighbour.
UNMAPPED_LINES = {
    "Upload HEIC / AVIF / WebP": "needs a delegate-capable fixture; add a per-release cell when the release touches formats — preflight decides BLOCKED vs runnable",
    "Gallery block: attached-images inserter": "editor-side; joins the ledger-selected browser list when the release touches the inserter",
    "Regenerate thumbnails / subsizes": "wp media regenerate is a T2 cell candidate, not in the committed T1 model",
    "Alt text and 'mark as decorative'": "browser media detail; ledger-selected",
    "Persistent toolbar in Post Editor and Site Editor": "editor chrome changes every release; cells come from the change ledger, not the committed model",
    "Distraction Free and Fullscreen toggles": "same — ledger-selected editor chrome",
    "Notes: add, @mention, resolve, delete": "same — ledger-selected editor chrome",
    "Responsive per-breakpoint styling": "same — ledger-selected editor chrome",
    "Interactive (hover/focus) state styling": "same — ledger-selected editor chrome",
    "Command palette": "same — ledger-selected editor chrome",
    "Patterns and reusable blocks": "same — ledger-selected editor chrome",
    "Copy/paste and undo/redo across blocks": "same — ledger-selected editor chrome",
    "Switch block theme to classic theme and back": "classic-theme fixture cell; T2 candidate",
    "Global Styles: edit and restore a revision": "ledger-selected browser work",
    "theme.json viewport breakpoints": "ledger-selected browser work",
    "Auto-update toggle": "needs a clock or a mock; T2 candidate",
    "WooCommerce: create, update, delete Products": "external plugin — no third-party plugins in the committed core model; see the ecosystem-compatibility lane",
    "WooCommerce: cart and checkout smoke": "same — ecosystem-compatibility lane",
    "Login, logout, and password reset": "browser auth flow; T2 candidate",
    "Personal data export and erase": "privacy tools flow; T2 candidate",
    "Site Health reports no new critical issues": "admin screen read; ledger-selected browser work",
}

# Cells the model defines that no checklist line owns, and why. These report in
# the thread, not the checklist. --strict errors on any verdicted cell that is
# neither owned nor listed here.
UNMAPPED_CELLS = {
    sel("post", "create", "multisite-subsite"): "subsite CRUD smoke — thread detail",
    sel("media", "create", "multisite-subsite"): "subsite quota lane — thread detail",
    "ladder:*": "ladder cells other than the two primary hops are thread material",
    "browser-t2:*": "demoted browser cells report in the thread if run at all",
}


def load_results(results_dir, tier):
    """Return {selector: (verdict, cell_id)} for verdicted cells at the tier."""
    out = {}
    sweep = results_dir / "sweep-matrix.csv"
    ladder = results_dir / "upgrade-ladder.csv"
    if sweep.exists():
        for row in csv.DictReader(sweep.open(encoding="utf-8")):
            if row["interface"] == "wp-cli":
                key = f"sweep:{row['entity']}/{row['operation']}/{row['environment']}"
            elif row["interface"] == "ecosystem":
                key = f"eco:{row['operation']}"
            else:
                key = f"browser:{row['entity']}/{row['operation']}"
            if key in out:
                sys.exit(f"selector {key} matches more than one cell — matrix is ambiguous")
            out[key] = (row["verdict"].strip().upper(), row["cell_id"], row["tier"])
    if ladder.exists():
        for row in csv.DictReader(ladder.open(encoding="utf-8")):
            key = f"ladder:{row['source_version']}/{row['env']}/{row['updater_lane']}"
            if key in out:
                sys.exit(f"selector {key} matches more than one cell — matrix is ambiguous")
            out[key] = (row["verdict"].strip().upper(), row["cell_id"], row["tier"])
    if tier:
        out = {k: v for k, v in out.items() if v[2] == tier or not v[0]}
    return out


def line_verdict(selectors, cells):
    verdicts = []
    for s in selectors:
        if s in cells and cells[s][0]:
            v = cells[s][0]
            if v not in SEVERITY:
                sys.exit(f"cell {cells[s][1]} carries verdict '{v}' — "
                         f"smoke verdicts are {sorted(SEVERITY)}; the finding vocabulary "
                         f"(CONFIRMED/REFUTED/...) never enters this matrix")
            verdicts.append(v)
    if not verdicts:
        return None
    return max(verdicts, key=lambda v: SEVERITY[v])


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--from-results", action="store_true")
    ap.add_argument("--results-dir")
    ap.add_argument("--tier", default="T1")
    ap.add_argument("--source", default="<SOURCE>")
    ap.add_argument("--target", default="<TARGET>")
    ap.add_argument("--method", default="<lane>")
    ap.add_argument("--env", default="<env>")
    ap.add_argument("--php", default="<PHP>")
    ap.add_argument("--theme", default="<theme>")
    ap.add_argument("--browser", default="<browser>")
    ap.add_argument("--site-mode", choices=["single", "multisite", "both"], default="both")
    ap.add_argument("--strict", action="store_true",
                    help="error on verdicted cells no line owns and no rule excuses")
    args = ap.parse_args()

    cells = {}
    if args.from_results:
        if args.results_dir:
            rdir = Path(args.results_dir)
        elif os.environ.get("WP_AUDIT_ROOT"):
            rdir = Path(os.environ["WP_AUDIT_ROOT"]) / "pilots" / "release-day"
        else:
            rdir = ROOT / "pilots" / "release-day"
        if not rdir.is_dir():
            sys.exit(f"no results directory at {rdir}")
        cells = load_results(rdir, args.tier)

    sections = [s for s in SECTIONS if not (args.site_mode == "single" and s[0] == "Multisite")]

    # Sanity on the mapping itself, every run: an empty selector list must be
    # excused, and a mapped selector must exist in the matrix when results loaded.
    for name, lines in sections:
        for label, selectors in lines:
            if not selectors and label not in UNMAPPED_LINES:
                sys.exit(f"line '{label}' owns no cells and gives no reason")
            if cells:
                for s in selectors:
                    if s not in cells:
                        sys.exit(f"line '{label}' cites {s}, which matches no cell in the "
                                 f"matrix — regenerate the matrices or fix the mapping")

    if args.strict and cells:
        owned = {s for _, lines in SECTIONS for _, sels_ in lines for s in sels_}
        orphans = []
        for key, (verdict, cell_id, tier) in cells.items():
            if not verdict or key in owned or key in UNMAPPED_CELLS:
                continue
            if key.startswith("ladder:"):
                continue  # covered by the ladder:* rule above
            if key.startswith("browser:") and tier != "T1":
                continue  # covered by browser-t2:*
            orphans.append(f"{cell_id} ({key})")
        if orphans:
            sys.exit("verdicted cells no checklist line owns and no rule excuses:\n  "
                     + "\n  ".join(orphans)
                     + "\nAdd them to a line's selectors or to UNMAPPED_CELLS with a reason.")

    total = counts = None
    rendered = []
    tally = {"pass": 0, "fail": 0, "partial": 0, "blocked": 0, "invalid": 0, "not": 0}
    for name, lines in sections:
        block = [f"*{name}*"]
        for label, selectors in lines:
            v = line_verdict(selectors, cells) if cells else None
            if v is None:
                mark = ":heavy_minus_sign:" if cells else ":white_large_square:"
                tally["not"] += 1
            else:
                mark = EMOJI[v]
                tally[{"PASS": "pass", "FAIL": "fail", "PARTIAL": "partial",
                       "BLOCKED": "blocked", "INVALID": "invalid", "SKIP": "not"}[v]] += 1
            block.append(f"• {label} {mark}")
        rendered.append("\n".join(block))

    total = sum(len(l) for _, l in sections)
    counts = (f"{tally['pass']} passed · {tally['fail']} failed · {tally['partial']} partial · "
              f"{tally['blocked']} blocked · {tally['not']} not tested")
    if tally["invalid"]:
        counts += f" · {tally['invalid']} invalid"

    print(f"*WordPress {args.target}* — upgraded from *{args.source}* via *{args.method}*")
    print()
    print(f"Environment: {args.env} · PHP {args.php} · {args.theme} · {args.browser}")
    print(f"Result: {counts}")
    print()
    print("\n\n".join(rendered))
    print(LEGEND)
    print()
    print("Findings and evidence in thread. Invalid batches are excluded from the counts above.")
    print(f"\n[{total} checks rendered · site-mode {args.site_mode} · tier {args.tier}]",
          file=sys.stderr)


if __name__ == "__main__":
    main()
