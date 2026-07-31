# wp-release-audit-method

A method and toolkit for auditing WordPress releases — betas, release candidates, and
the upgrade paths between them — so that what you report is what actually happened.

Built from a WordPress 7.1 beta cycle: runtime QA across four beta builds, a parallel
content audit, and an independent adversarial review that disagreed with enough of the
first pass to change the method.

## The thesis

**Runtime decides. Controls are mandatory. Refuted claims are assets.**

Source reading proposes; only running it disposes. A source-only pass over WordPress 7.1
Beta 4 called five claims confirmed — runtime testing changed two of them. That gap is the
whole reason this repo exists.

## The five laws

| Law | What it prevents |
|---|---|
| Source observation needs runtime proof | Confident wrong findings |
| Clean installs don't cover upgrade behavior | A whole defect class stays invisible |
| Assert fixtures and denominators before reading results | Misreading a success |
| Severity needs a real attacker boundary | Severity inflation, spent credibility |
| Performance claims need repeated stable comparisons | One-run "regressions" |

A sixth was added by the loop itself: **refuted claims are assets.** Nine narrowed or
refuted claims are kept as permanent negative controls. When one starts failing, the
harness is wrong before WordPress is.

## Why the laws exist

Each came from being wrong in a specific, reproducible way:

- A clean install shows nothing when `update_core()` leaves 243 removed files behind.
  WP-CLI's updater cleaned all 243 and said so; Core's own path did not. **Testing the
  tool proves nothing about Core** — run both lanes, always.
- A network upgrade reported "2/2 sites" while three sites sat held back at the old
  `db_version`. The denominator was the bug, not the upgrade.
- Two sessions disagreed on the Tabs block until the earlier run's *native button* was
  found failing the same synthetic input. That was an automation failure wearing a
  product failure's clothes. A native control must pass before a product verdict counts.

## What's here

| Path | What it is |
|---|---|
| [`method/`](method/) | The method itself — invariants, attack surfaces, validation standard, the learning loop |
| [`playbooks/`](playbooks/) | Per-axis runbooks: security, performance, source-and-content, release-day sweep, plus a template for the next release |
| [`prompts/`](prompts/) | Verbatim prompts — source discipline, chain generation, future-release audit |
| [`scripts/`](scripts/) | Runnable triage and fixture harnesses (WP-CLI + curl, no framework) |
| [`examples/chains/`](examples/chains/) | Four adjudicated feature chains with evidence, controls, and cleanup |

Start with [`method/release-audit-learning-loop.md`](method/release-audit-learning-loop.md)
for the laws and detectors, then [`method/audit-playbook.md`](method/audit-playbook.md)
for the phase structure.

## Feature chains: the part that surprised us

Every confirmed Beta 4 defect lived in an **interaction**, not a feature — validation
order across site modes, a UI counter reading the wrong option scope, an updater's
cleanup list disagreeing with the tree it shipped. Single-feature test passes are
structurally blind to all three.

So a cross-release ledger was built: 200 features across 6.3–7.0, each carrying where its
state persists and which subsystems it touches. Four lenses proposed 36 chains.

**Zero chains survived adjudication unchanged.** Sixteen were refuted on verified-false
premises; twenty needed correction. A proposer working from a catalog invents plausible
surface names and capability relationships that dissolve when a judge reads the actual
source — `map_meta_cap()` resolves `edit_css` in the same switch arm as `unfiltered_html`,
so a chain built on "two gates" was built on one.

The rule that came out of it: **chain proposals must cite source per leg, and an
independent source-reading judge adjudicates before anything becomes a test.** The judge
lane isn't review. It's the thing that made the output usable.

The strongest surviving chains share a shape: *an older release wrote data or set an
expectation that a newer release changes.*

## The example chains

Four chains ship with full evidence, positive and negative controls, and cleanup
verification. Note that the refuted one is included deliberately — a suite of only
confirmed findings is a suite that has never been calibrated.

| Chain | Subject | Verdict |
|---|---|---|
| `C-02` | Upgrade path × file-removal ledger × clean-tree integrity | CONFIRMED |
| `C-03` | Multisite status flags × network upgrade × first load | INCONCLUSIVE |
| `C-04` | Plugin activation scope × dependency resolution × UI/REST affordance | CONFIRMED |
| `X-PERS-03r` | KSES URL reparse × legacy stored background declarations | REFUTED |

## Setup

The scripts and prompts reference a run root by environment variable. Evidence lives in
the run root, not in this repo.

```bash
export WP_AUDIT_ROOT="$HOME/wp-release-audit"
```

Optional, referenced by some prompts: `WP_LEARN_AUDIT_ROOT`, `WP_AUDIT_SKILLS`,
`AGENT_SKILLS`, `NOTES_ROOT`.

Scripts assume WP-CLI, `curl`, and a disposable local WordPress. They create throwaway
installs with fixture credentials (`admin`/`password` on `.test` hosts) — that is
deliberate and safe **only** because these are disposable local sites.

## Scope and authorization

This is defensive QA tooling for **authorized testing of public WordPress releases in
disposable local environments**.

Not for: production sites, WordPress.org infrastructure, third-party sites, or extensions
you don't own. No credential attacks, no public scanning, no persistence. File tickets and
disclosures through the proper channels — security issues go to
[HackerOne](https://hackerone.com/wordpress), never a public tracker.

Findings under active coordinated disclosure reduce to a bare acknowledgment here.
Mechanism, endpoint, and reproduction stay out until a fix ships.

## Honest limits

- The performance playbook is **unexercised** — it states acceptance criteria, no
  benchmark has been run against it.
- Two detectors (Core-vs-tool updater lane, real-input a11y harness) are accepted but
  await a release candidate.
- A full Trac open-ticket census still needs a human browser session; roughly 84 open
  tickets stayed unenumerable by agent routes.
- The legacy `ms-files.php` serving path is blocked pending a fixture with the legacy
  rewrite rule.

## License

GPLv2 or later — see [LICENSE](LICENSE). Matches the WordPress ecosystem.
