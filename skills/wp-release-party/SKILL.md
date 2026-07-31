---
name: wp-release-party
description: Run the release-day smoke sweep and produce the Slack-formatted test report — T1 CRUD matrix across wp-cli and browser, single and multisite, plus the T1 upgrade ladder, then render the checklist for posting. Trigger on "release party", "run the release day sweep", "wp release party", "test the RC and post results", or during a live WordPress release party.
---

# wp-release-party

Phase 1. Breadth, fast: **does the release break the ordinary things people do?** Depth belongs to `wp-release-followup`.

Assumes `wp-release-prep` has run — fixtures built, seeded, asserted, controls calibrated. If not, run that first; testing an unasserted fixture produces results nobody can trust.

## 1. Re-run the build-identity gate

```bash
$WP_AUDIT_ROOT/scripts/rc_build_identity.sh <VERSION> <LABEL>
```

Even if prep passed it. Packages get republished and labels move. `WAITING` means stop the runtime cells — write the plan and report the block.

## 2. Run the T1 sweep (~61 cells)

`pilots/release-day/sweep-matrix.csv`, `tier == T1`: 51 wp-cli + 10 browser, across single-site, multisite-subsite, and multisite-network.

Order: CLI first (scriptable, parallel across fixtures), browser second (slow, and only the entities whose UI this release changes).

Per cell record `verdict` (`PASS` `FAIL` `PARTIAL` `BLOCKED` `SKIP` `INVALID`), `command`, `evidence_path`, `fixture_hash`, `cleanup_verified`. **These are smoke verdicts, not the finding vocabulary** — `CONFIRMED`/`REFUTED`/`INCONCLUSIVE` belong to chains and are reported separately.

Rules that hold all day: serialize mutations against one fixture · controls before cells · a control miscalibration makes the whole batch `INVALID` (preserve it, exclude it from counts) · verify cleanup · a harness fault is never a product failure.

## 3. Run the T1 upgrade ladder (9 cells)

`pilots/release-day/upgrade-ladder.csv`, `tier == T1`: 4.9, 5.0, 6.2, 6.3, 6.6, 6.9, 7.0.2 single-site, plus 4.9 and 7.0.2 multisite — all Core-updater lane.

Every ladder fixture pins **PHP 7.4** — the only band where the oldest source and the current target both run. This proves the *upgrade*, not the modern runtime; say so in the report.

Assert before and after: version, `db_version`, site inventory and flags, content counts, file tree versus a clean install of the same build, admin 200, front end 200, no new fatals.

## 4. Render the Slack checklist

```bash
python3 $WP_AUDIT_ROOT/scripts/render_slack_checklist.py --from-results --tier T1 \
  --source "<SOURCE BUILD>" --target "<TARGET BUILD>" --method "<Beta Tester plugin | WP-CLI | manual zip>" \
  --env "<single-site|multisite>" --php "<PHP>" --theme "<theme>" --browser "<browser>" \
  --site-mode <single|multisite|both>
```

64 checks across 9 sections (58 with `--site-mode single`). Emoji fill from recorded verdicts.

Before posting, verify: the header names the build **actually tested** (beta ≠ RC), the method line names the upgrade lane, invalid batches are counted and excluded, no local filesystem paths, no credentials, and any confidential finding is reduced to a bare acknowledgment.

**Claude does not post to Slack.** Output the text; the operator posts it. Making WordPress Slack is read-only under the standing source rules.

## 5. Thread the detail

Lead message = the checklist. Thread = one reply per non-PASS cell: mechanism → executed proof → consequence → evidence ceiling → rerun recipe. Size the consequence honestly — "243 files remain" is alarming; "integrity hygiene, not a functional break, not a vulnerability" is the same fact correctly sized.

## Done when

Every T1 cell has a verdict or an exact blocker; invalid batches excluded with diagnosis preserved; cleanup verified; the checklist renders and is handed to the operator; non-PASS cells are queued for `wp-release-followup`.
