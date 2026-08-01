---
title: "Release-audit learning loop — method decisions, controls, and detectors"
type: method
status: active
created: '2026-07-30'
updated: '2026-07-30'
tags:
  - wordpress
  - security-audit
  - methodology
  - release-audit
  - loop-engineering
  - controls
related:
  - '*index*'
  - '[validation-and-proof](../method/validation-and-proof.md)'
  - '[audit-playbook](../method/audit-playbook.md)'
  - '[security-invariants](../method/security-invariants.md)'
---

# Release-audit learning loop

> **Run these rules:** [`wp-release-prep`](../skills/wp-release-prep/SKILL.md) →
> [`wp-release-party`](../skills/wp-release-party/SKILL.md) → [`wp-release-followup`](../skills/wp-release-followup/SKILL.md).
> Worked examples: [`examples/chains/`](../examples/chains/). Start-here guide: [README](../README.md).

Generalizes the vault's *prove-by-firing* discipline from owned plugins to **WordPress core release auditing**. Built 2026-07-30 from WordPress 7.1 Beta 4 runtime QA, the 7.1 Learn content audit (runs 1 + 2), and an independent adversarial review of run 1.

Run root (evidence lives there, not here): `$WP_AUDIT_ROOT/`. Frozen predecessors: `$WP_LEARN_AUDIT_ROOT_R1/`, `$WP_LEARN_AUDIT_ROOT/`.

> Authorization: authorized defensive testing in disposable local environments only. Never production, WordPress.org infrastructure, third-party sites, or unowned extensions. No tickets, issues, PRs, or disclosures without explicit operator approval.

## 1. The five reusable laws

| Law | Origin | What it prevents |
|---|---|---|
| Source observation needs runtime proof | Beta 4: source-only pass called 5 claims confirmed; runtime changed 2 of them | Confident wrong findings |
| Clean installs don't cover upgrade behavior | `update_core()` left 243 removed files; a clean install shows nothing | Whole defect class invisible |
| Assert fixtures and denominators before reading results | network upgrade reported "2/2 sites" with 3 sites held back at the old `db_version` | Misread success |
| Severity needs a real attacker boundary | `wp_delete_site(1)` is reachable only by code already inside WordPress | Severity inflation, wasted disclosure credibility |
| Performance claims need repeated stable comparisons | — (no benchmark has been run; playbook is a design) | One-run "regressions" |

Sixth law added by this loop: **refuted claims are assets.** Nine narrowed/refuted claims are retained as permanent negative controls. If one starts failing, the harness is wrong before WordPress is.

## 2. Accepted controls (the ones that changed behavior)

- **Core-vs-tool updater lane separation.** WP-CLI's updater cleaned all 243 stale files and printed "243 files cleaned up"; Core's own path left them. Testing the tool proves nothing about Core. Two lanes, always.
- **Native-control calibration for keyboard/a11y claims.** Two Beta 4 sessions disagreed on the Tabs block. The earlier run's *native button* also failed the same synthetic input → automation failure, not product failure. A native control must pass before any product verdict counts. This rule reversed a wrong call.
- **Threat-model gate.** Internal footgun ≠ vulnerability; configuration-dependent ≠ default-configuration. Both distinctions came from narrowed Beta 4 claims.
- **Batch invalidation on harness fault.** Colima storage corruption, root-owned fixtures, a self-deleting source fixture, and a wrong site count each produced non-WordPress "failures." Diagnose, invalidate, preserve the diagnosis.
- **Mandatory evidence records** (URL, status, locator, excerpt, hash, replay command) for every non-clear claim — the single finding an independent review called release-blocking for credibility.

## 3. Detectors (calibrated, with controls)

Five detectors are proven against real positive **and** negative controls; two await a build. Scripts live in the run root's `scripts/`.

| Detector | Proves | Control result |
|---|---|---|
| Stale-file / `$_old_files` diff | Removed-but-undeclared files before any fixture exists | 243 (7.0.2→beta4), 1 (beta3→beta4), 0 on identical trees |
| Release build-identity gate | The build under test is the build you think | Correctly RELEASED on beta4, WAITING on RC1 and on a nonexistent version |
| Multisite denominator asserter | Held-back sites behind an "N/N success" | Live fixture: 5 total, 2 eligible, 3 held at old `db_version` |
| Content-vs-chrome extractor | Nav/sidebar/aria-label text isn't page content | Kills the false-positive class; **REST path only** |
| Embedded-config decoder | Quote-agnostic, multi-layer payloads | 3 pinned blueprints decoded; clean on a page with no embed |

**Calibration honesty:** three of the five failed a control on first run and were fixed before acceptance; one path (structural-strip fallback) was rejected outright for failing its negative control. A detector that has never failed a control has never been calibrated.

## 3b. Feature-chain testing (added 2026-07-30)

Every confirmed Beta 4 defect lived in an **interaction**, not a feature: validation order across site modes, a UI counter reading the wrong option scope, an updater's cleanup list disagreeing with the tree it shipped. Single-feature passes are structurally blind to those.

A cross-release ledger was built for this: 200 features across 6.3–7.0 from official sources, each carrying **where its state persists** and **which subsystems it must touch**. Four lenses (persistence, authorization, lifecycle, render) proposed 36 chains spanning releases.

**The result is the method lesson.** Zero chains survived adjudication unchanged — 16 refuted on verified-false premises, 20 corrected. Judges that read actual source disproved proposals that read as expert prose: `map_meta_cap()` resolves `edit_css` in the same switch arm as `unfiltered_html`, so a chain built on "two gates" was built on one. A proposer working from a catalog invents plausible surface names, capability relationships, and storage locations.

**Rule:** chain proposal must cite source per leg, and an independent source-reading judge adjudicates before any chain becomes a test. The judge lane is not optional review — it is the thing that made the output usable.

The strongest surviving chains all share a shape worth remembering: **an older release wrote data or set an expectation that a newer release changes.** Example — restoring a Global Styles revision silently reverts Font Library activation, because both live in the same `wp_global_styles` payload that revisions snapshot wholesale. Revision tests never build font state; font tests never restore a revision.

## 4. Sensitive / public boundary

- Credentials never enter reports, memories, or handoffs. One Beta 4 site-creation step printed an admin password into tool output — that is a process failure with its own register row.
- Confidential or privately-disclosed findings reduce to a bare acknowledgment in general reporting; mechanism, endpoint, and reproduction stay out.
- Sensitive evidence and any draft disclosure packet live in the run root's `private/security/` (mode 700), never in the vault.

## 5. Open threads

- Full Trac open-ticket census needs a human browser session; the MCP cannot filter by milestone and never returns `component`. ~84 open 7.1 tickets remain unenumerable by agent routes.
- Performance playbook is **unexercised** — no benchmark has been run. It states acceptance criteria only.
- Two detectors (Core-vs-tool updater lane, real-input a11y harness) are accepted but unexercised pending a release candidate.
- Legacy `ms-files.php` public-serving path stays blocked until a fixture ships the legacy rewrite rule.

## Related
- [validation-and-proof](../method/validation-and-proof.md) · [audit-playbook](../method/audit-playbook.md) · [security-invariants](../method/security-invariants.md) · *index*
- *Plugin Security Audit/index* — owned-plugin prove-by-firing (CONFIDENTIAL; findings not copied here)
- Content-audit half of the same loop: *llm-wiki-wp-training/wiki/analysis/2026-07-29-wp71-learn-content-audit-run*
