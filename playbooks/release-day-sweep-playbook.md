---
title: "Release-day sweep playbook — Phase 1 breadth before Phase 2 depth"
type: playbook
status: active
created: '2026-07-31'
updated: '2026-08-05'
source_run: "$WP_AUDIT_ROOT/ (matrices, scripts, evidence remain there)"
tags:
  - wordpress
  - wp-audit
  - release-audit
  - smoke-testing
  - upgrade-path
  - multisite
related:
  - '*../index*'
  - '[future-release-audit-template](../playbooks/future-release-audit-template.md)'
  - '[security-release-audit-playbook](../playbooks/security-release-audit-playbook.md)'
  - '*../cross-release-feature-chains*'
---

# Release-day sweep playbook

> **Runs as:** [`wp-release-party`](../skills/wp-release-party/SKILL.md) (Act II). Depth afterwards is
> [`wp-release-followup`](../skills/wp-release-followup/SKILL.md), whose
> [method index](../skills/wp-release-followup/SKILL.md#where-this-fits--the-whole-method-in-one-screen)
> maps every playbook and method doc. Report form:
> [Slack template](slack-test-report-template.md).

Two testing times with different jobs. **Phase 1 (release day) buys breadth fast: does the release break the ordinary things people do?** **Phase 2 (comprehensive) buys depth: every variation, driven by the chain register.** Phase 1's findings select Phase 2's targets — running them in the other order wastes the deep pass on surfaces that were never at risk.

Matrices and scripts live in the run root: `pilots/release-day/sweep-matrix.csv`, `pilots/release-day/upgrade-ladder.csv`, `scripts/build_release_day_matrices.py` (deterministic regenerator — re-run it per release rather than editing the CSVs by hand).

## Phase 1A — CRUD sweep

**Question:** can you still add, change, and remove the things a site is made of, through both interfaces, in both environments?

**Shape:** 19 entities × 7 operations × {wp-cli, browser} × {single, multisite-network, multisite-subsite}, with impossible combinations pruned.

Entities: post · page · custom post type · category · tag · custom taxonomy term · classic nav menu · Navigation-block menu · media attachment · user · comment · plugin · theme · block widget · reusable block/pattern · template & template part · option/setting · site (multisite) · role/capability.

Operations: create · read-list · update · delete · trash-restore · bulk · revision-restore (the last two only where the entity has that lifecycle).

**The interface asymmetry is the whole trick.** WP-CLI runs the *full* matrix — it is scriptable, fast, and gives breadth. The browser lane cannot mirror it on release day and should not try. Browser cells are selected by **this release's change ledger**: any entity whose `affected_surfaces` the release touches stays tier 1; everything else demotes. For the 7.1 cycle that set is media, plugins, posts, Navigation-block menus, and themes — because 7.1 changes the upload path, the library UI, the plugin-card buttons, the editor chrome, and the iframe. **Re-derive that set every release**; it is the one part of the matrix that must not be copied forward.

**Why both interfaces at all:** the beta4 plugin-dependency defect is exactly the class that only appears in one of them — `is_plugin_active()` returned true while the plugin-card button rendered disabled. A CLI-only sweep sees a healthy site; a browser-only sweep sees a broken button with no explanation.

**Why multisite is three environments, not two:** network-admin and subsite contexts resolve capabilities, plugin activation scope, and site status differently. Collapsing them hides exactly the defects the 7.1 cycle already produced.

## Phase 1B — Upgrade ladder

**Question:** does a site that has been alive for years survive the jump?

**Shape:** 22 source versions (4.9, 5.0–5.9, 6.0–6.9, 7.0.2) × {single, multisite} × {Core updater, WP-CLI updater} = 88 cells.

### The PHP constraint that shapes everything

WordPress 4.9 does not run on PHP 8.x. The target requires PHP ≥ 7.4 (`wp70-php-74-minimum`). **PHP 7.4 is the only band where both ends of the ladder run**, so every ladder fixture pins 7.4. Two consequences worth stating plainly:

1. A ladder run on 7.4 tests the *upgrade*, not the *modern runtime*. Sites that jump from 4.9 to current on PHP 8.3 are doing something this ladder does not cover — that is the `ENV` lens, and it belongs to Phase 2.
2. A realistic migration bumps PHP mid-ladder. That sequence — old WP on old PHP → upgrade WP → upgrade PHP — is its own scenario and deserves cells rather than an assumption.

PHP floors crossed by the ladder, from the feature ledger: **6.3** drops PHP 5.x, **6.6** drops 7.0/7.1, **7.0** raises the minimum to 7.4.

### Tiering — release day cannot run 88 cells

- **T1 (release day, ~10 cells):** the oldest source (4.9), the block-editor boundary (5.0), every PHP-floor boundary and its predecessor (6.2→6.3, 6.5→6.6, 6.9→7.0), and current stable (7.0.2) — single-site on the Core updater, plus 4.9 and 7.0.2 on multisite.
- **T2:** remaining majors, single-site, Core updater.
- **T3:** the entire WP-CLI updater lane, and multisite for the remaining sources.

**5.0 is the most interesting single cell.** It is the classic→block editor boundary, so content authored in 4.9 crosses a serialization change on the way to the target. That is where the `NEGSPACE` and `SERIAL` lenses will point in Phase 2.

**Keep the two updater lanes separate and never let one stand in for the other.** The beta4 finding depends on it: Core's updater left 243 removed files behind while WP-CLI's cleaned them. A ladder run only through WP-CLI would have reported a clean tree.

### The direct-jump matrix — every branch, one hop each, cheap

The seeded ladder is expensive per cell (fixtures with real content, asserted before-states). The **direct-jump matrix** (`scripts/direct-jump-matrix.sh`) buys the complementary breadth: a fresh install of the **latest patch of every release series**, one `wp core update` straight to the target, then five assertions — started from the version asked for, ended on the target, front and login answer 200, no fatal on the front end, a canary post survives. Roughly two minutes per rung, so all ~21 branches fit in an under-an-hour background run on 7.1-RC1 day, and it proved the one-hop path from every series including 4.9 (db 38590 → 61833 in one migration).

Three operational notes from that run:

- The script derives the expected post-upgrade version from the target zip's filename. The earlier version hard-coded it, which silently fails **every** rung the first time the target changes.
- Branch list comes from `api.wordpress.org/core/stable-check/1.0/` (max patch per series). Re-derive per release; override with `VERSIONS="..."` to rerun a subset.
- A rung that fails **before** the upgrade runs is a harness result, not a product one. The tell is a blank pre-upgrade `db_version` alongside a front-end 500: the install itself never came up. See the container-extraction trap below.

### Fixture traps proven on 7.1-RC1 day

**Parked fixtures self-upgrade.** Fresh installs since WordPress 5.6 default `auto_update_core_major` to enabled, so an old-version fixture left running quietly updates itself to current stable — two ladder cells were found sitting on 7.0.2 with their old `db_version` gone, which destroys the cell (the schema already migrated, so the old→target migration can no longer be proven). Pin `WP_AUTO_UPDATE_CORE=false` in the fixture config at build time, and **re-assert the before-state at run start, not fixture-build time** — the assertion that matters is the one taken the moment before the upgrade.

**Container tar truncates long paths.** `wp core download` inside a container can truncate tar entries whose path exceeds 100 characters (the classic tar name-field limit). Concrete case: Twenty Twenty-Two 1.x pattern filenames — `inc/patterns/header-text-only-with-tagline-black-background.php` lands with the name cut mid-word, `block-patterns.php` fatals, and the install 500s before any upgrade runs. It hits exactly the 5.9/6.0 rungs (TT2 1.x ships the long names; 6.1+ shortened them; pre-5.9 has no TT2), which reads like a version-specific upgrade bug and is not one. Fix: extract the release zip **on the host** into the mounted docroot, then `wp core install` in the container.

### When the target ships no schema change

If the target's `$wp_db_version` equals current stable's (7.1-RC1 shipped 61833, identical to 7.0.2), every "db_version advanced" assertion is wrong as written. Flip them deliberately rather than skipping them: same-branch cells assert **unchanged, as shipped**; older-source cells still assert the migration to the shipped value. On multisite, "eligible sites advanced" becomes vacuous — assert instead that the network updater **processed exactly the eligible count** and that held-back flags did not move. The updater's success line ("upgraded on 2/2 sites" on a 5-site network) is easiest to misread in precisely this case, so state the denominator in the report.

## Execution discipline (both phases)

Unchanged from the standing method, and non-negotiable:

1. **Build-identity gate first.** `scripts/rc_build_identity.sh $VERSION $LABEL`. WAITING means stop; never substitute a beta, trunk, nightly, or prior RC. Package URL lanes differ by release type — stable publishes at `downloads.wordpress.org/release/`, betas and RCs at the `wordpress.org` root — and a gate that checks only one lane reports WAITING while the build is live (this cost real time on 7.1-RC1 day; the script now checks both). When testing a locally supplied zip, its sha256 must match the canonical package before any cell counts.
2. **Assert fixture state and denominators before reading results** — version, `db_version`, site inventory with status flags, active plugins, theme, content counts, fixture hash. `scripts/assert_multisite_denominator.sh` for every multisite cell.
3. **Positive and negative control per batch.** Either miscalibrates → the batch is `INVALID`, excluded from counts, diagnosis preserved.
4. **Serialize mutations** against one fixture; verify cleanup; rerun valid batches from the restored baseline and require matching observations.
5. **Verdicts:** `CONFIRMED` `REFUTED` `INCONCLUSIVE` `BLOCKED` `INVALID`. Nothing else.
6. **Harness-health precheck** before each batch. A harness fault is never a product result.

## Release-day running order

| Slot | Work | Gate to proceed |
|---|---|---|
| 1 | Build-identity gate | RELEASED, package hash pinned |
| 2 | Fixture build + state assertions, all environments | every fixture prints a passed assertion |
| 3 | CLI sweep, T1 → T2 (scripted, parallel across environments) | controls calibrated |
| 4 | Upgrade ladder T1 (~10 cells, serialized) | each cell asserts pre and post |
| 5 | Browser sweep, T1 only (ledger-selected) | native-control calibration if any keyboard cell |
| 6 | Triage: verdict counts, invalid batches excluded, blockers with exact closing conditions | — |
| 7 | Share findings → they select Phase 2 targets | — |

T2/T3 cells run asynchronously after the release-day window; they are not gates on reporting.

## Where PHP versions belong in Phase 2

**PHP is an axis, not a chain.** Multiplying all 25 lenses by 4 PHP versions and 2 site modes is 200 cells of mostly-noise: rollback, removed-attribute, privacy-exporter, plugin-composition, and accessibility questions do not change answer by runtime. Placing PHP at the fixture layer and multiplying only where the runtime is load-bearing gives **~25 added cells instead of 200**. The per-chain decision is recorded in `pilots/release-day/php-axis.csv`.

### Three placements

**1. A standing PHP-compatibility matrix, once per release.** Install the target on each supported PHP and assert it runs clean — no fatals, and a deprecation log that is empty or explainable — on single-site and multisite. This is a release-health check, not a chain, and it is the cheapest PHP work available.

**2. A multiplier on seven named chains.** These are the ones where the runtime genuinely changes the answer:

| Chain | Why PHP is load-bearing | Versions |
|---|---|---|
| `X-ERR-01` ERRORPATH | The server fallback **is** the PHP image stack. MF-1 was exactly this: PHP 8.4 without Imagick → GD (`php-gd`) → no HEIC | 7.4, 8.1, 8.4 |
| `X-QUAL-01` QUALITY | Encoded subsize quality depends on the GD/Imagick build compiled against that PHP | 7.4, 8.1, 8.4 |
| `X-SERIAL-01` SERIAL | serialize/unserialize edge cases plus `wp69-utf8`'s PHP fallback pipeline; byte-identity is the assertion | 7.4, 8.1, 8.2, 8.4 |
| `X-HASH-01` HASH | `password_hash()` algorithm availability and cost defaults differ; a hash written under one runtime must verify under another | 7.4, 8.1, 8.4 |
| `X-BOUND-01` BOUNDARY | **PHP 8.0 made sorts stable** — term, menu, and query ordering can differ 7.4 vs 8.x exactly at boundary counts | 7.4, 8.1 |
| `X-TIME-01` TIME | Date/DST arithmetic shifted across 8.x; expiry and cron windows are time math | 7.4, 8.4 |
| `X-HOP-01` MULTIHOP | Migrations run under whatever runtime is present | 7.4, 8.4 |

**3. Site mode × PHP, where they genuinely interact.** For most chains, multisite adds nothing to the PHP question. The exception is **the network upgrade loop**: multisite iterates over every site in one request path, so `max_execution_time`, `memory_limit`, and opcache behavior become failure modes that single-site never reaches. That is why `X-HOP-01` carries multisite and why fixture `FX-15` exists — a 200+ site network specifically to expose timeout and memory failure during the loop. `X-ERR-01` and `X-HASH-01` also take multisite because network-scope users and per-site image handling differ.

### Version selection — boundaries, not "latest"

Pick versions because each one *changes behavior*, not to cover a range: **7.4** is the target's floor and the only band the full upgrade ladder runs in; **8.0** promoted many warnings to fatals and made sorts stable; **8.1** deprecated passing null to non-nullable internals — a large WordPress surface; **8.2** deprecated dynamic properties and `utf8_encode`/`decode`; **8.4** is current. A defensible minimum is **7.4, 8.1, 8.4**, adding 8.2 when the serialization lens runs.

### The fixture requirement, and the trap

PHP must be the **only** variable in any comparison. Fixtures `FX-10` through `FX-15` are PHP-matched pairs per site mode for exactly this reason. Do **not** compare the existing PHP 7.4 multisite fixture against the PHP 8.4 single-site fixture — that confounds runtime with site mode and produces a confident, worthless result. This caution is already carried on `X-ENV-01` in the chain register.

**One honest limit:** the Phase 1 upgrade ladder pins PHP 7.4 because that is the only band where 4.9 and the target both run. So the ladder proves the *upgrade*, never the *modern runtime*. Sites jumping from an old release to current on PHP 8.3 are covered only here in Phase 2, and the mid-ladder PHP bump — upgrade WordPress, then upgrade PHP — deserves its own cells rather than an assumption.

## How Phase 1 feeds Phase 2

Phase 1 answers *what broke*. Phase 2 answers *why, and what else shares that mechanism*. The handoff is mechanical:

- A CRUD cell that fails on one interface but not the other → an interface-parity chain (the beta4 plugin-dependency shape).
- A ladder cell that fails at one source version but not its neighbour → bisect the intervening releases; the boundary is the mechanism.
- A ladder cell that succeeds but leaves a divergent file tree, `db_version`, or content count → `MULTIHOP`, `ARTIFACT`, or the stale-file detector.
- Any cell where re-saving unchanged content changes bytes → stop and run `SERIAL` first; until that is clean, every byte-diff assertion elsewhere is measuring noise.
- Anything touching credentials, secrets at rest, or capability boundaries → the security lane with a threat model, not the sweep.

Phase 2 then runs the chain register: 20 adjudicated corrected chains, plus whichever of the 25 `UNADJUDICATED` lenses Phase 1 implicates — each only after source adjudication.

## Do not copy forward

Version numbers, the browser tier-1 entity set, PHP floors, fixture names and ports, `db_version` values, package hashes, and which source versions count as boundaries. Re-derive all of them per release; regenerate the matrices with the script rather than editing the CSVs.
