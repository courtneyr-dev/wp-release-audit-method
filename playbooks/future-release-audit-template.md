---
title: "Future release-audit template (release-parameterized)"
type: template
status: active
created: '2026-07-31'
updated: '2026-07-31'
source_run: "$WP_AUDIT_ROOT/ (evidence + scripts remain there)"
tags:
  - wordpress
  - wp-audit
  - release-audit
  - template
related:
  - '*../index*'
  - '[security-release-audit-playbook](../playbooks/security-release-audit-playbook.md)'
---

# Future release-audit template

> **Where this fits:** starting a cycle cold. Then [`wp-release-prep`](../skills/wp-release-prep/SKILL.md) →
> [`wp-release-party`](../skills/wp-release-party/SKILL.md) → [`wp-release-followup`](../skills/wp-release-followup/SKILL.md).
> Bracketed row ids like [D-03] and [FM-15] are defined in [registers.md](../method/registers.md).

A release-parameterized checklist. Every placeholder below must be substituted before use; no version number, ticket number, date, fixture path, or db_version from a prior cycle should appear here unsubstituted.

## Placeholders

| Placeholder | Meaning |
|---|---|
| `$VERSION` | Target release version (e.g. the next cycle's number) |
| `$PRIOR_STABLE` | Last stable release before `$VERSION` |
| `$PRIOR_BETA` | Prior beta/RC within the `$VERSION` cycle |
| `$TARGET_LABEL` | Build label under test (`rc1`, `beta4`, etc.) |
| `$BRANCH_POINT` | SVN/Git ref the cycle branched from |

The 7.1 cycle's concrete values (7.1, 7.0.2, 7.1-beta3, beta4/rc1, a trunk revision) appear in the cited evidence below only as illustration of the pattern — do not copy the values themselves into a `$VERSION` audit. See "Do not copy forward."

## G0 — build-identity gate

- **Entry condition:** a pilot or audit pass is about to start for `$VERSION` `$TARGET_LABEL`.
- **Required artifacts:** none — this gate runs before any fixture exists.
- **Procedure:** `scripts/rc_build_identity.sh $VERSION $TARGET_LABEL`. Requires BOTH an announcement-feed title match AND a downloadable package at `wordpress-$VERSION-$TARGET_LABEL.zip`; normalizes label casing/spacing/punctuation before comparing. [D-03]
- **Exit condition:** exit 0 / `VERDICT=RELEASED` to proceed. Exit 3 / `VERDICT=WAITING-FOR-$TARGET_LABEL` means stop — do not test a mislabeled or absent build. WAITING is a correct, expected outcome, not a gate failure: a live run on 7.1 rc1 correctly returned WAITING when three independent signals (announcement feed, package, trunk `version.php`) agreed rc1 didn't exist yet. [SR-04; MC-03]
- **Known miscalibration risk:** the detector's first-ever run reported a false WAITING because it compared an unnormalized label against the feed's title text; a second, fixed run confirmed RELEASED correctly. Confirm the normalization logic still matches the current announcement-feed title format for `$VERSION` before trusting a WAITING result from an unverified copy of the script. [SR-05 MISCALIBRATED-FIXED]
- **Detectors:** D-03 only.

## G1 — source-universe registers

- **Entry condition:** G0 passed, or this is explicitly a pre-release/source-only pass that doesn't need a shipped build.
- **Required artifacts:** the Make team-site matrix (RELEVANT-HITS-REVIEWED / ZERO-HITS-VERIFIED / NOT-ACTIVE-IN-WINDOW / BLOCKED per team), the GitHub org register with per-repo relevance rulings, the Trac census via allowed routes, and the Source-of-Truth register. Full schema and query rules Q-01/Q-02 in source-and-content-audit-playbook.md.
- **Exit condition:** all four registers populated for `$VERSION`, or every unpopulated cell carries a BLOCKED code routed to the blocker-remediation queue. [MC-15]
- **Ceiling to re-verify, not assume fixed:** the Trac MCP route couldn't filter by milestone and left `getTicket`'s component blank at 430-call scale in the 7.1 cycle. Confirm this is still true for `$VERSION` before relying on milestone-filtered counts — it may be fixed, or may not be. [FM-26]
- **Detectors:** none of D-01–D-07 apply directly; apply Q-01/Q-02 procedurally. No calibrated script exists for source-universe queries as of this loop.

## G2 — change ledger with provenance tiers and challenge verdicts

- **Entry condition:** G1 substantially complete — the registers supply the raw material for ledger rows.
- **Required artifacts:** a change ledger for `$VERSION`, one row per change/feature, each carrying a `challenge_status`. The one documented description of this field (from the chain-test generation prompt, outside this loop's four core registers) says `challenge_status` distinguishes UPHELD from UNVERIFIED, with rows additionally able to carry a VERIFY-RC flag when tied to a reopened Trac ticket. Prefer UPHELD rows as anchors for any interaction/chain testing in G4. Separately, that same document's chain-seed provenance table shows anchor-level annotations — REOPENED, NEW-THIS-RUN, REVISED — attached to specific tickets; treat these as descriptive context for an anchor, not confirmed as additional values of the `challenge_status` field itself, since the ledger file's full column definitions live outside this loop's required registers. [prompts/codex-feature-chain-test-generation-prompt.md]
- **Provenance discipline:** every non-clear ledger row (anything that isn't a plain NO-CHANGE) needs an evidence record — URL, status, locator, excerpt, sha256, replay command. This was release-blocking in an independent review of the r1 pass, which found narrative conclusions with no preserved original payload. [MC-13; FM-23]
- **Exit condition:** every ledger row has a `challenge_status`, and every non-clear row has an evidence record.
- **Detectors:** none directly; MC-13's evidence-record requirement is a process gate, not a script.

## G3 — fixture construction with state assertions

- **Entry condition:** G2 identifies the surfaces that need fixtures.
- **Required artifacts:** one fixture per test lane (single-site, multisite, upgrade-path, RC1 clean-install, etc.), each with its state-assertion procedure run and recorded before use — never assumed from the brief.
- **Procedure, by fixture type:**
  - Any fixture: harness-health precheck first — daemon, socket, container, ownership. A harness fault invalidates the whole batch; it is never read as a product result. [MC-09; FM-13; FM-14]
  - Multisite fixture: run `scripts/assert_multisite_denominator.sh` before reading any N/N upgrade output. Print total sites, eligible count, held-back count, and per-site db_version. [D-04; FM-03; FM-15]
  - Upgrade-path fixture: assert source-tree ownership before each attempt; rebuild the source fixture per attempt — a failed `update_core()` can delete its own source fixture and corrupt the next retry. [FM-14]
  - Offline release-tree fixture: checksum the tree before diffing it.
- **Exit condition:** every fixture used in G4 has a recorded, passed state assertion for this run of `$VERSION` — not a reused assertion carried over from a prior cycle.
- **Detectors:** D-04 (multisite); D-05 (stale-file, run offline against release trees before any upgrade fixture is built — see G4).

## G4 — security, performance, upgrade, and multisite passes

Four passes, each with its own playbook and detector set. None substitutes for another.

| Pass | Playbook | Detectors | Status entering a fresh cycle |
|---|---|---|---|
| Security | security-release-audit-playbook.md | Threat-model gate (MC-11), verdict vocabulary, permanent negative controls (FM-08–FM-12) rerun as-is every cycle | Calibrated — negative controls must stay clean |
| Performance | performance-release-audit-playbook.md | None calibrated yet | UNEXERCISED — every number produced is provisional until it has its own shadow run |
| Upgrade | This template plus D-05/D-06 | D-05 stale-file check, offline, before any upgrade fixture exists; D-06 Core-vs-tool lane separation — Core's `update_core()` is the only path that proves Core behavior, WP-CLI's extra cleanup is a separate lane and a negative control | D-05 calibrated (SR-01/02/03); D-06 UNEXERCISED, blocked on a real `$TARGET_LABEL` build (SR-14) |
| Multisite | This template plus D-04 | D-04 denominator asserter | Calibrated (SR-13) |

If the cycle's surfaces include keyboard/focus behavior, also run the native-control calibration rule: a native element must PASS the same synthetic input before any product accessibility verdict counts. [D-07; MC-10; FM-06] D-07 itself is UNEXERCISED pending a `$TARGET_LABEL` build with a browser-capable fixture. [SR-15]

- **Entry condition:** G3 fixtures built and asserted.
- **Exit condition:** each pass reports CONFIRMED/REFUTED/INCONCLUSIVE/BLOCKED/INVALID counts per the verdict vocabulary; permanent negative controls (FM-08–FM-12) confirmed still clean this cycle.

## G5 — content and method feedback

- **Entry condition:** G1–G4 produced findings, blockers, or method friction worth recording.
- **Required artifacts:**
  - Content claims run through D-01 (REST path only) with the GATED-OR-EMPTY guard, per source-and-content-audit-playbook.md.
  - Every BLOCKED row from any gate routed into the blocker-remediation queue with tier, owner, access requirement, and closure condition. [MC-15]
  - Any method friction — a detector miscalibration, a new false-positive class, a harness fault — written up as a new failure-mode-register row, and, if it changes a method, a new method-change-proposal row. This step is what makes the next cycle's G0–G4 better calibrated than this one's; skipping it is how the loop stops learning.
- **Exit condition:** failure-mode-register.csv and method-change-proposals.csv updated for `$VERSION` before the pass is called done. Any new detector gets a shadow-run row — positive and negative control — before it's marked ACCEPTED.
- **Detectors:** D-01, D-02 (content/blueprint claims); MC-14/Q-02 (semantic coverage, never key-join alone) for reconciling the ledger against the source-universe registers.

## Do not copy forward

Nothing version-specific from a prior cycle is a valid assumption for the next one. Concretely, do not carry forward:

- **Version numbers and labels** — re-derive via G0 for `$VERSION`; do not assume the prior cycle's label format (e.g. "beta4" vs "Beta 4") matches the next one.
- **Ticket numbers and their status** — a ticket REOPENED during one census (e.g. #65517) may be closed, reopened again, or superseded by the next cycle. Re-check status; don't assume it. [FM-04]
- **Dates** — announcement dates, freeze dates, branch points are per-cycle.
- **Fixture ports and fixture paths that bake in a version** — the 7.1 cycle's own fixture registry names paths like `codex-wp71-beta4-qa`, `codex-wp71-beta4-multisite`, `codex-wp702-upgrade`, and `codex-wp71-beta3-core-upgrader`, each with the version baked into the directory name. Build fresh, distinctly-named fixtures for `$VERSION` rather than reusing or renaming these.
- **db_version values** — the 7.1 cycle's 61833/61832 pair is specific to that cycle; the next cycle has its own values, and the multisite denominator check must re-read them live, never assume them. [FM-03]
- **Build-identity artifacts** — a recorded zip MD5 or similar hash authenticates one specific build and means nothing for `$VERSION`'s build; re-derive through G0 each cycle.
