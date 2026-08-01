# Contributing

## The bar for a finding

A claim isn't a finding until it has been fired. Every contribution that asserts WordPress
behaves a certain way needs:

- **A positive control** — the thing you expect to fail, failing.
- **A negative control** — the thing you expect to pass, passing.
- **The build identity you actually tested.** Beta is not RC. A build that reports the
  wrong version invalidates the batch.
- **An evidence record** — URL, status, locator, excerpt, hash, and a replay command.

A detector that has never failed a control has never been calibrated. Three of this
repo's five detectors failed a control on first run and were fixed before acceptance; a
sixth was rejected outright for failing its negative control. Say so when yours does.

## Adding a chain

Chains go in `examples/chains/<ID>/` with `run.sh`, `cleanup.sh`, a `README.md`, and the
evidence file. Register it in `chain-register.csv` with its hypothesis, source citations
per leg, matrix cells, fixture ID, both controls, and a threat model.

**Cite source per leg.** A chain whose legs aren't grounded in specific source lines will
be adjudicated against the source and, on this repo's record, has about a zero percent
chance of surviving unchanged.

Refuted and inconclusive chains are welcome and get merged. They become negative controls.

## Threat models

Distinguish an internal footgun from a vulnerability, and a configuration-dependent path
from a default-configuration one. If a defect is only reachable by code already running
inside WordPress, say that in the threat model rather than claiming severity.

## Disclosure

Security issues in WordPress go to [HackerOne](https://hackerone.com/wordpress), never a
public tracker and never a PR here. If you're contributing method that came out of a
finding still under coordinated disclosure, contribute the method and leave the mechanism,
endpoint, and reproduction out until a fix ships.

## Paths and credentials

No absolute paths — use `$WP_AUDIT_ROOT` and friends. No credentials beyond throwaway
fixture values on disposable local installs. No local directory layouts in prose.

## Style

Sentence case headings. Present tense. Say what failed and how you know.

---

## What's in here, and where a change belongs

| Area | For |
|---|---|
| `README.md`, `sources/` | Testing WordPress releases themselves |
| `plugin-theme-authors/` | Testing your own plugin or theme against a release |
| `accessibility/`, `i18n/` | Dimensions that apply to everything |
| `method/`, `playbooks/` | Why the rules exist, and per-axis runbooks |
| `scripts/`, `data/` | Executables and the data they read |
| `skills/`, `prompts/` | AI-assisted workflow |
| `examples/` | Worked investigations with evidence |

## Before you open a pull request

```bash
python3 scripts/check-repo.py
```

That runs what CI runs: internal links and anchors, code fences, absence of personal paths and
secrets, shell/PHP/JS syntax, YAML parsing, data-file shape, mermaid rendering, and script metadata.
`--quick` skips the slow external checks.

Adding a deprecation? `data/deprecations.csv` is meant to be community-maintained — one row, with a
source link so a reviewer can verify it without guessing.

## The highest-value open contributions

1. **Exercise the [performance playbook](playbooks/performance-release-audit-playbook.md).** It has
   never been run. One benchmark with its noise floor recorded would turn a design into a procedure.
2. **A worked example for a plugin or theme author.** `examples/` is all core testing.
3. **`wp menu` coverage in `crud-suite.sh`** — nav menus are on the browser checklist but no script
   asserts them.
4. **Parameterize the five scripts** that still hardcode a release zip URL.
