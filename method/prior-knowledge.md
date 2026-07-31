---
title: "Prior-Knowledge Brief — WordPress security-audit methodology"
type: analysis
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - wordpress
  - security-audit
  - loop-engineering
  - moc
related:
  - '*index*'
  - '[loop-engineering-ledger](../method/loop-engineering-ledger.md)'
  - '[audit-playbook](../method/audit-playbook.md)'
---

# Prior-knowledge brief

The vault already contains a **drafted, on-point methodology** and a mature Loop-Engineering / maker-checker corpus. This is a *reuse-and-generalize* job, not from-scratch.

## Conflict recorded (read first)
- **Overlap:** `1. Projects/Plugin Security Audit/` (dated 2026-07-20) already holds a *prove-by-firing* methodology for **owned plugins**. Its `audit-methodology-decisions-and-gaps.md` explicitly records creating a fresh folder and **not duplicating**. This project (`wordpress-security-audit-methodology`) is the **umbrella** that generalizes that approach to core / theme / block / dependencies. **Link, do not copy.**
- **Confidentiality inheritance:** the Plugin Security Audit methodology is CONFIDENTIAL because one confirmed third-party finding was **unpatched under coordinated disclosure as of 2026-07-20**. These umbrella notes are generic (no live target), so they carry no finding detail — but any future application must inherit the anonymization rules (no slugs/paths/line numbers/payloads) and re-check disclosure state before sharing.
- **Idealized vs. built:** the Plugin Security Audit retrospective is careful that its "maintainer agent" and "WP.org review-simulator agent" were **hand-run analysis, not automation**. This methodology must not present those as automated stages.

## Ideas adopted (with source path — link, don't duplicate)
From `1. Projects/Plugin Security Audit/adversarial-plugin-security-audit-methodology.md`:
- **Prove-by-firing gate** — "not a vulnerability until an exploit fires against a disposable install." Model opinions set priority, never truth.
- **No third door** — nothing is marked not-exploitable from reasoning; "bounded/harmless/does-not-reach" is banned unless an attempt *fired and was blocked*. Refutation needs fired-and-blocked evidence too.
- **Positive + negative controls per run** — each run first fires known-vuln (must confirm), known-safe (must refute), known-chain (must confirm); miscalibration aborts the run and discards findings.
- **Consensus ≠ truth** — provider diversity is about *error correlation, not headcount*; agreement *deprioritizes* firing, disagreement *escalates*. Only firing writes CONFIRMED/REFUTED.
- **Keep sub-critical observations** — the confirmed critical was a chain of individually-boring parts; don't drop everything below "vuln" or you lose chain fuel.
- **Assertion discipline** — regression tests assert *absence of side effects* (no state written, no hook fired); "returns 403" is trivially true of any error path.
- **False-positive lesson** — a whole IDOR family was real weak-check code but **refuted** because the abilities never register (underscore-vs-dash identifier rejected by the registry). "Model duplication is not confirmation." (Mirrors `*things_waiting_tag_namespacing*`-style exact-match traps.)
- **Tooling gap** — Plugin Check validates *patterns, not exploitability*; can hit zero warnings while auth-logic flaws remain.
- **Discovery breadth is the weak link** — firing only proves what you fire; diversify *discovery*, not just verification.
- **Disclosure discipline** — owned → private fix tasks/releases; third-party → private coordinated disclosure, never public tracker (mirrors WP 7.1 "route via HackerOne, never public Trac").

## Constraints adopted
- Write only inside this project folder; everything else read-only (vault rule + `*courtneyr_work_logging*`).
- Two house styles: match `1. Projects/**` project style here (lowercase-hyphen filenames; `title/type/status/tags`; `index.md` as MOC; aliased wikilinks; "Related (elsewhere — linked, not duplicated)" sections).
- `CLAUDE.md` writing style (no AI-words, contractions, sentence-case headings).

## Earlier decisions still applying
- Prove-by-firing + controls-per-run is the **evidence standard** — inherited wholesale into [validation-and-proof](../method/validation-and-proof.md).
- Private disclosure routing is the **default** — inherited into [validation-and-proof](../method/validation-and-proof.md) and [open-research](../method/open-research.md).

## Assumptions to retest when applied to a live target
- That a Studio-based disposable site reproduces the target's cache/persistence behavior (Playground/Studio may not model persistent object cache — [wordpress-attack-surfaces](../method/wordpress-attack-surfaces.md)).
- That "owned repos only" scoping holds (Phase 1 of `wp-audit`); widening scope needs explicit written authorization.

## Reusable patterns lifted
- Control-fixture harness (known-vuln / known-safe / known-chain) → [validation-and-proof](../method/validation-and-proof.md).
- Loop registry row for any recurring automation → `2. Areas/Loop Reports/_loop-registry.md` (add a row if this methodology becomes a scheduled loop).

## Deliberately excluded vault material
- Confidential third-party finding specifics (disclosure active) — referenced by path only, never copied.
- The separate `WordPress 7.1/testing/security-ai-audit.md` core-audit effort — kept distinct and cross-linked, not merged (different model panel/target).

## Karpathy + Loop Engineering
Translated into concrete project rules in [loop-engineering-ledger](../method/loop-engineering-ledger.md) (not merely cited).
