---
title: "WordPress Security Audit Playbook"
type: reference
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - wordpress
  - security-audit
  - playbook
  - methodology
related:
  - '*index*'
  - '[orchestration](../method/orchestration.md)'
  - '[security-invariants](../method/security-invariants.md)'
  - '[wordpress-attack-surfaces](../method/wordpress-attack-surfaces.md)'
  - '[validation-and-proof](../method/validation-and-proof.md)'
---

# WordPress security-audit playbook

Execution-ordered. Each stage: **objective · inputs · actions · evidence · failure modes · exit criteria**. Authorization + containment rules in *index* are non-negotiable and apply throughout.

## Current audit blind spots (why conventional reviews miss the article-class bug)
Sink-hunting, WPCS/lint, SAST, route-by-route review, happy-path tests, and single-agent LLM passes all look for *dangerous functions in one place*. The article's chain had **no dangerous function in the vulnerable code** — it was a `continue` that desynced two parallel arrays. Conventional methods miss:
- mismatched **parallel data structures** / validation applied to a *different representation* (the `$matches`/`$validation` desync);
- **scalar-vs-array** handling differences (`author__not_in`);
- **recursive / nested** processing (recursive batch to bypass method validation);
- **cache↔DB disagreement** and **stale-object** reconciliation (oembed popping);
- **temporary identity** not restored (`wp_set_current_user` via changeset);
- **dynamic hook construction** (`"{$new_status}_{$post_type}"` → `parse_request`);
- **invalid lifecycle transitions** and error-path inconsistencies;
- **source-vs-release** differences;
- assumptions spread **across files/subsystems**;
- **duplicate skills / model agreement** read as independent confirmation.
Full catalog → [security-invariants](../method/security-invariants.md). This is the reframe: **hunt broken invariants across subsystems, not sinks in one file.**

## Stage sequence

### 0. Authorization & scope
- **Objective:** fix what is in-scope and what proof is permitted. **Inputs:** owner statement, repo, environment. **Actions:** confirm owned/authorized; isolated disposable env; synthetic users/data; record excluded systems. **Evidence:** scope note. **Failure:** scope creep, testing a shared host. **Exit:** written scope + disclosure status.

### 1. Skill-provenance audit
- **Objective:** know your tools before trusting them. **Actions:** the *skill-provenance (not published — see README)* pass (hash, frontmatter, dedupe, role, scope-override on offensive skills). **Failure:** counting duplicate labels as two reviewers. **Exit:** provenance matrix complete.

### 2. Environment preparation
- **Objective:** a faithful, disposable target. **Actions:** build the test matrix (WP/PHP/DB/Node/browser, single+multisite, object cache on/off, persistent cache, filesystem method) *before* testing; stand up the disposable site (Studio/`wp-env`/Playground per fidelity — [wordpress-attack-surfaces](../method/wordpress-attack-surfaces.md)); verify reset. **Failure:** unrealistic config chosen because it makes a hypothesis work. **Exit:** matrix + reset verified.

### 3. Target & release inventory + change-intelligence ledger
- **Objective:** know exactly what shipped between baseline and target. **Actions:** [feature-change-ledger](../method/feature-change-ledger.md) — establish baseline/target commit+tag+artifact; classify every added/expanded/modified/deprecated/removed/renamed/moved/reverted/feature-flagged change; reconcile git ↔ release notes ↔ tests ↔ deps ↔ distributed ZIP. **Evidence:** ledger + [change-coverage-receipt](../method/change-coverage-receipt.md). **Failure:** limiting review to changed lines or the changelog. **Exit:** no in-scope change unclassified. **Anchoring guard:** the whole-surface first-principles read (Stage 4/6) runs **independently of and in parallel with** this ledger — the article's desync predated any diff window and was invisible to diffing. The ledger catches regressions; it does **not** find latent bugs, so it must never scope the first-principles pass.

### 4. Architecture & trust-boundary map
- **Objective:** where each layer *assumes* an earlier layer already did the work. **Actions:** map execution flow, subsystem interactions, lifecycle, global state, cache/DB relationships, direct-vs-background paths → [security-invariants](../method/security-invariants.md) "where established/transformed/consumed". **Exit:** boundary map with established/consumed points.

### 5. Attack-surface inventory
- **Objective:** enumerate entry points + state surfaces. **Actions:** the [wordpress-attack-surfaces](../method/wordpress-attack-surfaces.md) tables (request/execution, data/state, dynamic behavior). **Exit:** every surface has input/validation/authz/sink/assumption.

### 6. Invariant registry
- **Objective:** the falsifiable questions. **Actions:** instantiate [security-invariants](../method/security-invariants.md) for this target; for each, record where it can break + negative control. **Exit:** registry with tests.

### 7. Research-family registry + independent rounds
- **Objective:** diverse, non-converging hypotheses. **Actions:** [orchestration](../method/orchestration.md) families; keep incompatible routes independent; mark blocked routes; launch new rounds after weak ones. **Failure:** all agents converge on one lead; activity mistaken for coverage. **Exit:** each family = mechanism, evidence, or explicit block.

### 8. Adversarial verification
- **Objective:** kill plausible-but-wrong. **Actions:** fresh-context verifier receives claim+code+evidence, not the maker's story; must state what would change its mind; disagreements resolved by the smallest test (not a vote). **Exit:** each promising claim survived or died on evidence.

### 9. Static proof → 10. Dynamic proof → 11. Chain analysis
- **Static:** trace source (incl. dependency source and the distributed build) end-to-end; a static observation is not yet a vuln. **Dynamic:** the 20-step [validation-and-proof](../method/validation-and-proof.md) loop with negative + role controls, clean-env repeat, version matrix. **Chain:** build the `source → parse → canonicalize → validate → sanitize → authz → transform → store/cache → callback/state → sink → boundary → impact` graph; every edge needs source/runtime/test evidence or the whole chain is a **candidate**.

### 12. Bounded proof of impact
- Prove only reachability, control, privilege, boundary crossing, versions, impact — then **stop** ([validation-and-proof](../method/validation-and-proof.md) safe-proof standard). No persistence/shells/exfil.

### 13. Remediation → 14. Regression tests
- Fix the trust boundary, not the symptom; add the failing-first regression test that asserts **absence of side effects**; run the whole suite after each fix (cascade-aware).

### 15. Performance & accessibility checks (labeled non-vuln)
- Cache/amplification/unbounded ops (perf skills); security-critical UI a11y — both reported separately from vulnerabilities.

### 16. Compliance review
- WordPress.org guidelines, licensing, bundled libs, remote code, telemetry/consent — labeled compliance, not vuln.

### 17. Disclosure prep → 18. Knowledge capture → 19. Retrospective
- Owned → private fix/release; third-party → private coordinated disclosure, never public Trac. Bank decisions here; run the final independent methodology review → [open-research](../method/open-research.md).

## Target-specific emphasis
| Target | Emphasize |
|---|---|
| **Core / core patch** | Cross-subsystem interactions, REST infra (batch/recursion), global state, post lifecycle, caps, multisite, cache, `wpdb`, dynamic hooks, backward-compat, bundled libs, PHP/DB diffs, upgrade paths. |
| **Plugins** | Custom REST/AJAX/admin-post, settings, caps, nonces, custom tables, CPT/tax, blocks/shortcodes, import/export, uploads, webhooks, external APIs, cron/queues, activation/uninstall, upgrade routines, dependency loading, inter-plugin integration, .org compliance, release ZIP contents. |
| **Classic themes** | Template inclusion, output escaping, Customizer, `functions.php` app-logic, media, switching behavior, bundled libs. |
| **Block themes** | `theme.json`, patterns, dynamic blocks, starter content, Site Editor, source-vs-build. |
| **Blocks / editor ext** | `block.json` attribute schemas, serialization, server render callbacks, editor-only restrictions, REST preload, entity records, Interactivity API, client/server validation drift, build output, dependency versions. |
| **AI components (Airo-class)** | Who may invoke; cap/nonce/REST/AJAX perms; prompt-injection boundary; data sent to providers; secrets; model output treated as *instructions*; generated markup sanitization; action authorization; retries/idempotency; tenant isolation; publication transitions; cost amplification; audit logs. |

## Reusable process (checklist form)
`authorization → skill-provenance → environment → change-ledger → architecture map → trust-boundary map → attack-surface → invariant registry → research families → independent rounds → adversarial verify → static proof → dynamic proof → chain analysis → bounded proof → remediation → regression → perf/a11y → compliance → disclosure → knowledge capture → retrospective`
