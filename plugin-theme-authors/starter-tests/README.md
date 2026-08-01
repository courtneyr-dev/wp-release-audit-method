# Starter tests

*"Write some tests" is advice. These are the tests.*

Copy, rename to your plugin, fill in the `EDIT:` markers, and you have a suite in an afternoon.

They deliberately cover **the things that break during a WordPress release**, not the things that
are easy to test. Activation fatals, data that doesn't survive an upgrade, capability boundaries
that shift, REST schemas that tighten, and uninstall that doesn't clean up.

| File | Covers | Why it earns its place |
|---|---|---|
| [`test-activation.php`](phpunit/test-activation.php) | Activate, deactivate, reactivate, no fatals, no unexpected output | A fatal on activation affects 100% of users instantly |
| [`test-upgrade-path.php`](phpunit/test-upgrade-path.php) | Old data written, upgrade routine run, data still readable | The lane a fresh install can never test |
| [`test-capabilities.php`](phpunit/test-capabilities.php) | Every role you support, plus one you don't | Where cross-user bugs live, invisible from an admin account |
| [`test-rest.php`](phpunit/test-rest.php) | Routes registered, schema, permissions as a low role | Schema validation tightens between releases |
| [`test-uninstall.php`](phpunit/test-uninstall.php) | Options, meta, tables, and cron all removed | Guideline-relevant and almost never tested |
| [`test-editor-paradigm.php`](phpunit/test-editor-paradigm.php) | Block vs classic editor, block vs classic theme | ~9M sites run Classic Editor; a pass in one paradigm proves nothing about the other |

Plus a Playwright pair for what PHPUnit structurally can't see:

| File | Covers |
|---|---|
| [`editor-block.spec.js`](playwright/editor-block.spec.js) | Your block inserts, saves, reloads **without a validation error** |
| [`admin-smoke.spec.js`](playwright/admin-smoke.spec.js) | Settings screen loads and saves, with **zero console errors** |

## Setup

**PHPUnit** — if you have no harness yet:

```bash
wp scaffold plugin-tests your-plugin-slug
bash bin/install-wp-tests.sh wordpress_test root '' localhost latest
```

Then copy `phpunit/*.php` into your `tests/` directory and run `vendor/bin/phpunit`.

**Playwright** — for the editor tests:

```bash
npm install --save-dev @playwright/test @wordpress/e2e-test-utils-playwright
npx playwright install chromium
npx playwright test
```

These assume [`wp-env`](https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/)
at `http://localhost:8888` with `admin`/`password`. Adjust
[`playwright.config.js`](playwright/playwright.config.js) if yours differs.

## Why these and not others

**Test what a release can break, not what is easy to assert.** A hundred tests of your business logic
tell you nothing about whether WordPress 7.2 moved something under you. Five tests on the seams
between your code and core tell you immediately.

The seam tests are also the ones that stay valuable when you refactor. Business-logic tests get
rewritten with the logic; "does it activate without fatals" is true forever.

> [!IMPORTANT]
> **A passing test can be a wrong test.** When a dev note says a behavior changed and your test still
> passes unchanged, go read that test — it may be asserting the old behavior in a way that happens
> to still hold. This is the 🟠 cell of
> [the risk grid](../release-diff-method.md#the-risk-grid).

## Wire them into CI

The [CI workflows](../ci/) run these across your whole support matrix plus nightly against trunk.
That's the combination that matters: these tests tell you *what* broke, the canary tells you *when*.
