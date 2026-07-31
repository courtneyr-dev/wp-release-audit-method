---
name: wp-release-prep
description: Prepare WordPress Studio test environments before a release party — build-identity gate, fixture creation for single/multisite/PHP variants, theme-test-data import, state assertions, and control calibration. Trigger on "prep for the release party", "get environments ready", "wp release prep", "set up test sites for the beta/RC", or the day before a scheduled WordPress release.
---

# wp-release-prep

Phase 0 of release testing. Ends with fixtures that are **built, seeded, asserted, and calibrated** so the release party is spent testing, not provisioning.

Never do this against production, WordPress.org infrastructure, third-party sites, or plugins or themes the operator doesn't own. All Studio sites use the `codex-` or `rel-` prefix. Read-only for external WordPress.org, Trac, and GitHub access.

## 1. Build-identity gate — always first

```bash
$WP_AUDIT_ROOT/scripts/rc_build_identity.sh <VERSION> <LABEL>
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
| prior-beta → target upgrade source | prior-beta lane |
| clean install of target | the comparison baseline for file-tree diffs |

Add from `methods/test-and-fixture-registry.csv` when the release calls for it: PHP-matched pairs (FX-10..FX-14), the large network (FX-15), a classic-theme site, a block-theme site.

**Keep Core-updater and WP-CLI-updater lanes separate.** They produce different file trees — that's how the 243-stale-file finding surfaced.

## 3. Seed content — theme-test-data

Import the canonical corpus into every content fixture:

```bash
curl -sL -o /tmp/theme-unit-test-data.xml \
  https://raw.githubusercontent.com/WordPress/theme-test-data/master/themeunittestdata.wordpress.xml
studio-cli.sh wp plugin install wordpress-importer --activate
studio-cli.sh wp import /tmp/theme-unit-test-data.xml --authors=create
```

It covers markup edge cases, nested/long menus, embeds, image alignments, unicode and RTL strings, sticky/password/scheduled posts, and deep page hierarchies — the shapes hand-made content never has.

Seed **beyond** it for this method:
- a custom post type and custom taxonomy (mu-plugin fixture)
- a plugin with a `Requires Plugins` dependency, plus its dependency
- a second user at a lower role, for capability and per-user-preference cells
- media in each format the release touches (JPEG/PNG/HEIC/AVIF/WebP)
- attachments at a boundary count if the release changes library paging

## 4. Assert state before declaring ready

Per fixture, record and keep: WordPress version, `db_version`, PHP version, image stack (GD/Imagick, HEIC/AVIF support), site mode, full site inventory with status flags, active plugins, active theme, user count, content counts, fixture hash.

```bash
$WP_AUDIT_ROOT/scripts/assert_multisite_denominator.sh   # every multisite fixture
```

Harness-health precheck first — daemon, socket, container, ownership. A harness fault is an `INVALID` batch, never a product result.

## 5. Calibrate controls

Before the party, prove the instruments work:
- `scripts/stale_file_check.py <prior_tree> <target_tree>` — offline, predicts the upgrade answer
- a native-control keyboard check if any accessibility cell is planned (it must PASS before product results count)
- one positive and one negative control per planned batch

## 6. Regenerate the matrices

```bash
python3 $WP_AUDIT_ROOT/scripts/build_release_day_matrices.py
```

Re-derive `BROWSER_T1` in that script from **this** release's change ledger — the entities whose UI the release actually touches. It's the one input that must not carry forward.

## Done when

Every fixture has a recorded, passed state assertion for this release; both controls calibrated; matrices regenerated; build manifest pinned or honestly marked `WAITING`. Hand off to `wp-release-party`.
