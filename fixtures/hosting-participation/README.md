# Hosting-participation fixtures

Offline universes for `scripts/hosting-test-participation.py --control`. Each directory
answers the collector's requests from files named by its own `request_key()` — the same
`{"body": …, "headers": …}` wrapper the collector's `--evidence` mode writes for live
responses, so a captured live response can be replayed as a fixture verbatim. The shapes
mirror the live `wp/v2` surface on make.wordpress.org/hosting as captured 2026-08-27
(result posts with `parent` revision containers, `php-version`/`db-version`/`report-result`
taxonomy term ids, users by slug).

| Universe | Encodes |
|---|---|
| `universe-a` | The main cast: `hostco-shared-bot` current with an exact-target **failed** run, `hostco-managed-bot` current without the target, `staleco-bot` outside the 25-revision window, two `dupeco*` candidates for `--find` ambiguity, and 30 revision posts r90002…r89973 |
| `universe-paginated` | `pageco-bot` whose exact-target result sits on page 2 of a two-page history — the verdict is only right if pagination was followed |
| `universe-drifted` | A revision listing that lost its `slug` key — the collector must go `BLOCKED`, exit 3, not guess |
| `universe-netfail` | A simulated transport failure (`{"__error__": …}`) — same fail-closed expectation |
| `variants-hostco.csv` | Three declared variants: two mapped and confirmed, one with no reporter — drives the partial-coverage rollup |
| `variants-hostco-shared-login.csv` | Two variants confirmed to ONE account — must cap at `VERIFIED_CURRENT_HOST_ONLY`, never split |

The twelve scenario classes and their expected classifications are enumerated in
`run_control()` in the collector itself; `scripts/check-repo.py` runs them in CI. These
fixtures are synthetic (HostCo, StaleCo, PageCo, DupeCo are not real hosts); no real
provider's data is asserted here.
