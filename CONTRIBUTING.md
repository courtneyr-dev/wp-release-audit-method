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
| `scripts/env/` | Environment drivers — where WordPress runs. [Its own README](scripts/env/README.md) |
| `fixtures/` | Checked-in environment configs, so a fixture is a file rather than a paragraph |
| `skills/`, `prompts/` | AI-assisted workflow |
| `examples/` | Worked investigations with evidence |

## Adding an environment

A driver teaches the suites to run somewhere new — DDEV, Lando, Playground, a Local site,
a staging box. It's about 150 lines, it's self-contained, and it's a good first
contribution. [`scripts/env/README.md`](scripts/env/README.md) has the interface;
[`ddev.sh`](scripts/env/ddev.sh) is the reference implementation to copy from.

The bar is the same as for a finding, for the same reason. **Declare only capabilities you
have actually exercised.** Under-claiming costs a few `BLOCKED` cells; over-claiming turns
a cell that could never have failed into a `PASS`, and nobody downstream can tell. If you
can't test something, say so in the header — an unverified driver is welcome and useful,
an unverified driver that reads as tested is not.

## Before you open a pull request

```bash
python3 scripts/check-repo.py
```

That covers internal links and anchors, code fences, absence of personal paths and secrets,
shell/PHP/JS syntax, **shellcheck** (errors only, and silently skipped if it isn't installed
— `brew install shellcheck` / `apt install shellcheck`), YAML parsing, data-file shape,
mermaid rendering, and script metadata. `--quick` skips the slow external checks *and
shellcheck*, so run it without `--quick` at least once before opening a PR.

It is **one of four CI jobs**, not all of them. The others need a network or a container and
so aren't part of this script:

| CI job | What it does | Runs locally? |
|---|---|---|
| `check` | `check-repo.py`, as above | yes |
| `external-links` | curls every external URL in the docs | no — advisory, `continue-on-error` |
| `live-wordpress` | boots a real WordPress on DDEV and runs the CRUD suite against it | only if you have DDEV |
| `surface-inventory` | smoke-tests `wp-surface-inventory.sh` against a fixture | yes, see the workflow |

So a green `check-repo.py` means your change is well-formed, not that it works. If you touched
anything under `scripts/`, run the thing you changed against a real site too.

Adding a deprecation? `data/deprecations.csv` is meant to be community-maintained — one row, with a
source link so a reviewer can verify it without guessing.

## The highest-value open contributions

1. **Exercise the [performance playbook](playbooks/performance-release-audit-playbook.md).** It has
   never been run. One benchmark with its noise floor recorded would turn a design into a procedure.
2. **A worked example for a plugin or theme author.** `examples/` is all core testing.
3. **`wp menu` coverage in `crud-suite.sh`** — nav menus are on the browser checklist but no script
   asserts them.
4. **Parameterize the five scripts** that still hardcode a release zip URL.
