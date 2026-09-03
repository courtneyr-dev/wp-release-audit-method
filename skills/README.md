# Agent skills

These are [Claude Code skills](https://docs.claude.com/en/docs/claude-code/skills) — folders
containing a `SKILL.md` that an AI assistant loads when the work matches. They encode the
same method as the rest of this repository, but as instructions an agent follows rather than
a document you read.

**You don't need these.** Everything they do can be done by hand with the
[`scripts/`](../scripts/) and [`playbooks/`](../playbooks/). They're here for people who
already work with AI coding assistants and want the release-testing workflow wired in.

## Installing

Copy the folders you want into your skills directory:

```bash
git clone https://github.com/courtneyr-dev/wp-release-audit-method.git
cp -R wp-release-audit-method/skills/wp-release-* ~/.claude/skills/
```

Claude Code picks them up automatically. Then say *"prep for the release party"* or
*"run the release day sweep"* and the matching skill loads.

**Where the tests run is your call.** The skills take the driver and the install from your prompt, a path or a WP-CLI alias like `@staging` from your own `~/.wp-cli/config.yml`, and ask when you have not said. No host, alias, or credential is written into this repo. [`scripts/env/README.md`](../scripts/env/README.md) lists the drivers and what each one can and cannot do.

Other assistants that support the skill format read the same `SKILL.md`; check your tool's
documentation for where it looks.

## The three release phases

These run in order across a release cycle. Each one ends where the next begins.

### [`wp-release-prep`](wp-release-prep/) — before the release party

Builds and verifies your test environments *before* testing day, so the party is spent
testing rather than provisioning. Gates on build identity (are you actually running the
build you think?), creates single-site, multisite, and PHP-variant fixtures, imports theme
test data, asserts the state is what you expect, and calibrates controls.

Trigger: *"prep for the release party"*, *"get environments ready"*, *"set up test sites for
the Beta or RC"*.

### [`wp-release-party`](wp-release-party/) — during

Breadth, fast. Answers one question: **does this release break the ordinary things people
do?** Runs the tier-1 CRUD matrix across WP-CLI and browser, single site and multisite, plus
the upgrade ladder — then renders a Slack-ready checklist.

It deliberately does **not** post to Slack. It hands you the text; you post it.

Trigger: *"release party"*, *"run the release day sweep"*, *"test the RC and post results"*.

### [`wp-release-followup`](wp-release-followup/) — after

Depth. Establishes the host context (employee, hosted auditor, not hosted), then four jobs
in order, each gating the next: check whether previously filed issues got resolved, retest
anything newly fixed, run the full chain audit — including the distributed hosting-test
participation check before the fleet lane is called clean — and **draft** new tickets.

It drafts and never submits. Nothing gets filed without your explicit approval, and all
external access stays read-only.

Trigger: *"after the release party"*, *"check my filed tickets"*, *"what got fixed since
last release"*.

## Supporting skills

### [`wordpress-audit-handoff`](wordpress-audit-handoff/)

Turns testing work into one self-contained markdown file the recipient can act on. Two modes:

- **Coworker handoff** — findings as mechanism → evidence → fix, each linked to an
  authoritative WordPress source, with the methods and prompts used.
- **[SRE fleet brief](wordpress-audit-handoff/SKILL.md#mode-b--sre-fleet-brief)** — for people
  who run hosting for many sites. Rollout posture with movement conditions, a
  [fleet-variance matrix](wordpress-audit-handoff/SKILL.md#3-fleet-variance-matrix) (PHP
  versions, image delegates, object cache, edge header handling, pre-installed plugins),
  a distributed core-test participation table (is this infrastructure publicly running
  core's PHPUnit suite, per tier — via `scripts/hosting-test-participation.py`),
  blast radius per finding, numbered pre-GA gates, monitoring re-baselining, and where
  performance and security testing continues per tier.

Worth reading even if you never run it, for three things it enforces: **verify every GitHub
link is public before including it** (a private repo link gives your colleague a 404); **any
privately-disclosed finding reduces to a bare acknowledgment** — mechanism, endpoint, CVSS,
and reproduction all scrubbed, then grep the file to prove nothing remains; and the
**[silent-fallback class](wordpress-audit-handoff/SKILL.md#the-silent-fallback-class--worth-its-own-habit)**,
which is the habit of asking what happens when a header-gated or capability-gated feature
quietly doesn't engage and nothing logs it.

### [`wp-screenshots`](wp-screenshots/)

A screenshot harness for WordPress admin and front-end captures, driven by a JSON brief.
Headless Chromium, login-aware, hides update bubbles and admin notices, defaults to 2× DPR,
and writes an HTML gallery next to the PNGs. Useful for release posts, documentation, and
before/after visual comparison.

Needs Node — run `scripts/setup.sh` first. See [`briefs/example.json`](wp-screenshots/briefs/example.json)
for the input format.

**Screenshots are not proof.** They show what a page looked like, not what the code did.
Record the route, role, viewport, and build alongside them.

## Related skills published elsewhere

These cover WordPress development rather than release testing, and live in
[`courtneyr-dev/wp-dev-prompts`](https://github.com/courtneyr-dev/wp-dev-prompts):

WordPress Security · WordPress Plugin, Block & Theme Development · WordPress Testing & QA ·
WordPress Performance · WordPress Accessibility · WordPress Playground · UI/UX Audit

## A note on using multiple skills as reviewers

If you run several AI skills over the same question and they agree, that agreement is worth
less than it appears. Two skills by the same author, or two derived from the same source,
are **one opinion wearing two hats**.

This bit us: two separately-named WordPress penetration-testing skills turned out to be the
same author's work at two versions. Treating their agreement as confirmation would have been
counting one vote twice.

Count independent reviewers by *source*, not by label. And when a skill was written assuming
a live public target — most security skills are — its instructions do not override the
[authorization rules](../README.md#safety-and-scope) in this repository.
