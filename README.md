# Testing WordPress releases

A guide and a set of scripts for testing WordPress betas and release candidates, so the
problems you report are real ones and the passes you report actually mean something.

## Who this is for

You've offered to help test a WordPress beta, or you'd like to. You run WordPress sites.
You can follow instructions in a terminal. You are **not** expected to read WordPress core
code, write PHP, or know what a "changeset" is.

If you've ever thought *"I tested the beta and it seemed fine, but I'm not sure that
helped anyone"* — this is for exactly that.

## Contents

- [Before you start](#before-you-start)
- [Step 1: Check the build](#step-1-check-the-build-1-minute)
- [Step 2: Get a test site](#step-2-get-a-test-site)
- [Step 3: Run the test suites](#step-3-run-the-test-suites)
- [Step 4: Check what your setup can detect](#step-4-check-what-your-setup-can-detect)
- [Five mistakes that make results wrong](#five-mistakes-that-make-results-wrong)
- [How to report what you find](#how-to-report-what-you-find)
- [Where official information lives](#where-official-information-lives)
- [Using AI assistants](#using-ai-assistants)
- [Tools and integrations](#tools-and-integrations)
- [What's in this repository](#whats-in-this-repository)
- [Safety and scope](#safety-and-scope)

---

## Before you start

**You'll need:**

- A computer where you can run terminal commands (Mac, Linux, or Windows with WSL)
- The beta or RC `.zip` from [wordpress.org/download/releases](https://wordpress.org/download/releases/)

**You'll want, but don't need yet:**

- A local WordPress setup — see [Step 2](#step-2-get-a-test-site) for the options
- A [WordPress.org account](https://login.wordpress.org/register) so you can report findings
- [Making WordPress Slack](https://make.wordpress.org/chat/), where testing is coordinated

**Get the copy of this guide and its scripts:**

```bash
git clone https://github.com/courtneyr-dev/wp-release-audit-method.git
cd wp-release-audit-method
```

---

## Step 1: Check the build (1 minute)

Do this first. It needs no WordPress install, no Docker, and no database — just the zip
file you downloaded.

```bash
bash scripts/fast-triage.sh ~/Downloads/wordpress-7.2-beta1.zip
```

**What you'll see:** the version and database version, a checksum, and a list of files that
changed since the previous release.

**What matters in it:** a section listing files that were *removed* from WordPress but not
declared in the internal cleanup list (`$_old_files`). When that list isn't empty, sites
upgrading may keep old files that should have been deleted. During WordPress 7.1 testing
this surfaced **243 leftover files** — and a fresh install can never show you that, because
a fresh install has no old files to leave behind.

**Comparing two builds directly is even more useful:**

```bash
bash scripts/fast-triage.sh ~/Downloads/wordpress-7.2-RC1.zip ~/Downloads/wordpress-7.2-beta4.zip
```

Run this the moment a new build drops. It costs a minute and tells you where the rest of
your time is best spent.

---

## Step 2: Get a test site

**Never test a beta on a real site.** Use a disposable local one. Three options, easiest
first:

### Option A — WordPress Playground (no install at all)

[WordPress Playground](https://wordpress.org/playground/) runs WordPress in your browser.
Nothing to install, and you can throw it away by closing the tab. Best for clicking through
the editor and checking that features look right.

Related: [Playground documentation](https://developer.wordpress.org/playground/) ·
[Make/Playground team](https://make.wordpress.org/playground/) · a
[7.0 beta test blueprint](https://github.com/courtneyr-dev/WP7-testing) as a worked example.

**Limitation:** Playground can't test upgrades from an older version, and it can't tell you
anything about how your real server's PHP or image libraries behave.

### Option B — a local app (easiest full install)

[Local](https://localwp.com/), [Studio by WordPress.com](https://developer.wordpress.com/studio/),
or [MAMP](https://www.mamp.info/) give you a real WordPress install with a few clicks. Good
for hands-on testing and for testing upgrades — install the previous version, then upgrade
to the beta.

### Option C — wp-env (what most of these scripts use)

[`@wordpress/env`](https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/)
is the WordPress project's own Docker-based environment. It's what the scripts in this
repository drive, because it can reset a database and switch WordPress versions on command.

Requires [Docker](https://www.docker.com/products/docker-desktop/) and
[Node.js](https://nodejs.org/). Once those are installed:

```bash
npm install -g @wordpress/env
mkdir ~/wp-test && cd ~/wp-test
echo '{"core":"WordPress/WordPress#master"}' > .wp-env.json
wp-env start
```

That prints your site URL (usually `http://localhost:8888`). You'll pass that directory and
URL to the scripts below.

---

## Step 3: Run the test suites

Each script prints plain text results. Save the output — you'll need it when reporting.

```bash
bash scripts/crud-suite.sh ~/wp-test http://localhost:8888
```

| Script | What it checks | Roughly how long |
|---|---|---|
| `fast-triage.sh` | Build identity and changed files. **No site needed.** | 1 min |
| `preflight-sensitivity.sh` | What your environment can and can't detect | 1 min |
| `crud-suite.sh` | Posts, comments, media, categories — the everyday things | 5 min |
| `users-pages-install.sh` | Users, pages, fresh install, password-protected content | 10 min |
| `verify.sh` | One upgrade, captured cleanly | 5 min |
| `direct-jump-matrix.sh` | Upgrading from each older WordPress series | 30 min+ |
| `stepped-chain.sh` | WordPress 4.9 → today, carrying one database the whole way | 30 min+ |
| `multisite-suite.sh` | Multisite networks | 15 min |
| `multisite-11.sh` | A network with 10 subsites, built old then upgraded | 20 min |
| `seed-screenshot-rig.sh` | A site that produces presentable screenshots | 10 min |
| `lib-fast.sh` | Not a test — makes long suites about 12× faster | — |

### These were written during 7.1 — point them at your release

`fast-triage.sh` takes the zip as an argument, so it already works on any release. Five
others have the 7.1 beta URL written into them near the top:

```bash
cd scripts
sed -i '' 's|wordpress-7.1-beta4.zip|wordpress-7.2-beta1.zip|g' \
  verify.sh crud-suite.sh users-pages-install.sh multisite-suite.sh stepped-chain.sh
```

(On Linux, drop the `''` after `-i`.)

Two take the target without editing: `direct-jump-matrix.sh` as a third argument, and
`multisite-11.sh` via `TARGET_ZIP=...`. Patches that fix the other five are welcome.

---

## Step 4: Check what your setup can detect

```bash
bash scripts/preflight-sensitivity.sh ~/wp-test
```

This tells you what your environment is physically capable of noticing — for example
whether your zip library is old enough to reproduce a known class of archive bugs, or which
image-processing libraries you actually have installed.

**Why this matters:** if your setup couldn't have detected a problem, your "pass" isn't
evidence that the problem is absent. Save this output alongside your results, and include it
when you report.

---

## Five mistakes that make results wrong

Each of these produced a wrong conclusion during real testing.

### 1. You upgraded with WP-CLI, so you tested WP-CLI

WordPress 7.1 beta 4 left 243 removed files behind when upgraded through WordPress's own
built-in updater. WP-CLI's updater cleaned up all 243 and said so. Same build, opposite
result.

**What to do:** say which method you used — the Beta Tester plugin, WP-CLI, or a manual zip
replacement. If you only used one, you only tested one. Most users are on WordPress's own
updater.

### 2. You tested a fresh install, so you learned nothing about upgrading

A fresh install of the beta starts clean by definition, so a whole category of upgrade
problems can't appear.

**What to do:** if you did a fresh install, report "fresh install." To test upgrades,
install the *previous* version first, add some content, then upgrade.

### 3. Your success count had the wrong denominator

A multisite upgrade reported "2 of 2 sites upgraded." There were five sites. Three were
archived or marked as spam, got skipped, and stayed on the old database version — still
broken, just not counted.

**What to do:** count what you *expect* before you read what you got.

### 4. Your keyboard test failed because your tooling failed

Two testers disagreed about whether a block worked with the keyboard. It turned out the
testing tool couldn't drive a plain HTML button either. The tool was broken, not WordPress.

**What to do:** before reporting that something doesn't respond to keyboard or screen
reader input, confirm a normal control on the same page *does*.

### 5. You found something alarming that isn't reachable

Some functions look dangerous but can only be triggered by code already running inside
WordPress. That's a note, not a security issue.

**What to do:** ask *"who could actually do this, and what would they already need?"* If
the answer is "someone who already has full access," say so. Overstating severity once
costs you credibility on the next report.

**And one thing worth doing:** when you chase something and it turns out to be fine, write
that down too. Knowing something was checked and cleared is genuinely useful, and it saves
the next person the same hour.

---

## How to report what you find

Include these four things. They're what turns "it broke for me" into something someone can
act on:

1. **The exact build you tested.** Beta 1 is not beta 4 is not RC 1. Check it in
   **Dashboard → Updates** rather than assuming.
2. **How you upgraded** — Beta Tester plugin, WP-CLI, or manual zip.
3. **Your environment** — PHP version, single site or multisite, and your
   `preflight-sensitivity.sh` output.
4. **The steps to reproduce it**, specific enough that someone else can follow them.

[`playbooks/slack-test-report-template.md`](playbooks/slack-test-report-template.md) is a
format you can paste straight into Slack.

### Where to send it

| What you found | Where it goes |
|---|---|
| A bug in WordPress | [Core Trac](https://core.trac.wordpress.org/) — [search first](https://core.trac.wordpress.org/search), betas generate many duplicates |
| Not sure if it's a bug | [`#core-test` in Slack](https://make.wordpress.org/chat/), or the [Alpha/Beta forum](https://wordpress.org/support/forum/alphabeta/) |
| A bug on WordPress.org itself | [Meta Trac](https://meta.trac.wordpress.org/) |
| **A security vulnerability** | **[HackerOne](https://hackerone.com/wordpress) only** — never a public ticket, never a GitHub issue, never a pull request here |

New to Trac? Read [Reporting Bugs](https://make.wordpress.org/core/handbook/testing/reporting-bugs/)
in the Core handbook first.

---

## Where official information lives

Most weak bug reports aren't wrong about the symptom — they're wrong about what was
*supposed* to happen, because the tester read a planning post from months ago or asked an AI
that remembered an older version.

**[`sources/official-sources.md`](sources/official-sources.md)** is a full register of what's
authoritative for each kind of question, including which sources win when two disagree.

The short version:

| Your question | Where to look |
|---|---|
| Does this build exist? | [Release announcements](https://wordpress.org/news/) · [release archive](https://wordpress.org/download/releases/) |
| Did this actually ship? | [Trac milestones](https://core.trac.wordpress.org/) plus the package itself |
| Why did this change? | [Make/Core dev notes](https://make.wordpress.org/core/tag/dev-notes/) |
| What should I test? | [Make/Test](https://make.wordpress.org/test/) |
| How is it meant to work? | [Developer Resources](https://developer.wordpress.org/) · [user docs](https://wordpress.org/documentation/) |
| Has someone hit this? | [Trac search](https://core.trac.wordpress.org/search) · [Alpha/Beta forum](https://wordpress.org/support/forum/alphabeta/) |

Two rules worth memorizing: **a ticket marked "fixed" does not prove it shipped** — check
the package. And **when an announcement and the actual build disagree, the build wins**, and
that disagreement is itself worth reporting.

---

## Using AI assistants

You can hand this whole guide to an AI assistant instead of reading it. These work in
ChatGPT, Claude, Gemini, or anything else that can fetch a URL.

**Get started:**

```
Read https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/README.md

I want to help test the WordPress 7.2 beta. Walk me through it step by step.
I can use a terminal but I'm not a developer.
```

**Plan around your setup and your available time:**

```
Read https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/README.md
and https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/playbooks/release-day-sweep-playbook.md

I have a multisite install on PHP 8.2 and about two hours. What should I test,
and what will my setup be unable to detect?
```

**Check a claim before you repeat it:**

```
Read https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/sources/official-sources.md

I think WordPress 7.2 changed how X works. Which official source would confirm that,
and what would prove it actually shipped rather than just being planned?
```

**Turn your notes into a report:**

```
Read https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/playbooks/slack-test-report-template.md

Here's my terminal output and notes: [paste]

Write this up for #core-test. Then tell me which of my claims the output
doesn't actually support.
```

That last sentence matters more than it looks. **AI assistants agree with you by default**
and will happily promote "seemed broken" into "confirmed bug." Ask to be contradicted, every
time. That habit is most of what this repository is about.

---

## Tools and integrations

### WordPress Trac for AI assistants (MCP)

[`courtneyr-dev/meta-trac`](https://github.com/courtneyr-dev/meta-trac) is a hosted server
that lets an AI assistant search WordPress Trac directly — so "has anyone already reported
this?" becomes a question you can ask without leaving your chat window. Adapted from
[trac-mcp](https://github.com/Jameswlepage/trac-mcp) by James LePage. No coding required.

Add to Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json` on
Mac, `%APPDATA%\Claude\claude_desktop_config.json` on Windows):

```json
{
  "mcpServers": {
    "wordpress-core-trac": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp-server-wporg-core-trac.meta-trac-wordpress.workers.dev/mcp"]
    },
    "wordpress-meta-trac": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp-server-wporg-meta-trac.meta-trac-wordpress.workers.dev/mcp"]
    }
  }
}
```

For Claude Code:

```bash
claude mcp add wordpress-core-trac -- npx -y mcp-remote https://mcp-server-wporg-core-trac.meta-trac-wordpress.workers.dev/mcp
```

Then ask things like *"search Core Trac for open tickets about `$_old_files`."*

**Known limitation:** the underlying API doesn't return a ticket's component and can't
filter by milestone. Use it to find duplicates and read tickets — not to prove that no
ticket exists. During the 7.1 cycle roughly 84 open tickets couldn't be enumerated this way.

### WordPress's own AI integration

WordPress core is growing its own AI surface — see [Introducing the WordPress MCP
adapter](https://developer.wordpress.org/news/2026/02/from-abilities-to-ai-agents-introducing-the-wordpress-mcp-adapter/)
and the [Make/Core AI team](https://make.wordpress.org/ai/). Worth watching, and worth
testing when it lands in a release.

### Agent skills for release testing

[`skills/`](skills/) contains the release workflow as skills an AI assistant loads
automatically. **Optional** — everything they do can be done by hand with the scripts and
playbooks.

| Skill | When |
|---|---|
| [`wp-release-prep`](skills/wp-release-prep/) | Before testing day — build environments, verify identity, calibrate controls |
| [`wp-release-party`](skills/wp-release-party/) | During — the fast breadth sweep, ending in a Slack-ready report |
| [`wp-release-followup`](skills/wp-release-followup/) | After — recheck filed tickets, retest fixes, run the deep audit, **draft** new tickets |
| [`wordpress-audit-handoff`](skills/wordpress-audit-handoff/) | Package findings into one file a colleague can read |
| [`wp-screenshots`](skills/wp-screenshots/) | Capture clean admin and front-end screenshots |

Install by copying into your skills directory:

```bash
cp -R skills/wp-release-* ~/.claude/skills/
```

See [`skills/README.md`](skills/README.md) for details — including why running several AI
skills over the same question gives you less independent confirmation than it looks like.

### Prompt collections

- [`courtneyr-dev/wp-dev-prompts`](https://github.com/courtneyr-dev/wp-dev-prompts) —
  WordPress development skills: security, block and theme development, testing and QA,
  performance, accessibility, Playground, UI/UX audit
- [`courtneyr-dev/developer-education-prompts`](https://github.com/courtneyr-dev/developer-education-prompts) —
  prompts for writing documentation and training material
- [`prompts/`](prompts/) in this repository — prompts that make an AI assistant read source
  rather than guess at it

### Related testing projects

- [`courtneyr-dev/wp7-test-automation`](https://github.com/courtneyr-dev/wp7-test-automation) —
  a Playwright runner covering 123 steps across 14 areas, from the WordPress 7.0 cycle
- [`courtneyr-dev/WP7-testing`](https://github.com/courtneyr-dev/WP7-testing) — a beta test
  launcher and Playground blueprint

### The official tools these build on

[WP-CLI](https://wp-cli.org/) ([handbook](https://make.wordpress.org/cli/)) ·
[wp-env](https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/) ·
[WordPress Playground](https://wordpress.org/playground/) ·
[Beta Tester plugin](https://wordpress.org/plugins/wordpress-beta-tester/) ·
[Make/Test handbook](https://make.wordpress.org/test/handbook/)

---

## What's in this repository

| Folder | What's in it |
|---|---|
| [`scripts/`](scripts/) | The test scripts from Step 3 |
| [`sources/`](sources/) | Where official WordPress information lives |
| [`skills/`](skills/) | The release workflow as AI assistant skills (optional) |
| [`playbooks/`](playbooks/) | Longer runbooks: security, performance, content, release-day sweep, and a template for the next release |
| [`examples/chains/`](examples/chains/) | Four worked investigations with evidence and cleanup |
| [`prompts/`](prompts/) | Prompts for AI-assisted testing |
| [`method/`](method/) | The reasoning behind all of it |

### If you want to go further

The most useful testing looks at **interactions between features**, not features one at a
time. Every confirmed problem in the WordPress 7.1 cycle lived in one — a check happening in
the wrong order, a counter reading the wrong setting, an updater disagreeing with what it
shipped. Testing features individually can't find any of those.

Start with [`examples/chains/C-02/`](examples/chains/C-02/), which walks through the
leftover-files finding from start to finish. Then
[`method/release-audit-learning-loop.md`](method/release-audit-learning-loop.md).

One example of what's in there: 36 test scenarios were generated from a feature list, and
**every single one had to be corrected or thrown out** once someone checked them against
actual WordPress source. If you use AI to generate test ideas, verify them before you run
them.

---

## Safety and scope

**This is for testing public WordPress releases on disposable local sites.**

Do not point any of this at a live site, at WordPress.org's own servers, at anyone else's
site, or at plugins and themes you don't own. No password guessing, no scanning sites you
don't run.

The scripts create throwaway installs using obvious placeholder logins (`admin` /
`password`). That's fine because these sites are disposable and local — **don't copy that
pattern anywhere real.**

If you find a security vulnerability, report it through
[HackerOne](https://hackerone.com/wordpress). Not Trac, not GitHub, not here. Security
issues under coordinated disclosure appear in this repository as a bare acknowledgment
only — no reproduction steps until a fix ships.

---

## Known gaps

Stated plainly so you don't mistake these for tested ground:

- The **performance playbook has never actually been run.** It describes what a good
  benchmark would look like; treat it as a plan, not a proven procedure.
- Two checks (comparing WordPress's updater against WP-CLI's, and real-input accessibility
  testing) are written but haven't been exercised against a release candidate.
- Getting a complete list of open Trac tickets still needs a human with a browser.

## Contributing

Contributions welcome — including tests that found nothing. A test that checked something
and cleared it is useful, and gets merged. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPLv2 or later — see [LICENSE](LICENSE). Same license as WordPress.
