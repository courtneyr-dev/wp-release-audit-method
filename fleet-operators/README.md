# Fleet operators and site owners

*The lane for the person deciding whether to let a release onto 300 client sites.*

Everything else in this repo is written from the position of a core tester or a plugin
author. This lane is for the population that actually got hurt on 7.1 release day: agencies,
freelancers, and hosts who run fleets, whose sites auto-updated at 01:55 UTC and fataled
three seconds later. The question here isn't "is the release correct" — it's **"is my fleet
ready to receive it, and how would I know if it wasn't."**

The deliverable is the [fleet release-readiness brief](../templates/fleet-release-readiness-brief.md).
The SRE-grade version of the same document — posture, blast radius, gates — is
[`wordpress-audit-handoff` Mode B](../skills/wordpress-audit-handoff/SKILL.md#mode-b--sre-fleet-brief);
this page is the method behind both.

## 1. Pre-release inventory — the denominator comes first

Which plugins does the fleet run, at what versions, on how many sites? Without that table,
"is 7.1 safe for us" has no answer — it isn't even a question yet, because there's no
denominator. The post-mortem that made the WP Rocket outage legible worked precisely because
its author could say *332 sites on WP Rocket, 124 fataled, 37%* (Austin Ginder, Anchor
Hosting). No inventory, no denominator, no numbers — which is
[lie #3](../README.md#five-ways-your-test-can-lie-to-you) wearing operations clothing.

```bash
# one row per site, mergeable into the fleet table
wp plugin list --format=csv --fields=name,version,status
```

Inventory turns a release into a bounded question: *these 23 plugins, at these versions,
on these counts of sites.* It's also what makes the next step mechanical.

## 2. Dependency-tracker triage

For every plugin in the inventory, search its public tracker for open issues naming the
upcoming core version — before release day. The WP Rocket fatal sat on the vendor's own
tracker for 44 days with a proposed one-line fix before it took fleets down. The method and
the checkable step live in
[the ecosystem lane](../method/ecosystem-compatibility-lane.md#a-dependencys-public-tracker-is-a-release-readiness-input).

## 3. The auto-update decision — a real trade-off this repo has not resolved

The sources in this project's corpus **actively disagree**, and pretending otherwise would
be inventing a finding. The positions:

- **Mike Miler** (agency practice, WCUS 2026): disable plugin and theme auto-updates
  entirely; auto-update **only** WordPress minor core releases; deliberately hold major core
  updates a few days.
- **Jonathan Desrosiers** (supply chain, WCUS 2026): *deliberate delay* is the protective
  mechanism — the npm `min-release-age` / Dependabot-cooldown idea applied to updates
  generally. **He names no day count.**
- **Robert Abela** (Melapress): only ~20% of plugins patch within 24 hours and ~40% within
  1–2 weeks — so a delay window is expensive when the update you're delaying is a security
  fix for a public CVE.
- **Matt Dorman** (WCUS 2026) leaves it explicitly unresolved.

The structure of the trade-off: **delay protects against supply-chain compromise and
day-one breakage (both WP Rocket and the TanStack-class worms argue for it), and delay
hurts against known CVEs (public exploit, unpatched fleet, every day is exposure).** The
right number depends on inputs only you have — how fast you can detect breakage (see
monitoring, below), how fast you can roll a fix across the fleet, what fraction of your
plugins ship security releases versus feature releases, and whether a WAF buys you virtual
patching during the window.

**This repo has not measured a threshold and does not recommend one.** If you pick three
days, you picked it; write it down with the inputs above so future-you knows what it was
based on. What the 7.1 incident does establish: whatever your window is, core-major day
plus untriaged plugin trackers plus auto-update is the known-bad combination.

**A probe changes the shape of this trade-off, and it is the reason §4 exists.** Every
position above is arguing about *how long to wait*, because waiting was the only instrument
anyone had. If you can ask a specific site "does the new core fatal on you," the question
stops being how many days of exposure to buy and becomes how fast you can get an answer per
site. Delay is a proxy for evidence. §4 is the evidence.

## 4. Probe before you apply

**Credit: this section documents [Austin Ginder](https://anchor.host/)'s `update-core`
remote script in [CaptainCore](https://github.com/CaptainCore/captaincore) (MIT) —
[`lib/remote-scripts/update-core`](https://github.com/CaptainCore/captaincore/blob/master/lib/remote-scripts/update-core),
first committed 2026-08-23. Same operator as the 332/124 number in §1: this is what he built
four days after the outage.** The full write-up, with the invariants and the honest limits,
is [`method/preflight-core-probe.md`](../method/preflight-core-probe.md).

The move: **don't clone the site, sideload the core.** Download the new WordPress into a
temp directory, write a preview `wp-config.php` that points at the *live* database and the
*live* `wp-content`, boot it, render the front page over both WP-CLI and real HTTP, and grep
for fatals. Clean probe → apply. Failed probe → abort, with no live core file touched.

```bash
# on the site, from the WordPress root
update-core --version=7.2-RC1 --probe-only     # answer only, nothing applied
update-core --version=latest                   # probe, then apply if clean
```

Five things make it worth adopting even if you write your own:

- **It answers §8.** Testing against a clone diverges the moment the update writes to the
  database. This never clones, so there is nothing to promote backward — the site being
  tested *is* the site.
- **It catches the failure class §2 is about.** The probe boots the new core against the
  exact plugin set that site runs, in its real co-installed combination. The WP Rocket fatal
  needed a *third* plugin registering a closure; no pairwise matrix reaches that, and a probe
  doesn't have to — the fatal fires on `init` and the probe sees it.
- **It has no enumeration blind spots.** The top-100-plugins workflow proposed in
  [Trac #65920](https://core.trac.wordpress.org/ticket/65920) has two, both visible in its
  first full run (2026-08-23, 186 passed / 1 failed / 13 skipped): it draws from the
  wordpress.org directory API, so it cannot see WP Rocket at all, and it installed one plugin
  at a time, so plugins declaring `Requires Plugins` had nothing to run against. The second
  of those was fixed in the PR on 2026-08-24 and four named WooCommerce extensions now pass;
  the premium one is structural. A probe never enumerates plugins, so it has neither — it
  boots whatever is installed.
- **It tests past activation, which is where that run found its one real fatal.**
  `eps-301-redirects` 2.85 installs and activates cleanly, then fatals when WordPress is
  actually loaded with it active. If your own update checks stop at "the plugin is active,"
  they would have passed it too.
- **It reads the body, not the status code** — the same rule as §6, arrived at
  independently.

**And the thing a fleet can do that nobody else can.** Run `--probe-only` across the whole
fleet against an **RC**, before release day. That produces a compatibility census over the
population core-side testing structurally cannot reach: premium plugins, paid page builders,
bespoke client code, in the combinations real sites actually run. Three hundred sites is a
denominator. Report the failures to the plugin vendors and to
[Make/Test](https://make.wordpress.org/test/) — an RC-stage report naming a specific fatal in
a specific premium plugin is the single most valuable thing a fleet operator can hand the
release, and it costs one scripted pass.

> [!WARNING]
> **The probe half is exercised on a fixture. Ginder's script itself is not, and it runs
> against production.** On 2026-08-24 this repo ran its own CLI-only adaptation against a
> disposable DDEV fixture and both controls passed — the seeded fatal was caught, a clean
> fixture came back clean, and an aborted probe left every core file byte-identical
> ([the run](../method/preflight-core-probe.md#what-ran-2026-08-24)). That is **not** the same
> as having exercised the original, which additionally probes over HTTP, writes a temporary
> executable file into the live web root, applies the update, and restores on failure. None
> of that has been run here.
>
> Read the original before you point any derivative at a client site, and back up first
> regardless — runbook step 1 below is not optional because you have a probe.

## 5. The update-day runbook

The best-documented sequence in this project's corpus is Mike Miler's ("The Update Day,"
WCUS 2026 — disclosure: the visual-regression tool he recommends, Web Change Detector, is
his own product; the ordering logic stands independent of the tool). The order matters more
than the list — several steps exist to make a *later* step readable:

1. **Back up first** — it takes time; start it before anything else needs you.
2. **Capture baselines before touching anything**: visual-regression shots *and the browser
   console log*. The console baseline is what makes step 15 a diff instead of a guess.
3. **Record current versions** of core, plugins, themes — the rollback reference.
4. **Pause uptime monitoring** — or the update window becomes an alert storm someone learns
   to ignore.
5. **Check the PHP version before updating** — a core release can move the floor.
6. Update all. **Re-check shortly after**: translation files lag the code packages, so a
   just-updated site can be missing strings that arrive minutes later.
7. Post-update, **clear CDN and object caches first** — every check after this step is
   meaningless against a stale cache.
8. **Turn PHP error logging on *before* re-enabling uptime monitoring** — the monitor's
   re-triggered visit becomes the first traffic the now-active logs capture. Ordering these
   two the other way throws away the single most diagnostic request.
9. **Verify no plugin was deactivated or deleted** by the update.
10. **Flush permalinks** for plugins with public endpoints — rewrite rules regenerate on
    *activation*, not update, so an updated plugin's new routes can 404 until you do.
11. **Test mobile as its own explicit step** — not "the site works," which quietly means
    "the desktop site works."
12. **Manually exercise the contact form and the checkout**, on desktop and mobile both.
    These are the two flows whose silent failure costs real money (see the taxonomy below).
13. **Diff the console log against the baseline** from step 2.
14. **Review PHP error logs, then disable and delete them** — server error logs can be
    publicly reachable, and a log you leave on becomes next month's information disclosure.
15. **Visit the Action Scheduler screen manually** — there is no built-in notification, and
    stalled jobs silently break subscription renewals for weeks.
16. **Check Site Health** — discounting its disk-space figure on shared hosting, which
    reads the whole server.

## 6. Monitor for a known string, not a status code

Configure uptime monitoring to check for a **known string** — an `<h1>`, a footer line —
not just an HTTP status. A fataled WordPress site frequently serves its "There has been a
critical error" page, and depending on where the fatal lands that page can come back as an
HTTP 200 (Miler's practice rests on exactly this). It isn't universal — on this repo's own
disposable fixture, a front-end `init` fatal returned 500 — but that cuts only one way:
**keyword monitoring catches both the 200-shaped and 500-shaped failures; status-code
monitoring catches only the second.** A keyword monitor would have caught the WP Rocket
outage automatically, on every affected site, at update time.

## 7. The three-part failure taxonomy

Structure the post-update check — and the brief — around how failures announce themselves:

| Class | Examples | How it's caught |
|---|---|---|
| **Fatal / obvious** | Fatals, WSOD, gateway timeouts, redirect loops | Keyword monitoring, within minutes |
| **Visible but subtle** | Stray shortcodes from a deactivated plugin, CSS and font regressions | Visual regression against the baseline, human review |
| **Quiet / invisible** | A contact form that shows success and silently stops sending; invisible elements covering clickable buttons; silent 404s on plugin endpoints; subscriptions failing to renew | Only manual exercise of the flows (runbook steps 12 and 15) |

The third column is why the runbook has manual steps that automation never absorbs. The
quiet class is where **week-long undetected failures** live — nothing alerts, the site
"works," and the damage is a month of lost form submissions discovered by an angry client.

## 8. The unsolved problem, named

**Throwaway staging has no clean path back to live for database changes.** Clone → test →
discard works until the update writes to the database (migrations, option changes,
plugin-updater side effects); then the staging database has diverged from live, which kept
receiving orders and comments, and there is no general merge. Miler abandoned the
clone-test-discard approach over exactly this. Nobody in this project's corpus resolves it,
and any method that says "test on staging first" inherits the hole — usually silently.
This repo names it instead: staging validates *code* against a copy of your data;
promoting *data* backward from staging is unsolved here. Budget your update-day plan
accordingly (test on staging, then re-run the update on live with the runbook, rather than
promoting staging to live).

**§4 goes around this rather than solving it, and the distinction matters.** A preflight
probe never copies the database, so it never diverges — but that is a *different* test, not
a better one. It answers "does the new core fatal against this site's real code and data,"
which is the question that took fleets down on 7.1 day. It does not answer "did the update
change anything I care about," because it deliberately applies nothing and asserts only that
`db_version` held. Data-forward promotion from a staging clone remains unsolved here. What
changed is that the most expensive question no longer requires the clone.

## 9. Distributed core test participation — public evidence, scoped honestly

WordPress runs a program most fleet decisions never consult: hosts execute core's own
PHPUnit suite on their real infrastructure ([WordPress/phpunit-test-runner](https://github.com/WordPress/phpunit-test-runner))
and publish results per SVN revision ([WordPress/phpunit-test-reporter](https://github.com/WordPress/phpunit-test-reporter))
at [Host Test Results](https://make.wordpress.org/hosting/test-results/). For the person
choosing a host — or the host's own SRE writing a readiness brief — that page is public,
current, per-revision evidence of whether the infrastructure under your sites is exercised
against WordPress before release day. [Getting Started](https://make.wordpress.org/hosting/test-results-getting-started/)
is how a host joins.

This repo reads that evidence with one collector:

```bash
# a customer or consultant auditing the one tier they're on
python3 scripts/hosting-test-participation.py --host "Example Hosting" \
  --reporter examplebot --revision 63366 --format markdown --evidence "$WP_AUDIT_ROOT/participation"

# a host employee, with the canonical fleet-variant inventory
python3 scripts/hosting-test-participation.py --host "Example Hosting" \
  --variants fleet-variants.csv --revision 63366 --format markdown

python3 scripts/hosting-test-participation.py --find "example"   # candidate discovery only
python3 scripts/hosting-test-participation.py --control          # offline self-test
```

It is read-only by construction: it speaks to the core `wp/v2` REST surface the live
deployment already exposes publicly (verified 2026-08-27), never the authenticated
submission endpoint, and it preserves every raw response with URL, retrieval time, and
content hash in the evidence directory, with an exact replay command.

**The two operator positions get different ceilings, on purpose.**

- **A host employee** supplies the canonical fleet-variant inventory — every materially
  distinct product or tier (shared basic, managed WordPress, VPS…) — and the collector
  shows the denominator: variants declared, variants with exact-target evidence, with
  current-but-not-target evidence, with host-only evidence, with no public match, and
  blocked or ambiguous. A fleet variant is a hosting product, **not** the WordPress build
  under test; the two axes stay separate everywhere.
- **A customer, agency, or consultant** auditing one hosted server scopes the conclusion
  to the tier they are actually on plus host-level public evidence. The rest of the host's
  fleet is outside their evidence, and the output says so rather than letting a
  single-tier result imply fleet coverage.

**What the public data can and cannot attribute.** A result carries the reporter account,
the SVN revision (the parent post `rNNNNN`, linked to the changeset), PHP version,
database string, and a Passed/Failed/Errored status. It carries **no environment label**:
the reporter accepts an optional `env['label']` (`src/class-restapi.php:223` at
`fa1fa7b0`), the stock runner never sends one (`get_env_details()` in `functions.php`
produces no `label` key at `64e9da98`), and the label meta is not exposed on the
structured read surface even when present. So the only defensible public mapping from
results to a hosting product is **a separate reporter account per product** — which is
also the ask in [the participation request message](../templates/participation-request-messages.md).
One account mapped to several declared variants caps at `VERIFIED_CURRENT_HOST_ONLY`;
the collector refuses to promote it.

**Freshness is the dashboard's own rule.** A reporter is active iff it has a report on
one of the **25 most-recent revisions** (`src/class-display.php:227` at `fa1fa7b0`); the
public page renders everyone else under *"Registered, but no reports in >25 Revisions."*
The collector's `--window` defaults to the same 25 and measures the same way.

**Target mapping is where honest audits go to die, so it's explicit.** Reporters test
develop-SVN revisions — overwhelmingly trunk. A release package (say, 7.2-RC1) is built
from a branch; a same-week trunk revision is *adjacent* evidence, not the RC. The
collector takes the target as `--revision N` and matches exactly; given only a version
name, it records `INCONCLUSIVE(target-mapping)` instead of inventing coverage. Each
revision post's title is the commit message, so you can verify what a revision actually
was before treating a numeric match as meaningful.

**Six ways to fool yourself with this page**, all refused by the classification model:

1. **Absence of evidence** — `NO_PUBLIC_MATCH` means no defensible public match at
   retrieval time, not that the host doesn't test privately or report under another name.
2. **Coverage generalization** — one reporter result covers the infrastructure that ran
   it, not every tier the host sells.
3. **Outcome conflation** — participating is not passing. Participation status and test
   outcome (`PASSED`/`FAILED`/`ERRORED`/`NO_RESULT`/`INCONCLUSIVE`) are separate fields,
   and a verified reporter with a failing run is a *finding*, not a checkmark.
4. **Test-scope conflation** — a passing core PHPUnit run proves core's suite passed on
   that stack. It is not plugin compatibility, not upgrade safety, not browser behavior,
   and not a substitute for the [preflight probe](#4-probe-before-you-apply), the upgrade
   ladder, or monitoring.
5. **Identity confirmation bias** — a bot named like your host is a *candidate*
   (`--find` lists them as `AMBIGUOUS_MATCH`), never an automatic match. Domains, reverse
   DNS, and control-panel branding suggest; only the operator's confirmation attributes.
6. **Stale-evidence bias** — historical participation (`STALE_REGISTRATION`) establishes
   that the host once ran the suite, nothing about the release at hand.

If the answer is "not participating" or "stale," that is itself an actionable output:
[`templates/participation-request-messages.md`](../templates/participation-request-messages.md)
carries the message to send. Upstream facts above are pinned to
phpunit-test-reporter `fa1fa7b0` (GPL-3.0 — read as an external system; nothing adapted
into this GPL-2.0 repo) and phpunit-test-runner `64e9da98` (GPL-2.0-or-later), both
watched for drift in [`sources/upstream-watch.csv`](../sources/upstream-watch.csv).

## Related

[Preflight core probe](../method/preflight-core-probe.md) ·
[Fleet release-readiness brief template](../templates/fleet-release-readiness-brief.md) ·
[Participation request messages](../templates/participation-request-messages.md) ·
[`wordpress-audit-handoff` Mode B](../skills/wordpress-audit-handoff/SKILL.md#mode-b--sre-fleet-brief) ·
[Ecosystem compatibility lane](../method/ecosystem-compatibility-lane.md) ·
[Rollback](../method/rollback.md) ·
[Security releases and backports](../data/security-releases.csv)
