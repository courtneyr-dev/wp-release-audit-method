# WordPress 7.1 feature-chain suite

Target build: WordPress 7.1 RC1.

Current tested build: WordPress 7.1-beta4. The RC1 identity gate returned
`WAITING-FOR-RC1`; no RC1 result is inferred from beta4.

## Why the ids start at C-02

The `C-` numbers come from the chain-seed corpus in
[the chain-generation prompt](../../prompts/codex-feature-chain-test-generation-prompt.md)
(C-01 through C-10, all 7.1-specific), not from this directory — see
[registers.md](../../method/registers.md). Three seeds were built into worked examples
(C-02, C-03, C-04, plus the revised chain X-PERS-03r). **C-01** (media validation order ×
site mode × transport) was never built: its confirmed fragment (FM-04, the REST url-import
downloading the full file before the multisite size rejection) is blocked on owner approval
to comment on the already-reopened Trac #65517, and the full chain needs the multisite
quota fixtures that were queued behind that. The gap in the numbering is a fact about what
got built, not a missing file.

## Retest on 7.1 GA (2026-08-21)

7.1 shipped on 2026-08-19. C-02's headline finding — removed files undeclared in
`$_old_files` (243 on 7.0.2→beta4) — was retested offline against the GA package:
7.0.2→7.1 shows **254 deleted files, 1059 `$_old_files` entries, every deletion declared**
(`python3 scripts/stale_file_check.py <7.0.2-tree> <7.1-tree>` → exit 0; the tree-vs-itself
negative control also exits 0). The defect was fixed before GA. Per the learning loop, a
genuinely fixed finding becomes a **permanent negative control**: if this detector ever
reports undeclared deletions on a 7.0.2→7.1 pair again, suspect the harness before
WordPress. The beta4 evidence below is unchanged — it records what beta4 did.

Run each chain from its own directory. Tests use only the disposable local
Studio fixtures named in the chain README. They print evidence to standard
output and do not contact external services.

Verdicts use only `CONFIRMED`, `REFUTED`, `INCONCLUSIVE`, `BLOCKED`, or
`INVALID`. A control failure makes the affected batch `INVALID`.

