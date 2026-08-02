# Environment drivers

Pick where WordPress runs. The suites don't care.

```bash
bash scripts/crud-suite.sh --env=ddev ~/wp-test
bash scripts/crud-suite.sh --env=playground ~/wp-test
bash scripts/crud-suite.sh --env=cli "~/Local Sites/mysite/app/public"
```

Or set `WP_AUDIT_ENV=ddev` once and drop the flag.

## Why this exists, and why it isn't just a compatibility shim

These environments are not equivalent, and pretending otherwise produces confident
nonsense.

Playground has no shell at all, so any cell that writes a file into the document root is
unreachable there. It also has no HTTPS and cannot do subdomain multisite — Playground's
own `enableMultisite` throws on a custom port. wp-env has no HTTPS either, so `is_ssl()`
and secure-cookie bugs are invisible to it. A remote staging box has no host-readable
document root, so no file-tree diff is possible at all. And a DDEV project under `$TMPDIR`
on macOS silently cannot snapshot — configured, and broken.

> **A worked example of why these are probed and not assumed.** An earlier draft of this
> file asserted that Playground "structurally cannot" reach WordPress's own updater, and
> therefore could never reproduce this repo's best-known finding — 243 files left behind
> by the Core updater while WP-CLI cleaned all 243 and said so. That was wrong. Inside the
> WASM sandbox `WP_Filesystem()` initialises as `WP_Filesystem_Direct`, `api.wordpress.org`
> answers, and `Core_Upgrader::upgrade()` pulls the real partial-update package and
> rewrites the mounted document root. The claim was plausible, widely believed, and
> refuted the first time anyone ran it. That is the entire argument for `env_driver_caps`
> probing rather than declaring.

`scripts/preflight-sensitivity.sh` already exists because **a test that passes on an
environment that couldn't have detected the failure is not evidence.** That argument
applies to the environment tool at least as much as it applies to your zip library. So a
driver has two jobs: run commands, and **declare what it cannot do**. A cell that needs a
capability the driver lacks reports `BLOCKED` with the capability named — never `PASS`.

That's the whole design. Everything below is mechanics.

## Capabilities

| Token | Means |
|---|---|
| `hostfs` | Document root readable from the host, synchronously |
| `hostfs-synced` | Readable, but **asynchronously** — call `env_sync` before hashing or diffing |
| `core-updater` | WordPress's **own** updater is reachable, not just WP-CLI's. Stale-file findings need this |
| `db-reset` | Can empty the database |
| `snapshot` | Can snapshot **and restore** the database — a real round trip, not a one-way dump |
| `php-switch` | PHP version is a parameter, not a rebuild |
| `core-zip` | Can install an arbitrary core version or zip |
| `multisite-subdir` | Can convert to subdirectory multisite |
| `multisite-subdomain` | Can convert to subdomain multisite. Needs real hostnames — WP-CLI refuses this on `localhost:PORT`, so most drivers can't |
| `https` | Serves over TLS |
| `xdebug` | Xdebug can be toggled |
| `shell` | Arbitrary shell commands run inside the environment |
| `nginx` / `apache` | Web server actually in use |
| `mysql` / `mariadb` / `sqlite` | Database engine actually in use |

Check them from a script:

```bash
. scripts/lib-env.sh
env_init ddev ~/wp-test

env_caps                              # everything this driver can do
env_has snapshot && echo "reusable"   # quiet test
env_require T1-44 core-updater || return   # prints BLOCKED and returns 2
env_caps_report                       # the block preflight prints
```

## Writing a driver

DDEV is the **reference implementation** — it supports every capability above, so read
[`ddev.sh`](ddev.sh) first and describe your driver as a delta from it.

Define two functions:

```bash
env_driver_init() { … }   # 0 when ready; 1 plus a helpful stderr message otherwise
env_driver_caps() { … }   # echo space-separated capability tokens
```

Then override only what your tool can actually do:

```
env_start  env_stop  env_destroy  env_wp  env_exec  env_docroot  env_url  env_sync
env_db_reset  env_db_snapshot  env_db_restore  env_php_get  env_php_set
env_core_install  env_multisite_convert
```

Anything you don't override falls back to a loud "unsupported" error from
`lib-env.sh`. **That is the correct outcome** for something your tool can't do. Never
stub a fake success.

### Rules, in order of how much damage breaking them does

1. **Never over-claim a capability.** Under-claiming costs you a few `BLOCKED` cells.
   Over-claiming corrupts results and you won't know it happened.
2. **Probe, don't assume.** A capability can be configured-but-broken. DDEV snapshots
   fail under `$TMPDIR` on macOS with a permission error from the db container; a driver
   that declared `snapshot` from config alone would advertise something that doesn't
   work.
3. **`env_wp` must propagate WP-CLI's exit status.** The tempting one-liner
   `cmd | tr -d '\r'` returns *tr's* status — always 0 — which silently disables every
   `env_wp … || fallback` in every suite. Capture the output, then clean it.
4. **`env_exec` takes argv, not a shell string.** If your tool re-parses the command
   through a shell, disable that (DDEV needs `--raw`). Double-parsing eats inner quotes,
   and the symptom isn't an error — the command does nothing and the cell reports an
   empty result that reads like a WordPress failure.
5. **If your driver needs a change to `lib-env.sh`, say so instead of making one.** That
   would mean the interface leaked assumptions from another tool, and it's worth fixing
   properly rather than working around.

### Check your driver against the contract

```bash
bash scripts/env/conformance.sh mydriver
```

Needs no WordPress, no container, and not even the tool your driver drives — it stubs the
binary and checks what your driver reports back. It covers the rules above that can be
checked mechanically, and rule 3 is the one it exists for: it fails a driver whose
`env_wp` swallows the exit status, which is silent, valid shell that turns every failure
into a `PASS`.

`check-repo.py` runs it over every driver, so CI will catch this before a reviewer does.
A check it cannot perform reports `skip`, never `ok`.

### House rules

`#!/bin/bash` shebang and a description comment block (CI enforces both). No absolute
paths. Must pass `bash -n` and `shellcheck -S error`. Comment *why*, not *what*.

One bash trap worth knowing, since drivers are full of command substitution: **an
apostrophe inside a comment within `$( … )` breaks the parse.** Bash respects quoting
while scanning for the closing paren, so `# doesn't` opens a string that never closes and
the whole file fails `bash -n` at its last line. Put the comment above the substitution.

State plainly in the header comment what you verified and what you didn't. An untested
driver is fine and useful; an untested driver that reads as tested is not.
