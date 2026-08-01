# Testing alongside the plugins your users actually run

*The biggest hole in every static method: the bug isn't in your code or core's — it's in the seam.*

Your plugin can be perfectly compatible with WordPress and still break, because it runs beside
something else the release also changed. No amount of reading your own source finds that.

The good news: you don't need to test against thousands of plugins. You need **three**, and you can
work out which three from public data in about ten minutes.

---

## Finding your actual three

### 1. Your support channels already know

Read your last fifty support threads and count which other plugins get mentioned. This beats any
statistic, because it's *your* users, and a plugin that generates support load is a plugin that
interacts with yours.

Search your forum, issue tracker, and inbox for "conflict", "along with", "when I activate", and
"stopped working after".

### 2. Category leaders in your niche

Sort [the plugin directory](https://wordpress.org/plugins/) by your tags and look at active
installation counts. If you're an SEO plugin, the page builders matter. If you're a forms plugin,
the caching plugins matter.

### 3. The ones almost everyone has

Some plugins are near-universal, so a conflict with them is a conflict with a large share of
WordPress sites. Check active install counts on the directory — the top of any "popular" listing is
the current answer, and it does shift.

Categories that reliably matter regardless of what you build:

| Category | Why it interacts with almost everything |
|---|---|
| **Caching / performance** | Cached output, deferred scripts, and object caching change *when* your code runs and whether your changes are visible |
| **Page builders** | Replace the editor, the render path, or both |
| **SEO** | Filter `the_content`, `wp_head`, and post meta — high collision surface |
| **Security / firewall** | Block requests, strip headers, disable REST routes, restrict capabilities |
| **eCommerce** | Add post types, roles, capabilities, and their own REST namespace |
| **Multilingual** | Duplicate posts and terms, and rewrite URLs |
| **Membership / access control** | Override capability checks — the most likely to break your permission assumptions |

> [!TIP]
> If you can only test one category, test **caching**. It changes the timing and visibility of
> everything, and "works for me but not for the user" is very often a caching interaction.

### 4. Ask

A one-line post — *"what else do you run alongside this?"* — in your support forum or changelog will
get you a better list than any guess. It also tells users you're testing for them.

---

## Setting up the matrix

Add them to your `wp-env` config so a full environment is one command:

```json
{
  "core": "WordPress/WordPress#master",
  "plugins": [ ".", "https://downloads.wordpress.org/plugin/some-plugin.latest-stable.zip" ],
  "env": {
    "tests": {
      "plugins": [ "." ]
    }
  }
}
```

Any directory-hosted plugin is available at:

```
https://downloads.wordpress.org/plugin/{slug}.latest-stable.zip
https://downloads.wordpress.org/plugin/{slug}.{version}.zip
```

Or with WP-CLI against a disposable site:

```bash
wp plugin install plugin-a plugin-b plugin-c --activate
```

> [!CAUTION]
> **Pin versions for reproducible runs.** `latest-stable` means your test environment changes
> underneath you, and a failure you can't reproduce tomorrow is worse than no test. Use
> `latest-stable` for a canary, pinned versions for anything you'll debug.

---

## What to test in the seam

You're not re-testing your whole plugin against each one. You're testing the specific places two
plugins can collide.

| Collision | What to check |
|---|---|
| **Hook priority** | Both filter `the_content`. Does order change your output? Try activating in each order |
| **Shared option or meta keys** | Unprefixed keys collide. Your surface inventory lists yours — grep theirs |
| **Asset handles** | Two plugins registering `select2` at different versions. Whoever enqueues first wins |
| **REST namespace** | Route collisions, or a security plugin disabling REST entirely |
| **Capability overrides** | A membership plugin filtering `user_has_cap` changes what your checks return |
| **Post type / taxonomy** | Same slug registered twice — the second one silently loses |
| **Cron** | Another plugin clearing hooks broadly can unschedule yours |
| **Output buffering** | Optimization plugins buffer and rewrite the whole page, including your markup |

### The minimum viable interaction test

For each of your three, four steps:

1. **Activate both.** Any fatal? Any admin notice that wasn't there before?
2. **Run your primary feature.** Does it still work end to end?
3. **Read `debug.log`.** New notices that appear only with both active are the interaction.
4. **Toggle activation order.** Deactivate both, activate in the opposite order, repeat. Hook
   registration order changes with activation order, and that alone flushes out priority bugs.

Step 4 is the one people skip, and it's cheap.

---

## Automating it

Add a CI job that runs your suite with your three installed:

```yaml
  co-installed:
    name: With common plugins
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        companion:
          - 'plugin-slug-a'
          - 'plugin-slug-b'
          - 'plugin-slug-c'
    steps:
      - uses: actions/checkout@v4
      # ... your usual PHP + test-suite setup ...
      - name: Install the companion plugin
        run: |
          wp plugin install ${{ matrix.companion }} --activate --allow-root
      - name: Run tests with it active
        run: composer run test || vendor/bin/phpunit
```

`fail-fast: false` matters — you want to know about all three, not just the first to break.

> [!NOTE]
> **Expect some noise.** Other plugins have their own deprecations and notices, and those will show
> up in your log. Learn to read *whose* code triggered what — the
> [deprecation mu-plugin with stack traces](release-diff-method.md#runtime-deprecation-capture)
> makes that immediate.

---

## When you find one

Interaction bugs have three possible owners, and picking the right one saves everybody time:

| Where the fault is | What to do |
|---|---|
| **Yours** — unprefixed key, wrong hook priority, unguarded assumption | Fix it. Prefix everything; never assume you're alone |
| **Theirs** — they're overriding something they shouldn't | File in their tracker with a minimal reproduction. Be specific and kind; they're in the same position you are |
| **Core's** — the release changed something that made two reasonable behaviors collide | [File on Trac](https://core.trac.wordpress.org/) with both plugins named and the exact versions |

For the middle case: a reproduction that installs both plugins from the directory at pinned
versions, on a clean install, with numbered steps, is the difference between a fix and a thread that
dies.

## Related

[Plugin & theme guide](README.md) · [Release-diff method](release-diff-method.md) —
this is the "not covered" item it names · [CI workflows](ci/) · [Starter tests](starter-tests/)
