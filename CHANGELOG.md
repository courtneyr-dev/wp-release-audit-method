# Changelog

Notable changes to the method and toolkit. This project has no releases — it tracks WordPress's
cadence rather than its own, so entries are grouped by what changed.

## Unreleased

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
