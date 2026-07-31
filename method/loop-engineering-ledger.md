---
title: "Loop Engineering Ledger — WP security audit"
type: reference
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - loop-engineering
  - security-audit
  - maker-checker
  - verification
related:
  - '*index*'
  - '[prior-knowledge](../method/prior-knowledge.md)'
  - '[validation-and-proof](../method/validation-and-proof.md)'
---

# Loop Engineering, translated into project rules

Sourced from the user's own notes (`2. Areas/Loop Reports/_loop-registry.md`, `loop-engineering-lessons.md`, the Osmani + h100envy source texts, and the Karpathy files), not a generic definition.

## The 10 operating rules for this audit
1. **Externalized state.** Target model, research-family registry, evidence ledger, blocked routes, and this ledger live in these files — never chat-only. *"The agent forgets, the repo doesn't."* Every loop is restartable by another agent.
2. **One objective per loop.** State the exact question ("can REST validation and execution desync on this route?"), never "keep looking for vulns."
3. **Evidence-driven cycle.** orient → pick highest-uncertainty question → read source/history → falsifiable hypothesis → smallest test → **challenge** → update ledger → next. Plausibility is not progress.
4. **Evaluation gates.** A model may *propose* a status change; **evidence** justifies it. Gate ladder in [validation-and-proof](../method/validation-and-proof.md).
5. **Fresh-context verification (maker ≠ checker).** *"The model that wrote the code is too nice grading its own homework."* The checker re-derives from source and gets the claim + code + evidence, **not** the maker's narrative. Deterministic facts (exit codes, tar listings, HTTP status) need no second agent — *the script is the check*.
6. **Failure-aware iteration.** Record disproved theories and blocked routes; never re-run a blocked approach under new wording; reopen only on a materially new mechanism.
7. **Uncertainty reduction.** At each fork pick the branch with the most information gain; state it. Don't polish a theory whose central premise is unverified.
8. **Bounded loops.** Each loop has objective, inputs, `MAX_ITER` before reassessment, success evidence, failure evidence, escalation, stop condition. *"Define the loop by what it can destroy — radius first, task second."*
9. **Artifact-producing loops.** Every loop improves a durable artifact (surface map, invariant, ledger row, repro, test, remediation, decision). Activity without an improved artifact is not progress.
10. **Review and repair.** After each phase: compare to prompt, find missing coverage, challenge assumptions, repair plan, update stop conditions. Final independent review of the methodology itself → [open-research](../method/open-research.md).

## Karpathy principles → audit rules
| Karpathy principle (user's phrasing) | Applied to this audit |
|---|---|
| Think before coding; surface tradeoffs | State the invariant + falsification *before* writing a test. |
| Simplicity first | Smallest test that resolves the disputed mechanism; no scanner theater. |
| Surgical changes | Remediations touch only the broken trust boundary; no drive-by refactors. |
| Goal-driven execution | "Fix the bug" → "write the failing test that fires it, then make it pass." |
| Verify before done | Re-derive from the tree that actually ships; a green pipeline is not a shipped artifact. |

## Hard lessons wired in (from `loop-engineering-lessons.md`)
- *A green pipeline is not a shipped artifact* — verify at the destination (`wp plugin list`, the SVN tags dir), not the CI badge.
- *Stay open until the job is really done* — watchers poll to a terminal state; a dead watcher is never the last word (`*feedback_watchers_stay_open*`).
- *The first fix is rarely the whole story* — expect the failure mode to change as layers peel; re-derive from artifacts (`*feedback_anticipate_cascade*`).
- *Phantom success* — a 2xx that buries an insert error; when "some payloads work," look at what differs in the payload, not the kind.

## Go / no-go before any loop (h100envy Step 0)
Run this audit as a loop **only** where a check delivers a verdict independent of the agent. Self-assessment *"is not a check, it is an echo."* For findings that can't be fired, the verdict is **hypothesis**, not vulnerability.

## Loop ledger (living)
| Loop ID | Objective | Starting evidence | Hypothesis | Action/test | Result | Challenge | Artifact updated | Remaining uncertainty | Next decision | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| L0 | Analyze + critique the article | Full article scraped | Method's value = orchestration+invariants, not RCE | Read & separate practices | Done | Biases named | [article-methodology](../method/article-methodology.md) | Repeatability unproven upstream | Build umbrella methodology | done |
| L1 | Inventory + dedupe installed skills | 20 local `SKILL.md` hashes | Some labels share a source | Hash + frontmatter pass | Done | 2 pentest = same author | *skill-provenance (not published — see README)* | Two skills' authorship unverified | Assign roles | done |
| L2 | Consult vault before planning | Explore brief | Project may already exist | Read-only vault search | Found `Plugin Security Audit/` | Confidentiality flagged | [prior-knowledge](../method/prior-knowledge.md) | Live-target repro fidelity | Generalize + link | done |
| L3 | Independent review of this methodology | Draft files | Methodology has blind spots | Fresh adversarial subagent | 16 weaknesses found | 14 fixed, 2 residual | [open-research](../method/open-research.md) | corpus not yet built | build corpus on first live run | done |
