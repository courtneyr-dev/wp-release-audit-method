# Drop-in CI for plugin and theme authors

*The point: stop relying on remembering to test during the beta window.*

Most authors won't run a manual compatibility pass three times a year. Almost all of them will merge
a workflow that runs itself. These are written to be copied into your repo and edited in about five
minutes.

| File | What it does |
|---|---|
| [`wp-compat.yml`](wp-compat.yml) | Test matrix across the WordPress and PHP versions you claim to support, **plus a nightly canary against trunk that opens an issue when core breaks you** |
| [`plugin-check.yml`](plugin-check.yml) | Plugin Check on every push, plus readme.txt header validation and a "Tested up to is drifting" warning |

## Install

```bash
mkdir -p .github/workflows
curl -sSL -o .github/workflows/wp-compat.yml \
  https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/plugin-theme-authors/ci/wp-compat.yml
curl -sSL -o .github/workflows/plugin-check.yml \
  https://raw.githubusercontent.com/courtneyr-dev/wp-release-audit-method/main/plugin-theme-authors/ci/plugin-check.yml
```

Then edit the four things marked `EDIT:` in `wp-compat.yml`:

1. **`wp:` matrix** — your `Requires at least`, a middle version, and `latest`
2. **`php:` matrix** — your `Requires PHP` floor and the newest version you support
3. **The test command** — currently `composer run test || vendor/bin/phpunit`
4. **The multisite cell** — delete it if you don't claim multisite support

No test suite yet? Use [`../starter-tests/`](../starter-tests/) — five tests that cover the things
that actually break, or scaffold the harness with `wp scaffold plugin-tests <your-slug>`.

## The canary is the part that matters

The matrix job tells you about versions that already shipped. The **trunk canary** tells you about
the version that hasn't.

It runs nightly against WordPress trunk. When it fails on a scheduled run, it opens an issue —
titled, labeled `wp-trunk`, linking the run, the dev notes, and what to do next. If an issue is
already open it comments instead of filing a duplicate.

It's `continue-on-error: true` deliberately. Trunk breaking is **news, not a broken build** — it
shouldn't turn your contributors' pull requests red.

> [!TIP]
> This is the whole difference between finding out in week one of the beta and finding out from a
> one-star review. Core changes land in trunk long before a beta is packaged, so the canary
> typically warns you weeks earlier than any manual pass would.

It also surfaces **deprecation notices even when tests pass**, into the run summary. Deprecations
aren't failures — which is exactly why they get missed until they become failures.

## The surfaces job

Runs [`wp-surface-inventory.sh`](../../scripts/wp-surface-inventory.sh) against your code and writes
the result into the GitHub step summary, so every run shows what your code touches.

To get change detection, commit a baseline:

```bash
bash wp-surface-inventory.sh . --csv > .wp-surfaces-baseline.csv
git add .wp-surfaces-baseline.csv && git commit -m "Add surface baseline"
```

After that, every run reports **NEW** surfaces (ones your tests have never covered through an
upgrade) and **GONE** surfaces. Refresh the baseline after each release.

## Notes and caveats

**`bin/install-wp-tests.sh`** — the matrix job expects the standard WordPress test scaffold. If you
don't have it: `wp scaffold plugin-tests your-plugin-slug`. The workflow fails with that hint rather
than a confusing error.

**Themes** — `wp-compat.yml` works as-is. `plugin-check.yml` is plugin-specific; use the
[Theme Check](https://wordpress.org/plugins/theme-check/) plugin instead, and for block themes also
validate your `theme.json` against
[the schema](https://schemas.wp.org/trunk/theme.json).

**The PHP lint step** is cheap and catches something tests can't: syntax valid on your dev PHP but a
parse error on your declared floor. A parse error is a white screen, not a caught exception.

**The "Tested up to" check warns, never fails.** Nothing in CI can verify you actually tested — only
you can do that. It catches drift, which is the common case. The
[nine boxes](../README.md#bump-it-only-when-this-is-true) are still your job.

**Permissions** — the canary needs `issues: write` to file the breakage issue. If you'd rather it
didn't, remove that permission and the "Open an issue" step; you'll still get a failed run.

## Beyond GitHub Actions

The same three ideas port anywhere: **a supported matrix**, **a trunk canary on a schedule**, and
**a deprecation report that surfaces even on green**. GitLab CI, Bitbucket Pipelines, and CircleCI
all do scheduled jobs; only the syntax changes.
