# The standing environment — one site you never rebuild

*Every other environment in this repo is built fresh on purpose. Keep exactly one that isn't.*

The model is Chris Reynolds's [wpnext-test](https://github.com/jazzsequence/wpnext-test): a
Pantheon site that has existed for years, carries a deliberately gnarly plugin loadout, and is
upgraded **in place** to every Beta and RC by a weekly cron. It is never reinstalled. That
permanence is not laziness — it is the instrument.

## The bug class fresh fixtures cannot catch

This repo's fixtures are cattle: built from a known state, used, destroyed. That is right for
evidence — a finding on a fixture traces to a state you can name. But a fixture built this
morning **structurally cannot** have:

- options rows written by plugins deleted three years ago
- serialized meta in formats no current code writes
- tables created by an old plugin version and half-migrated by a newer one
- autoloaded option bloat that accumulated one row at a time
- user meta from accounts created under four different WordPress versions
- the residue of every previous upgrade, including the ones that half-failed

Real sites are made of exactly this. An upgrade routine that passes on clean state and breaks
on accumulated state ships broken for most of the installed base — and every fixture in this
repo will report PASS, honestly, because the failing input was never present. The [upgrade
ladder](../README.md#step-3-run-the-test-suites) varies the *starting version*; the standing
environment varies the *starting state*. You need both.

## The rules

1. **Never rebuild it.** A standing environment that gets reset "because it was in a weird
   state" has lost the only thing it was for. The weird state is the payload.
2. **Upgrade in place, every Beta and RC.** [Beta Tester](https://wordpress.org/plugins/wordpress-beta-tester/)
   in the admin, or `env_core_install` from the drivers. The moment
   [release watch](../.github/workflows/release-watch.yml) opens its issue, this site jumps.
3. **Snapshot before every jump.** `env_db_snapshot pre-<version>` — one command, and it turns
   "the upgrade broke something" into a diffable before/after instead of an anecdote. This is
   the one concession to safety: snapshot, never reset.
4. **Let state accumulate.** Install plugins, deactivate them, delete some, keep others active
   and outdated. Add content each cycle. Never spring-clean. The
   [debugging toolkit](../README.md#the-debugging-toolkit-works-with-any-option) belongs here
   permanently — deprecation notices in an aging site are exactly the early warning a new
   release cycle wants.
5. **Keep a ledger.** A `LEDGER.md` next to the site: date, what was installed or removed, which
   version jumped to which. Without it, a finding here is "something in my pile broke"; with
   it, the pile has provenance and the finding has a suspect list.

## What a finding here is, and is not

A failure on the standing environment is a **lead, not a filing**. The site's state is real but
not reproducible by anyone else, so the loop is:

1. The standing site breaks on upgrade → the ledger and the pre-jump snapshot narrow *which
   state* is involved.
2. Reduce it to the minimal state that still breaks — usually one plugin's rows, one option,
   one table.
3. Reproduce **that** on a fresh fixture (or a [blueprint](../playbooks/blueprint-repros.md)),
   and file it with the fixture, per [validation-and-proof](validation-and-proof.md).

Reported directly ("my old test site broke"), it is noise. Reduced first, it is the class of
report almost nobody else can produce, because almost nobody keeps a site like this.

## Designating one

Any driver works. The cheapest honest option is a Studio or Local site on your own machine —
name it so the intent is unmissable (`standing-do-not-reset`), exclude it from any cleanup
scripts, and point the suites at it with `--env=studio` when a cycle starts. A DDEV project
does the same with snapshots included. If you have real hosting, a standing staging site there
is strictly better — it adds the server dimension (real web server, real PHP build, real object
cache) that wpnext-test gets from Pantheon and no local driver can fake.

What it does **not** replace: the fresh fixtures. Evidence still comes from cattle. This is the
one pet, and its job is to get dirty.
