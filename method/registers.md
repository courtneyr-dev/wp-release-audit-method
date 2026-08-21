# Registers and identifiers — what FM-03 actually points at

Documents in `method/` and `playbooks/` cite evidence by row id: *"assert the denominator
[D-04; FM-03]"*. Until this page existed, those ids resolved to nothing a reader could open —
you saw the conclusion and had to take the register row on faith. This page defines every id
scheme, names the register it lives in, and says which parts are public.

## The id schemes

| Prefix | Means | Register | Example |
|---|---|---|---|
| `FM-` | Failure mode — a way the *method* was wrong, with its disposition | [`learning/failure-mode-register.csv`](../learning/failure-mode-register.csv) | FM-03: "upgraded on 2/2 sites" hid three held-back sites |
| `MC-` | Method-change proposal — a rule, with controls and an accept/reject status | [`learning/method-change-proposals.csv`](../learning/method-change-proposals.csv) | MC-08: assert the full multisite denominator before reading any N/N |
| `SR-` | Shadow run — one control run of a detector before acceptance | [`learning/shadow-run-results.csv`](../learning/shadow-run-results.csv) | SR-05: the build-identity gate's first run failed its positive control |
| `D-` | Detector — an accepted instrument, with calibration evidence | [`methods/detection-rules.csv`](../methods/detection-rules.csv) | D-05: the stale-file / `$_old_files` detector |
| `FX-` | Fixture — a named, buildable environment state | [`methods/test-and-fixture-registry.csv`](../methods/test-and-fixture-registry.csv) | FX-02: the 5-site multisite with archived/spam/deleted flags |
| `X-*-NN` | Cross-release chain, by lens (`X-SERIAL-01`, `X-PERS-03r`) | [`learning/cross-release-chain-register.csv`](../learning/cross-release-chain-register.csv) | An `r` suffix marks a revised chain rebuilt from its adjudication |
| `C-NN` | Chain seed from the generation prompt's corpus | Same register; seeds defined in [the chain prompt](../prompts/codex-feature-chain-test-generation-prompt.md) | C-02: upgrade path × file-removal ledger |
| `T1-NN` | A sweep cell at tier 1 | [`pilots/release-day/sweep-matrix.csv`](../pilots/release-day/sweep-matrix.csv) | T1-44 appears in the self-test's BLOCKED demonstration |
| `L1-NN` | An upgrade-ladder cell | [`pilots/release-day/upgrade-ladder.csv`](../pilots/release-day/upgrade-ladder.csv) | — |

## Public here vs private in the run root

The **schemas** of every register are in this repo (`learning/`, `methods/`, `pilots/`) —
header rows, so citations resolve to a file whose shape you can inspect. The **populated
rows** live in a private run root (`$WP_AUDIT_ROOT`), because they accumulate
mid-investigation verdicts and fixture details that aren't publication-ready.

Two public views substitute for the private rows:

- [`method-improvements-summary.md`](method-improvements-summary.md) — every FM, MC, SR, and
  D row that cleared review, in prose, with counts tallied against the registers rather than
  assumed. If a citation matters to you, this is where to read what the row says.
- [`examples/chains/`](../examples/chains/) — four chains published whole: register row,
  runnable scripts, both controls, and the evidence files.

A citation that appears in neither place is a claim about a private row. Treat it the way
this repo treats any un-inspectable evidence: as provenance for where a rule came from, not
as something you've verified.
