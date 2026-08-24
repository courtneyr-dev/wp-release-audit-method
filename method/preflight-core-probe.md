---
title: "Preflight core probe — boot the new core against the live site before you let it in"
type: method
status: active
created: '2026-08-23'
updated: '2026-08-23'
tags:
  - wordpress
  - release-audit
  - fleet
  - rollback
  - upgrade
related:
  - '[ecosystem-compatibility-lane](ecosystem-compatibility-lane.md)'
  - '[rollback](rollback.md)'
  - '[../fleet-operators/README](../fleet-operators/README.md)'
  - '[standing-environment](standing-environment.md)'
---

# Preflight core probe

> **Source and credit.** The technique on this page is documented from
> [`lib/remote-scripts/update-core`](https://github.com/CaptainCore/captaincore/blob/master/lib/remote-scripts/update-core)
> in [CaptainCore](https://github.com/CaptainCore/captaincore) by **Austin Ginder** — the
> CLI application behind [captaincore.io](https://captaincore.io) and
> [Anchor Hosting](https://anchor.host/). MIT licensed, © 2018–present Austin Ginder;
> first committed 2026-08-23. This page is a method write-up with short adapted excerpts,
> not a copy of the script. Read the original before running anything derived from it.
>
> Ginder is the same operator whose fleet numbers ground
> [`fleet-operators/README.md` §1](../fleet-operators/README.md#1-pre-release-inventory--the-denominator-comes-first)
> — *332 production sites on WP Rocket, 124 fataled, 37%* on 7.1 release day. This is what
> he built four days later. That provenance is the reason it's here: it is a fix shaped by
> the specific way the release-day failure actually arrived.

[`fleet-operators/README.md` §8](../fleet-operators/README.md#8-the-unsolved-problem-named)
names a hole this repo could not close: **throwaway staging has no clean path back to live
for database changes.** Clone → test → discard works until the update writes to the
database; then staging has diverged from a live site that kept taking orders, and there is
no general merge. Every method that says "test on staging first" inherits that hole.

This technique goes around it rather than through it. Don't clone the data. **Sideload the
new core into a temp directory, point it at the live `wp-config.php`, the live database, and
the live `wp-content`, boot it, and look for fatals — then decide whether to apply.** The
site being tested *is* the site, so there is nothing to promote backward. A failed probe
aborts before a single live core file changes.

## The shape of it

Five moves. The order is the whole design — each step exists to make a later step readable.

1. **Sideload.** `wp core download --path="$PREVIEW" --version="$version" --skip-content
   --force` into `$HOME/tmp/…`, not the web root. (`$HOME/tmp` rather than `$HOME/private`
   because Kinsta's `open_basedir` won't let PHP-FPM `require` out of the latter — a host
   detail, but the kind that decides where this can run at all.)

2. **Write a preview `wp-config.php` that borrows everything but the core files.** Copy the
   live config, strip its trailing `require ABSPATH . 'wp-settings.php'`, save it aside,
   and wrap it:

   ```php
   define( 'WP_CONTENT_DIR', '/live/root/wp-content' );  // the LIVE content dir
   define( 'WP_CONTENT_URL', 'https://example.com/wp-content' );
   define( 'WP_CACHE', false );
   define( 'DONOTCACHEPAGE', true );
   define( 'CORE_PREVIEW', true );
   require __DIR__ . '/wp-config.php.live.php';          // live DB credentials, salts, constants
   require ABSPATH . 'wp-settings.php';                  // …but the NEW core's wp-settings
   ```

   Existing `WP_CACHE` defines in the copied config are stripped by regex, not just
   overridden — otherwise the preview serves a cached HTML page from the *old* core and the
   probe reports a green that means nothing. This is the probe-side version of runbook step
   7 ("clear CDN and object caches first"): a check against a stale cache is not a check.

3. **Probe on the CLI.** Two passes, because they answer different questions:
   - `wp --path="$PREVIEW" eval` echoing `$wp_version`, `get_template()`, and the active
     plugin count — proves the new core *loads* with the live plugin and theme set.
   - `wp --path="$PREVIEW" eval-file probe-render.php /` — fakes `$_SERVER`, suppresses
     canonical redirects, runs `$wp->main('')` plus `template-loader.php`, and reports
     `bytes`, `is_404`, `<title>`, and `fatal_in_html`. A shutdown handler catches
     `E_ERROR`/`E_PARSE`/`E_COMPILE_ERROR`; a `try`/`catch ( Throwable )` catches the rest.
     Repeated against the first published page, so the probe isn't only ever measuring the
     home template.

4. **Probe over real HTTP.** A token-gated bootstrap file, written into the live web root,
   that `require`s the *preview's* `wp-blog-header.php`:

   ```php
   $given = $_SERVER['HTTP_X_CORE_PREVIEW'] ?? '';
   if ( ! is_string( $given ) || $given === '' || ! hash_equals( $expected, $given ) ) {
       header( 'HTTP/1.1 404 Not Found' ); echo 'not found'; exit;
   }
   header( 'X-Robots-Tag: noindex, nofollow' );
   header( 'X-Core-Preview-Version: ' . $wp_version );
   require '$PREVIEW/wp-blog-header.php';   // the sideloaded tree, interpolated at write time
   ```

   Reached through the host's on-server loopback — `curl -ksS -H "Host: <site>"
   https://localhost/…` — so the request traverses the real PHP-FPM stack, not WP-CLI's.
   The response is then checked three ways: body grepped for a fatal, status in
   `200|301|302`, and `X-Core-Preview-Version` equal to the target. That third check is the
   one that stops you from cheerfully passing a probe that silently booted the old core.

5. **Assert the probe changed nothing, then decide.** `db_version` is read before and after;
   a move aborts. Stable targets apply automatically after a clean probe; anything matching
   `nightly|alpha|beta|RC` requires an explicit `--apply`. After applying, HTTP is checked
   again — and a non-2xx/3xx **restores the previous core automatically**.

## The four ideas worth stealing even if you never run the script

**Two boots are two denominators.** `wp eval` and an HTTP request are not the same test.
CLI boot misses everything conditioned on the web-request path — `SERVER_SOFTWARE`,
mu-plugins that early-return on `WP_CLI`, page caches, request-scoped hooks. Both passes are
in the script because either alone is a smaller denominator than it looks, which is
[law 3](release-audit-learning-loop.md) wearing operations clothing.

**Grep the body, not the status code.** The probe fails on
`Fatal error|Parse error|Uncaught ` found *in the response*, independent of status. This is
[`fleet-operators/README.md` §6](../fleet-operators/README.md#6-monitor-for-a-known-string-not-a-status-code)
arrived at from the other direction, by someone who watched it happen: a fataled WordPress
site frequently serves its "critical error" page as an HTTP 200. Keyword checking catches
both the 200-shaped and the 500-shaped failure; status checking catches one.

**Move aside before you copy over.** The restore path never deletes live core first:

```
mv  live/wp-admin  live/wp-admin.cc-restore-$$     # original is still on disk
cp -a backup/wp-admin live/wp-admin                # if this fails…
mv  live/wp-admin.cc-restore-$$ live/wp-admin      # …put the original back
rm -rf live/wp-admin.cc-restore-$$                 # only after the copy succeeded
```

A restore that begins with `rm -rf` on live core has a window where a failed copy leaves the
site with no core at all. This ordering has none. See
[rollback](rollback.md#core-rollback-mechanics-for-when-its-genuinely-core--unexercised).

**Refuse to delete anything you didn't create.** Every removal in the script is guarded —
paths must match `$HOME/tmp/<exact-name>` with no `..`, must not be `/`, `$HOME`, or the
live root, must not be symlinks, and the injected boot file must still contain its
`X-Core-Preview-Boot` marker before it's removed. A cleanup routine on a production web root
is a destructive tool wearing a helpful name.

## What it would have caught

The WP Rocket outage documented in
[the ecosystem compatibility lane](ecosystem-compatibility-lane.md#the-worked-incident--wp-rocket-on-71-release-day),
on every affected site, before any core file changed.

That failure needed three parties — the 7.1 hook-key change, WP Rocket's `substr()` on a
hook key under `strict_types`, and *a third plugin registering a closure* on the right hook.
No single-plugin compatibility matrix reaches it, because the pair is green and the triple
is down. A preflight probe doesn't need to reach it by construction: it boots the new core
against **the exact plugin set that site actually runs**, closures and all, and the fatal
fires on `init` — the loudest possible place for it to land in a probe.

This is the piece [Trac #65920](https://core.trac.wordpress.org/ticket/65920)'s automated
top-100-plugins workflow structurally cannot cover — and its first full run, 2026-08-23,
made the shape of that gap concrete rather than theoretical. **Two blind spots, both from
the same root cause: the workflow has to enumerate plugins, and a probe doesn't.**

- **Premium plugins.** The workflow draws from the wordpress.org directory API, so they are
  invisible to it. Adam Silverstein says so himself, and WP Rocket is premium.
- **Plugins gated behind a dependency.** 13 of the 200 in that run were skipped for an unmet
  `Requires Plugins` header, all of them WooCommerce add-ons, because the workflow installs
  one plugin at a time and a dependent plugin has nothing to run against. Pre-installing
  declared dependencies is a proposed follow-up; until it lands, the skipped set correlates
  with a market segment rather than being random.

A preflight probe has neither, because it never enumerates anything. It boots whatever is
installed — premium, dependent, or written by the client's last agency — in whatever
combination the site actually runs. See
[the ecosystem lane](ecosystem-compatibility-lane.md#alignment-with-trac-65920--and-what-it-structurally-cannot-cover)
for the full numbers.

**Which suggests the fleet-scale move, and it belongs to this repo's testing lane, not just
its operations lane:** run the probe in `--probe-only` mode across a fleet against an **RC**,
before release day. The result is a real-world compatibility census over the exact
population the directory API can't see — premium plugins, paid page builders, bespoke client
code, in their real co-installed combinations. One agency with 300 sites produces a
denominator no core-side matrix can. That reading is worth more to the release than any
number of clean-install cells, and it is the cheapest RC feedback a fleet operator can
generate.

## What it does not do

Named plainly, because a probe you trust past its edges is worse than no probe:

- **`db_version` unchanged is not "the database was untouched."** It proves core schema
  migration didn't run. It proves nothing about what plugins wrote while rendering the
  probe pages — transients, option updates, hit counters, a cron event that fired on a real
  request. The invariant is narrow and correct; the sentence "the probe is read-only" is
  not.
- **Front-end only.** `/` and the first published page. `wp-admin`, `admin-ajax`, REST,
  cron, logged-in states, POST, and checkout are all outside it — and the 7.1 fatal that
  motivated it happened to kill all of them, so the front-end signal was sufficient *that
  time*. A fatal that only fires in an admin screen or on a `POST` passes this probe.
  Runbook steps 12 and 15 in the fleet lane still have to be executed by a human.
- **It writes an executable file into the live web root.** Token-gated with `hash_equals`,
  randomly named, `noindex`, and removed by an `EXIT` trap — good hygiene, and still a real
  file in a public directory during the run. A `SIGKILL`, a hard reboot, or an OOM kill
  skips the trap and the file survives. If you adapt this, sweep for
  `core-preview-boot-*.php` in the web root as a standing check, not a hope.
- **Host-shaped.** The on-server loopback (`https://localhost` with a `Host:` header) is a
  Kinsta and Rocket.net behavior. The `$HOME/tmp` placement is an `open_basedir` workaround.
  The cache purges call `wp kinsta cache purge`, `wp cdn purge`, and `rocket_clean_domain()`.
  Every one of those is a per-host adaptation point, and the loopback one is load-bearing —
  without it the HTTP half of the probe doesn't exist.
- **The preview inherits the live `wp-content`, which means it inherits live mu-plugins,
  drop-ins, and `object-cache.php`.** That is the point — but a drop-in incompatible with the
  new core is being loaded against a production object cache while you probe.

## Status in this repo: UNEXERCISED

**Not one line of this has been executed by this project.** It is documented from source,
not from a run. Per [rollback](rollback.md)'s standard — *a recovery path you have never run
is a hypothesis about your worst day* — this page is a hypothesis about someone else's good
idea until a run is recorded against it.

What would move it to EXERCISED, roughly in order of what each buys:

1. Run `--probe-only` against a disposable fixture seeded with the WP Rocket triple from
   [the ecosystem lane](ecosystem-compatibility-lane.md) — a positive control. The probe must
   **fail**. A probe that has never failed on a known-bad input is not a detector, it's a
   formality.
2. Run it against the same fixture without the closure-registering third plugin — the
   negative control. It must pass. Both controls in one run, per
   [validation and proof](validation-and-proof.md).
3. Assert the abort is genuinely non-destructive: checksum live `wp-admin`, `wp-includes`,
   and root PHP files before and after a failed probe, and diff. The claim "failed probes
   abort before any live core files change" is checkable, and unchecked it is marketing.
4. Confirm the `db_version` invariant fires — force a probe with a target whose
   `wp_db_version` differs and confirm the mismatch aborts rather than migrating.
5. Only then, the apply path with its auto-restore, on a fixture you are happy to lose.

Steps 1–3 are a well-shaped afternoon on a DDEV fixture. Anyone with a spare evening and the
[standing environment](standing-environment.md) can convert this page from documentation into
a result — and a `BLOCKED` or a surprising failure is as publishable as a pass.

## Related

[Fleet operators lane](../fleet-operators/README.md) ·
[Ecosystem compatibility lane](ecosystem-compatibility-lane.md) ·
[Rollback](rollback.md) ·
[Release-audit learning loop](release-audit-learning-loop.md) ·
[Validation and proof](validation-and-proof.md) ·
[CaptainCore `update-core`](https://github.com/CaptainCore/captaincore/blob/master/lib/remote-scripts/update-core) (Austin Ginder, MIT)
