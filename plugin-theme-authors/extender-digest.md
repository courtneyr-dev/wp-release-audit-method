# The extender digest

*Dev notes are written for core contributors. This is the shape they need to be in for everyone else.*

Every cycle, WordPress publishes dozens of dev notes across weeks. They're thorough, they're
authoritative, and they're organized by **who built the change** rather than by **what an extension
author has to do about it**.

So every plugin and theme author independently reads the same thirty posts and builds the same flat
list. This page is the template for building that list once — and the format is deliberately
greppable, because it's the input to
[the release-diff method](release-diff-method.md#step-2--build-the-release-change-inventory).

---

## How to build one

**Sources, in order.** All from [the official register](../sources/official-sources.md):

1. [The Field Guide](https://make.wordpress.org/core/tag/field-guide/) — published around RC1, links
   every dev note for the release. Start here; it's the index.
2. [Dev notes](https://make.wordpress.org/core/tag/dev-notes/) — the detail.
3. [Trac milestone](https://core.trac.wordpress.org/) — what actually shipped. **A closed ticket is
   not proof it's in the package.**
4. The package itself — when a note and the build disagree, the build wins.

**The extraction rule.** For each note, write down *every name it mentions* — functions, hooks,
classes, options, capabilities, packages, CSS classes, REST routes — and which bucket it belongs in.
Don't summarize the change yet. You're building nouns to grep for.

**The four buckets** are what make it useful:

| Bucket | Question it answers |
|---|---|
| **Removed / deprecated** | Will this stop working? |
| **Changed behavior** | Will this work *differently* and not tell me? |
| **New APIs** | What can I now delete from my own code? |
| **Editor / packages** | Does my block or editor extension still load? |

The second bucket is the dangerous one. Removals announce themselves at runtime; **changed defaults
and changed return shapes do not.** A dev note is your only warning.

---

## The template

Copy this per release. Keep the names in backticks so they grep cleanly against a surface inventory.

````markdown
# WordPress <VERSION> — what changed for extension authors

Sources: Field Guide <link> · dev notes tag <link> · Trac milestone <link>
Compiled <date> against <build actually read>. Anything marked ⚠ is unverified against a package.

## TL;DR — highest impact for extenders

1. …
2. …
3. …

## Removed or deprecated

| Symbol | Type | Replacement | Notes |
|---|---|---|---|
| `old_function_name()` | function | `new_function_name()` | Dev note: <link> |
| `old_hook_name` | filter | `new_hook_name` | Arguments changed too |

→ Grep your surface inventory for every name in this column.

## Changed behavior — same name, different result

| Symbol | What changed | How you'd notice |
|---|---|---|
| `some_function()` | Default for `$arg` flipped to `true` | Nothing errors; output differs |
| `some_filter` | Now receives a 4th argument | Your callback silently ignores it |

→ **No runtime warning exists for these.** This table is the only warning.

## New APIs worth adopting

| API | Replaces your… | Requires | Notes |
|---|---|---|---|
| `wp_new_thing()` | hand-rolled equivalent | WP <version> | Raises your floor — decide deliberately |

→ Feeds [the adoption pass](adopting-new-apis.md).

## Editor and @wordpress packages

| Package | Change | Impact |
|---|---|---|
| `@wordpress/components` | `<Thing>` removed | Editor UI breaks; migrate to `<NewThing>` |

→ Check the console on every editor screen, not just `debug.log`.

## Themes

| Surface | Change |
|---|---|
| theme.json | New setting `settings.x.y`; schema still v3 |
| Block markup | `core/x` serializes `color` differently — deprecations may be needed |

## Database and schema

| Change | Affects |
|---|---|
| `db_version` bumped to N | Sites querying tables directly get no warning |

## Verification status

| Claim | Verified how |
|---|---|
| Everything above | Read from dev notes on <date> |
| ⚠ items | Announced but not confirmed against a package |

## Flat name list — for grepping

```
old_function_name
old_hook_name
some_function
some_filter
wp_new_thing
```
````

That last block is the point of the whole document. Save it as `changed-names.txt` and:

```bash
bash ../scripts/wp-surface-inventory.sh . --csv > surfaces.csv
grep -Ff changed-names.txt surfaces.csv
```

Every line that comes back is a required test. That's the whole intersection, in one command.

---

## Rules that keep it trustworthy

**Cite every row.** A digest without links is a rumor. Link the dev note per entry.

**Separate announced from verified.** A dev note describes intent at the time of writing. Features
get punted between beta and GA — it happens every cycle. Mark anything you haven't confirmed against
an actual package with ⚠, and re-check at RC.

**Say when you compiled it and against which build.** A digest written at Beta 1 and read at RC2 is
stale in specific, invisible ways.

**Don't editorialize in the tables.** Put your opinion in the TL;DR. The tables are reference
material other people will grep — keep them mechanical.

**Record what you couldn't verify.** "Announced but I couldn't reproduce it" is useful information.
"Silence" is not.

---

## Doing this in public

If you compile one of these, publishing it is high-leverage — every other extension author is
otherwise duplicating your work. Reasonable homes: your own blog with a link from
[`#core-test`](https://make.wordpress.org/chat/), a gist, or a contribution to the
[Make/Test handbook](https://make.wordpress.org/test/handbook/).

Two things to get right if you do:

- **Link the dev notes, don't replace them.** You're an index, not a substitute — and the dev note is
  the authoritative source if you got something wrong.
- **Date it and version it prominently.** Someone will find it two releases later.

## Related

[Release-diff method](release-diff-method.md) — where the flat list gets used ·
[Adopting new APIs](adopting-new-apis.md) — where the "new APIs" bucket goes ·
[Official sources](../sources/official-sources.md)
