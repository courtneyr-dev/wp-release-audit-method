---
title: "Codex prompt — feature-chain test generation"
type: prompt
status: active
created: '2026-07-31'
updated: '2026-07-31'
source_run: "$WP_AUDIT_ROOT/ (evidence + scripts remain there)"
tags:
  - wordpress
  - wp-audit
  - codex
  - chain-testing
related:
  - '*../cross-release-feature-chains*'
  - '[codex-handoff-message](../prompts/codex-handoff-message.md)'
---

# Codex prompt — generate feature-CHAIN tests for WordPress release audits

> Paste the block below to Codex. It is release-parameterized: pass `TARGET_BUILD` (e.g. `7.1-beta4` today, `7.1-rc1` once released). Chain seeds are grounded in verified ledger rows and runtime-reproduced Beta 4 findings from `$WP_AUDIT_ROOT/` — not speculation.
>
> **Why chains:** every audit so far tested features one at a time. Every confirmed Beta 4 defect lived in an *interaction* — validation order across site modes, a UI counter reading the wrong option scope, an updater's cleanup list disagreeing with the tree it shipped. Single-feature passes are structurally blind to those.

---

```
<task>
Design and implement a suite of FEATURE-CHAIN tests for WordPress core release auditing: tests that
compose two or more shipped/changed features and assert the behavior of their INTERACTION, not each
feature alone. Target build: $TARGET_BUILD. Work only in disposable local environments.

Inputs (read, do not modify):
- $WP_AUDIT_ROOT/learning/failure-mode-register.csv
  (27 rows: confirmed defects, narrowed/refuted claims kept as NEGATIVE CONTROLS, harness failures)
- $WP_AUDIT_ROOT/methods/detection-rules.csv
  (5 calibrated detectors + 2 awaiting a build)
- $WP_AUDIT_ROOT/methods/test-and-fixture-registry.csv
  (fixtures, their asserted state, and their known limitations)
- $WP_LEARN_AUDIT_ROOT/ledger/imported-change-ledger.csv
  (98 change rows; `challenge_status` tells you which are UPHELD vs UNVERIFIED vs carrying
   a reopened-ticket VERIFY-RC flag. Prefer UPHELD rows as chain anchors.)

Deliverable: a runnable test suite plus a chain register. Each chain test must be executable
unattended, assert its own preconditions, and clean up after itself.
</task>

<chain_seeds>
Build tests for these interaction hypotheses first. Each names its ledger anchors and the failure
mode it generalizes. Do not treat any hypothesis as true — each is a question to answer with output.

C-01 MEDIA VALIDATION ORDER x SITE MODE x TRANSPORT
  Anchors: client-side-media (WASM, Chromium-only, silent server fallback), REST sideload-by-URL
  (Trac #65517, REOPENED), multisite upload quota, trac-65329 (sideload metadata moved to finalize),
  trac-65643 (EXIF-rotated sideload).
  Question: across {single-site, multisite} x {browser upload, REST file upload, REST url sideload}
  x {under quota, over quota} x {Chromium client-side path, forced server fallback} — in which cells
  does the full download/transcode complete BEFORE rejection, and what temp-file/attachment/postmeta
  residue survives the rejection? Generalizes FM-04 (download-before-reject) beyond the one cell it
  was found in.

C-02 UPGRADE PATH x FILE-REMOVAL LEDGER x CHECKSUM SURFACE
  Anchors: $_old_files, Core update_core() vs WP-CLI updater, per-release removed-file sets.
  Question: for {prior-stable -> target} and {prior-beta -> target}, does the post-upgrade tree
  match a clean install of the same build? Assert file-set equality, then run the site's own
  integrity/checksum surface. Chain the two upgrade paths against a clean install as the control.
  Generalizes FM-01/FM-02. Detector scripts/stale_file_check.py already predicts the answer offline —
  your test must confirm or refute the prediction at runtime.

C-03 MULTISITE STATUS FLAGS x NETWORK UPGRADE x FEATURE AVAILABILITY
  Anchors: network db upgrade eligibility filtering, site status flags (archived/spam/deleted).
  Question: after a network upgrade that reports N/N success, do held-back sites expose any
  7.x-era feature whose code assumes the new db_version? Un-archive a held-back site AFTER the
  network upgrade and assert what happens on first load. Generalizes FM-03 from a reporting
  nit into a functional question.

C-04 PLUGIN ACTIVATION SCOPE x DEPENDENCY RESOLUTION x UI AFFORDANCE
  Anchors: plugin dependencies, network-active vs site-local activation.
  Question: over the full matrix {dependency: network-active | site-active | inactive} x
  {dependent: network | site} x {viewer: super admin | site admin}, does every code path agree?
  Compare is_plugin_active(), the rendered action button, the REST plugins endpoint, and the
  dependency notice. Generalizes FM-05 (one path counted only site-local active_plugins).

C-05 SANITIZATION ALLOWLIST DRIFT x NESTING x BLOCK CONTENT
  Anchors: KSES allowlist EXPANSIONS (trac-65491 autofocus on dialog, trac-65619 global tabindex)
  and a KSES RESTRICTION shipping in the same release (r2-trac-65457, SVG inline styles removed),
  Custom HTML block with editable inner blocks, Block Bindings.
  Question: two allowlist changes in opposite directions in one release. Does content that is
  legal at the top level stay legal when nested inside Custom HTML / bound block attributes /
  serialized block comments, and vice versa? Include the FM-11 negative control: top-level `C:`
  blocked but nested `C:` invoked — nesting is the known blind spot.

C-06 EDITOR CHROME x MODE MATRIX x EXTENSION SURFACE
  Anchors: persistent toolbar (Post + Site Editor; hide condition DISPUTED between the dev note
  and the Source of Truth), Distraction Free, Fullscreen, editor components 40px default sizing,
  Navigation component removal, iframed editor (Block API v3 enforced).
  Question: over {Post Editor, Site Editor} x {default, Distraction Free, Fullscreen, DF+FS},
  is the toolbar present/absent as documented, and do plugin-registered toolbar nodes and
  non-v3 blocks survive? This test also SETTLES the documented source conflict — report which
  source is wrong.

C-07 ABILITIES API x EXPOSURE FLAG x EXECUTION FILTERS x REST AUTHZ
  Anchors: abilities-api execution lifecycle filters, trac-65568 public exposure flag,
  trac-65248 wp_ability_invoked action, r2-trac-65234 (get-user-info profile-field expansion).
  Question: with an ability marked public and lifecycle filters registered, what is the effective
  authorization boundary for {logged-out, subscriber, editor, admin, super admin} across
  {single-site, multisite}? Assert that a filter cannot widen exposure beyond the flag, and that
  wp_ability_invoked fires exactly once per invocation. THREAT-MODEL GATE applies (below).

C-08 VIEW CONFIG API x VERSIONING x DATAVIEWS PERSISTENCE
  Anchors: trac-65516 View Config REST API, #65577 versioning (REOPENED — behavior may change).
  Question: write a view config, then simulate a version bump/downgrade of the stored config.
  Does the API migrate, reject, or silently drop unknown keys? Mark results PROVISIONAL while
  #65577 is reopened.

C-09 RESPONSIVE STYLING x THEME.JSON BREAKPOINTS x GLOBAL STYLES REVISIONS
  Anchors: responsive-styling (per-breakpoint controls), viewport-breakpoints (theme-defined),
  text-shadow (theme.json only, no UI), interactive states, visual revisions.
  Question: define custom breakpoints in theme.json, set per-breakpoint + hover/focus + textShadow
  values, then revert via Global Styles revisions. Does the revision restore per-breakpoint and
  state-scoped values faithfully, or flatten them? Then switch to a theme with DIFFERENT breakpoints
  and assert what happens to styles authored under the old set.

C-10 MEDIA LIBRARY SCALE x INFINITE SCROLL x VISIBILITY FILTERING
  Anchors: media-infinite-scroll (default-on; enabling ticket #65564 REOPENED), per-user opt-out,
  attachment visibility filtering (the r1 content audit measured REST reporting 3,437 attachments
  while returning only 3,305 to an anonymous client).
  Question: at 5k+ attachments, does infinite scroll's paging agree with the REST total, with the
  opt-out paginated view, and with what each role can actually see? A count that disagrees across
  those three surfaces is the finding.
</chain_seeds>

<method_rules>
- RUNTIME DECIDES. Source reading and cross-model agreement raise priority; only executed output
  in an authorized local environment confirms a chain result.
- CONTROLS ARE MANDATORY. Every chain test ships a positive control (a cell expected to fail or
  differ) and a negative control (a cell expected to be clean). If either miscalibrates, ABORT that
  batch and invalidate its results — do not report them.
- ASSERT FIXTURE STATE AND DENOMINATORS FIRST. Print site inventory, status flags, db_version,
  active plugins, PHP/WP versions, and multisite mode BEFORE reading any result. Reuse
  scripts/assert_multisite_denominator.sh.
- SERIALIZE mutations against a single fixture. Never run concurrent commands against one wp-env
  or Studio project.
- HARNESS-HEALTH PRECHECK before each batch (daemon/socket/container/ownership). A harness fault is
  an INVALID batch, never a product failure.
- Verdicts are exactly: CONFIRMED | REFUTED | INCONCLUSIVE | BLOCKED | INVALID. Never call an
  unproven chain result a vulnerability.
- NEGATIVE CONTROLS FROM HISTORY: keep FM-08 (KSES img allowed in post context), FM-09 (pre-4.3
  guard), FM-10 (ms-files non-regression), FM-11 (top-level `C:` only), FM-12 (custom capability
  mapping) in the suite as tests that MUST come back clean. If one of them starts failing, your
  harness is wrong before WordPress is.
</method_rules>

<threat_model_gate>
For any chain touching authorization, sanitization, upload, or deletion, state before reporting:
attacker position (unauthenticated / subscriber / contributor / admin / super admin / code already
executing inside WP), the boundary crossed, and the default-configuration reachability. An API
reachable only by code already running inside WordPress is an INTERNAL FOOTGUN, not a vulnerability
(FM-07). A result that needs a custom capability mapping is CONFIGURATION-DEPENDENT (FM-12).
Sensitive detail goes to private/security/ only — never into a general report.
</threat_model_gate>

<a11y_calibration_rule>
For any chain asserting keyboard or focus behavior (C-06, and the Tabs/Playlist surfaces), a NATIVE
control element must respond correctly to the same synthetic input in the same harness BEFORE any
product verdict is recorded. If the native control does not respond, the result is an AUTOMATION
FAILURE, not a product failure (FM-06 — this exact rule reversed a prior wrong call).
</a11y_calibration_rule>

<structured_output_contract>
Produce:
1. chains/chain-register.csv —
   chain_id,name,anchor_change_ids,hypothesis,matrix_cells,fixture_id,positive_control,
   negative_control,threat_model,status,verdict,evidence_path
2. chains/<chain_id>/ — the runnable test (shell/PHP/WP-CLI/Playwright as appropriate), a README
   with exact invocation, and a cleanup script.
3. chains/results.csv — one row per matrix CELL, not per chain:
   chain_id,cell,expected,observed,verdict,command,output_path,fixture_state_hash,cleanup_verified
4. chains/report.md — mechanism first, then proof. Separate counts for CONFIRMED / REFUTED /
   INCONCLUSIVE / BLOCKED / INVALID. List every cell you did not run and the exact blocker.
</structured_output_contract>

<default_follow_through_policy>
Default to building and running rather than asking. Make reasonable calls on fixture details and
record each assumption inline. Stop and ask ONLY for: destructive operations outside a disposable
fixture, anything touching a non-local host, or external filing/disclosure. Never open tickets,
issues, PRs, or comments.

If $TARGET_BUILD is not downloadable, run the suite against the newest verified local build,
label every result with the build identity you actually tested, and mark the target-build cells
WAITING-FOR-BUILD. Do not test a mislabeled build.
</default_follow_through_policy>

<completeness_contract>
Done means: every chain has a register row; every matrix cell has a verdict or an exact blocker;
every CONFIRMED cell links to command output and a fixture-state assertion; both controls are
recorded per batch; invalidated batches are excluded from all counts and their diagnosis preserved;
cleanup is verified and recorded; and the suite runs end-to-end a second time from a clean fixture
with the same verdicts.
</completeness_contract>
```

---

## Chain-seed provenance

| Chain | Ledger anchors (r2, `challenge_status`) | Failure mode generalized |
|---|---|---|
| C-01 | client-side-media (UPHELD), #65517 (REOPENED), trac-65329/65643 (NEW-THIS-RUN) | FM-04 |
| C-02 | — (updater surface) | FM-01, FM-02 |
| C-03 | — (multisite upgrade surface) | FM-03, FM-15 |
| C-04 | plugin dependencies | FM-05 |
| C-05 | trac-65491, trac-65619 (UPHELD), r2-trac-65457 (NEW) | FM-08, FM-11 |
| C-06 | persistent-toolbar (UPHELD, source conflict), editor-components, iframed-editor | FM-06, SoT contradiction |
| C-07 | abilities-api, trac-65568, trac-65248, r2-trac-65234 | FM-07, FM-12 |
| C-08 | trac-65516 (REVISED — #65577 reopened) | VERIFY-RC discipline |
| C-09 | responsive-styling, viewport-breakpoints, text-shadow, interactive-states | audit P0 surface |
| C-10 | media-infinite-scroll (REVISED — #65564 reopened) | r1 attachment count gap |

## Cross-release chains (6.3 → 7.1) — added 2026-07-30

The 6.3–7.0 corpus named in the operator prompt does not exist on this machine, so it was **rebuilt**: `learning/cross-release-feature-ledger.csv` now holds **200 features across 6.3–7.0**, each fetched from its release announcement, Field Guide, or dev note, and each carrying a `persistence_surface` (where its state actually lives) and a `chain_affinity` (which subsystems it must touch). Those two fields are what make cross-release chaining possible.

Four independent lenses — persistence, authorization, lifecycle, render — proposed **36** cross-release chains. Every one was then adjudicated by a source-reading adversarial judge. **The result is the most important thing in this file: 0 chains survived unchanged.** 16 were dropped on verified-false premises and 20 were corrected. Judges refuted proposals by extracting the beta4 package and reading source, by checking that `map_meta_cap()` resolves `edit_css` in the same switch arm as `unfiltered_html` (so the proposed "two gates" were one), and by reading `block-bindings/post-meta.php` to disprove a claimed write path.

**Use `learning/cross-release-chain-register.csv` as the chain source — specifically its `corrected_chain` column, not `proposed_hypothesis`.** The 20 corrected chains (16 high-risk, 4 medium; 9 persistence, 4 authorization, 4 lifecycle, 3 render) are source-grounded. The 16 dropped ones are retained in the same file as negative controls with the judge's refutation, so nobody re-proposes them.

Representative corrected chains, all hinging on an older release writing data a newer release must still read:
- **Stored viewport tokens vs. theme-defined breakpoints** (7.0 → 7.1): visibility tokens written under `blockVisibility` get resolved against breakpoints a 7.1 theme may redefine.
- **Global Styles revision restore silently reverts Font Library activation** (6.3 → 6.5, reproduces on current releases): font activation lives in the same `wp_global_styles` payload that revisions snapshot wholesale — blast radius crosses the post, `wp_font_family`/`wp_font_face` rows, uploaded font files, and front-end `@font-face`. Revision tests never build Font Library state; Font Library tests never restore a revision.
- **`safecss_filter_attr()` url-value reparse on lower-privileged re-save** (6.5/6.6 → 7.0.1 → 7.1): stored background declarations rewritten when a user without `unfiltered_html` re-saves.

**Standing rule proven by this run (FM-28 / MC-22):** a chain proposer working from a feature catalog *without source access* invents plausible surface names, capability relationships, and storage locations. Chain proposal must cite source per leg, and an independent source-reading judge must adjudicate before any chain becomes a test. Without that judge lane this workflow would have shipped 36 confident, partly-false test specifications.

## Twenty-five new lenses — added 2026-07-31, ALL `UNADJUDICATED`

`learning/cross-release-chain-register.csv` now holds **61 rows: 20 REVISE (adjudicated, buildable), 16 DROP (refuted, kept as negative controls), 25 UNADJUDICATED (14 high-risk, 11 medium)**. The 25 are new proposals across 25 distinct lenses. None may become a test before source adjudication.

**Batch 2 — assumption-breaking lenses** (detail in the section below): `ROLL`, `USER`, `CACHE`, `PARTIAL`, `IDEM`, `LOCALE`, `ENV`.

**Batch 3 — coverage-gap lenses**, mined from the ledger dimensions batch 2 didn't touch:

| Lens | Chain | What it attacks | Anchors verified in ledger |
|---|---|---|---|
| `NEGSPACE` | X-NEG-01 | Is the removed thing gone, and does content written while it existed survive? **17 removals/deprecations, zero chains** | `search-block-buttonbehavior-removed`, `synced-pattern-overrides-reverted` (shipped **then reverted**), `wp69-block-apiversion-3` |
| `HASH` | X-HASH-01 | Credential-hash format migration; the untested population is users who **never logged in** post-6.8 | `bcrypt-password-hashing`, `fast-hash-blake2b-keys` |
| `MULTIHOP` | X-HOP-01 | Version-skipping upgrade — migration **ordering**, never exercised single-hop | `wp66-options-autoload`, `wp70-multisite-spam-decoupling`, bcrypt, manifest |
| `SECRET` | X-SECRET-01 | API keys at rest: autoload, REST exposure, export payloads | `wp70-connectors-api` (`connectors_{provider}_*` options) |
| `ROUNDTRIP` | X-TRIP-01 | Export→import fidelity; taxonomy is 6/200 features and 0 chains | `wp64-pattern-import-export` (post + terms + serialization) |
| `ARTIFACT` | X-ARTIFACT-01 | Stale **on-disk** generated artifact vs its source | `wp67-block-metadata-collection`, `register-block-types-from-metadata-collection` |
| `A11Y` | X-A11Y-01 | Motion, forced-colors, announcements — keyboard is the only axis tested | `wp70-modern-admin-view-transitions`, `r2-trac-65419` |
| `QUALITY` | X-QUAL-01 | Encoded subsize quality drift when the transcode engine changes | `editor-set-quality-size-arg` × 7.1 client-side media |
| `PRIVACY` | X-PRIV-01 | Does personal-data export/erase cover newly stored user data? | editor prefs, DataViews state, `admin_color`, app passwords |
| `COMPOSE` | X-COMPOSE-01 | Core **+ Gutenberg plugin**; every fixture runs core alone | `rtc` (plugin-only), `react-19` (punted to plugin flag) |
| `CONCUR` | X-CONCUR-01 | Two simultaneous writers; the notes permission bug needs two sessions | `notes-suite` + open bug #64779 |
| `BOUNDARY` | X-BOUND-01 | 0 / 1 / page-size / page-size+1 / large N | `media-infinite-scroll`, `wp69-query-cache-salt` |
| `RESIDUE` | X-RESID-01 | What a feature leaves behind on uninstall | `font-library`, `plugin-dependencies`, `wp64-block-hooks` |
| `SERIAL` | X-SERIAL-01 | **parse→serialize must be a fixed point** — prerequisite for trusting every byte-diff in the suite | 45 post-content features, `wp69-utf8`, KSES |
| `ERRORPATH` | X-ERR-01 | Fallbacks only run when the happy path fails, so they never run | 7.1 silent server fallback, `wp69-utf8` fallback |
| `THEMEPORT` | X-THEME-01 | Content authored under theme A rendered under theme B | `wp66-theme-json-v3`, `wp67-twentytwentyfive`, 7.1 breakpoints |
| `CAPCOMPOSE` | X-CAP-01 | Composed capabilities and mid-session role change, not named roles | `wp67-global-styles-read-access`, `rest-menu-read-access`, FM-12 |
| `TIME` | X-TIME-01 | Scheduling, expiry, DST spanning an upgrade | transient timeouts, cron, `wp67-global-styles-css-cache` |

**Run-order advice.** `SERIAL` (X-SERIAL-01) should run **first** — if re-saving unchanged content mutates bytes, every byte-diff assertion elsewhere is measuring noise. Then `NEGSPACE` and `HASH` (highest consequence), then `ROLL` and `CACHE` (no RC1 needed).

**Two anchors are pre-window and honestly labeled as such in the register:** core's personal-data exporter (`PRIVACY`) and post locking (`CONCUR`) both predate 6.3, so they anchor as the *stable* side of their chain rather than as ledger features.

**Three fixture cautions carried in the rows:** `X-CONCUR-01` intentionally races and must not run beside other fixture mutations; `X-PART-01` mutates destructively and must be strictly serialized; `X-ENV-01` needs a PHP-matched pair (comparing the existing 7.4-multisite against the 8.4-single-site confounds PHP with site mode). `X-HASH-01` and `X-SECRET-01` are security lanes — threat model, dummy credentials only, sensitive output to `private/security/`.

## Seven new lenses — batch 2 detail, ALL `UNADJUDICATED`

The original 36 chains were generated as exactly 9 per lens across four lenses (persistence, render, authorization, lifecycle). That bounded the output: **157 of the 200 catalogued 6.3–7.0 features have never been named in any chain.** More importantly, every chain built so far shares four unexamined assumptions — it runs *forward* (old data → new reader), as a *single user*, in a *single locale*, in a *single uninterrupted run*. The new lenses attack those assumptions directly.

Rows `X-ROLL-01`, `X-USER-01`, `X-CACHE-01`, `X-PART-01`, `X-IDEM-01`, `X-LOCALE-01`, `X-ENV-01` are in `learning/cross-release-chain-register.csv` with `judge_verdict = UNADJUDICATED`.

| Lens | Assumption it breaks | Anchors (verified present in the feature ledger) |
|---|---|---|
| `ROLL` | Forward direction only | `wp63-rollback-failed-updates`, `wp66-rollback-auto-update` — real filesystem backup paths |
| `USER` | Single user | `editor-preferences-unification`, `visual-editor-user-option-removed`, `wp69-dataviews-field-api`, `wp70-modern-admin-view-transitions` + 7.1 infinite-scroll opt-out |
| `CACHE` | Cache always coherent | `wp67-global-styles-css-cache`, `wp64-object-cache`, `wp64-template-loading`, `wp63-user-query-caching`, `set-transient-action-rename` |
| `PARTIAL` | Operations complete | rollback backups, the `trac-65329` sideload finalize seam, transcode temp files |
| `IDEM` | Run once | network db upgrade, KSES re-save, `wp_ability_invoked` (`trac-65248`) |
| `LOCALE` | English only | `wp67-jit-translation-warning`, `wp67-admin-email-locale`, translated block names, RTL |
| `ENV` | One PHP version | the fixture registry already runs PHP 7.4 (multisite) beside 8.4 (single-site) |

**`ROLL` is the highest-value lens** and the one most clearly missed: rollback is a shipped user action that inverts the data-flow direction, so no forward-direction test can observe it. **`ROLL` and `CACHE` need no RC1** — both are runnable against the current build today.

**These seven are hypotheses, not tests.** They were derived from the catalog, which is the exact mode with a measured 36-of-36 error rate. Before building any of them: read the named code path for each leg — the rollback backup path, the cache-key construction, the user-meta read path — and confirm the mechanism exists as described. Then have an independent source-reading judge adjudicate, and build only the corrected form. Two shard-specific cautions carried in the register: `X-PART-01` mutates fixtures destructively and must be strictly serialized, and `X-ENV-01` requires a PHP-matched fixture pair — comparing the existing 7.4-multisite against the 8.4-single-site would confound PHP with site mode.
