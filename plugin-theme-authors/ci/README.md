# Drop-in CI for plugin and theme authors

*The point: stop relying on remembering to test during the beta window.*

Most authors won't run a manual compatibility pass three times a year. Almost all of them will merge
a workflow that runs itself. These are written to be copied into your repo and edited in about five
minutes.

| File | What it does |
|---|---|
| [`wp-compat.yml`](wp-compat.yml) | Test matrix across the WordPress and PHP versions you claim to support, **plus a nightly canary against trunk that opens an issue when core breaks you** |
| **accessibility job** (in `wp-compat.yml`) | axe **and** pa11y against your screens on every push — two engines, different rule sets |
| [`plugin-check.yml`](plugin-check.yml) | Plugin Check on every push, readme.txt header validation, a "Tested up to is drifting" warning, and a check that your repo and wordpress.org agree on the field |

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

**The "Tested up to" checks warn, never fail.** Nothing in CI can verify you actually tested — only
you can do that. What CI *can* catch is the two mechanical failures around an honest test: the
field falling behind current WordPress, and your Git copy disagreeing with what wordpress.org
serves. The second one needs your directory slug — set `DOTORG_SLUG` at the top of
`plugin-check.yml` (the one `EDIT:` in that file); leave it empty and the check skips itself.
Disagreement usually means a bump was made by hand in SVN and never committed to Git, so the next
deploy will quietly re-lower the field on .org. The
[nine boxes](../README.md#bump-it-only-when-this-is-true) are still your job, and so is
[bumping every copy](../README.md#bump-every-copy--the-field-lives-in-more-than-one-place).

**Permissions** — the workflow is read-only at the top; the canary job grants itself
`issues: write` because it's the only job that files the breakage issue. That's least privilege:
a compromised dependency in any other job can't touch your issues. If you'd rather the canary
didn't file at all, remove the job-level `permissions:` block and the "Open an issue" step;
you'll still get a failed run.

## Workflow supply-chain hardening — the drop-ins already do this

The drop-ins ship hardened, because a workflow you copy is a workflow you inherit the risks of.
What's applied here, and why (all from Jonathan Desrosiers, "Software Supply Chain Security in the
Age of AI," WCUS 2026):

- **Every third-party action is pinned to a full-length commit hash**, not a mutable tag. `@v4`
  can be repointed at new code by whoever controls the tag; a 40-character SHA can't. The trailing
  `# v4.4.0` comment keeps it readable and Dependabot can still bump it.
- **`permissions:` is zeroed to `contents: read` at the top**, and the one job that needs more
  grants it to itself. The default `GITHUB_TOKEN` otherwise carries far more than any single job
  needs.
- **`persist-credentials: false` on every checkout**, so the token isn't left in the runner's
  git config for a later step (or a compromised dependency) to reuse.
- **Untrusted input never lands in a `run:` block.** The canary's issue-filing uses
  `actions/github-script` with `context.*` values only — no `${{ github.event.* }}` interpolated
  into a shell command, which is the classic Actions injection.

The repo scans all of this with **[Zizmor](https://docs.zizmor.sh/)** in its own CI — the same
scanner the WordPress.org GitHub org is piloting org-wide — and fixes what it finds rather than
just installing it. Run it against your own copy:

```bash
pipx run zizmor .github/workflows/
```

For JavaScript tooling in your own pipeline, two more Desrosiers rules worth adopting:

- **`npm ci`, never `npm install`** in CI — plain `install` silently regenerates the lockfile,
  so CI stops testing the dependency tree you committed. Add `save-exact=true` to pin. (The
  `npm install -g @wordpress/env` in `wp-compat.yml` is a *global tool bootstrap*, not a project
  dependency — a different thing, and the one place `npm ci` doesn't apply.) Note **npm 12 will
  disable install scripts by default** — the exact mechanism the Axios and TanStack worms used.
- **`composer audit`** in CI — and note **Composer 2.9 turns a detected vulnerability into a
  blocking fatal**, not a warning, so it fails the build rather than printing something nobody
  reads.

## Beyond GitHub Actions

The same three ideas port anywhere: **a supported matrix**, **a trunk canary on a schedule**, and
**a deprecation report that surfaces even on green**. GitLab CI, Bitbucket Pipelines, and CircleCI
all do scheduled jobs; only the syntax changes.
