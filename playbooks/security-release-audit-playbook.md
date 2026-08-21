---
title: "Security release-audit playbook"
type: playbook
status: active
created: '2026-07-31'
updated: '2026-07-31'
source_run: "$WP_AUDIT_ROOT/ (evidence + scripts remain there)"
tags:
  - wordpress
  - wp-audit
  - security
  - release-audit
related:
  - '*../index*'
  - '*../release-audit-learning-loop*'
---

# Security release-audit playbook

> **Where this fits:** the security axis of [`wp-release-followup`](../skills/wp-release-followup/SKILL.md) §3.
> Grounded in [security invariants](../method/security-invariants.md) and
> [attack surfaces](../method/wordpress-attack-surfaces.md). Proof standard:
> [validation and proof](../method/validation-and-proof.md).

Operator-grade procedure for security-relevant findings in the WordPress release-audit loop. Every rule below cites the FM-/MC-/SR- row it comes from. Do not add a rule here without a citation.

## Scope and authorization boundary

- Authorized defensive testing only, in disposable local environments (Studio sites, wp-env cells). Never production, wordpress.org, third-party sites, or unowned plugins.
- No external filing — Trac comments, new tickets, disclosures — without explicit operator approval, even for a CONFIRMED finding. Auto-filing was proposed and rejected specifically because external side effects require operator sign-off under standing rules. [MC-18 REJECTED]
- Concrete case: the CONFIRMED REST url-sideload defect (full file downloads before the multisite size check rejects it) maps onto an existing, currently-REOPENED upstream ticket, Trac #65517. Filing is BLOCKED pending owner approval to comment on that ticket — it does not get a new filing. [FM-04]
- Sensitive material (credentials, exploit-grade detail) never leaves the loop's private channel. See "Sensitive-material boundary" below. [FM-18]

## The backport matrix — which branches got the fix, and to what version

A fleet on mixed branches has an operational question no single-build check answers: *which
branches carry this security fix, and what is the exact fixed version on each?* Three
WordPress security releases shipped in under a month, and they establish the pattern —
including that the assumptions break:

| Release | Date | CVE / CVSS | Backported through | Note |
|---|---|---|---|---|
| **7.0.2** | July 2026 | — | — | Critical pre-auth RCE + high-severity SQLi |
| **7.0.3** | 2026-08-06 | CVE-2026-64638 / **8.9** | **4.7** branch — every version | Pre-auth reflected XSS on the login screen. Root cause is a **parser disagreement**: a tag-like string with whitespace after the opening `<` survives `wp_strip_all_tags()` (built on PHP `strip_tags()`) as text, but `wp_kses_post()` treats it differently. Two facts worth encoding as invariants — a **nonce-based CSP using `strict-dynamic` did not block the demonstrated path**, and in the full chain **the uploaded plugin did not need to be activated** for its PHP to be requested directly |
| **7.0.4** | — | **none published** | **4.7** through 7.0 | Author+ RCE via Imagick + Ghostscript. **No CVE and no CVSS** in available sources — encode that: a security release does not imply a CVE. The [upload-content-signature class](../plugin-theme-authors/upload-content-signature.md) is the plugin-author inheritance of this |

The scope discipline in the sources is worth copying: the 7.0.3 XSS was reproduced against
two live 7.0.2 deployments, but the full PHP-execution chain was demonstrated **only on a
clean local install** — so "affects every version" applies to the XSS, not automatically to
the chain (The Hacker News, 2026-08-07). State which claim your evidence actually reaches.

The matrix lives in [`data/security-releases.csv`](../data/security-releases.csv). The
security-fix presence gate reads it:

```bash
# does the build carry every fix in the matrix, across the whole backport set?
bash scripts/security_fix_presence.sh <target-zip-or-dir> --all
```

`--all` diffs each row's `diff_prev -> fixed_in` fix set against the target and flags any
that read VULNERABLE — so a fleet build on an arbitrary version is checked against the whole
known set rather than one hardcoded pair. Calibrated 2026-08-21: 7.0.3 reads all-PATCHED for
the 7.0.2 and 7.0.3 rows and correctly VULNERABLE for the 7.0.4 fix that shipped after it —
the exact "we're a point release behind on this branch" signal. The single-pair form
(`... <prev> <fixed>`) still works for one release.

Honest limits carry over from the single-pair mode: it reads lines not semantics (a change
confined to a docblock reads VULNERABLE), DIVERGED needs a human, and for any high-severity
fix confirm behaviorally rather than trusting the line diff.

## Lanes: blind first-principles, changed-surface, reconcile

Run two independent passes and reconcile only after both report — never mid-pass.

| Lane | Inputs allowed | Inputs forbidden |
|---|---|---|
| Blind first-principles | A clean source snapshot of the target build only | `.git` history, changelogs, known Trac ticket numbers, prior findings/registers, internet search |
| Changed-surface | The diff/changelog against the prior stable and prior beta, the change ledger, prior findings | — |

Pattern-matching against a known fix only finds what pattern-matching already knew. The blind lane exists to force first-principles analysis on a snapshot with the answer key removed; the changed-surface lane exists to test what actually shipped. Neither substitutes for the other.

Reconciliation is not "the second pass polices the first." Two loop lessons say so directly:

- A blueprint-decoder finding was initially quarantined, then the orchestrator's own refutation of it was shown to be wrong on a later independent pass — the finding was reinstated. Challenge cycles must be able to cut in either direction. [FM-19]
- Source-only agreement is not proof by itself: five beta4 defects confirmed by source-reading alone were re-checked at runtime, and two changed on execution. Cross-lane agreement raises priority; runtime reproduction decides the verdict. [MC-17]

## Threat-model gate

Before any authorization, sanitization, upload, or deletion finding gets a CONFIRMED verdict, state three things:

1. Attacker position — unauthenticated / subscriber / contributor / admin / super admin / code already executing inside WordPress.
2. The boundary crossed.
3. Default-configuration reachability — does this fire on a stock install, or only with a non-default grant?

Two rules follow directly from this loop's own history of over-claiming severity:

| Rule | Grounding | Effect |
|---|---|---|
| An API reachable only by code already executing inside WordPress is an internal footgun, not a vulnerability | `wp_delete_site(1)` deletes the main site when called directly with no default deletion validator on that path — but normal Core UI callers guard it. [FM-07] | Downgrade to footgun; do not report at vulnerability severity |
| A result that only holds under a custom capability mapping is configuration-dependent | A subadmin's `edit_users` capability only returned true after granting a custom `manage_network_users` capability; default roles denied it. [FM-12] | Record the non-default precondition; do not claim default-install exposure |

This gate is [MC-11], derived from FM-07 and FM-12 specifically to prevent severity inflation and keep any future disclosure channel credible.

## Verdict vocabulary

Every finding resolves to exactly one of: **CONFIRMED, REFUTED, INCONCLUSIVE, BLOCKED, INVALID**. Never call an unproven result a vulnerability.

- **CONFIRMED** — reproduced at runtime in an authorized fixture, with fixture-state assertions and required controls recorded.
- **REFUTED** — tested and did not hold, or held only under a mechanism that disqualifies it (see negative controls below).
- **INCONCLUSIVE** — tested, but the result doesn't settle the question — for example, an automation fault masking the product result (see FM-06 under Control discipline).
- **BLOCKED** — cannot be tested from here; route to the blocker-remediation queue with a tier, owner, access requirement, and closure condition (see source-and-content-audit-playbook.md, MC-15).
- **INVALID** — the batch itself is unfit to produce a verdict (harness fault); exclude it from every count.

A finding that gets scoped down after more evidence is not silently reclassified — it's tracked as NARROWED in the register (FM-03, FM-07, FM-09, FM-11, FM-12 all moved this way) and the final entry becomes a permanent negative control.

## Control discipline and batch invalidation

Every test batch ships a positive control (a case expected to fail or differ) and a negative control (a case expected to come back clean). If either miscalibrates, abort the batch and exclude its results from the count.

A harness-health precheck — daemon, socket, container, ownership — runs before every batch. A harness fault is an INVALID batch, never a product failure. [MC-09] Three separate beta4 batches were invalidated by exactly this:

| FM | Fault | Rule |
|---|---|---|
| FM-13 | Colima/Docker storage I/O error misread as a WordPress failure | H-01: verify daemon/socket/container health before classifying any test as a product failure |
| FM-14 | Root-owned fixture files; `update_core()` deleted its own failed source fixture on retry | H-02: rebuild the source fixture and assert ownership before every retry; exclude failed attempts from all counts |
| FM-16 | A Core_Upgrader run left the icon directory at 331 files and was initially claimed as a reproduction | Do not claim a reproduction from an undiagnosed fixture state; row stays BLOCKED pending diagnosis |

A related control-discipline rule that applies to any keyboard/focus claim: a native control element must PASS the same synthetic input in the same harness before a product verdict counts. The first beta4 accessibility run produced what looked like INCONCLUSIVE Tabs behavior, but its native-button control also failed in that run — the automation was broken, not the product. A rerun with a passing native control confirmed the Tabs keyboard defects were real. [MC-10; FM-06]

## Permanent negative controls

Five rows in the failure-mode register are refuted or narrowed claims that stay in the suite permanently as negative controls — tests that must keep coming back clean every cycle. If one starts failing, the harness is wrong before WordPress is. [MC-12]

| FM | Claim tested | Why it stays a negative control |
|---|---|---|
| FM-08 | KSES strips/permits `img` — claimed sanitization defect | `wp_kses_post()` allows literal `img` in post context by design; the claim mis-modeled the allowed-tag context. Do not resurrect without a new mechanism and a new reproduction. |
| FM-09 | Strict `Sub_part` comparison is a live defect | Sits behind a pre-4.3 DB-version guard, unreachable on any supported upgrade path. Negative control for the "reachability gate" rule. |
| FM-10 | ms-files.php legacy routing regression | Source guards intact; direct handler returns a clean 404. The public-serving path is still UNTESTED — blocked because wp-env's `.htaccess` lacks the legacy rewrite; closes when FX-09 (legacy rewrite fixture, currently PROPOSED) exists. |
| FM-11 | Serialization: top-level `C:` blocked proves the CVE path fixed | Top-level `C:` is blocked, but nested `C:` inside an accepted array still invokes the callback. Retained against over-claiming a fix from a single input shape. |
| FM-12 | Multisite capability boundary makes `edit_users` Super-Admin-only | Only true under a custom capability grant; default roles deny it. Also the concrete negative control behind the threat-model gate above. |

## Sensitive-material boundary

Credentials, secrets, and exploit-grade detail never enter a report or a memory file. One beta4 rollout printed an admin password into tool output, and it was preserved in a summary. [FM-18, rule P-01] Sensitive material goes to `private/security/` only and is never synthesized into a general report or memory.

## Evidence record requirement

Every non-clear claim (anything that isn't a plain NO-CHANGE) ships an evidence record: URL, status, locator, excerpt, sha256, and a replay command. [MC-13] This was raised as release-blocking by an independent review of the r1 pass, which found narrative conclusions with no preserved original payload — findable in the audit's CSV/JSON/markdown outputs but not reproducible from them. [FM-23] The r2 pass produced 155+ hashed evidence records under this rule. Treat it as mandatory, not optional documentation.
