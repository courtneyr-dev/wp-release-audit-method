---
title: "Codex handoff — single paste-ready message"
type: prompt
status: active
created: '2026-07-31'
updated: '2026-07-31'
source_run: "$WP_AUDIT_ROOT/ (evidence + scripts remain there)"
tags:
  - wordpress
  - wp-audit
  - codex
  - handoff
related:
  - '[codex-feature-chain-test-generation-prompt](../prompts/codex-feature-chain-test-generation-prompt.md)'
---

# Single-message Codex handoff (copy/paste)

Self-contained. Assumes only that Codex can read the local filesystem and run disposable local WordPress environments.

> **Path note (2026-08-21).** The message below is preserved as run on 2026-07-30 and
> describes that run root's layout. Since then, several artifacts it cites moved into this
> repo: `rc_build_identity.sh`, `stale_file_check.py`, and `assert_multisite_denominator.sh`
> live at [`scripts/`](../scripts/) (in-repo since 2026-08-05 for the identity gate), the
> register schemas at [`learning/`](../learning/) and [`methods/`](../methods/), and
> `deliverables/codex-feature-chain-test-generation-prompt.md` is
> [`prompts/codex-feature-chain-test-generation-prompt.md`](codex-feature-chain-test-generation-prompt.md).
> Reusing this message means substituting those paths; the body is unchanged because audit
> records cite it as run.

---

You are taking over feature-CHAIN test development for a WordPress core release audit. Chains = tests that compose two or more shipped features and assert the behavior of their INTERACTION. Every confirmed defect in the prior Beta 4 pass lived in an interaction, not in a feature: validation order across site modes, a UI counter reading the wrong option scope, an updater's cleanup list disagreeing with the tree it shipped. Single-feature tests are structurally blind to those.

## Scope and authorization

Authorized defensive testing in disposable local environments only. Never test production sites, WordPress.org infrastructure, third-party sites, or plugins/themes you do not own. Never open tickets, issues, PRs, comments, or disclosures — those require the operator's explicit approval. Never bypass core.trac.wordpress.org's bot challenge (it 403s non-browser clients; that is a documented constraint, not an obstacle). Read-only HTTP: GET only, User-Agent `wp-release-audit (read-only enumeration)`, ~1 request/second on wordpress.org properties.

## Build identity — check this first

WordPress 7.1 RC1 was NOT published as of 2026-07-30, verified three ways: the releases feed's newest entry is "WordPress 7.1 Beta 4"; `https://wordpress.org/wordpress-7.1-rc1.zip` returns 404; trunk `src/wp-includes/version.php` reads `7.1-beta4-62899-src`.

Run `$WP_AUDIT_ROOT/scripts/rc_build_identity.sh 7.1 rc1` before anything else. If it returns WAITING, build and run against the newest verified local build (`7.1-beta4`), label every result with the build identity you actually tested, and mark target-build cells WAITING-FOR-BUILD. Do not test a mislabeled build.

Local trees already on disk: `$HOME/.studio/server-files/wordpress-versions/{7.0.2, 7.1-beta3, 7.1-beta4}`. Beta 4 package MD5 `ab34d9b77d234770fde218adef3546e9`. `db_version 61833` is unchanged across beta2/3/4.

## Read these first

Run root: `$WP_AUDIT_ROOT/`

- `learning/failure-mode-register.csv` — 29 rows. Confirmed defects, narrowed/refuted claims retained as NEGATIVE CONTROLS, harness failures, method gaps. Read `control_role` and `learning_decision`.
- `learning/cross-release-chain-register.csv` — 36 adjudicated cross-release chains. **Use the `corrected_chain` column. Never use `proposed_hypothesis`.** See the warning below.
- `learning/cross-release-feature-ledger.csv` — 200 features across WordPress 6.3–7.0, each with `persistence_surface` (where its state actually lives) and `chain_affinity` (which subsystems it must touch). These two fields are what make chaining possible.
- `methods/detection-rules.csv` + `scripts/` — five calibrated detectors you can reuse directly.
- `methods/test-and-fixture-registry.csv` — FX-01..FX-09, each with required state assertions and known limitations.
- `pilots/wp71-rc1/` — the armed-but-waiting RC1 pilot, including the Beta 4 rerun matrix.
- `$WP_LEARN_AUDIT_ROOT/ledger/imported-change-ledger.csv` — 98 WordPress 7.1 change rows. `challenge_status` tells you which are UPHELD vs UNVERIFIED vs carrying a reopened-ticket VERIFY-RC flag. Prefer UPHELD rows as anchors.

## Warning that will save you a day

36 cross-release chains were proposed by agents working from a feature catalog **without source access**. A separate set of judges **with** source access then adjudicated them. **Zero survived unchanged** — 16 refuted on verified-false premises, 20 corrected.

The refutations came from reading actual code: `map_meta_cap()` resolves `edit_css` in the same switch arm as `unfiltered_html`, so a chain built on "two independent gates" was built on one gate; `block-bindings/post-meta.php` disproved a claimed write path; extracting the beta4 package disproved two more.

A proposer without source access invents plausible surface names, capability relationships, and storage locations. So: **cite source per chain leg, and treat every unverified chain premise as false until you have read the code.** The 16 dropped chains stay in the register with their refutations so nobody re-proposes them.

## What to build

**Priority 1 — the 20 corrected cross-release chains** in `cross-release-chain-register.csv` (`judge_verdict = REVISE`, use `corrected_chain`). 16 are high-risk, 4 medium; 9 persistence, 4 authorization, 4 lifecycle, 3 render. They are adjudicated but never executed — that is the highest-value untested work in this project, and it does not need RC1.

Their shared shape is worth internalizing: **an older release wrote data or set an expectation that a newer release changes.** Examples:
- Restoring a Global Styles revision silently reverts Font Library activation — both live in the same `wp_global_styles` payload that revisions snapshot wholesale. Blast radius crosses the post, `wp_font_family`/`wp_font_face` rows, uploaded font files, and front-end `@font-face`. Revision tests never build font state; font tests never restore a revision.
- Stored viewport tokens (`blockVisibility`, 7.0) resolved against breakpoints a 7.1 theme redefines.
- `safecss_filter_attr()` url-value reparse rewriting stored background declarations when a user without `unfiltered_html` re-saves.

**Priority 2 — the ten 7.1-internal chains**, full text at `deliverables/codex-feature-chain-test-generation-prompt.md` lines 9–183:

- C-01 media validation order × site mode × transport: {single, multisite} × {browser upload, REST file, REST url sideload} × {under, over quota} × {client-side path, forced server fallback}. Which cells complete the download before rejecting, and what temp-file/attachment/postmeta residue survives?
- C-02 upgrade path × file-removal ledger × checksum surface: does a post-upgrade tree equal a clean install of the same build, for prior-stable→target and prior-beta→target? `scripts/stale_file_check.py` predicts the answer offline — confirm or refute it at runtime.
- C-03 multisite status flags × network upgrade × feature availability: after an "N/N success," un-archive a held-back site and assert first load.
- C-04 plugin activation scope × dependency resolution × UI affordance: full {network, site, inactive} × {network, site} × {super admin, site admin} matrix; compare `is_plugin_active()`, the rendered button, the REST endpoint, and the notice.
- C-05 sanitization allowlist drift × nesting: two KSES changes ship in opposite directions in one release (autofocus/tabindex expansions vs SVG inline-style removal). Does content legal at top level stay legal nested inside Custom HTML, bound attributes, and block comments? Include the known negative control: top-level `C:` blocked but nested `C:` invoked.
- C-06 editor chrome × mode matrix × extension surface: {Post, Site Editor} × {default, Distraction Free, Fullscreen, DF+FS}. This one also SETTLES a documented source conflict — the dev note and the Source of Truth disagree on the toolbar hide condition. Report which is wrong.
- C-07 Abilities API × exposure flag × lifecycle filters × REST authz: assert a filter cannot widen exposure beyond the public flag, and that `wp_ability_invoked` fires exactly once.
- C-08 View Config API × versioning × DataViews persistence: mark results PROVISIONAL while its versioning ticket is reopened.
- C-09 responsive styling × theme.json breakpoints × Global Styles revisions: author per-breakpoint + hover/focus + textShadow, revert via revisions, then switch to a theme with different breakpoints.
- C-10 Media Library scale × infinite scroll × visibility filtering: at 5k+ attachments, does paging agree with the REST total, the opt-out paginated view, and per-role visibility? A prior audit measured REST reporting 3,437 attachments while returning 3,305 to an anonymous client.

## Method rules — non-negotiable

**Runtime decides.** Source reading and cross-model agreement raise priority; only executed output in an authorized local environment confirms a result. Never call an unproven claim a vulnerability.

**Controls are mandatory.** Every chain ships a positive control (a cell expected to fail or differ) and a negative control (a cell expected to be clean). If either miscalibrates, ABORT that batch and invalidate its results — do not report them. Three of the five existing detectors failed a control on first run and were fixed before acceptance; a detector that has never failed a control has never been calibrated.

**Activation is not a boot, and the boot must be HTTP.** "It activated" is not a PASS — activation runs a narrow path, often before the hooks and globals the real implementation assumes. But make the check an HTTP request (`/` and `wp-login.php`, require 200), **not** `wp eval`. WP-CLI requires `wp-settings.php` from inside `WP_CLI\Runner->load_wordpress()`, and PHP runs an included file in the including scope, so a plugin's file-scope `$Var = new Thing()` becomes a local of that method rather than a global; a later `global $Var` gets null and can fatal — under WP-CLI only, on a site HTTP serves fine. Run the CLI boot last if at all, and record a CLI-only fatal as a note. Receipt is a refutation: core's workflow reported `eps-301-redirects` as a real 7.1 fatal on that basis and the plugin was healthy. CLI boot, HTTP request, and activation are three different tests, and **none of them contains the others**.

**Report skips beside passes, never folded into them.** Every count states passed / failed / SKIPPED / blocked separately, with a reason per skip. That same run read 186 passed / 1 failed / 13 skipped, with the reason given as one vendor's add-ons with an unmet `Requires Plugins` header — and when the fix landed it named FOUR such plugins, leaving nine skips whose cause is unstated. A reason attached to a COUNT rather than to each skip is itself a hiding place; attach it per unit. A skip class that correlates with a vendor, a dependency, a licence, or a site mode is a blind spot to name.

**Assert fixture state and denominators before reading any result.** Print site inventory, status flags, `db_version`, active plugins, PHP/WP versions, and multisite mode first. Reuse `scripts/assert_multisite_denominator.sh`. A prior run reported "upgraded on 2/2 sites" while three sites sat at the old `db_version`.

**Serialize mutations** against a single fixture. Never run concurrent commands against one wp-env or Studio project.

**Harness-health precheck** before each batch (daemon, socket, container, ownership). Colima storage corruption, root-owned fixtures, and a self-deleting source fixture each produced non-WordPress "failures" in a prior run. A harness fault is an INVALID batch, never a product failure.

**Verdicts:** CONFIRMED | REFUTED | INCONCLUSIVE | BLOCKED | INVALID. Report counts separately. Never turn model agreement, a static warning, or one benchmark run into proof.

**Negative controls from history** — keep these in the suite; they MUST come back clean, and if one starts failing your harness is wrong before WordPress is:
- `wp_kses_post()` allows literal `img` in post context (a prior claim that this was a defect was refuted).
- The strict `Sub_part` comparison sits behind a pre-4.3 db_version guard — unreachable on supported paths.
- `ms-files.php` shows no regression; its guards are intact.
- Top-level `C:` serialization is blocked but nested `C:` inside an accepted array is not.
- Multisite capability boundaries hold for default roles; only a custom `manage_network_users` grant changes the outcome.

**Threat-model gate.** For any chain touching authorization, sanitization, upload, or deletion, state attacker position (unauthenticated / subscriber / contributor / admin / super admin / code already executing inside WP), the boundary crossed, and default-configuration reachability. An API reachable only by code already running inside WordPress is an INTERNAL FOOTGUN, not a vulnerability. A result requiring a custom capability mapping is CONFIGURATION-DEPENDENT. Sensitive detail goes to `private/security/` only, never a general report. Credentials never enter reports, logs, or memories.

**Accessibility calibration.** For any chain asserting keyboard or focus behavior, a NATIVE control element must respond correctly to the same synthetic input in the same harness BEFORE any product verdict is recorded. If the native control does not respond, the result is an AUTOMATION FAILURE, not a product failure. This exact rule reversed a wrong call on the Tabs block.

**Performance.** No benchmark has been run in this project. If you benchmark: fixed dataset with a recorded id, more than one run, variance reported, machine-state controls noted. A single run is never proof.

## Output contract

1. `chains/chain-register.csv` — `chain_id,name,anchor_change_ids,hypothesis,source_citations,matrix_cells,fixture_id,positive_control,negative_control,threat_model,status,verdict,evidence_path`
2. `chains/<chain_id>/` — the runnable test, a README with exact invocation, and a cleanup script.
3. `chains/results.csv` — one row per matrix CELL, not per chain: `chain_id,cell,expected,observed,verdict,command,output_path,fixture_state_hash,cleanup_verified`
4. `chains/report.md` — mechanism first, then proof. Separate counts for CONFIRMED / REFUTED / INCONCLUSIVE / BLOCKED / INVALID. List every cell you did not run and its exact blocker.

Every result row links to actual command output. Every non-clear claim gets an evidence record: URL or file path, status, locator, excerpt under 200 characters, sha256, and a replay command.

## Follow-through

Default to building and running rather than asking. Make reasonable calls on fixture details and record each assumption inline. Stop and ask only for: destructive operations outside a disposable fixture, anything touching a non-local host, or external filing. Done means every chain has a register row, every matrix cell has a verdict or an exact blocker, both controls are recorded per batch, invalidated batches are excluded from counts with their diagnosis preserved, cleanup is verified, and the suite reruns from a clean fixture with the same verdicts.
