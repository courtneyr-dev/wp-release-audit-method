---
name: wp-release-prep
description: Prepare WordPress Studio test environments before a release party, through control calibration. Trigger on "prep for the release party", "get environments ready", "wp release prep", "set up test sites for the beta/RC", or the day before a scheduled WordPress release.
---

# wp-release-prep

Phase 0 of release testing. Ends with fixtures that are **built, seeded, asserted, and calibrated** so the release party is spent testing, not provisioning.

Never do this against production, WordPress.org infrastructure, third-party sites, or plugins or themes the operator doesn't own. All Studio sites use the `codex-` or `rel-` prefix. Read-only for external WordPress.org, Trac, and GitHub access.

**Where paths point:** run commands from a clone of `wp-release-audit-method` — script and CSV paths are repo-relative. The repo carries the schemas and blank matrices; verdicts and evidence go in your run root's copies (`$WP_AUDIT_ROOT`), never the repo's. See [`pilots/README.md`](../../pilots/README.md).

## 0. Scan the ecosystem for what changed since last cycle

Before building anything, run the ecosystem-signals scan — the change ledger that selects this
release's browser cells *is* an ecosystem-signals output, and the WP Rocket lane exists because
someone read an outage post-mortem, not because a cell failed.

```bash
export WP_AUDIT_SIGNALS=<your ecosystem notes: a file or folder of .md/.txt>
export WP_AUDIT_FLEET="<your fleet's plugin slugs, comma-separated>"
bash scripts/ecosystem-signals.sh --version <this release>
```

Each hit is a candidate, not a finding — adjudicate against the primary source before it
becomes a cell, a lane, or a register row. Method: [`ecosystem-signals`](../../method/ecosystem-signals.md).
With no signals source set it prints the source types to watch by hand.

## 1. Build-identity gate — always first

```bash
scripts/rc_build_identity.sh <VERSION> <LABEL>
```

Exit 0 = RELEASED, proceed. Exit 3 = `WAITING`, **stop**. Never substitute a beta, trunk, nightly, or prior RC for a build that doesn't exist. If WAITING, still build fixtures — they're reusable — but mark every runtime cell `WAITING-FOR-<LABEL>` and say so in the handoff.

When the target exists, pin it before touching a fixture: package URL, sha256/md5, `$wp_version`, `$wp_db_version`, Gutenberg version included, Field Guide URL. Record in `pilots/<release>/build-manifest.json`.

## 2. Fixtures to build

Studio CLI: `/Applications/Studio.app/Contents/Resources/bin/studio-cli.sh` — run `wp` commands **from the site directory**.

Minimum set for a release party:

| Fixture | Purpose |
|---|---|
| single-site, current PHP | the T1 smoke lane |
| multisite (5 sites: normal, archived, spam, deleted, plus main) | held-back-site denominator, network upgrade |
| prior-stable → target upgrade source | Core-updater lane |
| clean install of target | the comparison baseline for file-tree diffs |
| *conditional:* prior-beta → target | prior-beta lane — **build it the day the second prerelease drops**, the only window it can exist. It went unbuilt for the whole 7.1 cycle and its C-02 cells sat BLOCKED; outside the window record `BLOCKED(no-prior-beta)`, not a prep gap |

Add from `methods/test-and-fixture-registry.csv` when the release calls for it: PHP-matched pairs (FX-10..FX-14), the large network (FX-15), a classic-theme site, a block-theme site.

**Keep Core-updater and WP-CLI-updater lanes separate.** They produce different file trees — that's how the 243-stale-file finding surfaced.

## 3. Seed content — the canonical corpora

Import both into every content fixture. The second is derived from the first, so the overlap
deduplicates on import; the items that don't are the point.

```bash
studio-cli.sh wp plugin install wordpress-importer --activate

curl -sL -o /tmp/theme-test-data.xml \
  https://raw.githubusercontent.com/WordPress/theme-test-data/master/themeunittestdata.wordpress.xml
studio-cli.sh wp import /tmp/theme-test-data.xml --authors=create

curl -sL -o /tmp/a11y-test-data.xml \
  https://raw.githubusercontent.com/wpaccessibility/a11y-theme-unit-test/master/a11y-theme-unit-test-data.xml
studio-cli.sh wp import /tmp/a11y-test-data.xml --authors=create
```

It covers markup edge cases, nested/long menus, embeds, image alignments, unicode and RTL strings, sticky/password/scheduled posts, and deep page hierarchies — the shapes hand-made content never has.

Seed **beyond** it for this method:
- a custom post type and custom taxonomy (mu-plugin fixture)
- a plugin with a `Requires Plugins` dependency, plus its dependency
- a second user at a lower role, for capability and per-user-preference cells
- media in each format the release touches (JPEG/PNG/HEIC/AVIF/WebP)
- attachments at a boundary count if the release changes library paging

## 4. Assert state before declaring ready

Per fixture, record and keep: WordPress version, `db_version`, PHP version, image stack (GD (`php-gd`) / Imagick, HEIC/AVIF support), site mode, full site inventory with status flags, active plugins, active theme, user count, content counts, fixture hash.

```bash
scripts/assert_multisite_denominator.sh <site-path>   # every multisite fixture
```

Harness-health precheck first — daemon, socket, container, ownership. A harness fault is an `INVALID` batch, never a product result.

## 5. Read the release's own declared regressions

Release announcements now document known-bad shipped defaults with their opt-outs — 7.1
shipped media-library infinite scroll while calling it a known inaccessible pattern, with a
Profile toggle, the `media_library_infinite_scrolling` filter, and a third-party plugin as
the outs ([the worked example](../../accessibility/README.md#read-the-release-notes-for-the-releases-own-declared-regressions)).
Before the drop: read the announcement and Field Guide for anything the release itself
declares as a regression or known-bad default, and give each one a fleet-wide policy
decision — accept, filter off, or hold. Record the decision; the matching checklist line
exists so it leaves a trace.

## 6. Calibrate controls

Before the party, prove the instruments work:
- `scripts/stale_file_check.py <prior_tree> <target_tree>` — offline, predicts the upgrade answer
- a native-control keyboard check if any accessibility cell is planned (it must PASS before product results count)
- one positive and one negative control per planned batch

## 7. Regenerate the matrices

```bash
python3 scripts/build_release_day_matrices.py --browser-t1 <this release's ledger entities>
```

Re-derive `BROWSER_T1` in that script from **this** release's change ledger — the entities whose UI the release actually touches. It's the one input that must not carry forward.

## 8. Retro — before you hand off

Two minutes on the tool, not on WordPress: did the fixtures build as documented, did any
instruction assume a driver you weren't on, did a script error? Fill in
[`templates/skill-run-retro.md`](../../templates/skill-run-retro.md); durable tool problems
become `PROPOSED` rows in your run root's `learning/` registers, and anything worth the next
stranger's time goes to a [field report](../../CONTRIBUTING.md#suggesting-improvements-from-real-use).
Method: [`retro`](../../method/retro.md). A WordPress bug is a finding, not a retro item.

## Done when

Every fixture has a recorded, passed state assertion for this release; both controls calibrated; matrices regenerated; build manifest pinned or honestly marked `WAITING`; the retro is filed. Hand off to `wp-release-party`.
