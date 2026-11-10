---
name: wp-release-party
description: Run the release-day smoke sweep and produce the Slack-formatted test report. Trigger on "release party", "run the release day sweep", "wp release party", "test the RC and post results", "basic upgrades", "Slack checklist", when a watcher started in prep sees the build land, or during a live WordPress release party.
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

## 0. The first paste: grouped, green, fast

The output with a deadline is the [fast block](../../playbooks/slack-test-report-template.md#the-fast-block--post-this-first), handed over in chat within 5 minutes of `RELEASED`. The operator pastes it into Slack by hand, so:

- Plain text: no `*bold*`, no `•`, no code fence, no Markdown links.
- One check per line, ending in its Slack emoji code (`:white_check_mark:`, `:warning:`, `:x:`).
- Short plain-word group headers with a blank line between groups, in this order: Upgrades, Basics, Hosted, Multisite upgrade, Content and users, Media, Network admin, Not covered.
- Put each site mode's emoji on the line (`single :white_check_mark: main :white_check_mark: subsite :white_check_mark:`) instead of a parenthetical.
- Put the multisite denominator on its line ("2 of 5 sites upgraded, 3 held back").

Media is part of the CRUD level at every party. Run it on single site and on a subsite. "Supported" means four different things in core, so test one file per display path, not one per format. 7.2 Beta 5 lets an administrator upload 94 MIME types in 9 groups (`wp_get_ext_types()`), and only some of them display.

| Display path | Party sample | What to assert |
|---|---|---|
| Image with sub-sizes (GD: JPEG, PNG, GIF, WebP, AVIF) | all five | every registered sub-size exists; `srcset` and `sizes` on the front end |
| Image without sub-sizes on this stack (HEIC/HEIF, BMP, TIFF, ICO on GD) | HEIC | upload result (converted, original kept, or rejected), recorded per image stack |
| Audio with a player (`wp_get_audio_extensions()`: mp3, ogg, flac, m4a, wav) | mp3 | player markup renders and the source URL is unchanged |
| Video with a player (`wp_get_video_extensions()`: mp4, m4v, webm, ogv, flv) | mp4 | player markup renders and the source URL is unchanged |
| Audio or video without a player | mov | stored, and linked as a file |
| PDF | one PDF | File block inline preview; thumbnail when Imagick can render it |
| Upload only (documents, spreadsheets, presentations, text, archives) | docx | stored and linked; code types (css, htm, html, php, js) refused for a user without `unfiltered_html` |

Embed each sample the ways content really carries it:

- **Blocks:** Image, Gallery, Cover, Media & Text, Audio, Video, File, Featured Image, Site Logo, and an inline image in a paragraph.
- **Shortcodes,** for classic and migrated content: `[gallery]`, `[audio]`, `[video]`, `[playlist]`, `[caption]`, `[embed]`.
- **oEmbed:** a pasted URL and the Embed block variations.
- **Site surfaces:** site icon, custom header and background images, attachment pages.

On the front end, assert the output, not only that the page renders: `srcset` and `sizes`, `loading="lazy"`, and `fetchpriority="high"` on the first image.

Media library operations:

- upload, edit details (alt text, caption), search, grid and list views, delete
- the REST `/wp/v2/media` create, update and delete endpoints the editor uses
- library paging if the release changes it

Image editing: crop, rotate, flip and restore original, on GD and on Imagick when both are available.

Openverse (inserter, Media tab): first `curl` the API (`https://api.openverse.org/v1/images/?q=<term>`) and record the status code and time, then search in the editor. A 504 or a 10-second answer from the API is an Openverse outage, not a release result: at 7.2 Beta 5, 5 of 5 searches returned 504 and the editor code was unchanged. Mark the cell `BLOCKED(openverse-api)` and say so under "Not covered".

Every type, both image stacks: that sweep is `wp-release-followup` §3's job, not the party's.

In the paste these lines go in a Media group after Content and users, one site-mode emoji per line.


The paste holds green lines only. Non-green lines go below it, under "Held for follow-up", after the register check in "A second drop" step 3; they're handed to `wp-release-followup`, not pasted.

Don't wait for slow lanes: at 7.2 Beta 5 the hosted multisite upgrade took 6 minutes. Hand over the lines already proven, and send the rest as a second paste for the thread. Depth work (probes, diff reads, Site Health calls) waits until the first paste is out.

The shape, from 7.2 Beta 5's real results:

```
WordPress 7.2 Beta 5 · official zip, sha256 43ab43ff…a793 · db 64486

Upgrades
7.2 Beta 4 -> 7.2 Beta 5 via Beta Tester :white_check_mark:
7.2 Beta 4 -> 7.2 Beta 5 via WP-CLI :white_check_mark:
7.1.4 -> 7.2 Beta 5 via Core updater :white_check_mark:
Front end, login and REST API load :white_check_mark:
Security fixes from all 7 security releases present :white_check_mark:

Basics (single site)
Create Post :white_check_mark:
Create Page :white_check_mark:
Delete Post :white_check_mark:
Delete Page :white_check_mark:
Install and Uninstall Plugin :white_check_mark:
```

Second paste, for the thread:

```
Hosted
Single site, Beta 4 -> Beta 5 :white_check_mark:
Multisite, Beta 4 -> Beta 5, 3 of 3 sites upgraded :white_check_mark:

Multisite upgrade
Local network: 2 of 5 sites upgraded, 3 held back (archived, spam, deleted) as designed :white_check_mark:

Content and users
Categories: single :white_check_mark: main :white_check_mark: subsite :white_check_mark:
Tags: single :white_check_mark: main :white_check_mark: subsite :white_check_mark:
Custom post type and taxonomy: single :white_check_mark: main :white_check_mark: subsite :white_check_mark:
Comments: single :white_check_mark: main :white_check_mark: subsite :white_check_mark:
Users: single :white_check_mark: main :white_check_mark: subsite :white_check_mark:
Media upload and sub-sizes: single :white_check_mark: main :white_check_mark: subsite :white_check_mark:
Menus: single :white_check_mark: main :white_check_mark: subsite :white_check_mark:

Network admin
Sites: create, archive, spam, delete :white_check_mark:
Network users and super admin :white_check_mark:
Plugins: network and per-site activate, uninstall :white_check_mark:
Themes: network enable and disable :white_check_mark:

Not covered: Dashboard Updates click · Beta Tester on multisite · browser UI checks · local subsite page loads
```

Held for follow-up, shown in chat and not pasted: `WP_SECRETS_KEY absent on upgraded sites :warning:`. The 13 stale files were reported as "expected before RC1", and `/random/` got no line because the register marks it REFUTED.

## 1. Re-run the build-identity gate

```bash
scripts/rc_build_identity.sh <VERSION> <LABEL>
```

Even if prep passed it. Packages get republished and labels move. Run the script itself, not a HEAD request: a drop can show the root URL 404 and the downloads URL 200 for several minutes (7.2 Beta 4 did). Pin the URL the script prints as `RELEASED`; while it prints `WAITING`, poll the script, not curl. `WAITING` means stop the runtime cells — write the plan and report the block.

As a background watcher: `while bash scripts/rc_build_identity.sh <VERSION> <LABEL> >/dev/null; [ $? -eq 3 ]; do sleep 30; done`.

## 2. Run the T1 sweep (~74 cells)

`pilots/release-day/sweep-matrix.csv`, `tier == T1`: 51 wp-cli + 12 browser + 3 ecosystem + 4 accessibility + 4 i18n, across single-site, multisite-subsite, and multisite-network. The ecosystem block is [its own lane](../../method/ecosystem-compatibility-lane.md); the i18n cells are gated by `scripts/preflight-sensitivity.sh --gate=i18n` — on an en_US-only environment they are `BLOCKED(locale-en_US)`, never SKIP and never PASS.

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

`crud-suite.sh` observes but does not run these T1 cells: T1-06, 19, 20, 28, 32, 34, 37, 40, 41, 42, and it leaves T1-04/05 PARTIAL (restore not exercised). After the scripts, list T1 cells with an empty verdict and cover them with one probe script saved as `evidence/probes-<fixture>.sh`. Scheduled-post cells need a publish date more than 60 seconds ahead (use +150 s, sleep 165 s) or WordPress publishes the post at once.

Run each repo script with `</dev/null` when several start from one heredoc or `bash -s`: `users-pages-install.sh` and `wp-env run` read stdin and swallow the rest. A suite with no log file did not run; it did not fail.

Rules that hold all day: serialize mutations against one fixture · controls before cells · a control miscalibration makes the whole batch `INVALID` (preserve it, exclude it from counts) · verify cleanup · a harness fault is never a product failure.

Harness traps seen at 7.2 Beta 5:

- Log `wp`'s own exit code. `wp … | grep` reports grep's; use `${PIPESTATUS[0]}`, or run `wp` unpiped.
- WP-CLI 2.12 on PHP 8.5 prints `PHP Deprecated:` lines to stdout. Run `php -d display_errors=0 $(which wp)` rather than filtering them.
- Stop test servers by port (`lsof -ti tcp:<port> | xargs kill`), not with `pkill -f localhost:<port>`.
- `wp server` doesn't route subdirectory multisite, so a subsite page 404 there is `INVALID`. Check subsites with `wp --url=`, and log the `--url` on every command line.
- `Core_Upgrader` run from WP-CLI skips the database step (`update_core()` posts to `upgrade.php?step=upgrade_db` and nothing answers), so follow it with `wp core update-db`.
- In zsh, quote globs in flags (`--include='*.md'`) and don't run a command stored in a `$VAR`; use a function.

## 3. Run the T1 upgrade ladder (9 cells)

`pilots/release-day/upgrade-ladder.csv`, `tier == T1`: 4.9, 5.0, 6.2, 6.3, 6.6, 6.9, 7.0.2 single-site, plus 4.9 and 7.0.2 multisite — WP-CLI lane. `direct-jump-matrix.sh` runs `wp core update`. For the Core-updater lane, run the PHP `Core_Upgrader` class on a fresh source-version fixture and diff the tree against a clean install; this is how 10 stale files surfaced at 7.2 Beta 3. Record `updater_lane` per rung and say in the report which lane each rung used. Put current stable at the top of the ladder (7.1.4 for 7.2), not 7.0.2. The T1 subset's 6.3 and 6.6 are not in the series list above; use the latest patch of each (6.3.8, 6.6.5 this cycle).

The 4.9 multisite rung has no script: `multisite-suite.sh` hard-codes 7.0.2. WP-CLI on 4.9 stores subsite domains without the port, so every subsite 404s until `wp_blogs` is repaired. A rung that fails that way is INVALID, not FAIL.

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

**Claude does not post to Slack.** Output the text; the operator posts it. Making WordPress Slack is read-only under the standing source rules. Release-lead and core channels are read in the operator's signed-in Chrome, never through a connector. If a permalink drops the tab out of its group, open `app.slack.com/client/<team>/<channel>/thread/<channel>-<ts>` and use single calls, not `browser_batch`. Record each channel in the coverage register as read or unread.

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

## 6. Retro — the party told you about the tool too

Separate from the findings (which are about WordPress), spend two minutes on what the *tool*
did: did every cell run, did a script error, did a rendered count not match the matrix, did the
renderer's `--strict` flag an orphan? Fill in [`templates/skill-run-retro.md`](../../templates/skill-run-retro.md).
`WRONG`/`GAP` items become `PROPOSED` rows in your run root's `learning/` registers; the
shareable ones go to a [field report](../../CONTRIBUTING.md#suggesting-improvements-from-real-use).
Method: [`retro`](../../method/retro.md). Keep it apart from the finding vocabulary — a cell that
couldn't run is a tool `GAP`, not a WordPress `FAIL`.

## A second drop (Beta 4, RC2)

When a new build lands mid-cycle and an incremental update is asked for:

1. Run the identity gate, not the full sweep.
2. Upgrade each environment from the previous build and once from current stable by both lanes; record version, db revision and checksums. Stage this before the zip lands as one runner, in this order: Beta Tester upgrade on its fixture, the five basics (create and delete a post and a page, install and uninstall a plugin), the WP-CLI and Core-updater lanes, multisite, then the Media group. Start hosted lanes in the background; they never hold up the first paste.
3. Before re-testing an open finding, read its row in `pilots/filed-issues-register.csv` (verdict and notes) and the ticket's newest comments. Rerun the original reproduction from that row, including any step that heals it (for #64498, one logged-out `/wp-admin/` request). Never carry a claim forward from a previous drop's Slack draft. A finding the register marks REFUTED gets no line. `$_old_files` is updated in the run-up to RC1. Before RC1, files the Core updater leaves behind are expected: report them as "expected before RC1" (never ❌), keep the path list in the run's evidence, and draft no ticket or comment. From RC1 on, a removed path still missing from `$_old_files` is a finding; file it once, with the whole beta-cycle list.
4. Diff the two packages from fresh installs and report file counts.
5. Re-run CRUD once on a fresh install and diff the normalized output against the prior run.
6. Hand over §0's first paste, then a second paste for the slower lanes. Map results into matrix cells and re-render under `--strict` when time allows; until then, record "hand-built" in the run log, not in the paste.

Also on every drop: the SVN deletion diff (`svn diff --summarize` between the previous tag and the new source) beside the offline and tree-diff stale-file checks, a Beta Tester plugin upgrade (single and multisite subdirectory), a `core_updater.lock` check after each upgrade, a downgrade then upgrade sequence, and PHP 8.5 and MariaDB when the environment allows.

## Done when

Every T1 cell has a verdict or an exact blocker; invalid batches excluded with diagnosis preserved; cleanup verified; the checklist renders and is handed to the operator; non-PASS cells are queued for `wp-release-followup`; the retro is filed.
