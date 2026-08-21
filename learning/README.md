# Learning registers — the schema contract

The learning loop's registers are cited throughout `method/` and `playbooks/` by row id —
`FM-03`, `MC-10`, `SR-05`. The populated registers live in a private run root
(`$WP_AUDIT_ROOT/learning/`), because rows accumulate mid-investigation verdicts, fixture
details, and occasionally material that is redacted before anything public quotes it.

What ships here is the **schema contract**: each register with its real header row, so a
citation like `learning/failure-mode-register.csv#FM-01` resolves to a file whose shape you
can see, and so anyone running the loop on their own releases starts from the same columns.

**What the ids mean, and which registers are public where:** [`method/registers.md`](../method/registers.md).
The public digest of the populated registers — every FM, MC, SR, and D row that has cleared
review, in prose — is [`method/method-improvements-summary.md`](../method/method-improvements-summary.md).

| Register | One row per | Cited as |
|---|---|---|
| [`failure-mode-register.csv`](failure-mode-register.csv) | Way the method itself was wrong, with its disposition | `FM-*` |
| [`method-change-proposals.csv`](method-change-proposals.csv) | Proposed rule change, with controls and status | `MC-*` |
| [`shadow-run-results.csv`](shadow-run-results.csv) | Control run of a detector before acceptance | `SR-*` |
| [`cross-release-chain-register.csv`](cross-release-chain-register.csv) | Proposed or adjudicated cross-release chain | `X-*`, `C-*` |
| [`cross-release-feature-ledger.csv`](cross-release-feature-ledger.csv) | Feature change across 6.3–7.0+, with where its state persists | ledger |

Don't put populated rows in the repo copies. If a row is worth publishing, it goes through
`method-improvements-summary.md` as prose with its controls shown.
