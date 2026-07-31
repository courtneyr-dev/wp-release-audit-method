# wp-release-audit-method

Tools and habits for testing a WordPress beta or RC so that what you report holds up.

Written for people who already test releases — you know WP-CLI, you can get a local site
running, you've filed a Trac ticket or posted in `#core-test`. You don't need to read core
source to use any of this.

## Start here: one command, 60 seconds

Download the beta zip and hand it to the triage script. No Docker, no database, no install.

```bash
git clone https://github.com/courtneyr-dev/wp-release-audit-method.git
cd wp-release-audit-method
bash scripts/fast-triage.sh ~/Downloads/wordpress-7.2-beta1.zip
```

You get the build identity (version, db_version, sha256), what changed since the previous
build, and — the useful part — **which removed files aren't declared in `$_old_files`**.
That last one is a real defect class that a clean install can never show you.

Comparing two builds directly is even better:

```bash
bash scripts/fast-triage.sh ~/Downloads/wordpress-7.2-RC1.zip ~/Downloads/wordpress-7.2-beta4.zip
```

Run this the moment a build drops. It costs a minute and it tells you where to spend the
next hour.

## Or hand this repo to an AI assistant

You don't have to read any of this yourself. Paste one of these into ChatGPT, Claude,
Gemini, or whatever you use — they all fetch URLs.

**Get oriented:**

```
Read https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/README.md

I'm testing the WordPress 7.2 beta on a local site. Walk me through what to run first
and what to watch out for. I know WP-CLI but I'm not a core developer.
```

**Plan a session around your setup:**

```
Read https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/README.md
and https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/playbooks/release-day-sweep-playbook.md

I have a multisite install on PHP 8.2 and about two hours. Build me a test plan,
and tell me what my setup can't detect.
```

**Turn a messy result into a filable report:**

```
Read https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/playbooks/slack-test-report-template.md

Here's my terminal output: [paste]

Write this up. Flag anything I claimed that the output doesn't actually support.
```

That last instruction matters more than it looks. Assistants are agreeable by default and
will happily upgrade "seems broken" into "confirmed bug." Ask to be contradicted.

In Claude Code or any agent with shell access, cloning and pointing it at the repo works
directly:

```bash
git clone https://github.com/courtneyr-dev/wp-release-audit-method.git && cd wp-release-audit-method
```

Then: *"Read the README and CONTRIBUTING, then run fast-triage on the beta zip in my
Downloads folder and tell me what's worth chasing."*

## Five ways your test can lie to you

These aren't theory. Each one burned a real testing session and cost real credibility.

**1. You upgraded with WP-CLI, so you tested WP-CLI.**
WordPress 7.1 beta4 left 243 removed files behind when upgraded through Core's own
updater. WP-CLI's updater cleaned all 243 and printed "243 files cleaned up." Same target
build, opposite result. **Whichever lane you used, you didn't test the other one** — and
most users are on Core's.

**2. You tested a clean install, so you tested nothing about upgrades.**
A fresh install of the beta shows a clean tree by definition. The entire class of
upgrade-path defects is invisible to it. If you only did a fresh install, say "fresh
install" in your report — don't say "upgrade works."

**3. Your success count had the wrong denominator.**
A network upgrade reported "2/2 sites upgraded." There were five sites. Three were
archived or spam and got held back at the old `db_version` — still sitting there, still
broken. The report was true and useless. **Count what you expected before you read what
you got.**

**4. Your keyboard test failed because your automation failed.**
Two sessions disagreed about the Tabs block until someone checked whether a plain HTML
button passed the same synthetic keypress. It didn't. That was a broken harness wearing a
product bug's clothes. **Get a native control to pass first**, then believe your result.

**5. You found a footgun and called it a vulnerability.**
`wp_delete_site(1)` looks alarming until you notice it's only reachable by code already
running inside WordPress. If an attacker needs to already be inside to trigger it, that's
a note, not a severity. Overclaiming once costs you the benefit of the doubt next time.

A sixth, earned the hard way: **a refuted claim is worth keeping.** When you chase
something and it turns out fine, write that down. It becomes the control that tells you
your setup still works.

## The fuller suites

These use [`@wordpress/env`](https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/),
so you'll need Docker and Node. Point them at a wp-env project directory and its URL.

| Script | What it covers |
|---|---|
| `fast-triage.sh` | Build identity, file diff, `$_old_files` gaps. **No Docker needed.** |
| `preflight-sensitivity.sh` | What your environment can and can't detect. Run this first. |
| `crud-suite.sh` | Posts, comments, media, terms — the everyday smoke pass |
| `users-pages-install.sh` | Users, pages, fresh install, manual install, password-protected content |
| `verify.sh` | One upgrade hop, captured cleanly |
| `direct-jump-matrix.sh` | Latest of each series → target, fresh install per hop |
| `stepped-chain.sh` | 4.9 → target carrying one database the whole way |
| `multisite-suite.sh` | Network CRUD, network users, network activation |
| `multisite-11.sh` | 1 site + 10 subsites, built on the previous release then upgraded |
| `seed-screenshot-rig.sh` | A site that produces publishable screenshots |
| `lib-fast.sh` | Source this to skip npx startup — 12× faster on long suites |

### Run preflight before you trust a pass

```bash
bash scripts/preflight-sensitivity.sh ~/projects/my-wp-env-project
```

It tells you things like whether your libzip is old enough to reproduce the CHECKCONS zip
regressions, or which image library delegates you actually have. **A test that passes on an
environment that couldn't have detected the failure is not evidence.** Save this output
next to your results.

### These were written during 7.1 — retarget them

`fast-triage.sh` takes zips as arguments, so it already works on any release. Five others
hardcode the target near the top of the file:

```bash
cd scripts
sed -i '' 's|wordpress-7.1-beta4.zip|wordpress-7.2-beta1.zip|g' \
  verify.sh crud-suite.sh users-pages-install.sh multisite-suite.sh stepped-chain.sh
```

Two take the target without editing — `direct-jump-matrix.sh` as a third argument, and
`multisite-11.sh` via `TARGET_ZIP=...`.

Patches that parameterize the rest are very welcome.

## Reporting what you find

Whatever you file, include these four. They're what turns "it broke for me" into something
someone can act on:

- **The build you actually tested.** Beta is not RC. `wp core version` it, don't assume.
- **The upgrade lane.** Beta Tester plugin, WP-CLI, and manual zip give different results.
- **Your environment.** PHP version, single vs multisite, and the preflight output.
- **A replay command.** The exact thing you ran, so someone else can run it too.

[`playbooks/slack-test-report-template.md`](playbooks/slack-test-report-template.md) has a
format ready to paste into `#core-test`.

**Where to file:** ordinary bugs go to
[Trac](https://core.trac.wordpress.org/) — search first, betas generate a lot of
duplicates. Security issues go to [HackerOne](https://hackerone.com/wordpress), **never** a
public ticket and never a PR here.

### Searching Trac without leaving your assistant

There's a hosted MCP server for WordPress Core Trac, which makes "has anyone already filed
this?" a question your AI assistant can answer while you're still in the terminal:

```
https://mcp-server-wporg-core-trac.meta-trac-wordpress.workers.dev/mcp
```

It exposes ticket search, single tickets, changesets, the timeline, and metadata
(components, milestones, priorities, severities). Add it to Claude Desktop or any
MCP-capable client:

```json
{
  "mcpServers": {
    "wordpress-core-trac": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp-server-wporg-core-trac.meta-trac-wordpress.workers.dev/mcp"]
    }
  }
}
```

Claude Code: `claude mcp add wordpress-core-trac -- npx -y mcp-remote https://mcp-server-wporg-core-trac.meta-trac-wordpress.workers.dev/mcp`

Then you can ask things like *"search Trac for open tickets about `$_old_files` in the 7.2
milestone"* before you write anything up.

**One limitation worth knowing:** the API doesn't return `component`, and can't filter by
milestone directly. During the 7.1 cycle roughly 84 open tickets stayed unenumerable this
way — a full census still needs a browser. Use it to check for duplicates and read
tickets, not to prove a ticket doesn't exist.

## Going deeper

Once the scripts feel routine, the interesting part is testing **interactions** rather than
features. Every confirmed defect in the 7.1 cycle lived in one: validation order across
site modes, a counter reading the wrong option scope, an updater disagreeing with the tree
it shipped. Single-feature passes are structurally blind to all three.

- [`examples/chains/`](examples/chains/) — four worked examples with evidence, controls,
  and cleanup. Read `C-02` first; it's the stale-file finding end to end. `X-PERS-03r` is
  included precisely because it was **refuted** — that's what a calibrated suite looks
  like.
- [`playbooks/`](playbooks/) — per-axis runbooks: security, performance, source-and-content,
  release-day sweep, plus a template for the next release.
- [`method/`](method/) — the reasoning underneath. Start with
  [`release-audit-learning-loop.md`](method/release-audit-learning-loop.md).
- [`prompts/`](prompts/) — if you use AI assistants for this, these enforce reading source
  over guessing at it. Worth knowing: of 36 chains proposed from a feature catalog, **zero
  survived source review unchanged.** Models invent plausible-sounding capability
  relationships. Make them cite source per step.

## Scope

Defensive QA for **public WordPress releases in disposable local environments**.

Not for production sites, WordPress.org infrastructure, other people's sites, or extensions
you don't own. No credential attacks, no public scanning, no persistence.

The scripts create throwaway installs with fixture credentials (`admin`/`password` on
`.test` hosts). That's deliberate and safe only because these sites are disposable — don't
copy the pattern anywhere real.

Findings under active coordinated disclosure appear here as a bare acknowledgment.
Mechanism and reproduction stay out until a fix ships.

## Known gaps

- The performance playbook states acceptance criteria but **no benchmark has been run
  against it**. Treat it as a design, not a proven procedure.
- Two detectors (Core-vs-tool updater lane, real-input a11y harness) are accepted but
  await a release candidate.
- A full Trac open-ticket census still needs a human browser session — roughly 84 open
  tickets couldn't be enumerated by automated routes.

Contributions welcome, including refuted and inconclusive results — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPLv2 or later — see [LICENSE](LICENSE).
