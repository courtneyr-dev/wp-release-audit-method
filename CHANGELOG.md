# Changelog

Notable changes to the method and toolkit. This project has no releases — it tracks WordPress's
cadence rather than its own, so entries are grouped by what changed.

## Unreleased

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
