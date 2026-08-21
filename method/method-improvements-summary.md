---
title: "Method improvements summary — release-audit learning loop"
type: analysis
status: active
created: '2026-07-31'
updated: '2026-07-31'
source_run: "$WP_AUDIT_ROOT/ (evidence + scripts remain there)"
tags:
  - wordpress
  - wp-audit
  - loop-engineering
  - controls
related:
  - '*index*'
  - '[release-audit-learning-loop](../method/release-audit-learning-loop.md)'
---

# Method improvements summary — WordPress release-audit learning loop

Executive summary of the WP 7.1 learning loop at `$WP_AUDIT_ROOT/`.
Every claim below traces to an id in `learning/failure-mode-register.csv` (FM-*),
`learning/method-change-proposals.csv` (MC-*), `learning/shadow-run-results.csv` (SR-*), or
`methods/detection-rules.csv` (D-*) — id schemes and the public/private split are defined in
[registers.md](registers.md). No RC1 build exists yet (verified 2026-07-30) — nothing below
claims an RC1 test result.

## Count verification

The register was tallied against the stated totals rather than assumed.

| Decision | Stated | Counted | Result |
|---|---|---|---|
| CHANGED-MECHANISM | 13 | 13 | match |
| REFUTED-BY-BETTER-CONTROL | 7 | 7 | match |
| BLOCKED | 7 | 7 | match |

13 + 7 + 7 = 27, which accounts for all 27 rows in `failure-mode-register.csv`. No mismatch.

## What changed and why

### Changed mechanism (13) — the finding was real (or real enough), the METHOD had to change

| FM | What happened | What changed |
|---|---|---|
| FM-01 | Stale files survive Core's own `update_core()` because `$_old_files` never declared them | D-05 stale-file detector: diff release trees offline before any upgrade fixture is built |
| FM-02 | WP-CLI's updater does extra cleanup that masks FM-01 entirely | Core-vs-tool lane separation: only `update_core()` proves Core behavior; WP-CLI is a separate lane and a negative control |
| FM-03 | "Upgraded on N/N sites" hid non-uniform `db_version` on held-back sites | D-04 multisite denominator asserter: print total/eligible/held-back before reading any N/N |
| FM-05 | The Activate-button UI counted only site-local `active_plugins`, missing network activation | Rule: exercise the full local x network activation matrix, never a single option value |
| FM-07 | `wp_delete_site(1)` deletes the main site with no default guard on the direct API path | MC-11 threat-model gate: inside-WP-only reachability is a footgun, not a vulnerability |
| FM-15 | A network was assumed to have 11 sites; it had 10 | Same denominator-assertion rule as FM-03 (fixture rule F-01): assert live inventory before reading any result |
| FM-18 | A Studio admin password reached tool output and a summary | Rule P-01: credentials never enter reports/memory; sensitive material goes to `private/security/` only |
| FM-20 | Chrome-vs-content false positives were the single highest-frequency method failure in the content audit | D-01 content-vs-chrome extractor (REST `content.rendered` as ground truth) + the gated-content guard |
| FM-21 | Version-form search missed a canonical post with zero literal version-string hits in its body | Query rule Q-01: supplement version-form search with a date-window pass + cross-post-redirect enumeration |
| FM-22 | Ticket-number key-joins overstated an "uncovered" population by roughly an order of magnitude | Query rule Q-02: coverage comparison must be semantic, never a bare key-join |
| FM-23 | An independent (Codex) review found no evidence-preservation layer at all | MC-13 mandatory evidence record: URL/status/locator/excerpt/SHA-256/replay command on every non-clear claim |
| FM-24 | 28 of 42 BLOCKED findings had no path back to resolution | MC-15 blocker-remediation queue: every BLOCKED row gets tier/owner/access/closure condition |
| FM-27 | GitHub's org-wide `is:pr is:merged` returned 0 on a repo that shipped thousands of changes | Standing rule: never use PR-merge status as release evidence on an SVN-mirrored repo (also a permanent negative control) |

### Refuted by better control (7) — the claim did NOT survive a stronger control

| FM | Claim | What the better control showed |
|---|---|---|
| FM-06 | A keyboard defect first read INCONCLUSIVE | The automation's own native-button control also failed on that run — an automation fault, not a product fault. A rerun with a passing native control correctly reached CONFIRMED. Became MC-10, the a11y native-control calibration rule |
| FM-08 | KSES sanitization defect (img stripped/allowed incorrectly) | `wp_kses_post()` allows literal `<img>` in post context BY DESIGN. Permanent negative control |
| FM-09 | A strict `Sub_part` comparison is a live defect | The code path sits behind a pre-4.3 DB-version guard, unreachable on any supported upgrade path. Permanent negative control for a "reachability gate" rule |
| FM-11 | Serialization CVE path is fixed (top-level `C:` blocked) | True only for TOP-LEVEL input — a nested `C:` inside an accepted array still invoked its callback. Narrowed, not fixed. Permanent negative control against over-claiming a fix from one input shape |
| FM-12 | Multisite capability boundary makes `edit_users` Super-Admin-only | True only under a CUSTOM `manage_network_users` grant; default roles were denied by default. Permanent negative control for default-vs-custom-configuration severity |
| FM-19 | A Playground blueprint decode was initially quarantined as a false lead | The orchestrator's own refutation was WRONG — it mis-modeled single-quoted attributes and double-nested base64. Became D-02, the quote-agnostic multi-layer payload decoder |
| FM-25 | Title-term text matching is a workable shard-selection strategy | 3/25 true hits on one shard, then 0/17 on the next. Retired; permanent negative control against reintroducing it |

### Blocked (7) — real or plausible, progress blocked by tooling/access/fixture gaps

| FM | Status |
|---|---|
| FM-04 | Confirmed defect (REST url-import downloads the full file before a multisite size rejection), but its upstream home is an existing, already-REOPENED Trac ticket (#65517) — blocked pending owner approval to comment |
| FM-10 | Refuted as a regression on the direct-handler path; the public legacy-URL serving path is untested because the wp-env fixture's `.htaccess` lacks the legacy rewrite |
| FM-13 | Colima/Docker storage corruption misread as a WordPress failure until diagnosed — folded into MC-09's harness-health precheck |
| FM-14 | A tool deleted its own failed source fixture on retry — same precheck/rebuild-before-retry rule (MC-09) |
| FM-16 | An upgrade fixture left an undiagnosed file count (331 vs expected) — explicitly NOT claimed as a reproduction |
| FM-17 | The intended browser-Dashboard upgrade path was blocked by unavailable Studio tooling; a direct-API equivalent was substituted, and the Studio CLI path is now located and recorded |
| FM-26 | Two structural Trac MCP limitations (no milestone filter, blank `component` field) cap what the census can enumerate automatically |

## Accepted method changes

15 ACCEPTED + 1 ACCEPTED-WITH-LIMIT (MC-04, REST path only). Verified against `method-change-proposals.csv`.

| MC | Rule | Prevents | Controls (pos / neg) | Shadow-run evidence |
|---|---|---|---|---|
| MC-01 | Diff release trees against `$_old_files` before any upgrade fixture test | FM-01 | SR-01, SR-02 / SR-03 | SR-01/02 CAUGHT-REAL-ISSUE (243; 1 undeclared removal); SR-03 CLEARED-SUSPECTED (0 on identical trees) |
| MC-02 | Core's own `update_core()` is the only path that proves Core behavior; WP-CLI is a separate lane and negative control | FM-01, FM-02 | beta4 runtime (Core left 243) / beta4 runtime (WP-CLI cleaned 243) | Runtime-reproduced in beta4 QA |
| MC-03 | Run the build-identity gate before any pilot testing | FM-16 | SR-05 / SR-06 | SR-05 MISCALIBRATED-FIXED; SR-06 CLEARED-SUSPECTED |
| MC-04 | REST `content.rendered` as ground truth for content-vs-chrome extraction (ACCEPTED-WITH-LIMIT: REST path only) | FM-20, FM-21 | SR-07 / SR-08 | SR-07 CAUGHT-REAL-ISSUE; SR-08 CLEARED-SUSPECTED |
| MC-06 | Gated/empty content is never evidence of absence | FM-20 (r1 BLOCKED population) | SR-10 / SR-07 unaffected | SR-10 MISCALIBRATED-FIXED |
| MC-07 | Quote-agnostic, multi-layer payload decoder for embedded config | FM-19 | SR-11 / SR-12 | SR-11 CAUGHT-REAL-ISSUE; SR-12 MISCALIBRATED-FIXED |
| MC-08 | Assert the full multisite denominator before reading any N/N result | FM-03, FM-15 | SR-13 / n/a | SR-13 CAUGHT-REAL-ISSUE |
| MC-09 | Harness-health precheck with batch invalidation on failure | FM-13, FM-14, FM-16, FM-17 | beta4 Colima recovery / n/a | Three separate beta4 batches invalidated by harness faults |
| MC-10 | Native control must PASS before any product keyboard verdict | FM-06 | beta4 rerun confirmed Tabs defects / beta4 first run native button also failed | Reversed a wrong INCONCLUSIVE-vs-CONFIRMED call |
| MC-11 | Threat-model gate: inside-WP-only reachability is a footgun, not a vulnerability | FM-07, FM-12 | beta4 `wp_delete_site(1)` / beta4 default-role denial | Prevents severity inflation |
| MC-12 | Preserve refuted/narrowed claims as permanent negative controls | FM-08, 09, 10, 11, 12, 25 | n/a / the 9 negative-control rows | Directly implements the operator's stated working read |
| MC-13 | Mandatory evidence record for every non-clear claim | FM-23 | r2 run, 155+ records / n/a | Was release-blocking for credibility in the r1 Codex review |
| MC-14 | Semantic coverage matching; never key-join alone | FM-22 | r2 CH-B semantic matches / r2 census 247-ticket overstatement | Key-join overstated uncovered population by an order of magnitude |
| MC-15 | Blocker-remediation queue: tier/owner/access/closure condition | FM-24, FM-10, FM-17 | r2 53-row queue / n/a | 28 of 42 blocked rows were previously unrouted |
| MC-16 | Retire title-term shard selection | FM-25 | n/a / 3/25 then 0/17 true-hit rate | Replaced by version-taxonomy and change-surface selection |
| MC-17 | Cross-model agreement raises priority only; runtime reproduction decides | FM-06; carried from the wp-audit skill | beta4 source-only 5 confirmed → runtime changed 2 / n/a | Carried forward verbatim |

## Rejected / deferred method changes

| MC | Proposal | Reason |
|---|---|---|
| MC-05 | Structural-strip fallback for non-REST content pages | REJECTED — failed its negative control. SR-09: an in-body Table-of-Contents widget on a non-REST page survived structural stripping and scored a false CONTENT-HIT (NOISE). Replaced by exact-phrase claim matching + manual locator; the fallback path stays in D-01 as advisory-only |
| MC-18 | Auto-file Trac tickets for confirmed defects | REJECTED — external side effects out of scope. Operator approval is required for any external filing under standing rules; confirmed defects route to the blocker-remediation queue instead |
| MC-19 | Use GitHub PR merge-status as release evidence on mirror repos | REJECTED — structurally false signal (FM-27). The mirror bot-closes PRs rather than merging them; org-wide `is:pr is:merged` returned 0 despite thousands of shipped changes |
| MC-20 | Full open-ticket Trac census via MCP | DEFERRED — needs a human browser session on Trac's query UI. `searchTickets` cannot filter by milestone and `getTicket`'s `component` field is always blank (FM-26); roughly 84 open tickets remain unenumerable through allowed automated routes |

## Detector status

5 of 7 detectors are calibrated-and-proven; 2 are accepted but unexercised, awaiting a build.

| D | Detector | Status | Positive control | Negative control |
|---|---|---|---|---|
| D-01 | content-vs-chrome extractor | ACCEPTED (REST path only) | SR-07 CAUGHT-REAL-ISSUE | SR-08 CLEARED-SUSPECTED (fallback path separately tested and REJECTED — SR-09 NOISE) |
| D-02 | Playground blueprint decoder | ACCEPTED | SR-11 CAUGHT-REAL-ISSUE | SR-12 MISCALIBRATED-FIXED |
| D-03 | release build-identity gate | ACCEPTED | SR-05 MISCALIBRATED-FIXED | SR-06 CLEARED-SUSPECTED |
| D-04 | multisite denominator asserter | ACCEPTED | SR-13 CAUGHT-REAL-ISSUE | n/a (read-only; no false-positive surface) |
| D-05 | stale-file / `$_old_files` detector | ACCEPTED | SR-01, SR-02 CAUGHT-REAL-ISSUE | SR-03 CLEARED-SUSPECTED |
| D-06 | Core-vs-tool updater lane separation | ACCEPTED-UNEXERCISED | SR-14 UNEXERCISED — blocked on RC1 | — |
| D-07 | real-input a11y calibration harness | ACCEPTED-UNEXERCISED | SR-15 UNEXERCISED — blocked on RC1 | — |

## The calibration honesty section

Three of the five proven detectors FAILED a control on their first run and were fixed before
acceptance. One path was rejected outright rather than fixed. This is the loop working as designed:
a detector that has never failed a control has never actually been calibrated — it has only been
run once and believed.

- **SR-05, D-03 build-identity gate.** First run reported a real, released build (WordPress 7.1
  Beta 4) as `WAITING-FOR-BETA4`. Cause: the release feed's title ("Beta 4") didn't match an
  un-normalized comparison pattern ("7.1beta4"). Left unfixed, this detector would have reported
  WAITING forever on an already-released build. Fixed with case/space/dot normalization, then
  re-verified RELEASED.
- **SR-10, D-01 gated-content guard.** Before the guard existed, every enrollment-gated Learn lesson
  silently read as content-clean — zero-length content meant every search term scored ABSENT, which
  looked identical to a genuinely clean page. The guard now emits `STATE=GATED-OR-EMPTY` and exits
  non-zero instead of reporting a false-clean result.
- **SR-12, D-02 blueprint decoder.** First run matched the plugin's site-wide enqueued script and
  reported a false `EMBED-PRESENT` on a lesson page with no actual Playground block. Fixed by
  tightening detection to the block marker itself rather than the script tag — the same
  chrome-vs-content trap recurring inside a different detector.
- **SR-09, D-01 fallback path — rejected, not fixed.** The structural-strip fallback for non-REST
  pages was tested against an in-body Table-of-Contents widget and produced a false CONTENT-HIT
  (NOISE) because in-body widgets aren't inside `<nav>`/`<aside>` tags the stripper removes. Rather
  than patch the stripper, the fallback path was demoted to advisory-only; the REST-only path, which
  has both controls passing, is the accepted rule.

None of this is a black mark against the method — it is the calibration step doing its job. A
detector accepted without ever having failed a control is a detector nobody tried to break.

## Negative controls preserved

Nine failure-mode rows are permanently preserved as negative controls (`control_role=negative-control`
in the register) — they must come back clean on every future run, and none should be resurrected
without a genuinely new mechanism and a fresh reproduction.

| FM | Protects against |
|---|---|
| FM-03 | Re-filing "N/N success hides held-back sites" as an upgrade defect instead of a reporting-clarity issue |
| FM-07 | Treating an inside-WP-only reachable API (`wp_delete_site(1)` direct call) as an externally reachable vulnerability |
| FM-08 | Re-raising KSES's by-design allowance of `<img>` in post context as a sanitization defect |
| FM-09 | Re-raising a defect behind an unreachable pre-4.3 DB-version guard as a live issue |
| FM-10 | Treating ms-files.php's non-regressed direct-handler behavior as a routing regression |
| FM-11 | Over-claiming a serialization-CVE fix from one input shape (top-level `C:` only) when nesting still invokes the callback |
| FM-12 | Reporting a capability-boundary finding that only appears under a custom grant as a default-configuration finding |
| FM-25 | Reintroducing title-term text matching as a shard-selection strategy |
| FM-27 | Using GitHub PR merge-status as release evidence on an SVN-mirrored repo |

## Open threads — exact closing conditions

| Thread | Closing condition |
|---|---|
| D-06 and D-07 are ACCEPTED-UNEXERCISED (SR-14, SR-15); fixtures FX-07/FX-08 are WAITING-FOR-RC1; the phase-2 chain-test suite (`deliverables/codex-feature-chain-test-generation-prompt.md`) needs a verified build to run against | WordPress 7.1 RC1's build-identity gate (D-03) returns RELEASED. Does not exist as of 2026-07-30 |
| FM-04 (REST url-import downloads before multisite size rejection) is BLOCKED from new filing | Owner approval to comment on the existing, already-REOPENED Trac #65517 |
| FM-10's public legacy-URL serving path remains untested | FX-09, the legacy ms-files rewrite fixture — currently PROPOSED, not yet built |
| FM-16's Core_Upgrader run left an undiagnosed file count (331); FX-04 is marked AVAILABLE-SUSPECT | Diagnose invocation vs. fixture before reusing FX-04 or claiming this as a reproduction |
| FM-26 / MC-20: roughly 84 open Trac tickets are unenumerable through allowed automated routes (searchTickets has no milestone filter; getTicket's component is always blank) | A human browser session against Trac's query UI — deferred, not scheduled |
