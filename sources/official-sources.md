# Where official WordPress information lives

**Short version:** if you're about to say "WordPress 7.2 does X," this page tells you where
to check before you say it.

*(Adapting a technique from another open-source project rather than citing WordPress? That's
the sibling page: [`upstream-techniques.md`](upstream-techniques.md) — licence discipline,
and the register that keeps borrowed attributions from going stale.)*

Most weak bug reports aren't wrong about the symptom — they're wrong about what was
*supposed* to happen. Someone read a planning post from four months ago, or a summary blog,
or asked an AI that remembered an older version. This page lists what's authoritative for
each kind of question so you can check in about thirty seconds.

**Three rules that catch most mistakes:**

1. **A ticket marked "closed/fixed" does not mean it shipped.** Check the actual package.
2. **Announcements describe intent; the build describes reality.** When they disagree, the
   build wins — and that disagreement is itself worth reporting.
3. **Only two non-WordPress.org sources are on the allowlist** ([Gutenberg
   Times](https://gutenbergtimes.com/) and [nomad.blog](https://nomad.blog/)), and only for
   discovery. Follow their links to the official source before citing anything.

**Just want the quick answer?**

| Your question | Where to look |
|---|---|
| Does this build exist, and what's in it? | [Release announcements](https://wordpress.org/news/) · [release archive](https://wordpress.org/download/releases/) |
| Did this actually ship? | [Trac milestones](https://core.trac.wordpress.org/) + the package itself |
| Why did this change? | [Make/Core dev notes](https://make.wordpress.org/core/tag/dev-notes/) |
| What should I be testing? | [Make/Test](https://make.wordpress.org/test/) |
| How is this supposed to work? | [Developer Resources](https://developer.wordpress.org/) · [end-user docs](https://wordpress.org/documentation/) |
| Has someone hit this already? | [Trac search](https://core.trac.wordpress.org/) · [Alpha/Beta forum](https://wordpress.org/support/forum/alphabeta/) |

The rest of this page is the complete register, including the evidence rules that decide
what wins when two sources disagree.

---

Use this register for WordPress release, feature, documentation, and Learn audits. Re-enumerate living indexes each cycle. A required source is not covered until its hits, verified zero hits, inactive status, or access blocker are recorded.

## Evidence order by question

Do not force every question into one global source hierarchy. Use the evidence that can prove the claim:

- **What build exists:** official release announcement, release archive, downloadable package and hashes, version API, then the build's own version output.
- **What shipped:** exact package/source and executed runtime behavior, then Core SVN changesets, Core Trac, and relevant official GitHub repository history.
- **Why it changed and how to adopt it:** Make/Core dev notes, Field Guides, release posts, component posts, and Developer Resources.
- **What users must learn:** shipped behavior plus current end-user documentation, Developer Resources, Learn WordPress, and relevant Make team work.
- **What may be going wrong:** canonical tickets/issues and runtime reproduction. Support forums and Slack are discovery signals until corroborated.

When sources conflict, preserve the conflict. The exact target package and a valid runtime test outrank a planning post for claims about shipped behavior. A ticket or pull request marked complete does not prove inclusion in a release package.

## Tier 1: official build, source, and implementation evidence

### Release identity and packages

- Release announcements: `https://wordpress.org/news/`
- Release archive, including stable, beta, and RC packages and hashes: `https://wordpress.org/download/releases/`
- Version-offer API: `https://api.wordpress.org/core/version-check/1.7/`
- Core checksum API: `https://api.wordpress.org/core/checksums/1.0/?version={VERSION}&locale={LOCALE}`
- Release downloads, by exact filename: `https://downloads.wordpress.org/release/wordpress-{VERSION}.zip` (the bare `/release/` path does not list — browse [wordpress.org/download/releases](https://wordpress.org/download/releases/) instead)

Require announcement identity and an exact downloadable package before running a named prerelease lane. Use nightly or trunk only when the task names that moving target; never substitute it for a missing beta or RC.

### Core source and work tracking

- Core Trac tickets, milestones, reports, timeline, and changesets: `https://core.trac.wordpress.org/`
- Core release source: `https://core.svn.wordpress.org/`
- Core development source and tests: `https://develop.svn.wordpress.org/`
- WordPress GitHub organization: `https://github.com/WordPress`
- Core GitHub mirror: `https://github.com/WordPress/wordpress-develop`
- Gutenberg: `https://github.com/WordPress/gutenberg`
- Learn WordPress source: `https://github.com/WordPress/learn`
- WP-CLI GitHub organization: `https://github.com/wp-cli`
- WP-CLI main repository: `https://github.com/wp-cli/wp-cli`
- WP-CLI release history and assets: `https://github.com/wp-cli/wp-cli/releases`

Use the repository that owns the relevant artifact. WP-CLI is maintained in the separate `wp-cli` GitHub organization, not the `WordPress` organization, so a WordPress-org-only census is incomplete when WP-CLI is in scope. Use the WP-CLI releases page for tagged version history, release notes, and attached assets, then verify the installed binary and command behavior. Do not use merged-PR searches in `wordpress-develop` as a shipping census; it mirrors the SVN-governed Core history.

### Other official implementation surfaces, when relevant

- Meta Trac: `https://meta.trac.wordpress.org/`
- Plugins Trac: `https://plugins.trac.wordpress.org/`
- Themes Trac: `https://themes.trac.wordpress.org/`
- Plugin directory: `https://wordpress.org/plugins/`
- Theme directory: `https://wordpress.org/themes/`
- Translation platform: `https://translate.wordpress.org/`
- WordPress.tv: `https://wordpress.tv/`

Scope these to the feature being audited. Plugin/theme directory material does not prove Core behavior, and a Meta ticket does not prove a change shipped in a Core package.

### Distributed hosting test results

- Host Test Results dashboard: `https://make.wordpress.org/hosting/test-results/`
- Getting started (how a host joins): `https://make.wordpress.org/hosting/test-results-getting-started/`
- Reporter (the dashboard's plugin): `https://github.com/WordPress/phpunit-test-reporter`
- Runner (what hosts execute): `https://github.com/WordPress/phpunit-test-runner`

Official evidence that a **reporter account** ran core's PHPUnit suite at a **develop-SVN
revision** on **some infrastructure** (PHP and database recorded), with a
passed/failed/errored status. It proves participation and that run's outcome — never
plugin compatibility, upgrade safety, fleet-wide coverage, or attribution to a specific
hosting tier (the public data carries no environment label). The dashboard's own
freshness split is the 25 most-recent revisions. Read it with
`scripts/hosting-test-participation.py` (read-only, evidence-preserving); classifications
and reasoning-error guards live in
[the participation lane](../fleet-operators/README.md#9-distributed-core-test-participation--public-evidence-scoped-honestly).
Both repositories are watched for drift in [`upstream-watch.csv`](upstream-watch.csv)
because the collector is coupled to the reporter's public data model.

## Tier 2: official release, team, documentation, and education evidence

### Make WordPress team register

Re-read `https://make.wordpress.org/` each audit rather than freezing this list. As of the 2026-07-31 census, the index links:

- Core, Design, Mobile, Accessibility, Polyglots, Support, Documentation, Themes, Plugins, Community, Meta, Training, Test, TV, CLI, Hosting, Tide, Openverse, Photos, Core Performance, Playground, Core AI, and Core Program;
- Marketing, which the index marks archived.

Also check these official Make sites when their scope intersects the release, even if the current team index does not list them as active teams:

- Project: `https://make.wordpress.org/project/`
- Security: `https://make.wordpress.org/security/`
- Sustainability: `https://make.wordpress.org/sustainability/`
- Media Corps: `https://make.wordpress.org/media-corps/`

Record each relevant site as `ACTIVE`, `ARCHIVED`, `UNLISTED_OFFICIAL`, `INACTIVE`, `ZERO_HITS_VERIFIED`, or `BLOCKED`. Do not infer zero hits from a stale tag page; use direct search, date windows, feeds, and canonical post URLs.

The current indexed sites include:

- Core `https://make.wordpress.org/core/`
- Design `https://make.wordpress.org/design/`
- Mobile `https://make.wordpress.org/mobile/`
- Accessibility `https://make.wordpress.org/accessibility/`
- Polyglots `https://make.wordpress.org/polyglots/`
- Support `https://make.wordpress.org/support/`
- Documentation `https://make.wordpress.org/docs/`
- Themes `https://make.wordpress.org/themes/`
- Plugins `https://make.wordpress.org/plugins/`
- Community `https://make.wordpress.org/community/`
- Meta `https://make.wordpress.org/meta/`
- Training `https://make.wordpress.org/training/`
- Test `https://make.wordpress.org/test/`
- TV `https://make.wordpress.org/tv/`
- Marketing `https://make.wordpress.org/marketing/`
- CLI `https://make.wordpress.org/cli/`
- Hosting `https://make.wordpress.org/hosting/`
- Tide `https://make.wordpress.org/tide/`
- Openverse `https://make.wordpress.org/openverse/`
- Photos `https://make.wordpress.org/photos/`
- Core Performance `https://make.wordpress.org/performance/`
- Playground `https://make.wordpress.org/playground/`
- Core AI `https://make.wordpress.org/ai/`
- Core Program `https://make.wordpress.org/program/`

### Official documentation and education

- WP-CLI project landing page: `https://wordpress.org/cli/`
- Developer Resources: `https://developer.wordpress.org/`
- Developer Blog: `https://developer.wordpress.org/news/`
- End-user documentation: `https://wordpress.org/documentation/`
- Learn WordPress: `https://learn.wordpress.org/`
- Legacy Codex: `https://codex.wordpress.org/Main_Page`

Use the Codex for historical discovery only. Flag Codex-only claims as legacy and reconcile them against current Developer Resources, source, and runtime behavior.

Use the WP-CLI landing page as official project-overview and discovery evidence. Follow it to the Make/CLI handbook, Developer Resources command reference, and current release notes as the claim requires. Do not use the landing page alone to prove version-specific command behavior; verify that against the relevant WP-CLI version and executed output. Keep Core updater and WP-CLI updater evidence in separate lanes.

### Developer Resources — the handbooks

Twelve public handbooks plus the generated API reference. Go to the one that owns your question:

| Handbook | Covers |
|---|---|
| [Code Reference](https://developer.wordpress.org/reference/) | Every function, class, hook, and method, generated from source |
| [APIs](https://developer.wordpress.org/apis/) | Core APIs — options, transients, settings, HTTP, filesystem |
| [Plugin](https://developer.wordpress.org/plugins/) | Plugin architecture, hooks, security, internationalization |
| [Theme](https://developer.wordpress.org/themes/) | Classic and block themes, template hierarchy, theme.json |
| [Block Editor](https://developer.wordpress.org/block-editor/) | Blocks, the editor, `@wordpress/*` packages, `wp-env` |
| [REST API](https://developer.wordpress.org/rest-api/) | Routes, schemas, authentication, extending |
| [Coding Standards](https://developer.wordpress.org/coding-standards/) | PHP, JS, CSS, HTML, accessibility, inline docs |
| [Advanced Administration](https://developer.wordpress.org/advanced-administration/) | Server config, security, performance, upgrading, multisite |
| [WP-CLI Commands](https://developer.wordpress.org/cli/commands/) | Every command and subcommand |
| [Playground](https://developer.wordpress.org/playground/) | Blueprints, the JS API, embedding |
| [Secure Custom Fields](https://developer.wordpress.org/secure-custom-fields/) | SCF fields and functions |
| [Developer Blog](https://developer.wordpress.org/news/) | Practical articles, often the clearest explanation of a new feature |

Two rules for using them:

- **Code Reference is source-derived** — treat it as API evidence, but verify release-specific
  behavior against the target build and a runtime test. A parser page describes trunk, not
  necessarily the version you're testing.
- **Handbooks are guidance, not proof.** They describe intent. When a handbook and the running
  build disagree, the build wins — and that disagreement is worth reporting, to the docs team if
  the build is right and to Trac if the handbook is.

<details>
<summary>Bulk discovery via RSS (only when you need completeness)</summary>

For sweeping *everything* that changed across the handbooks — an audit needing coverage proof
rather than an answer — Developer Resources exposes a combined feed. Most people never need this;
use the handbook links above instead.

```
https://developer.wordpress.org/feed/?post_type[0]=wporg_explanations&post_type[1]=apis-handbook&post_type[2]=plugin-handbook&post_type[3]=theme-handbook&post_type[4]=blocks-handbook&post_type[5]=wpcs-handbook&post_type[6]=rest-api-handbook&post_type[7]=wp-parser-function&post_type[8]=wp-parser-class&post_type[9]=wp-parser-hook&post_type[10]=wp-parser-method&post_type[11]=command&post_type[12]=scf-handbook&post_type[13]=adv-admin-handbook&post_type[14]=playground-handbook
```

Also: [Developer Blog feed](https://developer.wordpress.org/news/feed/) ·
[registered REST types](https://developer.wordpress.org/wp-json/wp/v2/types) · handbook indexes and
sitemaps when pagination matters.

A feed proves *discovery*, never *completeness*. Deduplicate cross-posted dev notes by canonical URL.

</details>

## Tier 3: official but non-durable signals

### Support forums

- Alpha/Beta/RC: `https://wordpress.org/support/forum/alphabeta/`
- All topics: `https://wordpress.org/support/view/all-topics/`
- Plugins: `https://wordpress.org/support/forum/plugins-and-hacks/`
- Themes: `https://wordpress.org/support/forum/themes-and-templates/`

Classify every relevant report:

1. `CONFIRMED_CANONICAL` — linked to a canonical ticket/issue or reproduced on the exact build.
2. `PROBABLE_COMPATIBILITY` — exact build and named interaction, but no canonical ticket or valid reproduction yet.
3. `UNVERIFIED_SIGNAL` — plausible symptom without enough version or reproduction detail.
4. `UNRELATED` — outside the target release or mechanism.

Volume is not proof. Preserve the forum URL and state `no canonical ticket found` when applicable.

### Making WordPress Slack

- Official access and joining instructions: `https://make.wordpress.org/chat/`
- Workspace: `https://wordpress.slack.com/`

Use an available authorized connector read-only. Never post, react, or DM for the user. Treat Slack as official but ephemeral: cite channel, UTC date, and permalink when available. It can establish that a discussion occurred, but publish release scope, schedule, ownership, or defect claims only after checking a durable official source. If no durable source exists, label the statement `Slack discussion, not yet posted`.

Discover current release channels, meetings, scrub schedules, and squads from the current release hub and Make posts. Do not carry channel names or meeting times from a prior release.

## Supplementary discovery sources — not official

The standing allowlist contains exactly:

- Gutenberg Times: `https://gutenbergtimes.com/`
- nomad.blog: `https://nomad.blog/`

Use them for discovery, contributor perspective, and framing. Follow their links to official evidence. Do not use either publication alone to prove that a feature shipped, a defect exists, a schedule changed, or a contributor holds a current role. Keep them labeled `SUPPLEMENTARY`, never `OFFICIAL` or `SOURCE_OF_TRUTH` in the evidence register.

Any other third-party publication, forum, social network, search snippet, or model memory is out of scope for WordPress factual claims unless the task explicitly changes the allowlist.

## Verification rules

- Recheck current milestone, exact package, announcement, and runtime at publication time. RC status raises confidence but does not guarantee final inclusion.
- Verify contributor roles against the current release-squad announcement or other current official record.
- Cite claims inline with the most direct evidence. Keep ticket, changeset, pull request, package, and runtime evidence distinct.
- Search by version, date window, component, ticket, changeset, package, API name, old/new terminology, and affected user task. Version tags alone miss untagged material.
- Preserve negative searches with the query, page range or pagination cursor, date, and result count.
- Mark inaccessible network-dependent checks `UNVERIFIABLE_OFFLINE` with an exact replay recipe. Do not convert a planned source universe into claimed coverage.

## Per-release source register

Record one row per source surface with:

`source_id,authority_class,host,section_or_post_type,team_status,release_window,query_or_feed,pages_or_cursor,items_reviewed,relevant_hits,zero_hits_verified,blocked_reason,last_checked,evidence_path`

For each factual claim, record:

`claim_id,claim,question_type,primary_evidence,corroborating_evidence,conflict_status,runtime_status,publication_wording`

Re-read the Make team index and Developer Resources REST type index each cycle. Add new public surfaces and record renamed, archived, or retired ones rather than assuming this census is permanent.
