# Supply-chain security — the scale that justifies the practice

Why workflow hardening ([plugin-theme-authors/ci/](../plugin-theme-authors/ci/README.md#workflow-supply-chain-hardening--the-drop-ins-already-do-this))
is not paranoia. The figures below are the argument, drawn from Jonathan Desrosiers'
"Software Supply Chain Security in the Age of AI" (WCUS 2026) and the incidents it cites.

## The dependency surface is enormous and invisible

- **WordPress Develop carries roughly 5,000 transitive dependencies.** Gutenberg carries
  roughly 3,800. Almost none are ones a contributor chose directly — they arrive through the
  packages that arrive through the packages you installed. You cannot review 5,000 things;
  you can only pin them, scope their blast radius, and scan.

## Attestation alone is not a control

- The **TanStack worm** published **84 malicious releases across 42 packages in a 6-minute
  window** — faster than any human review loop. It was the **first known supply-chain worm to
  ship with valid, signed provenance certificates.** That last fact is the important one:
  provenance attestation proves *who built it and from what source*, not *that the source is
  benign*. A signed malicious package is still malicious. Attestation raises the floor; it is
  not the ceiling, and a pipeline that treats a green attestation as "safe" has misread what
  the signature means.
- The **Axios** and TanStack incidents both propagated through **npm install scripts** — the
  lifecycle hooks that run arbitrary code at install time. **npm 12 will disable install
  scripts by default**, which is why the CI drop-ins note it: the default is changing under
  everyone, and code that depends on an install script running will break, while code that
  depends on one *not* running gets safer for free.

## What this buys the hardening rules

Each rule in the [CI hardening section](../plugin-theme-authors/ci/README.md#workflow-supply-chain-hardening--the-drop-ins-already-do-this)
maps to a specific way the above bites:

| Rule | The scale figure it answers |
|---|---|
| Pin actions to a commit hash | 5,000 transitive deps means you cannot re-review on every tag repoint; the SHA freezes it |
| Zero `permissions:`, grant per job | a compromised dep in any of thousands runs with only the token that job holds |
| `persist-credentials: false` | the worm that reaches one step can't reuse a token a later step left lying around |
| No untrusted input in `run:` | the injection path that turns a PR title into code execution |
| `npm ci`, install scripts off | the exact propagation mechanism of Axios and TanStack |
| `composer audit` (fatal in 2.9) | turns "a vulnerable dep exists" from a line nobody reads into a failed build |

## The cross-domain lesson this repo already holds

Scanner output requires a human verification gate — four independent domains in this
project's corpus converge on it (accessibility ~70% scanner confidence; security ~90–95% of
flagged vulnerabilities not actually relevant; visual-regression 800 false alarms across
1,000 pages; multi-model malware consensus with a correlated-blind-spot caveat). Supply-chain
scanning is the same shape: Zizmor and `composer audit` are the cheap first filter that tells
you *where to look*, not the verdict. Fix what they find, but read each finding — a suppressed
rule with a written reason (see [`zizmor.yml`](../zizmor.yml)) is honest; a suppressed rule
with no reason is the confident shrug this repo exists to prevent.
