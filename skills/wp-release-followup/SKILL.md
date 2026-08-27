---
name: wp-release-followup
description: Follow up after a WordPress release party — recheck filed tickets, retest what was resolved, run the full Phase 2 chain audit, check the fleet's distributed hosting-test participation, and draft (never submit) new issues, Trac tickets, or security reports. Trigger on "after the release party", "check my filed tickets", "what got fixed since last release", "run the full audit", "wp release followup", "check host test participation", or "log the new issues".
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
| [retro](../../method/retro.md) | The short post-run pass that turns a run into method improvements |
| [ecosystem-signals](../../method/ecosystem-signals.md) | Turning dev notes, security releases, and incident write-ups into method changes |
| [ecosystem compatibility lane](../../method/ecosystem-compatibility-lane.md) | The release is fine and the site still dies — the WP Rocket class, its probe, and its cells |
| [preflight core probe](../../method/preflight-core-probe.md) | Boot the new core against a live site's real plugins before applying — the fleet-scale RC signal core-side testing can't reach (Austin Ginder / CaptainCore) |
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

## 0. Establish the host context

One question, asked once, scoping every hosting-related claim downstream. Which is the
operator?

| Context | Meaning | What to ask for |
|---|---|---|
| `host_employee` | Works for (or is authorized by) a hosting company | The **canonical fleet-variant inventory** — every materially distinct product/tier — and any known reporter-account aliases |
| `hosted_server_auditor` | Customer, agency, or consultant testing a server a web host runs | The provider's name, and the tier/product actually being tested, **if known** |
| `not_hosted` | Self-hosted, bare metal, own infrastructure | Nothing — participation checks read `NOT_APPLICABLE` |
| `unknown` | Can't or won't say | Proceed; hosting-scoped sections read `BLOCKED(host-context)` rather than guessed |

Ask only for what can't be established safely: provider name, product/tier, whether the
operator represents the host, and (employees only) the variant inventory and aliases. A
**fleet variant** is a hosting product or tier — never the WordPress build under test;
keep the two axes separate in every table. Never infer that an auditor can see the host's
full fleet, and never treat a domain, reverse-DNS result, IP owner, control-panel brand,
or similar-looking account name as confirmed host identity — those are candidate signals
the operator must confirm. Method: [the participation lane](../../fleet-operators/README.md#9-distributed-core-test-participation--public-evidence-scoped-honestly).

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

**Import fleet probe results if any exist.** The ecosystem cell block can only build cells for plugins you can obtain — premium plugins read `BLOCKED(premium-license)`, and that block is where the 7.1 outage lived. A fleet operator running a [preflight core probe](../../method/preflight-core-probe.md) in `--probe-only` mode across their sites against an RC produces exactly the evidence those cells can't: real fatals, on real co-installed plugin sets, with a denominator. Ask for it, in the [ecosystem-signals](../../method/ecosystem-signals.md) sweep, before concluding that a silent ecosystem lane means a clean one. Treat an imported result as an external report — it goes to step 2's retest discipline and gets a `CONFIRMED`/`INCONCLUSIVE` verdict here, not a free pass — and route what survives to the plugin's own tracker and [Make/Test](https://make.wordpress.org/test/) in step 4, not only to Trac. When your own test cleared a plugin or theme someone else maintains and their "Tested up to" still trails the release, hand the operator [the tested-up-to request message](../../templates/participation-request-messages.md) to send.

**Run the hosting-test participation check before calling the fleet or ecosystem lane clean** — for `host_employee` and `hosted_server_auditor` contexts from §0 (skip as `NOT_APPLICABLE` for `not_hosted`):

```bash
python3 scripts/hosting-test-participation.py --host "<PROVIDER>" \
  --variants <fleet-variants.csv or --variant/--reporter for one tier> \
  --revision <develop-SVN revision of the target, if mapped> \
  --format markdown --evidence "$WP_AUDIT_ROOT/participation"
```

The output is external evidence under the same discipline as the probe imports: a
`FAILED`/`ERRORED` outcome on a verified reporter goes to step 2's retest scope, and a
passing run is a participation fact, **never** a substitute for the preflight probe, the
upgrade ladder, the plugin-compat sweep, browser checks, or production monitoring.
Variants reading `NO_PUBLIC_MATCH`, `STALE_REGISTRATION`, `AMBIGUOUS_MATCH`, or `BLOCKED`
go into the run's blockers/evidence-gaps list with the exact replay command the collector
prints — and `NO_PUBLIC_MATCH` is an absence of public evidence, not proof the host
doesn't test. Unattributable-but-current hosts read `VERIFIED_CURRENT_HOST_ONLY`; the fix
is per-variant reporter accounts, and [the participation request message](../../templates/participation-request-messages.md)
is the ask. Classifications, freshness, and ceilings: [the participation lane](../../fleet-operators/README.md#9-distributed-core-test-participation--public-evidence-scoped-honestly).

## 4. Draft new issues, tickets, and security reports

One draft per confirmed defect, routed by system:

- **Trac** — check for duplicates first; summary, steps to reproduce, expected vs actual, environment (build, PHP, site mode, theme), and the exact rerun recipe
- **GitHub** (Gutenberg, Learn, docs) — same, in the owning repo
- **Security** — never public. Draft into `private/security/` (mode 700) with attacker position, boundary, required capability, default-config reachability, and executed proof. Reduce to a bare acknowledgment in any general report. Never include credentials

**Every AI-assisted Trac/GitHub draft carries a disclosure block**, per the [WordPress AI Guidelines §1.2](https://make.wordpress.org/ai/handbook/ai-guidelines/) — disclosure is required when AI meaningfully contributed, in the Trac ticket comment or the GitHub issue/PR body (the locations the guideline names). The three official fields, appended to the draft:

```
## Use of AI Tools
AI assistance: Yes
Tool(s): Claude Code
Used for: <what the assistant did; what you, the human, reviewed, tested, and take responsibility for>
```

The `## Use of AI Tools` heading and a `Model(s):` line are an optional committer convention, not policy — fine to add, never cited as required. Run the [pre-filing checklist](../../method/ai-issue-writing/checklist.md) before the operator files.

Every draft states its **evidence ceiling** — what was proven, what wasn't, and what would change the verdict. An internal API footgun is not a vulnerability; a result needing a custom capability mapping is configuration-dependent.

Update `filed-issues-register.csv` when the operator confirms a filing.

## 5. Feed the loop

New failure modes, false-positive classes, blocked fixtures, and method changes → `learning/failure-mode-register.csv` and `learning/method-change-proposals.csv`. Any new detector needs a shadow run with both controls before it's `ACCEPTED`. Bank durable method decisions to the vault projects; leave evidence in the run root.

**Check what the projects this method borrows from learned since last cycle.** `python3 scripts/upstream-watch.py` reports commits landed in the upstream paths this repo adapts technique from, against the baselines in [`sources/upstream-watch.csv`](../../sources/upstream-watch.csv). Review the drift, then `--update` to move the baselines and commit — the baseline means *someone looked*, not *someone integrated*, so a cycle where nothing was worth taking still moves it. The review question is whether anything upstream changes a limit written down here, contradicts an attribution, or covers a lane left `BLOCKED`. The discipline and the licence rules are in [`sources/upstream-techniques.md`](../../sources/upstream-techniques.md); a weekly workflow files the same report as one standing issue, so this step is usually reading a queue rather than starting a search.

This is the deep end of the same loop the lighter [retro](../../method/retro.md) feeds after every run, and that [ecosystem-signals](../../method/ecosystem-signals.md) feeds from reading the news. The routine ones stay in your run root; the ones worth the next stranger's time go to a [field report or PR](../../CONTRIBUTING.md#suggesting-improvements-from-real-use). Nothing is filed upstream without the operator's approval.

## Done when

Every register row has a current status and a retest verdict or exact blocker; every selected chain has an executed verdict or blocker; the host context is recorded and, when hosted, every declared fleet variant has a participation classification or an exact blocker; drafts exist for each confirmed defect with sensitive material separated; the learning registers are updated; and the next build has an exact rerun recipe.
