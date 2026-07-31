# WordPress 7.1 feature-chain suite

Target build: WordPress 7.1 RC1.

Current tested build: WordPress 7.1-beta4. The RC1 identity gate returned
`WAITING-FOR-RC1`; no RC1 result is inferred from beta4.

Run each chain from its own directory. Tests use only the disposable local
Studio fixtures named in the chain README. They print evidence to standard
output and do not contact external services.

Verdicts use only `CONFIRMED`, `REFUTED`, `INCONCLUSIVE`, `BLOCKED`, or
`INVALID`. A control failure makes the affected batch `INVALID`.

