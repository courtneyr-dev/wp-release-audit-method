# Reproducible bug reports with Playground blueprints

*Turn "here are twelve steps" into a link that reproduces the bug in one click.*

The slowest part of fixing a bug is usually **reproducing it**. A triager reads your steps, builds an
environment, guesses at the parts you left implicit, and often can't get there. Reports die at that
step every day.

A [WordPress Playground](https://wordpress.org/playground/) blueprint removes it. It's a JSON file
describing a WordPress environment — version, PHP version, plugins, theme, content, and setup steps —
and Playground boots it in the browser from a URL.

> [!TIP]
> Attaching a blueprint to a Trac ticket is probably the single highest-leverage thing you can do to
> get a bug fixed. It converts "I can't reproduce this" into a click.

---

## The shape

```json
{
  "$schema": "https://playground.wordpress.net/blueprint-schema.json",
  "meta": {
    "title": "Repro: gallery block loses caption on save (Trac #12345)",
    "description": "Steps 1-3 are automated; step 4 is the manual action that fails.",
    "author": "your-wporg-username"
  },
  "preferredVersions": { "php": "8.3", "wp": "beta" },
  "steps": [
    { "step": "login", "username": "admin", "password": "password" },
    {
      "step": "installPlugin",
      "pluginZipFile": { "resource": "wordpress.org/plugins", "slug": "some-plugin" }
    },
    {
      "step": "importWxr",
      "file": { "resource": "url", "url": "https://example.com/repro-content.xml" }
    },
    {
      "step": "runPHP",
      "code": "<?php require_once '/wordpress/wp-load.php'; update_option( 'some_option', 'the value that triggers it' );"
    }
  ]
}
```

Launch it with:

```
https://playground.wordpress.net/?blueprint-url=<raw URL to your blueprint.json>
```

Host the JSON anywhere raw-servable — a gist, a repo, your own site. GitHub gists work well and are
easy for a triager to read before running.

---

## Writing a good repro blueprint

**Automate everything up to the failure, then stop.** The blueprint should land the user exactly one
action away from seeing the bug. Then your ticket says: *"click the link, then do this one thing."*

**Pin the version.** `"wp": "beta"` tracks the current beta, which is right during a release cycle
but means the blueprint stops reproducing once that beta ships. For a durable ticket, pin the exact
version — `"wp": "6.8"` — so it still reproduces in six months.

**Include the minimum.** Every plugin you add is a variable a triager has to rule out. If the bug
reproduces with no plugins, ship a blueprint with no plugins — that's a much stronger report.

**State what should happen.** A blueprint proves the environment, not the expectation. Your ticket
still needs expected vs actual.

**Say what Playground can't show.** It runs in the browser on WebAssembly with SQLite by default.
Anything depending on real MySQL, server headers, filesystem permissions, cron timing, or a specific
image library **won't reproduce there** — and a blueprint that appears to disprove a real bug is
worse than none. If your bug is in that category, say so and provide steps instead.

---

## Useful steps

| Step | For |
|---|---|
| `login` | Skip the login screen |
| `installPlugin` / `installTheme` | From the directory by slug, or a zip URL |
| `importWxr` | Load content — including [theme-test-data](https://github.com/WordPress/theme-test-data) |
| `runPHP` | Set options, create posts, register test fixtures |
| `setSiteOptions` | Change settings without PHP |
| `defineWpConfigConsts` | `WP_DEBUG`, `SCRIPT_DEBUG`, multisite constants |
| `enableMultisite` | Reproduce network-only bugs |
| `writeFile` | Drop in an mu-plugin that instruments the failure |

An mu-plugin via `writeFile` is a strong pattern: log exactly the state you claim is wrong, so the
triager sees your evidence rather than taking your word.

---

## Beyond bug reports

**Testing a Beta or RC.** The [official beta-rc blueprint](https://github.com/WordPress/blueprints/tree/trunk/blueprints/beta-rc)
boots a loaded test site with content and debugging plugins —
[covered in the main guide](../README.md#option-b--wordpress-playground-fastest-possible-start).

**Sharing a test scenario.** A blueprint is a reproducible fixture. If your team runs the same setup
each cycle, that's a blueprint rather than a wiki page of steps.

**Plugin and theme authors** — ship a blueprint in your repo that boots your extension with demo
content. It's a live demo, an onboarding aid, and a support tool at once: *"does it happen here
too?"* is a much faster diagnostic than a screenshot exchange.

**Confirming someone else's report.** Rewriting a prose report as a blueprint is genuinely useful
triage work — either it reproduces and you've made the ticket actionable, or it doesn't and you've
learned something specific about what else is involved.

---

## Checklist

```markdown
- [ ] Blueprint boots to one action before the failure
- [ ] WordPress and PHP versions pinned (or `beta` deliberately, and noted)
- [ ] Minimum plugins — every extra one is a variable
- [ ] Expected vs actual stated in the ticket, not just the blueprint
- [ ] Noted whether the bug is Playground-reproducible at all (MySQL, headers,
      filesystem, cron, image libraries → probably not)
- [ ] JSON is raw-servable and I clicked the launch URL myself
```

## Related

[How to report](../README.md#how-to-report-what-you-find) ·
[Slack test-report template](slack-test-report-template.md) ·
[Playground docs](https://developer.wordpress.org/playground/) ·
[Blueprint gallery](https://wordpress.github.io/blueprints/) ·
[Make/Playground](https://make.wordpress.org/playground/)
