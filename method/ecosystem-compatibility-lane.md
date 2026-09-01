---
title: "Ecosystem compatibility lane — the release is fine and the site still dies"
type: method
status: active
created: '2026-08-21'
updated: '2026-08-23'
tags:
  - wordpress
  - release-audit
  - ecosystem
  - plugins
related:
  - '[release-audit-learning-loop](release-audit-learning-loop.md)'
  - '[rollback](rollback.md)'
  - '[preflight-core-probe](preflight-core-probe.md)'
  - '[registers](registers.md)'
---

# Ecosystem compatibility lane

This repo tests core. [`plugin-theme-authors/`](../plugin-theme-authors/) helps an author test
their own plugin. Between them sits a lane neither covers: **testing the release against the
plugins people actually run** — where the release is correct, the plugin's assumption about a
core internal is not, and the crash arrives anyway. On 7.1 release day that gap took down
production sites by the hundred while every core-lane cell in this method read PASS, because
every core-lane cell was measuring the right thing and the failure wasn't in core.

## The structural reason single-plugin matrices miss this class

The failure that defines this lane needs **three parties**:

1. **A core change** — legitimate, often an improvement.
2. **A plugin assumption** about the internal that change touched.
3. **A third plugin or theme supplying the trigger state** that routes execution into the
   assumption.

A compatibility matrix that installs one plugin at a time tests pairs: core × plugin. The
class lives in triples. `core × plugin-A` is green, `core × plugin-B` is green, and
`core × plugin-A × plugin-B` fatals — not because A and B conflict with each other, but
because B creates the state under which A's assumption about core finally executes. No
number of single-plugin cells reaches that cell, which is why "we tested the top N plugins
individually" and "the top N plugins are safe" are different claims.

## The worked incident — WP Rocket on 7.1 release day

Timeline, from public sources (dates verified against the cited pages):

- **2026-07-06** — during the 7.1 beta cycle, a report is filed on WP Rocket's own tracker
  ([wp-media/wp-rocket#8596](https://github.com/wp-media/wp-rocket/issues/8596)) naming the
  incompatibility, **with a suggested one-line fix included**. It sits untriaged.
- **2026-08-19** — WordPress 7.1 ships. WP Rocket sites start fataling within hours.
- **2026-08-20** — WP Rocket 3.23.2.2 ships the fix
  ([wp-media/wp-rocket#8745](https://github.com/wp-media/wp-rocket/pull/8745)) — the same
  one-line string cast proposed on July 6, 44 days earlier. Affected: roughly 3.16 through
  3.23.2.1.

**The mechanism.** 7.1 changed `_wp_filter_build_unique_id()` from `spl_object_hash()` (a
32-character hex string) to `spl_object_id()` (a small integer cast to string) — commit
[`9560811`](https://github.com/WordPress/wordpress-develop/commit/956081111b451bf312be89665d643387f9cd48ac),
itself a **performance improvement** ("Plugins: Improve hook performance…"). PHP silently
converts numeric string array keys to integers, so `$wp_filter` callback keys that had been
strings since forever became `int`. WP Rocket's Cloudflare module
(`inc/ThirdParty/Plugins/CDN/Cloudflare.php:562`) calls `substr( $key, -strlen( $method ) )`
on those keys under `declare(strict_types=1)` — `substr()` on an `int` under strict types is
a `TypeError`, which is fatal. Core's side of the fallout is tracked as
[Trac #65919](https://core.trac.wordpress.org/ticket/65919) — *"Array keys in
WP_Hook::$callbacks may now be integers instead of strings in 7.1 causing fatal errors with
string functions"* — accepted and milestoned 7.1.1.

**The third ingredient.** The fatal only fires when *another* plugin or theme hooks a
**closure** on `deleted_post` (priority 10) or `transition_post_status` (priority
`PHP_INT_MAX`) — closures are what get keyed by object id. Elementor Pro and Contact Form 7
Redirection are common triggers. **A clean install of 7.1 plus WP Rocket alone does not
crash.** That is the whole lesson: the pair is green, the triple is down.

**Blast radius.** The Cloudflare module runs on every request whether or not the site uses
Cloudflare, and the fatal fires on `init` — killing the front end, wp-admin, admin-ajax,
REST, cron, **and WP-CLI**. The ordinary recovery path was dead too; see
[rollback](rollback.md) for the escape hatches that still worked. Measured impact from one
fleet: Austin Ginder (Anchor Hosting) reported **332 production sites running WP Rocket, of
which 124 — 37% — fataled**. Wordify's writeup records a first customer whose core
auto-update ran at 01:55 UTC and whose first fatal followed **three seconds later**, with
roughly 35 minutes to resolution — most of it diagnosis, because nobody had yet connected
"7.1" to "WP Rocket."

Sources: The Repository, "WP Rocket Releases Fix for WordPress 7.1 Fatal Error"
(2026-08-21; sourced heavily from embedded X posts); Wordify, "Fixed: WP Rocket fatal error
after WordPress 7.1" (2026-08-20) — the technical root cause, independently reproduced on
their own test site, though note the piece is vendor content marketing for Wordify's own
monitoring and update products; the reproduction stands on its own. These are external
reports, not this repo's findings — this repo has not independently reproduced the fatal.

## The detector: hook-key-type probe

[`scripts/hook-key-type-probe.sh`](../scripts/hook-key-type-probe.sh) walks `$wp_filter` on
a seeded fixture and reports:

- the PHP **type of every callback key** (int keys mean the 7.1 behavior reached this site),
- **which plugins and themes register closures**, on which hooks, at which priorities — the
  candidate third ingredients,
- hooks where int and string keys coexist at one priority.

It ships with both controls in the same file: a positive control that registers a closure on
`deleted_post` at priority 10 in-process and requires the probe to see it, and a negative
control that registers only a named function and requires the probe to report no closure
there. A probe run without its controls passing is not a reading.

What the probe does **not** do: it cannot tell you which plugin *consumes* hook keys with
string functions — that's a static question. The cheap static complement is grepping the
plugin corpus for `_wp_filter_build_unique_id`, `spl_object_hash`, and string operations on
`$wp_filter` keys.

## The co-installed cell block in the T1 sweep

The sweep matrix carries an `ecosystem` cell block ([`pilots/release-day/sweep-matrix.csv`](../pilots/release-day/sweep-matrix.csv),
entity `ecosystem`): a fixture with the top co-installed plugin pairs by real-world
prevalence, upgraded across the release boundary, asserting **no new fatals in `debug.log`**
and a front end and admin that still answer 200. Pair selection follows
[`plugin-theme-authors/co-installed-plugins.md`](../plugin-theme-authors/co-installed-plugins.md)
— category leaders (caching, SEO, forms, page builders, eCommerce) plus anything your own
support channels name.

Two honest limits, stated up front:

- **Premium plugins cannot be fetched from the directory API.** WP Rocket — the very plugin
  that motivated this lane — is premium. A tester who doesn't own a license cannot build the
  cell; the cell reads `BLOCKED(premium-license)`, never `SKIP`. Supply the zip yourself if
  you hold a license.
- Pair cells still miss triples. The block buys breadth against the *common* failure (a
  popular plugin's assumption breaking on upgrade with its usual companions active); the
  probe above is what hunts the trigger ingredient.

## A dependency's public tracker is a release-readiness input

Six weeks of notice existed for the WP Rocket fatal, in public, with a proposed patch — and
nobody testing the release consumed it. The learning-loop rule this adds
([release-audit-learning-loop.md](release-audit-learning-loop.md)): **for every plugin in
your fleet, search its public tracker for issues referencing the upcoming core version,
before release day.** The checkable step:

```bash
# per plugin: does its tracker already know about this release?
gh search issues --repo <owner>/<repo> "7.2" --state open --limit 20
# for wordpress.org-hosted plugins: search the support forum for the version string
```

An open issue naming the next core version, filed by someone else, with a proposed fix, is
the cheapest finding you will ever import. Read it before you build a single fixture.

## Alignment with Trac #65920 — and what it structurally cannot cover

Adam Silverstein opened [Trac #65920](https://core.trac.wordpress.org/ticket/65920)
(2026-08-20, feature request, milestoned 7.2, backed by Jeffrey Paul): a GitHub Actions
workflow auto-testing the **top 100 wordpress.org plugins** against unreleased builds —
draft PR [WordPress/wordpress-develop#13198](https://github.com/WordPress/wordpress-develop/pull/13198).
That workflow is the right infrastructure and this lane should defer to it for what it
covers. **Silverstein himself notes it would not have caught this bug**: WP Rocket is
premium, and the directory API the workflow draws from only covers free plugins.

**It has since been run at full scale, and the numbers change what we can say about it.**
On 2026-08-23 Silverstein posted results from a 200-plugin run on his own fork: **186
passed, 1 failed, 13 skipped**, 4m32s across 8 shards. Two things in that line are worth
more than the headline:

- **It caught a real fatal, and caught it past the point most checks stop.**
  `eps-301-redirects` 2.85 installs and activates cleanly, then fatals the moment WP-CLI
  loads WordPress with the plugin active (`Call to a member function add_admin_message() on
  null`). An activation-only check reports PASS on that plugin. See
  [activation is not a boot](#activation-is-not-a-boot), below.
- **The 13 skips are a blind spot, not noise** — and the skip line turned out to be looser
  than it read. The summary reported *13 skipped (WooCommerce add-ons with an unmet
  `Requires Plugins` header)*, which sounds like one clean cause. When the fix landed
  (below), it named **four**: `woocommerce-payments`, `google-listings-and-ads`,
  `woocommerce-paypal-payments`, `woocommerce-gateway-stripe`. **What the other nine were
  skipped for is not stated anywhere in the thread.** Preserved as a conflict rather than
  resolved to a number, per [validation and proof](validation-and-proof.md).

  That gap is the *skips-beside-passes* rule proving itself twice over. The first reading
  was that "186 passed" hides 13 untested units. The second is that a **reason attached to
  a count rather than to each skip** is itself a place error hides: one plausible cause got
  written next to thirteen units and only fit four of them.

**The dependency gap was closed on 2026-08-24, in `67005f527b`** (in the PR; still
unmerged). A plugin declaring `Requires Plugins` now gets its dependencies installed and
activated before it is activated itself. Three details make it more than a convenience:

- The header is read with `get_plugin_data()`, not a grep — so the workflow applies the same
  rules core does when it decides whether a plugin's requirements are met.
- Chains are followed one level at a time, and anything already installed is left alone,
  which is what terminates a circular declaration rather than a cycle-detector.
- **The misattribution guard is the part this lane should steal.** After the dependencies
  are activated and *before* the plugin under test is, the front page and login screen are
  requested on their own, and `debug.log` is cleared at that same point. A site already
  broken there is the dependency's fault, so the plugin under test is recorded as skipped
  *against the dependency* instead of failing for someone else's bug. The results table
  gains an **"Also active"** column so a failure can be read in context.

That guard is the answer to the objection every co-installed matrix runs into, including
[the cell block above](#the-co-installed-cell-block-in-the-t1-sweep): once you stop testing
one plugin at a time, a failure has more than one candidate owner. **Baseline the
environment after the companions are active and before the subject is**, and the ambiguity
mostly goes away — you get "broken before we touched it" as a distinct, recordable state
rather than a mystery failure attributed to whatever was activated last. Cost: the job
timeout went 30 → 45 minutes, because activating something the size of WooCommerce once per
extension is not free.

A second real plugin fatal surfaced in the same re-test: **`instagram-feed` 6.12.0 fatals on
`wp_loaded` against 7.1** on a fresh database — `wp_get_image_editor( WP_Error )`, the same
trace as an earlier sighting but reached directly rather than through cron, and the previous
version of the script reports it identically. Two real fatals now, from a workflow whose
whole premise was that this class is findable at scale before release day.

Also settled by the same thread, and worth knowing before anyone proposes it as the
alternative: **Tide is effectively unsupported.** Jeff Paul, who maintains it, says it has
been "generally unsupported for years," that he has considered shutting it down, and that
the PHP Compat Checker plugin is about the only consumer of its audit data. Treat it as a
non-option unless somebody funds it.

Source: review comments on
[WordPress/wordpress-develop#13198](https://github.com/WordPress/wordpress-develop/pull/13198),
2026-08-23. The workflow is proposed for 7.2 and **not merged**; the run was on a fork with
its repository guards loosened, since manual dispatch isn't available until the workflow
exists on trunk. External report, independently reproduced by nobody here.

## Activation is not a boot — but boot it over HTTP

**This section shipped on 2026-08-23 with a receipt that was refuted on 2026-08-24. The
correction is more useful than the original claim, so both are kept.**

What was written here: `eps-301-redirects` 2.85 installs and activates cleanly, then fatals
when WP-CLI loads WordPress with it active, therefore an activation-only check is not enough.

What turned out to be true: the plugin is **healthy**. Installed by hand through wp-admin,
nothing breaks — front page 200, `wp-login.php` 200, `/wp-admin/` 302, no `debug.log` written
at all. The only thing that failed was the WP-CLI boot.

**The mechanism, and it is not WordPress's.** WP-CLI requires `wp-settings.php` from inside
`WP_CLI\Runner->load_wordpress()`. PHP executes an included file in the *including scope*, so
a plugin's file-scope assignment becomes a local of that method instead of a global.
`eps-301-redirects` does `$EPS_Redirects_Plugin = new EPS_Redirects_Plugin();` at file scope
and reads it back with `global $EPS_Redirects_Plugin;` on `init`; under WP-CLI that is null,
and the null then takes a method call. It only fires when `permalink_structure` is empty —
which is exactly what a fresh `wp core install` leaves behind, so a CI fixture hits it and a
real site almost never does.

Verified here independently, without WordPress, because the claim is pure PHP scoping:

```php
include_once 'plugin.php';                          // at global scope  → global is VISIBLE
(new Runner)->load_wordpress();                     // include inside a method → MISSING
```

### The rule that survives, in corrected form

**Activation is still not a boot** — activation runs a narrow path, often before the hooks and
globals a plugin's real code assumes. But the check has to be an **HTTP request**, not
`wp eval`. A CLI-only fatal is a *note*, not a failure: it is at least as likely to be this
scoping artifact as a real defect. Run the CLI boot **last**, after the HTTP checks, so its
fatal doesn't also poison a `debug.log` assertion — which is what core's workflow now does.

Anything that genuinely fatals on load still fails, because it fails the HTTP check first.

### What this costs the lane, honestly

The 200-plugin run's headline was *186 passed, 1 failed, 13 skipped*. The 1 failure was this,
and it was not a real one. So that run found **zero** genuine core-related plugin fatals, and
the `instagram-feed` sighting recorded above is now the only candidate — itself unverified
here. A workflow that finds nothing is still worth having; a workflow reported as finding
something it didn't is worse than one that reports nothing, which is why this correction
matters more than the original claim did.

## The co-installed cell block in the T1 sweep

The sweep matrix carries an `ecosystem` cell block ([`pilots/release-day/sweep-matrix.csv`](../pilots/release-day/sweep-matrix.csv),
entity `ecosystem`): a fixture with the top co-installed plugin pairs by real-world
prevalence, upgraded across the release boundary, asserting **no new fatals in `debug.log`**
and a front end and admin that still answer 200. Pair selection follows
[`plugin-theme-authors/co-installed-plugins.md`](../plugin-theme-authors/co-installed-plugins.md)
— category leaders (caching, SEO, forms, page builders, eCommerce) plus anything your own
support channels name.

Two honest limits, stated up front:

- **Premium plugins cannot be fetched from the directory API.** WP Rocket — the very plugin
  that motivated this lane — is premium. A tester who doesn't own a license cannot build the
  cell; the cell reads `BLOCKED(premium-license)`, never `SKIP`. Supply the zip yourself if
  you hold a license.
- Pair cells still miss triples. The block buys breadth against the *common* failure (a
  popular plugin's assumption breaking on upgrade with its usual companions active); the
  probe above is what hunts the trigger ingredient.

## A dependency's public tracker is a release-readiness input

Six weeks of notice existed for the WP Rocket fatal, in public, with a proposed patch — and
nobody testing the release consumed it. The learning-loop rule this adds
([release-audit-learning-loop.md](release-audit-learning-loop.md)): **for every plugin in
your fleet, search its public tracker for issues referencing the upcoming core version,
before release day.** The checkable step:

```bash
# per plugin: does its tracker already know about this release?
gh search issues --repo <owner>/<repo> "7.2" --state open --limit 20
# for wordpress.org-hosted plugins: search the support forum for the version string
```

An open issue naming the next core version, filed by someone else, with a proposed fix, is
the cheapest finding you will ever import. Read it before you build a single fixture.

## Alignment with Trac #65920 — and what it structurally cannot cover

Adam Silverstein opened [Trac #65920](https://core.trac.wordpress.org/ticket/65920)
(2026-08-20, feature request, milestoned 7.2, backed by Jeffrey Paul): a GitHub Actions
workflow auto-testing the **top 100 wordpress.org plugins** against unreleased builds —
draft PR [WordPress/wordpress-develop#13198](https://github.com/WordPress/wordpress-develop/pull/13198).
That workflow is the right infrastructure and this lane should defer to it for what it
covers. **Silverstein himself notes it would not have caught this bug**: WP Rocket is
premium, and the directory API the workflow draws from only covers free plugins.

**It has since been run at full scale, and the numbers change what we can say about it.**
On 2026-08-23 Silverstein posted results from a 200-plugin run on his own fork: **186
passed, 1 failed, 13 skipped**, 4m32s across 8 shards. Two things in that line are worth
more than the headline:

- **It caught a real fatal, and caught it past the point most checks stop.**
  `eps-301-redirects` 2.85 installs and activates cleanly, then fatals the moment WP-CLI
  loads WordPress with the plugin active (`Call to a member function add_admin_message() on
  null`). An activation-only check reports PASS on that plugin. See
  [activation is not a boot](#activation-is-not-a-boot), below.
- **The 13 skips are a blind spot, not noise** — and the skip line turned out to be looser
  than it read. The summary reported *13 skipped (WooCommerce add-ons with an unmet
  `Requires Plugins` header)*, which sounds like one clean cause. When the fix landed
  (below), it named **four**: `woocommerce-payments`, `google-listings-and-ads`,
  `woocommerce-paypal-payments`, `woocommerce-gateway-stripe`. **What the other nine were
  skipped for is not stated anywhere in the thread.** Preserved as a conflict rather than
  resolved to a number, per [validation and proof](validation-and-proof.md).

  That gap is the *skips-beside-passes* rule proving itself twice over. The first reading
  was that "186 passed" hides 13 untested units. The second is that a **reason attached to
  a count rather than to each skip** is itself a place error hides: one plausible cause got
  written next to thirteen units and only fit four of them.

**The dependency gap was closed on 2026-08-24, in `67005f527b`** (in the PR; still
unmerged). A plugin declaring `Requires Plugins` now gets its dependencies installed and
activated before it is activated itself. Three details make it more than a convenience:

- The header is read with `get_plugin_data()`, not a grep — so the workflow applies the same
  rules core does when it decides whether a plugin's requirements are met.
- Chains are followed one level at a time, and anything already installed is left alone,
  which is what terminates a circular declaration rather than a cycle-detector.
- **The misattribution guard is the part this lane should steal.** After the dependencies
  are activated and *before* the plugin under test is, the front page and login screen are
  requested on their own, and `debug.log` is cleared at that same point. A site already
  broken there is the dependency's fault, so the plugin under test is recorded as skipped
  *against the dependency* instead of failing for someone else's bug. The results table
  gains an **"Also active"** column so a failure can be read in context.

That guard is the answer to the objection every co-installed matrix runs into, including
[the cell block above](#the-co-installed-cell-block-in-the-t1-sweep): once you stop testing
one plugin at a time, a failure has more than one candidate owner. **Baseline the
environment after the companions are active and before the subject is**, and the ambiguity
mostly goes away — you get "broken before we touched it" as a distinct, recordable state
rather than a mystery failure attributed to whatever was activated last. Cost: the job
timeout went 30 → 45 minutes, because activating something the size of WooCommerce once per
extension is not free.

A second real plugin fatal surfaced in the same re-test: **`instagram-feed` 6.12.0 fatals on
`wp_loaded` against 7.1** on a fresh database — `wp_get_image_editor( WP_Error )`, the same
trace as an earlier sighting but reached directly rather than through cron, and the previous
version of the script reports it identically. Two real fatals now, from a workflow whose
whole premise was that this class is findable at scale before release day.

Also settled by the same thread, and worth knowing before anyone proposes it as the
alternative: **Tide is effectively unsupported.** Jeff Paul, who maintains it, says it has
been "generally unsupported for years," that he has considered shutting it down, and that
the PHP Compat Checker plugin is about the only consumer of its audit data. Treat it as a
non-option unless somebody funds it.

Source: review comments on
[WordPress/wordpress-develop#13198](https://github.com/WordPress/wordpress-develop/pull/13198),
2026-08-23. The workflow is proposed for 7.2 and **not merged**; the run was on a fork with
its repository guards loosened, since manual dispatch isn't available until the workflow
exists on trunk. External report, independently reproduced by nobody here.

## Activation is not a boot

The `eps-301-redirects` result is the cheapest lesson in this document, and it generalizes
past plugin-compatibility workflows to every cell in this repo that touches a plugin.

**Activation writes a row in `active_plugins`. It does not prove the plugin's code survives
a request.** A plugin can install and activate cleanly and still fatal on the next load,
because activation runs a narrow path — often before the hooks, globals, and other plugins
its real code assumes are there. The failing plugin called a method on `null` at load time;
nothing in the activation path went near it.

So a compatibility check that stops at "did it activate" has a PASS that means considerably
less than it looks like, and this is [law 1](release-audit-learning-loop.md) — source or
partial observation needs runtime proof — with a fresh, executed receipt. **A plugin cell is
not clean until WordPress has been loaded with the plugin active and the load produced no
fatal.** The cheap version, which is what the core workflow does:

```bash
wp plugin install <slug> --activate
wp eval 'echo "booted";'   # loads WordPress with it active — this is the test
```

It is also the same shape as the [preflight core probe](preflight-core-probe.md)'s
*two boots are two denominators*: CLI boot and an HTTP request are different tests, and
activation is a third and weakest one. Arriving at it twice from different directions in one
week is the argument for writing it down as a rule rather than a note.

The division of labor between this workflow, this lane, and a third source neither of them
covers is the table at the end of the next section.

A draft comment — supporting the dependency-pre-install proposal, asking for skips to be
reported beside passes, and offering a canary mu-plugin for the closure class — is in
[`drafts/trac-65920-comment.md`](../drafts/trac-65920-comment.md). Draft, not filed; filing
is the operator's call.

## The third source: fleets, probing an RC against their own sites

Both approaches above enumerate plugins — the workflow from the directory API, this lane from
a co-installed-prevalence list — and enumeration is exactly where the premium blind spot comes
from. A **[preflight core probe](preflight-core-probe.md)** doesn't enumerate anything. It
sideloads the new core, points it at a real site's live database and live `wp-content`, boots
it, and greps for fatals. Whatever that site runs is what gets tested, licence or no licence,
in its real co-installed combination — which is the triple this lane exists to chase.

Run `--probe-only` across a fleet against an **RC** and the output is a compatibility census
over the population core-side testing structurally cannot reach. One agency with 300 sites has
a denominator; the fatal it finds on 7.2-RC1 is worth more to the release than any number of
clean-install cells, and it costs one scripted pass. The technique, its invariants, and its
limits are documented from Austin Ginder's CaptainCore script in
[preflight-core-probe.md](preflight-core-probe.md); the operator-facing version is
[`fleet-operators/README.md` §4](../fleet-operators/README.md#4-probe-before-you-apply).

The division of labor, across all three:

| | Automated workflow (#65920) | This lane | Fleet preflight probe |
|---|---|---|---|
| Free directory plugins, singly | covered, at scale, every build | don't duplicate | incidental |
| Premium plugins | structurally blind — no API source | manual cells, license required | covered, on any site that owns one |
| Co-installed pairs and triples | not in scope | pair cells + the closure probe | covered by construction, on real sites |
| Plugins gated behind `Requires Plugins` | **covered as of `67005f527b`** — dependencies are installed and activated first, and four named WooCommerce extensions moved from SKIPPED to passing. Unmerged | pair cells reach the common ones | covered — on a real site the dependency is already installed |
| Bespoke client code | not in scope | not in scope | covered |
| Isolating *which* plugin | n/a — one at a time | the point of the cells | **not covered** — a probe says "this site fatals," not why |
| Tracker triage | not in scope | the checkable step above | not in scope |

That last row is the honest boundary. A probe is a **detector, not a diagnosis**: it converts
"is my fleet ready" into a number, and then someone still has to bisect the failing site to
name the plugin. This lane's cells and the closure probe are what do that naming. Neither
replaces the other, and a fleet reading fatals it never diagnoses has bought monitoring, not
understanding.
