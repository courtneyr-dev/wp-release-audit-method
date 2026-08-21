---
name: wp-release-followup
description: Follow up after a WordPress release party — recheck filed tickets, retest what was resolved, run the full Phase 2 chain audit, and draft (never submit) new issues, Trac tickets, or security reports. Trigger on "after the release party", "check my filed tickets", "what got fixed since last release", "run the full audit", "wp release followup", or "log the new issues".
---

# wp-release-followup

Phase 2. Depth, after the party. Four jobs in order — each gates the next.

**Nothing is filed without the operator's explicit approval.** Draft issues, tickets, and security reports; never open, comment, or submit. External WordPress.org, Trac, and GitHub access stays read-only.

| | |
|---|---|
| **Previous phase** | [`wp-release-party`](../wp-release-party/SKILL.md) — Act II, the breadth sweep whose non-PASS cells feed this |
| **Feeds** | The next cycle's [`wp-release-prep`](../wp-release-prep/SKILL.md) |
| **Handoff** | [`wordpress-audit-handoff`](../wordpress-audit-handoff/SKILL.md) — package findings for a colleague |

---

## Where this fits — the whole method, in one screen

This skill is the deep end. Everything below exists because a shallow pass wasn't enough, and
each piece is here for a reason you can trace to a specific way of being wrong.

### The layers

| Layer | What it is | Read when |
|---|---|---|
| **[README](../../README.md)** | Support doc: install a build, test it, report it | You're starting out |
| **Skills** ([prep](../wp-release-prep/SKILL.md) · [party](../wp-release-party/SKILL.md) · followup) | The three acts as runnable workflow | You want the cycle automated |
| **[Playbooks](../../playbooks/)** | Per-axis runbooks with acceptance criteria | You're going deep on one axis |
| **[Method](../../method/)** | Why the rules exist, and what breaks without them | A rule feels arbitrary and you want the receipt |
| **[Examples](../../examples/chains/)** | Four adjudicated chains with evidence and controls | You want to see one done end to end |

### The playbooks — pick by axis

| Playbook | Answers | Status |
|---|---|---|
| [release-day sweep](../../playbooks/release-day-sweep-playbook.md) | Breadth before depth; the non-PASS → chain mapping used in §3 below | Exercised |
| [security release audit](../../playbooks/security-release-audit-playbook.md) | Attack surfaces, threat-model gate, disclosure routing | Exercised |
| [source and content audit](../../playbooks/source-and-content-audit-playbook.md) | Does the documentation match what shipped? | Exercised |
| [performance release audit](../../playbooks/performance-release-audit-playbook.md) | Benchmark design and acceptance criteria | **UNEXERCISED** — a design, not a proven procedure |
| [future release template](../../playbooks/future-release-audit-template.md) | Starting the next release cold | Template |
| [Slack test-report template](../../playbooks/slack-test-report-template.md) | The 75-check report form | Generated |

### The method — why the rules exist

Start here if a constraint in this skill seems excessive:

| Document | The question it settles |
|---|---|
| [release-audit learning loop](../../method/release-audit-learning-loop.md) | **Start here.** The five laws, the calibrated detectors, and which failed a control first |
| [registers](../../method/registers.md) | What FM-, MC-, SR-, D-, and FX- ids point at, and which registers are public |
| [ecosystem compatibility lane](../../method/ecosystem-compatibility-lane.md) | The release is fine and the site still dies — the WP Rocket class, its probe, and its cells |
| [rollback](../../method/rollback.md) | The escape hatches when the fatal kills WP-CLI too, and what core rollback can't recover |
| [validation and proof](../../method/validation-and-proof.md) | What counts as proof; the finding templates; controls |
| [security invariants](../../method/security-invariants.md) | The invariant catalog — audit broken invariants, not dangerous sinks |
| [WordPress attack surfaces](../../method/wordpress-attack-surfaces.md) | Where to look, by subsystem |
| [cross-release feature chains](../../method/cross-release-feature-chains.md) | Why chains, and the 36/36 adjudication result behind §3's warning |
| [audit playbook](../../method/audit-playbook.md) | The full phase structure this compresses |
| [orchestration](../../method/orchestration.md) | Root agent, subagents, research families — how to fan out without converging |
| [prior knowledge](../../method/prior-knowledge.md) | Inherited constraints, including disclosure discipline |
| [article methodology](../../method/article-methodology.md) | The source technique, and where it does *not* apply |
| [open research](../../method/open-research.md) | Known limitations and what independent review found |
| [loop engineering ledger](../../method/loop-engineering-ledger.md) | Decision log — what changed and why |
| [method improvements summary](../../method/method-improvements-summary.md) | What this cycle changed about the method itself |

Templates: [feature/change ledger](../../method/feature-change-ledger.md) ·
[change-coverage receipt](../../method/change-coverage-receipt.md) ·
[repo audit prompt](../../method/repo-audit-prompt.md)

### The prompts — for AI-assisted work

[source discipline](../../prompts/codex-wordpress-source-discipline.md) — read source, don't
search docs · [chain generation](../../prompts/codex-feature-chain-test-generation-prompt.md) —
cite source per leg · [future release audit](../../prompts/future-wordpress-release-audit-prompt.md) ·
[handoff message](../../prompts/codex-handoff-message.md)

### The short version of the whole thing

Five laws, from [the learning loop](../../method/release-audit-learning-loop.md):

1. **Source observation needs runtime proof.** A source-only pass called 5 claims confirmed; runtime changed 2.
2. **Clean installs don't cover upgrade behavior.** 243 removed files stayed put; a fresh install shows nothing.
3. **Assert fixtures and denominators before reading results.** "2/2 sites" — there were 5.
4. **Severity needs a real attacker boundary.** Internal footgun ≠ vulnerability.
5. **Performance claims need repeated stable comparisons.** One run is not a regression.

And the sixth this loop added: **refuted claims are assets.** Which is most of what §2 below is about.

---

## 1. Did previously filed issues get resolved?

Read `pilots/filed-issues-register.csv` (create it if missing — columns: `filed_id,date_filed,system,url,title,our_verdict_at_filing,status_now,retested_build,retest_verdict,notes`). Seed it from the vault's existing drafts and submissions under `WordPress 7.1/testing/`.

For each open row: check current status through an allowed route — Trac via the MCP for status/milestone/owner (its `component` is always blank and `searchTickets` can't filter by milestone; don't fight the bot challenge), GitHub via `gh`, HackerOne through the operator only.

**A ticket marked fixed is not a fixed behavior.** Every closed item goes to step 2 for a runtime retest. Record the status check and the retest separately.

## 2. Retest everything newly resolved since the last release

Build the list from: closed tickets on the milestone, changesets in the release branch since the prior tag, and the register rows that flipped to closed.

For each, reproduce the **original** failing condition on the new build with calibrated controls. Verdicts: `CONFIRMED` (still broken), `REFUTED` (genuinely fixed), `INCONCLUSIVE`, `BLOCKED`, `INVALID`.

Two failure modes to avoid: don't accept a source diff as proof of a runtime fix, and don't declare a fix from a passing test whose *original* reproduction was never re-established — if you can't reproduce the old failure on the old build, you can't claim the new build fixed it.

Newly refuted items become permanent negative controls: add them to `learning/failure-mode-register.csv` with `control_role = negative-control`.

## 3. Run the full audit

Feed Phase 1's non-PASS cells into chain selection — that mapping is in the release-day sweep playbook:

- interface-split failure → interface-parity chain
- ladder failure at one source version but not its neighbour → bisect the intervening releases; the boundary is the mechanism
- clean upgrade leaving a divergent file tree, `db_version`, or content count → `MULTIHOP`, `ARTIFACT`, or the stale-file detector
- anything touching credentials, secrets, or capability boundaries → the security lane with a threat model

Then run `learning/cross-release-chain-register.csv`. **Take the row counts from the
register itself, never from prose** — this paragraph once said "20 REVISE / 25
UNADJUDICATED / 16 DROP" while the live register read differently, because hardcoded counts
drift the moment a chain executes. What each status means:
- **`REVISE`** — adjudicated; build from `corrected_chain`, never `proposed_hypothesis`
- **`UNADJUDICATED`** — hypotheses only. Source-adjudicate each leg first; catalog-derived proposals have a measured 36/36 error rate here
- **`DROP`** — refuted; keep as negative controls, don't re-propose
- **`EXECUTED-*`** — already run; the verdict column is the record

**Run `X-SERIAL-01` first.** If re-saving unchanged content mutates bytes, every byte-diff assertion elsewhere is measuring noise.

PHP is an axis, not a chain — multiply only the seven chains listed in `pilots/release-day/php-axis.csv`, on PHP-matched fixture pairs (`FX-10`..`FX-15`). Never compare a 7.4 multisite fixture against an 8.4 single-site one; that confounds runtime with site mode.

Sweep the remaining tiers too: sweep-matrix T2/T3 and upgrade-ladder T2/T3, including the WP-CLI-updater lane.

## 4. Draft new issues, tickets, and security reports

One draft per confirmed defect, routed by system:

- **Trac** — check for duplicates first; summary, steps to reproduce, expected vs actual, environment (build, PHP, site mode, theme), and the exact rerun recipe
- **GitHub** (Gutenberg, Learn, docs) — same, in the owning repo
- **Security** — never public. Draft into `private/security/` (mode 700) with attacker position, boundary, required capability, default-config reachability, and executed proof. Reduce to a bare acknowledgment in any general report. Never include credentials

Every draft states its **evidence ceiling** — what was proven, what wasn't, and what would change the verdict. An internal API footgun is not a vulnerability; a result needing a custom capability mapping is configuration-dependent.

Update `filed-issues-register.csv` when the operator confirms a filing.

## 5. Feed the loop

New failure modes, false-positive classes, blocked fixtures, and method changes → `learning/failure-mode-register.csv` and `learning/method-change-proposals.csv`. Any new detector needs a shadow run with both controls before it's `ACCEPTED`. Bank durable method decisions to the vault projects; leave evidence in the run root.

## Done when

Every register row has a current status and a retest verdict or exact blocker; every selected chain has an executed verdict or blocker; drafts exist for each confirmed defect with sensitive material separated; the learning registers are updated; and the next build has an exact rerun recipe.
