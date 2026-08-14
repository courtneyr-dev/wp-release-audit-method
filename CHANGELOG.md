# Changelog

Notable changes to the method and toolkit. This project has no releases — it tracks WordPress's
cadence rather than its own, so entries are grouped by what changed.

## Unreleased

### Fixed — the chain prompt's adjudication rule was unreachable (2026-08-13)
- **`ADJUDICATE BEFORE YOU BUILD` now lives inside the pasted block.** The rule "none may become a
  test before source adjudication" existed only in the lens sections *below* the fenced prompt, so
  an agent handed the block to run never saw it — the fenced artifact contained no mention of
  adjudication at all. It is now a `<method_rules>` entry carrying its own evidence (of the first
  36 lens-generated proposals, zero survived adjudication unchanged: 16 refuted on verified-false
  premises, 20 corrected), and the completeness contract now requires every built chain to trace to
  a REVISE-status register row with the adjudicating source cited. A suite built from unadjudicated
  proposals tests things that cannot happen and reports the resulting silence as evidence.
  The amendment is flagged in the prompt header, since audit records cite this prompt as run.
  Checked the release-audit prompt for the same defect: its safety rules were already inside its
  fence, and its out-of-fence section is a pure rule-provenance table.

### Changed — interface and vocabulary pass (2026-08-13)
- **One target idiom across all seven upgrade suites.** `verify.sh`, `users-pages-install.sh`,
  `multisite-suite.sh`, `stepped-chain.sh`, `direct-jump-matrix.sh` and `multisite-11.sh` now take
  `--target=<zip-url>`, falling back to `WP_AUDIT_TARGET`, then to each script's existing default —
  so every prior invocation behaves identically. Four of them previously required editing the
  source to point at a new build, which made the file's insides part of its interface; the README
  section teaching that `sed` is gone. Legacy forms (`direct-jump-matrix.sh`'s third positional,
  `multisite-11.sh`'s `TARGET_ZIP=`) still work. Suites still never auto-detect: the caller passes
  a target it can name in a report.
- **The detector has controls.** `check-latest-release.sh` gained three test seams
  (`WP_AUDIT_FEED_FILE`, `WP_AUDIT_STABLE`, `WP_AUDIT_SKIP_PACKAGE_CHECK`) and `check-repo.py`
  gained three calibration cells against a captured feed snapshot in `fixtures/feeds/`: the known
  answer, the no-cycle negative control (same feed, stable pinned past the prerelease), and garbage
  in / no version out. Its only prior test was one live run, which is the confident shrug this repo
  argues against.
- **`CONTEXT.md`** — the glossary for language the repo already spoke but defined in thirty places:
  cell, lane, chain, act, driver, capability, gate, control, fixture, standing environment, target,
  corpus, ledger, BLOCKED, INVALID, harness fault, evidence ceiling, finding. One conflict resolved:
  "standing" now means the never-rebuilt environment and never a lane that runs every cycle (that is
  a *recurring* lane).
- **Skill descriptions pruned** — the five shipped skills' frontmatter descriptions are always-loaded
  context, and carried feature enumeration the bodies already document. Cut 33% (2302 → 1544
  characters) with every trigger phrase preserved verbatim.

### Added — adopted from jazzsequence/wpnext-test (2026-08-11)

Chris Reynolds's [wpnext-test](https://github.com/jazzsequence/wpnext-test) is a standing
Pantheon site that detects new Betas/RCs and upgrades itself unattended. Four of its
capabilities translate to this repo; the standing-site pattern itself becomes a method document.

- **`scripts/check-latest-release.sh`** — Beta/RC detector. Merges the News and Make/Core
  release feeds (the API's version-check never surfaces prereleases), version-sorts the
  mentions, then gates on api.wordpress.org's current stable so a remembered *last* cycle is
  never reported as an active one — the check wpnext-test does by comparing against its live
  site, done here without a site. Verifies the package is actually live (exit 3 = announced
  but not built, mirroring `rc_build_identity.sh`). Calibrated live on 7.1-RC2.
- **`.github/workflows/release-watch.yml`** — daily cron on the detector. On a newly packaged
  build it opens one tracking issue (the issue is the dedup record and the human checklist:
  sweep, build identity, security-backport gate, Slack post) and dispatches the prerelease
  suite, so first results exist before anyone sits down.
- **`.github/workflows/prerelease-suite.yml`** — weekly plus dispatch-on-drop. `self-test.yml`
  proves the tooling against pinned versions; this proves the release: current stable
  installed, upgraded in place to the newest Beta/RC, CRUD suite against the result, output
  kept as an artifact. Green-but-idle outside a cycle, and says so.
- **`scripts/seed-test-content.sh`** — parity between scripted environments and the beta-rc
  Playground blueprint: installs the six-plugin debugging toolkit (including Test Reports)
  and imports both content corpora — theme-test-data (the corpus wpnext-test ships in its
  rig) and a11y-theme-unit-test. Import success is judged by post count, not exit code, and
  a driver without `hostfs` reports BLOCKED for the content half rather than passing vacuously.
- **`method/standing-environment.md`** — the pattern that would not port as code: one site you
  never rebuild, upgraded in place every Beta/RC, state deliberately accumulating. Names the
  bug class fresh fixtures structurally cannot catch (dirty-state upgrades), the rules
  (snapshot before every jump, keep a ledger, never spring-clean), and the reporting loop —
  a failure there is a lead to reduce onto a fresh fixture, not a filing.

### Added — from the 7.1-RC1 release-day run (2026-08-05)
- **`scripts/security_fix_presence.sh` — the security-backport gate.** Diffs a stable security
  release against its predecessor to derive the fix set from source (no hand-maintained CVE
  signatures), then classifies a target build PATCHED / VULNERABLE / DIVERGED per fix. Answers the
  question nothing else in the sweep asks: does this RC contain the fixes from a stable security
  release that shipped after it was cut? Controls calibrate exactly — run against the patched
  release → all PATCHED / exit 0, against the predecessor → all VULNERABLE / exit 4. Playbook gains
  a section on the gate, its two honest limits (line-level not semantic; strong signal not proof —
  confirm high-severity fixes behaviorally), and where it runs (right after build identity).
- **The fast block, and checklist-first ordering** — the report template now opens with the
  short per-check block the community actually reads, and the playbook gains a measured
  fast path (~30 minutes on prebuilt fixtures) that runs exactly the cells proving those
  lines, posts, and lets the ladder, matrix, and browser cells land in the thread. Two
  rules ride along: every posted line traces to a cell that individually executed it (no
  marking by association — the renderer bug that motivated this), and controls still run
  before cells.
- **`scripts/rc_build_identity.sh`** — the build-identity gate the playbook already required but the
  repo never shipped. Checks both package lanes (stable at `downloads.wordpress.org/release/`,
  betas/RCs at the `wordpress.org` root — checking only one lane reports WAITING while the build is
  live), pins sha256 plus `$wp_version`/`$wp_db_version`, and exits 0/3/2 for RELEASED/WAITING/error.
  Calibrated both directions against 7.1-RC1.
- **Direct-jump matrix as a standing lane** — `scripts/direct-jump-matrix.sh` now derives the
  expected post-upgrade version from the target zip name (previously hard-coded, which silently
  failed every rung on a new target) and defaults to the latest patch of **every** release series
  (from `api.wordpress.org/core/stable-check`), overridable via `VERSIONS`. All 21 branches
  4.9 → 7.0.2 proved one-hop clean to 7.1-RC1 in under an hour.
- **Playbook: fixture traps proven on RC1 day** — parked old-version fixtures self-upgrade
  (`auto_update_core_major` defaults on since 5.6; pin `WP_AUTO_UPDATE_CORE=false` and re-assert
  before-state at run start), and container tar truncates >100-char paths (TT2 1.x pattern
  filenames fatal the 5.9/6.0 installs before any upgrade runs; host-extract the zip instead).
- **Playbook: the no-schema-change release** — when the target ships `$wp_db_version` equal to
  current stable, "db advanced" assertions flip to "unchanged, as shipped", and the multisite
  check becomes "processed exactly the eligible count, flags unmoved" — the case where the
  updater's "upgraded on 2/2 sites" line misleads hardest.

### Added
- **Self-test** — `scripts/check-repo.py` and a CI workflow running nine checks, plus an external
  link sweep and a smoke test that proves the inventory tool produces the sections it documents.
- **Issue and PR templates** that require build identity, upgrade lane, environment, controls, and an
  evidence ceiling.
- **[i18n and RTL](i18n/)** — translation loading, the WordPress 6.7 just-in-time change, RTL layout,
  and locale edge cases.
- **[Accessibility](accessibility/)** — the layered method sourced from the WordPress Accessibility
  knowledge base, the accessibility-ready theme guidelines, and the native-control calibration rule.
- **[Blueprint repros](playbooks/blueprint-repros.md)** — Playground blueprints as one-click
  reproductions for bug reports.
- **[Plugin and theme authors](plugin-theme-authors/)** — the release-diff method, adoption of new
  APIs, block testing, co-installed plugins, the extender digest, drop-in CI, and starter tests.
- **`scripts/wp-surface-inventory.sh`** — derives which core surfaces a codebase touches, with
  `--csv` and `--baseline` diff modes.
- **`data/deprecations.csv`** — community-maintainable, with version and replacement per symbol.
- **Classic and block coverage** as four deployments: {block, classic} editor × {block, classic}
  theme.

### Changed
- Performance playbook now carries a concrete path from UNEXERCISED to validated, including the
  negative control that makes a benchmark credible.
- Developer Resources section simplified from a wall of post-type slugs to a handbook table.
- `plugin-authors/` renamed to `plugin-theme-authors/` — it covers themes equally.

### Fixed
- Beta Tester plugin maintainer list, via [#1](https://github.com/courtneyr-dev/wp-release-audit-method/pull/1)
  from @afragen.
- `--baseline` count comparison used `join -t,` which split on the comma inside the composite key.
