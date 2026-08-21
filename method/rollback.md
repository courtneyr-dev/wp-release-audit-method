---
title: "Rollback — a procedure, not a checklist line"
type: method
status: active
created: '2026-08-21'
updated: '2026-08-21'
tags:
  - wordpress
  - release-audit
  - rollback
  - recovery
related:
  - '[ecosystem-compatibility-lane](ecosystem-compatibility-lane.md)'
  - '[standing-environment](standing-environment.md)'
---

# Rollback

The 64-check form has carried *"Rollback / reactivate previous version"* since it existed,
with nothing behind it — a line whose emoji nobody could honestly fill, because there was no
procedure to execute. This is the procedure. On 7.1 release day the only real remedy for a
fleet of fataled sites was one of the escape hatches below, executed under time pressure, by
people discovering them one support ticket at a time.

Each section says whether it has been executed. **A recovery path you have never run is a
hypothesis about your worst day.**

## The decision, before any mechanics

Three moves, in rising order of cost. Pick by where the fault is and what's dead:

| Situation | Move |
|---|---|
| One plugin fatals; core is fine | **Deactivate the plugin.** Never roll back core for a plugin's bug — you'd re-expose the site to whatever the release fixed, to work around code that isn't core's |
| The plugin is load-bearing (cart, cache, membership) and a fixed version exists | **Hotfix forward** — update the plugin, not core. WP Rocket's fix shipped in ~26 hours; sites that rolled core back then had two problems |
| Core itself broke the site and no plugin is implicated | **Restore from backup.** There is no supported downgrade from a major WordPress release — "rollback" of core means the backup you took before upgrading, and that's a conversation about how old the backup is, not a button |

## Escape hatch 1 — deactivate via WP-CLI when WP-CLI itself is dead — EXERCISED

The trap that made 7.1 day expensive: a fatal on `init` kills WP-CLI too, because wp loads
WordPress — so the ordinary `wp plugin deactivate` dies with the same fatal it's trying to
cure. The escape is to load WordPress *without* the broken plugin:

```bash
wp plugin deactivate wp-rocket --skip-plugins=wp-rocket
```

`--skip-plugins=<slug>` excludes only that plugin from loading; the deactivation then writes
`active_plugins` normally. `--skip-plugins` alone (no value) skips all plugins, which also
works and is easier to remember at 2 a.m.

**Exercised 2026-08-21** on a disposable DDEV fixture running 7.1: a plugin fataling on
`init` made every plain wp command exit nonzero with the plugin's fatal; the `--skip-plugins`
form deactivated it on the first try and the site answered 200 immediately after. Evidence
in the walkthrough log for this repo's happy-path proof.

## Escape hatch 2 — folder rename, the no-shell path — EXERCISED

Shared hosting with no SSH: rename the plugin's directory over SFTP or the host file
manager.

```
wp-content/plugins/wp-rocket  ->  wp-content/plugins/wp-rocket.disabled
```

WordPress detects the missing plugin file on the next load and deactivates it (you'll see
"Plugin file does not exist" in the admin). The site comes back without a single line of
shell.

**Exercised 2026-08-21** on the same fixture: rename brought the front end back on the next
request.

Renaming the whole `plugins/` directory works the same way when you don't know which plugin
is at fault — cruder, but it turns "site down" into "site up, all plugins off," which is a
better place to debug from.

## What NOT to do — the surgical deletion trap

Do **not** delete the single offending file (on 7.1 day: `Cloudflare.php`) out of a plugin
that fatals. Modern plugins wire classes into a dependency-injection container; removing one
file swaps the original fatal for a class-not-found fatal and adds a corrupted plugin
install to your problems. Deactivate whole plugins, never amputate files.

## Core rollback mechanics, for when it's genuinely core — UNEXERCISED

Not one line of this section has been executed by this repo. It's here because the checklist
line implies it, and the honest state is written down rather than implied:

- **Files:** replacing a 7.1 tree with a 7.0.x tree is mechanically possible (re-run the
  updater against the old zip, or restore files from backup).
- **Database:** `db_version` does not migrate downward. If the major ran schema migrations,
  the old code meets a new schema; WordPress mostly tolerates a *newer* db_version, but
  nothing guarantees it, and `wp core update-db` has no downgrade.
- **Content:** anything written by new-version features after the upgrade — new block
  markup, new meta, new tables — is **not recoverable** into the old version's
  understanding. A restore-from-backup loses everything written since the backup; a
  files-only downgrade keeps the data but the old code may not read it.
- The supported story is and has always been: **backup before upgrading; rollback = restore
  that backup; accept the data loss window.** Any procedure claiming better than that on a
  major release should be treated as unexercised marketing until you've run it on a
  disposable fixture.

Exercising this section — old zip over a new tree on a fixture with seeded content, then a
content diff — is a well-shaped afternoon contribution.

## The checklist line, redefined

From now on the *"Rollback / reactivate previous version"* line renders from a cell that
means: **the two exercised escape hatches above were executed on this release's fixture.**
Not "we believe rollback would work" — the hatches ran. The core-rollback section stays
UNEXERCISED and the line does not claim it.
