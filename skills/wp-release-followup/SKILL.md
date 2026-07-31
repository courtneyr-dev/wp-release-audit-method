---
name: wp-release-followup
description: After a WordPress release party — check whether previously filed issues and tickets were resolved, retest everything newly resolved since the last release, run the full Phase 2 chain audit, and draft (never submit) new issues, Trac tickets, or security reports. Trigger on "after the release party", "check my filed tickets", "what got fixed since last release", "run the full audit", "wp release followup", or "log the new issues".
---

# wp-release-followup

Phase 2. Depth, after the party. Four jobs in order — each gates the next.

**Nothing is filed without the operator's explicit approval.** Draft issues, tickets, and security reports; never open, comment, or submit. External WordPress.org, Trac, and GitHub access stays read-only.

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

Then run `learning/cross-release-chain-register.csv`:
- **20 `REVISE` rows** — adjudicated; build from `corrected_chain`, never `proposed_hypothesis`
- **25 `UNADJUDICATED` rows** — hypotheses only. Source-adjudicate each leg first; catalog-derived proposals have a measured 36/36 error rate here
- **16 `DROP` rows** — refuted; keep as negative controls, don't re-propose

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
