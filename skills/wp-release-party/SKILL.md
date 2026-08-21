---
name: wp-release-party
description: Run the release-day smoke sweep and produce the Slack-formatted test report. Trigger on "release party", "run the release day sweep", "wp release party", "test the RC and post results", or during a live WordPress release party.
---

# wp-release-party

Phase 1. Breadth, fast: **does the release break the ordinary things people do?** Depth belongs to [`wp-release-followup`](../wp-release-followup/SKILL.md).

Assumes [`wp-release-prep`](../wp-release-prep/SKILL.md) has run — fixtures built, seeded, asserted, controls calibrated. If not, run that first; testing an unasserted fixture produces results nobody can trust.

**Where paths point:** run commands from a clone of `wp-release-audit-method` — script and CSV paths are repo-relative. Record verdicts in your run root's copies of the matrices (`$WP_AUDIT_ROOT/pilots/release-day/`), not the repo's blank ones. See [`pilots/README.md`](../../pilots/README.md).

| | |
|---|---|
| **Previous phase** | [`wp-release-prep`](../wp-release-prep/SKILL.md) — Act I, before the build drops |
| **Next phase** | [`wp-release-followup`](../wp-release-followup/SKILL.md) — Act III, depth |
| **Playbook** | [release-day sweep](../../playbooks/release-day-sweep-playbook.md) |
| **Report form** | [Slack test-report template](../../playbooks/slack-test-report-template.md) *(blank; filled example [below](#example-output))* |
| **Scripts** | [`crud-suite.sh`](../../scripts/crud-suite.sh) · [`users-pages-install.sh`](../../scripts/users-pages-install.sh) · [`multisite-suite.sh`](../../scripts/multisite-suite.sh) · [`direct-jump-matrix.sh`](../../scripts/direct-jump-matrix.sh) · [`stepped-chain.sh`](../../scripts/stepped-chain.sh) |
| **Why these rules** | [release-audit learning loop](../../method/release-audit-learning-loop.md) — the five laws and the calibrated detectors |

## 1. Re-run the build-identity gate

```bash
scripts/rc_build_identity.sh <VERSION> <LABEL>
```

Even if prep passed it. Packages get republished and labels move. `WAITING` means stop the runtime cells — write the plan and report the block.

## 2. Run the T1 sweep (~72 cells)

`pilots/release-day/sweep-matrix.csv`, `tier == T1`: 51 wp-cli + 10 browser + 3 ecosystem + 4 accessibility + 4 i18n, across single-site, multisite-subsite, and multisite-network. The ecosystem block is [its own lane](../../method/ecosystem-compatibility-lane.md); the i18n cells are gated by `scripts/preflight-sensitivity.sh --gate=i18n` — on an en_US-only environment they are `BLOCKED(locale-en_US)`, never SKIP and never PASS.

Order: CLI first (scriptable, parallel across fixtures), browser second (slow, and only the entities whose UI this release changes).

### What gets checked — entity × operation

Every row runs on **single-site** and, where the column is marked, on **multisite** (both subsite and network admin). ✅ = a script covers it; 👁 = browser check, no script yet.

| Entity | Create | Read / list | Update | Delete | Trash → restore | Multisite | Covered by |
|---|:--:|:--:|:--:|:--:|:--:|:--:|---|
| Posts | ✅ | ✅ | ✅ | ✅ | ✅ | subsite | `crud-suite.sh` |
| Pages | ✅ | ✅ | ✅ | ✅ | ✅ | subsite | `crud-suite.sh` · `users-pages-install.sh` |
| Custom post type | ✅ | ✅ | ✅ | ✅ | — | subsite | `crud-suite.sh` |
| Comments | ✅ | ✅ | ✅ | ✅ | — | subsite | `crud-suite.sh` |
| Categories & tags | ✅ | ✅ | ✅ | ✅ | — | subsite | `crud-suite.sh` |
| Custom taxonomy terms | ✅ | ✅ | ✅ | ✅ | — | subsite | `crud-suite.sh` |
| Media (JPEG/PNG/PDF/video) | ✅ | ✅ | ✅ | ✅ | — | subsite + quota | `crud-suite.sh` · `multisite-11.sh` |
| Media (HEIC/AVIF/WebP) | 👁 | 👁 | 👁 | 👁 | — | — | browser |
| Users | ✅ | ✅ | ✅ | ✅ | — | network + per-site roles | `users-pages-install.sh` · `multisite-suite.sh` |
| Roles & capabilities | — | ✅ | ✅ | — | — | super-admin asymmetry | `multisite-11.sh` |
| Themes | ✅ install | ✅ | ✅ update | ✅ | — | network activate | `crud-suite.sh` · `multisite-suite.sh` |
| Plugins | ✅ install | ✅ | ✅ update | ✅ | — | network + site activate | `crud-suite.sh` · `multisite-suite.sh` |
| Plugin dependencies | 👁 | 👁 | — | — | — | network vs site scope | browser + REST |
| **Nav menus** (classic + Navigation block) | 👁 | 👁 | 👁 | 👁 | — | per-site | **browser only — no script yet** |
| Widgets screen | 👁 | 👁 | 👁 | 👁 | — | — | browser |
| Templates & template parts | 👁 | 👁 | 👁 | 👁 revert | — | — | browser |
| Global Styles + revisions | — | 👁 | 👁 | 👁 restore | — | — | browser |
| Settings (General/Reading/Writing/Discussion) | — | ✅ | ✅ | — | — | network settings | `crud-suite.sh` |
| Permalinks + front-end routing | — | ✅ | ✅ | — | — | subsite | `crud-suite.sh` |
| Sites (network) | ✅ | ✅ | ✅ | ✅ | archive/spam/delete | network only | `multisite-11.sh` |

Also per site mode: password-protected posts and password-protected sites, scheduled-post publishing, WXR export/import round-trip, Site Health, and application passwords.

> **Nav menus are the known coverage hole.** They're on the browser checklist but no script asserts them. A patch adding `wp menu` coverage to `crud-suite.sh` is a genuinely useful contribution.

### Site modes and surfaces

| Axis | Values |
|---|---|
| Site mode | single-site · multisite **subdirectory** · multisite **subdomain** · network admin |
| Surface | WP-CLI · browser · REST API · Docker/wp-env |
| Lane | fresh install · upgrade · everyday use |
| Updater | Core's own updater · WP-CLI updater *(keep separate — they produce different trees)* |

When two surfaces disagree about the same state, that **is** the finding. Record both; don't pick a winner.

### Versions to test upgrades from

Each hop lands on the **target build**. Two shapes, and they answer different questions:

| Script | Shape | Question |
|---|---|---|
| `direct-jump-matrix.sh` | Latest of each series → target, **fresh install per hop** | Can someone on an old version jump straight to this release? |
| `stepped-chain.sh` | 4.9 → 5.0 → … → target, **one database carried through** | Does data survive every intermediate `db_version` migration? |

Series covered: **4.9.29 · 5.0.25 · 5.2.24 · 5.5.18 · 5.9.13 · 6.0.12 · 6.2.9 · 6.5.8 · 6.8.6 · 6.9.5 · 7.0.2**

The T1 ladder is the 9-cell subset: 4.9, 5.0, 6.2, 6.3, 6.6, 6.9, 7.0.2 single-site, plus 4.9 and 7.0.2 multisite. Run the full list in `wp-release-followup` if the party surfaces anything on the ladder.

Refresh the tail of that list each cycle — the newest entry should be the **current stable**, which is the version most sites will actually upgrade from.

Per cell record `verdict` (`PASS` `FAIL` `PARTIAL` `BLOCKED` `SKIP` `INVALID`), `command`, `evidence_path`, `fixture_hash`, `cleanup_verified`. **These are smoke verdicts, not the finding vocabulary** — `CONFIRMED`/`REFUTED`/`INCONCLUSIVE` belong to chains and are reported separately.

Rules that hold all day: serialize mutations against one fixture · controls before cells · a control miscalibration makes the whole batch `INVALID` (preserve it, exclude it from counts) · verify cleanup · a harness fault is never a product failure.

## 3. Run the T1 upgrade ladder (9 cells)

`pilots/release-day/upgrade-ladder.csv`, `tier == T1`: 4.9, 5.0, 6.2, 6.3, 6.6, 6.9, 7.0.2 single-site, plus 4.9 and 7.0.2 multisite — all Core-updater lane.

Every ladder fixture pins **PHP 7.4** — the only band where the oldest source and the current target both run. This proves the *upgrade*, not the modern runtime; say so in the report.

Assert before and after: version, `db_version`, site inventory and flags, content counts, file tree versus a clean install of the same build, admin 200, front end 200, no new fatals.

## 4. Render the Slack checklist

```bash
python3 scripts/render_slack_checklist.py --from-results --tier T1 \
  --source "<SOURCE BUILD>" --target "<TARGET BUILD>" --method "<Beta Tester plugin | WP-CLI | manual zip>" \
  --env "<single-site|multisite>" --php "<PHP>" --theme "<theme>" --browser "<browser>" \
  --site-mode <single|multisite|both>
```

75 checks across 12 sections (69 with `--site-mode single`). Emoji fill from recorded verdicts.

Before posting, verify: the header names the build **actually tested** (beta ≠ RC), the method line names the upgrade lane, invalid batches are counted and excluded, no local filesystem paths, no credentials, and any confidential finding is reduced to a bare acknowledgment.

**Claude does not post to Slack.** Output the text; the operator posts it. Making WordPress Slack is read-only under the standing source rules.

### Example output

The **blank form** — all 75 checks across 12 sections, unmarked — lives in
[`playbooks/slack-test-report-template.md`](../../playbooks/slack-test-report-template.md).
Copy from there; the version below is the same form *filled in*, to show what a finished
report looks like.

An abridged real-shape report. Note what it does *and doesn't* claim.

```
*WordPress 7.1-RC1* — upgraded from *7.0.2* via *Beta Tester plugin (Core updater)*

Environment: multisite (subdirectory, 5 sites) · PHP 8.4 · Twenty Twenty-Five · Chrome 141
Result: 54 passed · 2 failed · 1 partial · 2 blocked · 5 not tested

*Upgrade*
• Upgrade completed without error :white_check_mark:
• Version and db_version correct after upgrade :white_check_mark:
• No PHP fatals or new deprecations in debug.log :white_check_mark:
• wp-admin loads (dashboard + all core screens) :white_check_mark:
• Front end loads :white_check_mark:
• File tree matches a clean install of the same build :x:
• Rollback / reactivate previous version :heavy_minus_sign:

*Content*
• Create, update, and delete Posts :white_check_mark:
• Create, update, and delete Pages :white_check_mark:
• Trash and restore Posts :white_check_mark:
• Post revisions save and restore :white_check_mark:
• Create, update, and delete Custom Post Types :white_check_mark:
• Add and delete Comments on Posts :white_check_mark:
• Add and remove Categories and Tags :white_check_mark:
• Scheduled post publishes :white_check_mark:

*Media*
• Upload, edit, and delete media (JPEG/PNG) :white_check_mark:
• Upload HEIC / AVIF / WebP :no_entry_sign:
• Media Editor Modal: crop, rotate, flip :white_check_mark:

*Themes and Site Editor*
• Switch between block themes :white_check_mark:
• Classic and Navigation-block menus :white_check_mark:
• Global Styles: edit and restore a revision :warning:

*Plugins*
• Install plugin :white_check_mark:
• Activate, deactivate, and delete plugin :white_check_mark:
• Plugin dependencies (Requires Plugins header) :x:

*Users and roles*
• Create, update, and delete Users :white_check_mark:
• Change user role :white_check_mark:
• Application passwords :white_check_mark:

*Multisite*
• Network upgrade completes; report the full site count :white_check_mark:
• Held-back sites report correctly (archived/spam/deleted) :white_check_mark:
• Network-activate and site-activate a plugin :x:

:white_check_mark: pass · :x: fail · :warning: partial or unexpected · :no_entry_sign: blocked · :heavy_minus_sign: not tested · :recycle: invalid batch, rerun needed

Upgrade lane note: Core's own updater only. WP-CLI updater not run this pass —
it cleans up files Core leaves behind, so treat the file-tree result as
Core-lane-specific.

Findings and evidence in thread. One batch (HEIC/AVIF) invalidated — the fixture
had no HEIC support compiled in, so those cells prove nothing and are excluded
from the counts above.
```

**Then the thread.** One reply per non-PASS cell — mechanism → executed proof → consequence → evidence ceiling → rerun recipe:

```
:x: *File tree matches a clean install* — 243 extra files remain

Mechanism: files removed from core in this release aren't declared in
$_old_files, so the Core updater never deletes them. WP-CLI's updater cleans
them up and prints "243 files cleaned up" — Core's path doesn't.

Proof: post-upgrade tree vs a clean install of the same build →
243 extra files under wp-includes/images/icon-library/, 0 missing.
Reproduced on 7.0.2 → RC1. Clean-vs-clean control: 0 diff.

Consequence: integrity hygiene. Not a functional break, not a vulnerability —
stale files sit unused on disk. Worth fixing before GA so checksum tools and
security scanners don't flag every upgraded site.

Evidence ceiling: proven on the Core-updater lane, single + multisite,
PHP 8.4. Not tested: manual-zip lane. Would change my verdict: the files
appearing in $_old_files in a later RC.

Rerun: bash scripts/fast-triage.sh <target.zip> <prior.zip>
```

Two things that example does deliberately: it **sizes the consequence down** ("integrity hygiene, not a vulnerability") rather than up, and it states what would *change* the verdict. Both make the report easier to act on and harder to dismiss.

## 5. Thread the detail

Lead message = the checklist. Thread = one reply per non-PASS cell: mechanism → executed proof → consequence → evidence ceiling → rerun recipe. Size the consequence honestly — "243 files remain" is alarming; "integrity hygiene, not a functional break, not a vulnerability" is the same fact correctly sized.

## Done when

Every T1 cell has a verdict or an exact blocker; invalid batches excluded with diagnosis preserved; cleanup verified; the checklist renders and is handed to the operator; non-PASS cells are queued for `wp-release-followup`.
