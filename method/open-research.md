---
title: "Open Research, Limitations & Independent Review"
type: analysis
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - wordpress
  - security-audit
  - limitations
  - review
related:
  - '*index*'
  - '[security-invariants](../method/security-invariants.md)'
  - '[validation-and-proof](../method/validation-and-proof.md)'
---

# Open research, limitations & independent review

A fresh-context agent adversarially reviewed the finished methodology (Loop rule 5/10). Its findings are recorded with disposition: **fixed** (repaired in the files) or **residual** (a real limitation this methodology still carries).

## Independent-review dispositions
| # | Weakness (fresh-context reviewer) | Disposition |
|---|---|---|
| 1 | Playground/SQLite can't reproduce the MySQL-specific SQLi crux | **Fixed** — DB-engine gate added: forbid Playground/SQLite for `wpdb`/SQLi/collation proofs; require real MySQL/MariaDB + pinned collation ([wordpress-attack-surfaces](../method/wordpress-attack-surfaces.md), *skill-provenance (not published — see README)*). |
| 2 | Same-model verifier isn't truly independent | **Fixed** — high/critical findings now require a differently-constructed oracle (differential test / different model) ([orchestration](../method/orchestration.md)). |
| 3 | Catalog over-fits the one chain; next differently-shaped bug has no home | **Partly fixed** — added invariants #27–35, a mandatory `unknown-shape` family, and "measure coverage against an external corpus." **Residual:** the corpus itself isn't built yet (see open questions). |
| 4 | No deserialization / object-injection invariant | **Fixed** — invariant #27. |
| 5 | Negative controls model-authored; calibration corpus undefined | **Fixed** — controls must come from a pre-registered human-curated corpus; a model-authored control can't promote a finding ([validation-and-proof](../method/validation-and-proof.md)). **Residual:** the corpus must actually be assembled. |
| 6 | "No third door" vs "coverage receipt has no gaps" — null result had no exit | **Fixed** — null-result closure rule (source-trace + bounded enumerated config set) ([validation-and-proof](../method/validation-and-proof.md)). |
| 7 | Bounded-proof + no-third-door unsatisfiable for un-buildable third-party targets | **Fixed** — bounded-environment escape hatch: unprovable → hypothesis with stated limitation. |
| 8 | Convergence cap could starve the correct crowded family | **Fixed** — convergence is now yield-gated, not headcount-gated ([orchestration](../method/orchestration.md)). |
| 9 | "Blocked, reopen only on new mechanism" shelves chainable dead-ends | **Fixed** — mandatory bypass check (re-entry/recursion/other primitive) before a route is called blocked. |
| 10 | No SSRF invariant (ironic, chain runs through oEmbed) | **Fixed** — invariant #28. |
| 11 | XSS output-context and CSRF-nonce-required under-specified | **Fixed** — invariants #29, #30. |
| 12 | No charset/collation/i18n invariant | **Fixed** — invariant #31 + connection-charset parity in the matrix. |
| 13 | No race/TOCTOU invariant; single-request repro can't surface one | **Fixed** — invariant #32 + concurrency note that single-request repro can't disprove races. |
| 14 | Hand-run analysis presented as automation | **Fixed** — `fired` vs `source-attested` labeling; only owned-repo `wp-audit` is a real harness ([validation-and-proof](../method/validation-and-proof.md)). |
| — | Diff-ledger anchoring re-introduces the diffing blind spot | **Fixed** — anchoring guard: first-principles read runs independently of the ledger ([audit-playbook](../method/audit-playbook.md)). |
| — | Autoload options/meta + Interactivity API listed but not tested | **Fixed** — invariants #33, #34. |

## Residual limitations (what this methodology still may miss)
- **The external bug corpus is a dependency, not yet an asset.** Invariant-coverage measurement and control calibration both assume a curated corpus (CWE / Patchstack-class advisories / prior audits). Until it exists, coverage claims and control calibration rest partly on judgment.
- **Third-party proof is attestation, not enforcement.** For targets that can't be safely built, the gates are a checklist a model checks off. That is honest but weaker than the owned-repo firing loop; treat third-party "findings" as `source-attested` hypotheses pending coordinated verification.
- **Discovery breadth remains the true ceiling** (vault lesson): firing only proves what you fire; the invariant catalog only finds what it names. A genuinely novel bug shape can pass everything here. The `unknown-shape` family mitigates but does not remove this.
- **Repro fidelity caps some classes outright:** persistent object cache, multisite boundary bugs, external queues, and races need environments/harnesses beyond a single disposable site; where they're unavailable the verdict is *hypothesis*, not clean.
- **Cost/repeatability are unmeasured.** Like the source article, this methodology has no measured false-positive/false-negative rate, coverage %, or time-to-verification. Those require running it against a known-bug corpus.
- **Model monoculture** in orchestration: most agents share a base model; cross-model verification is required only for high-severity, so mid-severity findings still carry correlated blind spots.

## Open questions
1. Which corpus becomes the calibration + coverage oracle, and who curates it? (candidate: a private set drawn from prior owned-plugin audits + published advisory classes.)
2. Should the full multi-round audit become a scheduled **Workflow** (opt-in) with a registry row, or stay operator-launched per target?
3. What's the minimum faithful environment for the cache↔DB reconciliation class — Studio + Redis, or a container with a real persistent object cache?
4. Can the null-result closure rule be made deterministic enough to be a script (exit-code check), or does it stay a human sign-off?

## Untested areas (recorded, not hidden)
No live target was audited in this methodology-design task — the feature/change ledger, coverage receipt, and repo prompt are **templates**, unexercised against real code. First real application should treat its own first run as a calibration run and feed misses back into [security-invariants](../method/security-invariants.md) and the corpus.
