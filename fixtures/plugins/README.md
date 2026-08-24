# Fixture plugins — the seeded failures the probes are calibrated against

Two single-file plugins that reconstruct the **shape** of the WP Rocket 7.1 fatal
([ecosystem lane](../../method/ecosystem-compatibility-lane.md#the-worked-incident--wp-rocket-on-71-release-day))
without needing WP Rocket, which is premium and cannot be fetched in CI.

| Plugin | Role |
|---|---|
| `fx-strict-consumer.php` | Stands in for WP Rocket's Cloudflare module — `substr()` on a `$wp_filter` callback key, under `declare(strict_types=1)`, on `init` |
| `fx-closure-registrar.php` | The **third ingredient** — registers a closure on `deleted_post`, which is what gets keyed by object id |

Drop both into `wp-content/plugins/` on a fixture running a core version **older** than the
`spl_object_id()` change and activate them.

- **Both active** = the triple. The target core keys the closure with an integer, `substr()`
  on an int under strict types is a `TypeError`, and the site fatals on `init`. This is the
  positive control for [`core-preflight-probe.sh`](../../scripts/core-preflight-probe.sh).
- **Consumer only** = the pair. Nothing registers a closure on that hook, the loop finds
  nothing to measure, and the target boots clean. Negative control.

That pair/triple asymmetry is the whole point of the ecosystem lane, and these two files are
the cheapest way to have it on hand. They are a **reconstruction of the mechanism**, not a
reproduction of WP Rocket — see [validation and proof](../../method/validation-and-proof.md)
for why that distinction is load-bearing in anything you report.
