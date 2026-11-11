# Testing WordPress 7.2 on a hosting fleet

*For DevRel and SRE teams at hosts and agencies who want to test 7.2 before it reaches their customers.*

WordPress 7.2 ships on December 8, 2026 (RC1 November 17). This page lists what changed in 7.2 that behaves differently on a hosting platform than on a laptop, how to test each change with this repository, and what one host's pre-release testing on 7.2-beta4 and 7.2-beta5 already found (updated November 10, 2026, for Beta 5). Every claim links to a public WordPress source. Run what applies to your platform, and share what you find in the places listed at the end.

## Contents

1. [Start here: the method in one afternoon](#start-here-the-method-in-one-afternoon)
2. [Changes in 7.2 that need a hosting test](#changes-in-72-that-need-a-hosting-test)
3. [Edge and page-cache tests](#edge-and-page-cache-tests)
4. [Performance](#performance)
5. [Security](#security)
6. [Keep up with replies to what you file](#keep-up-with-replies-to-what-you-file)
7. [Not covered yet: where help is most useful](#not-covered-yet-where-help-is-most-useful)
8. [Where to share results](#where-to-share-results)

## Start here: the method in one afternoon

Clone the repository, then work through these in order. Each step names the page that explains it.

1. **Pin the build you're testing.** `scripts/rc_build_identity.sh 7.2 RC1` records the package hash and `$wp_db_version` from WordPress.org's own feeds. A result is tied to a named build or it isn't a result. Package drops land at 15:00 UTC; trigger on the package URL, not the clock.
2. **Triage the package.** `scripts/fast-triage.sh wordpress-7.2-RC1.zip wordpress-7.2-beta5.zip` lists what changed between two drops before you run anything.
3. **Count your fleet first.** Which PHP versions, database engines, object caches, multisite modes and pre-installed plugins do you run, on how many sites? The [fleet operators page](README.md) explains why the denominator comes first, and `scripts/assert_multisite_denominator.sh` asserts it on a network.
4. **Run the release-day sweep.** The [release-day sweep playbook](../playbooks/release-day-sweep-playbook.md) is the CRUD sweep, the upgrade ladder and the execution rules: expected result written before each check, a positive and a negative control per batch, exit codes captured before any filter.
5. **Check the security backports.** `scripts/security_fix_presence.sh <target_zip> --all` confirms the fixes shipped in 7.1.x are still present in the 7.2 package. The [security playbook](../playbooks/security-release-audit-playbook.md#reading-the-exit-code) explains the exit codes.
6. **Write it up for your SRE team.** The [fleet release-readiness brief](../templates/fleet-release-readiness-brief.md) turns results into a rollout posture (READY, READY WITH CONDITIONS, or HOLD), a blast radius per finding, and numbered gates with owners and dates.

The repository's own rule applies to everything below: a finding is a claim until something runs, and an untested tier is a gap, not a pass.

## Changes in 7.2 that need a hosting test

### The two upgrade paths leave different file trees

- **What changed:** `$_old_files` in `wp-admin/includes/update-core.php` hasn't been updated for 7.2 yet. Upgrading from 7.1.4 through the Dashboard, auto-update or the Beta Tester plugin (all `Core_Upgrader`) leaves 10 files under `wp-includes/` that the 7.2 package doesn't ship. WP-CLI's `wp core update` removes them, because it also deletes files the old version's checksums list and the new version's don't. Tracked in [Trac #66456](https://core.trac.wordpress.org/ticket/66456). Beta 5 leaves the same 10 on an upgrade from 7.1.4. A site upgraded from a 7.2 prerelease through `Core_Upgrader` also keeps three Secrets API files that Beta 5 renamed (`wp-includes/secrets/interface-wp-secrets-{store,keyring,provider}.php`), 13 in all; WP-CLI removed them. In a local upgrade ladder, WP-CLI upgrades from 7.0.2 still left 21 other stale files, so check the WP-CLI path too.
- **Why a host cares:** integrity monitoring keyed to WordPress.org checksums flags those files on every site upgraded the first way, and on none upgraded the second way.
- **How to test:** upgrade one site each way, then run `scripts/stale_file_check.py <prior_tree> <target_tree>` and `wp core verify-checksums` on both. Record which path each result used: the [sweep playbook's upgrade ladder](../playbooks/release-day-sweep-playbook.md#phase-1b--upgrade-ladder) explains why one path never stands in for another.
- **Check on RC1:** whether `$_old_files` lists the 10 files, and whether it also removes `default-editor-styles.css`. 7.2 no longer ships that file, but `wp-includes/block-editor.php` still reads it, so sites upgraded through `Core_Upgrader` keep the editor's default styles only because the old copy is still on disk. WP-CLI upgrades delete that file, so those sites, like fresh installs, already lose the styles. Still true in Beta 5.

### `/random/` returns 404 after an upgrade, per site, until a wp-admin request

- **What changed:** 7.2 adds a `/random/` route that redirects to a random published post ([Trac #64498](https://core.trac.wordpress.org/ticket/64498), [dev note](https://make.wordpress.org/core/2026/11/05/your-content-is-going-to-get-more-random/)). An in-place upgrade doesn't write the new rewrite rules. `upgrade_all()` sets the `db_upgraded` option, and `wp-admin/admin.php` flushes rewrite rules on the next wp-admin request, logged in or not. Until then `/random/` is a 404.
- **On multisite it's per site.** A local subdirectory network upgraded from 7.1.4 with `wp core update-db --network`, and again with Network Admin > Upgrade Network, left every site at 404. Requests to the main site's wp-admin, Network Admin screens included, fixed only the main site. Each subsite stayed at 404 until a request reached its own `/sitename/wp-admin/` ([Trac #64498 comment 73](https://core.trac.wordpress.org/ticket/64498#comment:73)).
- **Why a host cares:** fleet upgrades by WP-CLI or automation, and subsites whose administrators rarely log in, can sit at 404 indefinitely. An edge cache can then keep the 404 for its full lifetime: see [Edge and page-cache tests](#edge-and-page-cache-tests).
- **How to test:** before upgrading, confirm each site has stored rewrite rules (`wp option get rewrite_rules`) with no random entries. After upgrading, check `db_upgraded`, the rule count and `/random/` on every site, then request one site's `/wp-admin/` and check them all again.
- **Mitigation:** after each upgrade, run `wp rewrite flush` on every site (`wp site list --field=url` on a network), then purge the edge cache. Purge after the flush, not at deploy: core fires the `after_db_upgrade` action right after the flush in `wp-admin/admin.php`, which makes it a good place for a platform purge. See the post-upgrade test in [Edge and page-cache tests](#edge-and-page-cache-tests).
- **Turning it off:** the `wp_enable_random_content_redirect` filter disables both `/random/` and `?random`. Add it before the upgrade. Added afterwards, it leaves the stored rule in place: `/random/` then serves a copy of the home page with a 200 until rewrite rules are flushed, and on 7.2-beta5 a wp-admin request didn't flush them. Flush, then purge.
- **Load:** every `/random/` request, and `?random` on any archive URL, runs an `ORDER BY RAND()` query that isn't cached, and the 302 isn't cached at the edge either. On large sites, a crawler hitting it is a cheap way to load the database. Not measured yet.

### Secrets API: no key, no Secrets API (changed in Beta 5)

- **What changed:** 7.2 adds encrypted secret storage ([Trac #66187](https://core.trac.wordpress.org/ticket/66187), [proposal](https://make.wordpress.org/core/2026/08/25/proposal-a-secrets-api-for-wordpress-7-2/)). Beta 4 derived the key from the site's salts when `WP_SECRETS_KEY` wasn't defined. Beta 5 removed that fallback ([changeset 65385](https://core.trac.wordpress.org/changeset/65385)): without a usable `WP_SECRETS_KEY`, the Secrets API is off and every call that needs the key returns `secret_key_unavailable`. Only the browser installer writes a key ([changeset 65389](https://core.trac.wordpress.org/changeset/65389)); existing sites and `wp config create` get none. Two upgraded sites checked on one host's platform had no key, and `wp_is_secrets_api_available()` returned false on both.
- **Why a host cares:** after upgrading, every site without a key shows a Site Health recommendation that includes a ready-to-paste `define()` line with a newly generated random key. That key is different on every page load and per environment, so customers who paste it get a key their other environments don't share. Nothing in core 7.2 calls the API yet, so this isn't an outage on day one, but plugins that move credentials into it will fail on sites without a key.
- **What counts as a usable key:** the recommended form is base64 of 32 random bytes. An empty value, the `wp-config-sample.php` placeholder, or a value equal to any of the keys and salts is rejected. Any other string is hashed into a key, so stray whitespace silently produces a different key: trim values read from a secrets store.
- **The key can't change once secrets exist.** A database copied to an environment with a different key can't read its secrets. Core still has no command or admin screen for re-wrapping secrets under a new key (planned for 7.3, [Trac #66399](https://core.trac.wordpress.org/ticket/66399)). Secrets stored under Beta 4's salt-derived key can be recovered: set the new `WP_SECRETS_KEY`, set `WP_SECRETS_KEY_PREVIOUS` to the old `LOGGED_IN_KEY . LOGGED_IN_SALT`, and call `WP_Secrets_Key_Manager::rotate_site_key()` with the old and new keyrings from code, for example `wp eval`. That worked on one host's single site on Beta 5; multisite isn't tested.
- **Drop-ins:** a `wp-content/secrets.php` drop-in loads after `wp-config.php` and before mu-plugins, and can override the provider, the store or the keyring. In Beta 5 those are abstract classes ([changeset 65390](https://core.trac.wordpress.org/changeset/65390)), so a drop-in written against Beta 4's interfaces is a fatal error until it uses `extends`. Core reports the API as available for any custom provider or keyring without testing it. So a read-only provider set as a platform default would let plugins try to save and then fail with `secret_provider_read_only`. The lowest-risk platform default is a drop-in that only defines `WP_SECRETS_KEY` from your secrets store and leaves core's encryption in place.
- **How to test:**
  - **Clone:** store a secret on site A, copy A's database to site B, and read it on B with the same and with a different `WP_SECRETS_KEY`.
  - **Leak check:** store a unique test value through `wp_set_secret()`, then search your object cache and database for it in raw, base64 and hex form. Store the same kind of value as a plain option as the positive control. On one host with a Redis object cache, the secret's plaintext reached neither Redis nor the database, while the plain-option control was found in both.
  - **Plugin pitfall:** passing a `WP_Secret` object to `wp_cache_set()` throws an uncaught `LogicException` ("WP_Secret cannot be cloned"). Nothing leaks, but the request fails.
- **Decide before December 8:** where each site's key comes from, whether one key covers all of a site's environments (clones keep working) or live gets its own (clones lose their secrets), and that the key is never regenerated by migrations or rebuilds.

### Client-side media processing falls back silently

- **What changed:** in supported browsers, the editor makes image sub-sizes in the browser and uploads each through new REST routes (`/wp/v2/media/<id>/sideload` and `/finalize`). It engages only when all of these hold: a Chromium browser recent enough to honor `Document-Isolation-Policy`, that header on the editor page, `is_ssl()` true (or a `localhost` host), `upload_files` for the user, and the `wp_client_side_media_processing_enabled` filter not returning false.
- **Why a host cares:** if anything in your stack strips the header (a CDN rule, a proxy, a security plugin), every site behind it quietly returns to server processing. Nothing logs it. Where client processing does engage, PNG sub-sizes came out 3.3 to 5 times the size the server path makes for the same file, and a sub-size over a low `upload_max_filesize` is dropped with no error ([gutenberg issue 86456](https://github.com/WordPress/gutenberg/issues/86456)).
- **How to test:** check for the header from outside your edge, not from the origin. Upload the same image in Chromium and in Firefox (the negative control), and look for POST requests to `/sideload` and `/finalize` in access logs: there's no admin indicator.

### Other 7.2 changes worth a quick check

- **KSES rewritten with the HTML API, on by default** ([Trac #66208](https://core.trac.wordpress.org/ticket/66208)). Content saved by users without `unfiltered_html` comes back with attributes sorted, entities decoded and tag names lowercased. On multisite that includes Editors and site administrators. Opt out with a later filter on `wp_kses_force_legacy_parser` returning true.
- **Admin script and style concatenation retired** ([changeset 64585](https://core.trac.wordpress.org/changeset/64585)). `wp-admin/load-scripts.php` and `load-styles.php` answer 410, and `CONCATENATE_SCRIPTS` is no longer read. Check edge rules, monitors and plugins that call those URLs.
- **Network upgrade edge cases.** Archived, spam and deactivated subsites keep the old database version, and their administrators don't get `manage_secrets`, because the role update runs inside the per-site upgrade. Run `wp core update-db --url=<site>` when you reactivate one. Separately, Upgrade Network can report "All done!" when a subsite's upgrade request returned an HTTP error ([Trac #66477](https://core.trac.wordpress.org/ticket/66477)); check `db_version` per site after every network upgrade.
- **Requests HTTP library 2.0.17 to 2.0.21** in Beta 5. On old system libraries, outbound HTTP on libcurl 7.64.0 matched 7.1.4 request for request, and plugin and theme zips installed on libzip 1.7.3, including one that needs the PclZip fallback. libcurl 7.29 wasn't tested.
- **Application password email.** Creating an application password now sends an "Application Password Created" email. Expect support questions when it arrives unexpectedly.
- **`NO_BACKSLASH_ESCAPES` removed from WordPress's own database session** ([dev note](https://make.wordpress.org/core/2026/10/09/no_backslash_escapes-sql-mode-is-now-turned-off-by-default-in-wordpress-7-2/)). Only matters where the server sets that SQL mode globally; check yours.
- **Admin icons are inline SVG.** Sites running the Gutenberg plugin 23.7.2 get notices and missing admin-bar icons ([Trac #66344](https://core.trac.wordpress.org/ticket/66344)); 22.8.0 and 24.3.1 are fine.
- **Ipsum, the new default theme, on fresh installs.** It loads 341 KiB of Inter font files that aren't subset on every page ([ipsum issue 194](https://github.com/WordPress/ipsum/issues/194)) and shifts layout when the font swaps in ([ipsum issue 195](https://github.com/WordPress/ipsum/issues/195)). Upgraded sites keep their theme.

## Edge and page-cache tests

One host ran a 28-test suite for 7.2-beta4 behind its default CDN on November 7, 2026, against a single site and a subdirectory multisite (four sites, 112 test-and-site combinations). It finished with no protection stop: 36 passed, 4 failed (all one finding), 6 were inconclusive and 66 didn't run, most for missing fixtures or because they wait on later builds. What it found, as tests you can repeat on your own edge:

- **Check whether your platform's cache code overrides core's no-cache headers.** This was the one failure. Core 7.2 sends `nocache_headers()` on the empty-archive `/random/` 404 (`WP::handle_random()` in `wp-includes/class-wp.php`) and on the 302 (`wp_random_content_redirect()` in `wp-includes/query.php`). A platform plugin that sets `Cache-Control` on the `send_headers` hook for every anonymous request replaced core's value on the 404, so the edge cached that 404 for the site's full page lifetime, 7 days there, while core's `Expires` and `X-Robots-Tag: noindex` still arrived beside it. The 302 escaped because the redirect exits before `send_headers` fires. To test: request `/random/category/<an empty category>/` twice and read `Cache-Control` and your cache-status header. If your code sets `Cache-Control` itself, have it respect a `no-cache` or `no-store` value core already sent (`headers_list()` shows it). The same override gives the post-upgrade `/random/` 404 the full page lifetime.
- **`/random/` redirects were never cached**, including with `utm_` and `__` query parameters and the category form. Check that your edge leaves marketing parameters out of the cache key for that route too.
- **Cookies that should bypass the cache did:** logged-in, `wp-postpass_*` (password-protected posts), `comment_author_*` and `NO_CACHE`. Analytics cookies didn't change caching. Test your platform's own cache-variant cookies the same way.
- **Error responses:** REST and 5xx errors reached the client as WordPress's own JSON. Anonymous REST refusals (a draft request answering 400, `users/me` answering 401) were cached for the page lifetime but never served to an authenticated request. Check that on your edge before relying on it.
- **Nonces in cached pages came from plugins,** a membership plugin and an ecommerce plugin, not from core 7.2. Crawl your own cached pages for nonce fields and trace each to its source.
- **The CDN added its bot-management cookie to cached responses,** cache hits included. WordPress set no cookie on any cached response. Worth a line in your cookie-consent documentation.
- **Loopbacks passed through the edge without a challenge,** and Site Health's REST and loopback checks were good. Check that your bot protection doesn't challenge a site's requests to itself.
- **Large uploads:** one 50 MB raw-body request to the new `/sideload` route got a 503 generated in front of WordPress, while the same request on another site got WordPress's own 400. Unexplained: a body-size limit or a transient failure. Check the size limits in front of WordPress for the new routes.

**After an upgrade (7.2-beta5, November 10):** on one host's default CDN, a `/random/` 404 cached two days before the upgrade, with a 7-day lifetime, was still served after the code update to Beta 5, the database upgrade and the first wp-admin request, while the origin already answered 302. A request that bypassed the cache between the code update and the rule flush got a fresh 404 that was cached for 7 days too. An environment cache purge ended it; no other remedy was tried. So purge after the flush, and treat it as required.

**Running these tests without tripping your own protection:**

- **Pace requests.** Test scripts met a bot challenge after about 90 requests from one IP in a short window. The suite kept every run to 40 requests at 1-second spacing, with 5 minutes between runs on one site.
- **Use your platform's documented route for test traffic,** such as a bypass header or token, rather than changing the user agent.
- **Classify every unexpected response by its content and origin headers, not its status, and save the body.** A 200 with no cache status and no origin header is the edge's own page. Sandbox-plan interstitial pages look like success until you read them.

**Not tested there, and worth running:** whether `Document-Isolation-Policy` survives the edge on the editor page, and rate limits on the new upload routes. A membership plugin's wp-admin block kept the test Author out of the editor, so check that your test user can reach it first. Edge tiers with a web application firewall or image optimization weren't tested at all.

## Performance

The [performance release audit playbook](../playbooks/performance-release-audit-playbook.md) sets the rules: a repeatable dataset, PHP-matched pairs against 7.1.4, an A/A run before any A/B, and a practical-significance floor written down before you look at a comparison. One host ran it in pilot form on 7.2-beta4, locally and on sandbox environments. What that pilot taught, in order of usefulness:

- **Start with byte counts and query counts.** They were identical on every run of the same build, so any difference is real. Beta 4's front page came out 2,186 bytes larger than 7.1.4's with Twenty Twenty-Five, with the same 40 to 54 database queries per render.
- **Expect timing to be noisy on small environments.** In-process render time spread over 10% to 19% of its median across identical A/A runs, wider than the differences being measured, so the pilot withheld every timing verdict. Use bigger samples, a quieter machine or both before stating a timing result.
- **Run the final A again.** After a downgrade-and-upgrade round trip, peak memory sat 0.75 to 0.88 MB above the first runs on a byte-identical core tree, so a third A run catches drift that a single A/B would report as a change.
- **Benchmark what 7.2 changed,** not a generic page average: media upload CPU and storage per path (client vs server), fresh-install weight with Ipsum, admin screens rendering SVG icons, and cron duration after the upgrade.

## Security

- **New authenticated surfaces to test below administrator:** Secrets API storage and its `manage_secrets` capability (site administrators hold it on multisite), the media `/sideload` and `/finalize` routes, Notes reactions (a new comment type) and the Abilities API query endpoints. The [security invariants catalog](../method/security-invariants.md) lists what to check on each.
- **Capability boundaries on multisite.** Test as an Author and as a site administrator who isn't a super admin. Single-admin test sites can't see cross-user bugs.
- **Previous fixes.** 7.1.4 fixed several Interactivity API binding issues; that subsystem deserves a fresh look this cycle, and `scripts/security_fix_presence.sh` confirms the 7.1.x fixes are still in each 7.2 drop.
- **Route vulnerabilities privately.** Report them through [WordPress's HackerOne program](https://hackerone.com/wordpress), never in a public ticket, Slack channel or shared document.

## Keep up with replies to what you file

Testing a release means filing tickets and leaving test reports, and then missing the follow-up questions. The repository's [follow-up watch](../.github/workflows/followup-watch.yml) checks twice a day for new replies by anyone else on the Core Trac tickets, GitHub issues, Make posts and forum topics you took part in since the cycle started, plus @mentions anywhere on Core Trac, and posts what's new as a comment on one issue in your fork. Set three repository variables: `WATCH_WPORG_USER`, `WATCH_GITHUB_USER` and `WATCH_SINCE` (7.2 Beta 1 was October 20, 2026). `python3 scripts/followup-watch.py --control` runs its checks without touching the network.

## Not covered yet: where help is most useful

These weren't tested in the pre-release work this page draws on. A result on any of them, pass or fail, is worth sharing:

- Subdomain multisite networks.
- Upgrades on PHP 8.x. One host's local upgrade ladder (22 source versions, 4.9 to 7.0.2, both upgrade paths) passed 79 of 79 on PHP 7.4 only; PHP 8.1, 8.2 and 8.4 got fresh installs and one network upgrade. MySQL 8 on a hosted platform.
- Platform-managed upgrade paths other than the Dashboard and WP-CLI.
- Memcached and other persistent object caches with 7.2 (one host tested Redis), including comment counts with Notes reactions.
- HEIC and AVIF uploads per image library and delegate.
- Client-side media in real Firefox and Safari on a hosted site.
- Cron after upgrade: scheduled publishing and cleanup.
- Screen-reader passes on the reorganized Options menu and the new admin icons.
- Edge tiers with a web application firewall or image optimization in front of WordPress, and `/random/` load on large sites.
- The Secrets API on multisite (network secrets, recovery), and a key read from a platform secrets store inside `wp-config.php`.
- Hosts still on libcurl 7.29.

## Where to share results

- **Bugs in WordPress:** a [Core Trac](https://core.trac.wordpress.org/) ticket, or a comment on the existing one, with the build, the upgrade path, both controls and a reproduction.
- **Test reports:** the [Help Test WordPress 7.2](https://make.wordpress.org/test/2026/10/20/help-test-wordpress-7-2/) post on Make WordPress Test.
- **Hosting-specific results and questions:** the #hosting channel in [Making WordPress Slack](https://make.wordpress.org/chat/).
- **Problems with this method or its scripts:** a [field report](https://github.com/courtneyr-dev/wp-release-audit-method/issues/new?template=field-report.yml) on this repository.
