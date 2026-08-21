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

## 4. The update-day runbook

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

## 5. Monitor for a known string, not a status code

Configure uptime monitoring to check for a **known string** — an `<h1>`, a footer line —
not just an HTTP status. A fataled WordPress site frequently serves its "There has been a
critical error" page, and depending on where the fatal lands that page can come back as an
HTTP 200 (Miler's practice rests on exactly this). It isn't universal — on this repo's own
disposable fixture, a front-end `init` fatal returned 500 — but that cuts only one way:
**keyword monitoring catches both the 200-shaped and 500-shaped failures; status-code
monitoring catches only the second.** A keyword monitor would have caught the WP Rocket
outage automatically, on every affected site, at update time.

## 6. The three-part failure taxonomy

Structure the post-update check — and the brief — around how failures announce themselves:

| Class | Examples | How it's caught |
|---|---|---|
| **Fatal / obvious** | Fatals, WSOD, gateway timeouts, redirect loops | Keyword monitoring, within minutes |
| **Visible but subtle** | Stray shortcodes from a deactivated plugin, CSS and font regressions | Visual regression against the baseline, human review |
| **Quiet / invisible** | A contact form that shows success and silently stops sending; invisible elements covering clickable buttons; silent 404s on plugin endpoints; subscriptions failing to renew | Only manual exercise of the flows (runbook steps 12 and 15) |

The third column is why the runbook has manual steps that automation never absorbs. The
quiet class is where **week-long undetected failures** live — nothing alerts, the site
"works," and the damage is a month of lost form submissions discovered by an angry client.

## 7. The unsolved problem, named

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

## Related

[Fleet release-readiness brief template](../templates/fleet-release-readiness-brief.md) ·
[`wordpress-audit-handoff` Mode B](../skills/wordpress-audit-handoff/SKILL.md#mode-b--sre-fleet-brief) ·
[Ecosystem compatibility lane](../method/ecosystem-compatibility-lane.md) ·
[Rollback](../method/rollback.md) ·
[Security releases and backports](../data/security-releases.csv)
