# Contributing

## Suggesting improvements from real use

The best improvements to this method have come from running it and noticing something — a
script that lied, a missing cell, an instruction that assumed the wrong environment. If that's
you, there are three doors, lowest-friction first:

| You have… | Use | Bar |
|---|---|---|
| A quick note — "I ran it and X" | [**Field report**](.github/ISSUE_TEMPLATE/field-report.yml) | None. A sentence. Refuted/inconclusive welcome |
| A specific change, ideally with what happened when you ran it | [**Method improvement**](.github/ISSUE_TEMPLATE/method-improvement.yml) | Show the run if you have one |
| The change already made | A **pull request** (the [template](.github/pull_request_template.md) walks you through it) | Controls if it's a detector; a green `check-repo.py` |

Two minutes, from the terminal:

```bash
# a field report — the low door
gh issue create --repo courtneyr-dev/wp-release-audit-method \
  --title "[Field report] step 4 assumes Studio; I was on DDEV" \
  --label field-report \
  --body "Ran wp-release-party on 7.2-beta1, DDEV. The path in step 4 didn't resolve because it assumes a Studio site dir."
```

**This is meant to be routine, not exceptional.** Each run of a skill ends with a
[retro](method/retro.md) whose whole job is to surface these, and the [ecosystem-signals](method/ecosystem-signals.md)
routine surfaces the ones that come from reading the news rather than running the tool. Both
feed the same [learning loop](method/release-audit-learning-loop.md). You don't need to
adjudicate your own note — surfacing it is the contribution; adjudication happens here.

**Writing prose for this repo?** [`CONTEXT.md`](CONTEXT.md) is the ubiquitous language —
cell, suite, lane, fixture, target, fleet variant, and the rest are used exactly, everywhere,
and each entry lists the words to avoid. A PR that says "test case" where the repo says
"cell" will get a rename request, so reading it first is the shorter path.

The one rule: **a tool problem is a field report; a WordPress bug is a [test report](.github/ISSUE_TEMPLATE/test-report.yml)
or a Trac ticket** (and a security bug is [HackerOne](https://hackerone.com/wordpress), never
here). Keeping those apart is the same `INVALID`-vs-`FAIL` discipline the method runs on.

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
| `README.md`, `sources/` | Testing WordPress releases themselves. Adapting a technique from another project? [`sources/upstream-techniques.md`](sources/upstream-techniques.md) — verify the licence from its LICENSE file, add a watch row |
| `plugin-theme-authors/` | Testing your own plugin or theme against a release |
| `fleet-operators/`, `templates/` | Deciding whether a release ships to a fleet, and the readiness brief |
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

1. **Run the [Lando driver](scripts/env/lando.sh) once.** It has never been executed —
   written against the docs on a machine with no Lando installed, so every capability it
   reports is a hypothesis. `bash scripts/env/conformance.sh lando`, then the CRUD suite
   against a real site. Its header has a verification checklist, one line per claim.
   **A report that it works is as valuable as a bug report**, and either one removes the
   unverified banner.
2. **Exercise the [performance playbook](playbooks/performance-release-audit-playbook.md).** It has
   never been run. One benchmark with its noise floor recorded would turn a design into a procedure.
3. **A worked example for a plugin or theme author.** `examples/` is all core testing.
4. **`wp menu` coverage in `crud-suite.sh`** — nav menus are on the browser checklist but no script
   asserts them.
5. **Exercise the core-rollback section of [`method/rollback.md`](method/rollback.md).** The
   two plugin escape hatches are exercised; the core files-plus-database rollback mechanics
   are written and have never been run. An afternoon on a disposable fixture with seeded
   content settles what a downgraded tree actually does to the data.
6. **The `cli` driver over SSH.** Local targets are tested; a remote `wp @alias` is not.

(A seventh used to sit here — parameterizing the scripts that hardcoded a release zip URL —
and shipped on 2026-08-13: all seven upgrade suites now take `--target=`.)
