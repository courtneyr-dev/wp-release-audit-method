---
title: "Orchestration — root agent, subagents, research families"
type: reference
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - security-audit
  - orchestration
  - subagents
  - loop-engineering
related:
  - '*index*'
  - '*skill-provenance (not published — see README)*'
  - '[loop-engineering-ledger](../method/loop-engineering-ledger.md)'
---

# Orchestration

**A skill is a method; a subagent owns a bounded question. Not interchangeable.** Two agents with the same skill+prompt, or two skill labels sharing a source, are **not** independent confirmation — nor are two models sharing one unsupported assumption.

## Root-orchestrator contract
Maintain the target model, *skill-provenance (not published — see README)* matrix, research-family registry, and evidence ledger. Preserve several incompatible hypotheses. Redirect agents off crowded families. Spot repeated ideas disguised by wording. Launch new rounds after weak ones. Separate reachability from exploitability and theoretical from demonstrated impact. Require negative controls + independent adversarial verification. Resolve conflicts by source/test, never by vote. Record what's untested. Stop tests at the bounded-proof boundary. Decide when done ([loop-engineering-ledger](../method/loop-engineering-ledger.md) rule 10).

**Explicit convergence control (yield-gated, not headcount-gated):** crowding on one family is only a problem when that family is *low-yield*. Reassign surplus agents **only** when a family has produced no new mechanism/evidence across its bounded attempts — never merely because >⅓ of agents are there. The article's real bug was one deep chain in one family; a raw headcount cap would have starved it. Cap total agents per round to the smallest set that covers the families — *activity ≠ coverage*.

## Recommended subagents (roles, not file slices)
1. **Architecture & trust-boundary analyst** — flow, subsystem interactions, lifecycle, privilege boundaries, global state, cache/DB, direct-vs-background.
2. **Input / parser / REST analyst** — parsing, REST schemas, route matching, nested/batch, recursion, scalar-vs-array, canonicalization, malformed input, encoding.
3. **Authorization & identity analyst** — caps, roles, nonces, permission callbacks, current-user changes, multisite, app passwords, confused-deputy.
4. **Persistence / cache / lifecycle analyst** — object + persistent cache, stale objects, in-memory-vs-DB, post type/status, migrations, activation, upgrades, cleanup, races.
5. **Filesystem / dependency / build analyst** — uploads, extraction, paths, includes, writes, Composer/npm, autoloading, generated assets, release ZIP, source-vs-distribution.
6. **Adversarial verifier** — tries to *disprove*: impossible attacker control, missing prerequisites, unsupported config, wrong framework behavior, unreachable code, a check the first analyst missed, a negative control that behaves identically, impact exceeding evidence.
7. **Test & reproduction analyst** — env fidelity, fixtures, repeatability, instrumentation, negative controls, regression tests, version matrices, patch verification.

## Skill → agent routing (from *skill-provenance (not published — see README)*)
| Agent | Primary skills | Cross-check (not a 2nd vote) |
|---|---|---|
| Architecture | `wordpress-pro` | `wordpress-plugin-core` |
| Input/REST | `WordPress Plugin, Block & Theme Development` | `wordpress-block-editor-fse` |
| Authz/identity | `WordPress Security` | `wordpress-security-validation` |
| Cache/lifecycle | `wordpress-pro` + `WordPress Performance` | `wordpress-performance-best-practices` |
| Filesystem/deps/build | `wordpress-plugin-core`, `wordpress-org-compliance` | — |
| Attacker paths | `wordpress-penetration-testing` (scope-overridden) | — (2nd pentest skill same author) |
| Verifier | *fresh context, no skill bias* | — |
| Test/repro | `WordPress Testing & QA` + `WordPress Playground` | `wordpress-testing-qa` |
| Baseline pass | `wp-audit` (owned repos) | — |
| Evidence | `wp-screenshots` | — |

## Adversarial interaction rules
Challenge claims, not people. Assign incompatible theories deliberately. Keep work independent long enough to expose real differences; cross-pollinate only after each route has a mechanism/evidence/block. The verifier gets the claim + evidence, **not** the maker's persuasive narrative, and must state what would change its mind. Disagreements → smallest resolving test. Preserve minority hypotheses until disproved. **"Three agents agree" is not verification.**

**Same-model verification is correlated, not independent.** Two fresh contexts of the same base model share training priors and blind spots, so a fresh-context verifier is necessary but not sufficient for a high-severity claim. For high/critical findings, require a **differently-constructed oracle**: a differential test, a property/invariant oracle the model can't edit, or a genuinely different model (`*grok_xai_configured*` as cross-model verifier). Dedupe reviewers by *model and source*, not just by skill label.

## Research families (start diverse; keep an escape hatch)
Seed the registry with the standard families (auth bypass, authz/cap confusion, nonce misuse, REST permission callbacks, request-to-handler mismatch, validation/execution desync, parallel-array/object desync, schema confusion, scalar-vs-array, type juggling, mass assignment, SQLi, unsafe queries, stored/reflected XSS, block/HTML sanitization drift, SSRF, unsafe redirects, upload/archive, path traversal/LFI, unsafe writes, object injection/deserialization, unsafe dynamic callbacks, recursive processing, confused deputy, temporary privilege, global-identity leakage, cache poisoning, request-cache-vs-persistent disagreement, stale objects, races/TOCTOU, lifecycle violations, post-type/status confusion, multisite boundaries, supply-chain, source-vs-build, update-channel, cleanup/uninstall, privacy/telemetry, unsafe defaults, error-path inconsistency, charset/collation/Unicode, resource amplification, unbounded queries, UI-mediated mistakes, generated-content trust, model I/O).
**Mandatory extra family — `unknown-shape`:** any surface that fits *no* invariant in [security-invariants](../method/security-invariants.md) is assigned here and treated as **under-covered**, not clean. This is the guard against over-fitting to the one known chain.

## Stop conditions
Stop a research family at: verified vulnerability (→ bounded proof), disproved (negative control matches), or blocked (mechanism exhausted; reopen only on new mechanism). **Before marking any route blocked, run the bypass check:** can this block be sidestepped by re-entry, recursion, another primitive, or a different representation? (The article's SQLi only worked because the batch API's `GET` rejection was bypassed by *recursively re-entering batch*.) A route isn't blocked until the bypass check itself comes up empty. Stop the audit when the [audit-playbook](../method/audit-playbook.md) definition-of-done is met and coverage receipt has no unexplained gaps — not when the first finding appears, and not after "enough activity."

## When to escalate to a Workflow
Manual `Agent` fan-out is fine for a handful of families. For a full multi-round audit (discover → verify → chain across many surfaces), prefer the **Workflow** tool (terminates by design, cheaper) — but it needs explicit per-task opt-in ("ultracode" / direct ask); flag it, don't self-invoke (`*credit-routing*`). Owned-plugin prove-by-firing already has one: `wp-audit-pipeline`.
