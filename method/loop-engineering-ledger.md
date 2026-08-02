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

This translates other people's ideas into rules for one audit. It is not a generic
definition of loop engineering and not an original one — [the sources are listed at the
bottom](#sources), and the phrasings in the tables below are this repo's, not theirs.

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

The first four come from the widely-circulated "Karpathy `CLAUDE.md`" — which Karpathy did
not write; [Sources](#sources) traces who did and what he actually said. **"Verify before
done" is not one of them**; it's this repo's addition, and it's the one carrying the weight
here.

| Karpathy principle (this repo's phrasing) | Applied to this audit |
|---|---|
| Think before coding; surface tradeoffs | State the invariant + falsification *before* writing a test. |
| Simplicity first | Smallest test that resolves the disputed mechanism; no scanner theater. |
| Surgical changes | Remediations touch only the broken trust boundary; no drive-by refactors. |
| Goal-driven execution | "Fix the bug" → "write the failing test that fires it, then make it pass." |
| Verify before done | Re-derive from the tree that actually ships; a green pipeline is not a shipped artifact. |

## Hard lessons wired in

Not from the sources below — these came out of the author's own shipped-and-broken
projects, and are the reason the rules above are phrased the way they are.

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

---

## Sources

None of the ideas above originate here. What this file adds is the translation into audit
rules and the ledger that records whether they held.

### Loop engineering

| Source | Author | What this repo took from it |
|---|---|---|
| [Loop Engineering](https://thenewstack.io/loop-engineering/) (The New Stack, 2026-06-10) | Reporting on Boris Cherny and Addy Osmani | Names the pattern: replacing yourself as the prompter. The maker/checker split — *a model is too generous grading its own homework* — is rule 5 |
| [Loop Engineering: A Technical Roadmap for an Autonomous Loop](https://twitter.com/h100envy/status/2068987470960623783) | h100envy, 2026-06-22 | *"A check that delivers a verdict independent of the agent"*, and *"self-assessment is not a check, it is an echo"* — the go/no-go gate above, and rule 5's deterministic-facts carve-out |
| [Loop Engineering Clearly Explained](https://twitter.com/akshay_pachaar/status/2069118430582866051) | Akshay Pachaar, 2026-06-22 | The harness matters more than the model; put something in the loop that can say no. Stop conditions feed rule 8 |
| [Prompt engineering & loop engineering, clearly explained](https://twitter.com/_avichawla/status/2070443217850671526) | Avi Chawla, 2026-06-26 | The inner loop (ReAct) is solved; the outer loop is the remaining work. *A terminal message ends the turn, not the task* — rule 8's stop condition |

The last three landed within four days of each other and converge independently on the
same claim: an agent cannot check its own work. Three people reaching that separately is
part of why it became a rule here rather than a preference.

### Karpathy

Worth untangling, because this one is usually miscredited as "Karpathy's CLAUDE.md" and
he did not write it.

| Link in the chain | What it actually is |
|---|---|
| [Andrej Karpathy's post](https://x.com/karpathy/status/2015883857489522876) | **The origin.** His observations on where LLMs go wrong writing software — wrong assumptions carried silently, unmanaged confusion, no pushback, overcomplicated code, edits to things they don't understand. Prose about failure modes, not a set of rules |
| [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | **The rules.** Jiayuan ([@jiayuan_jy](https://x.com/jiayuan_jy)) turned those observations into a single `CLAUDE.md`. This is what the four principles are actually from. Originally published at `forrestchang/andrej-karpathy-skills`, which now redirects here |
| [self.dll's thread](https://twitter.com/seelffff/status/2057396108809081289) | **The retelling this repo first read** (2026-05-23), which lists the four rules and is where the "Karpathy's CLAUDE.md" framing comes from |

So the honest description is *Karpathy-derived*, not Karpathy-authored. The rules are
Jiayuan's reading of Karpathy's complaint.

Karpathy's own work: [karpathy.ai](https://karpathy.ai/) · [@karpathy](https://x.com/karpathy)
