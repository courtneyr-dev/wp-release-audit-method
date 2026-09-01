# Upstream techniques — what this repo borrows, and how it keeps looking

[`official-sources.md`](official-sources.md) answers *where authoritative WordPress
information lives.* This page answers a different question: **what third-party work this
method is built on, and how we notice when that work moves.**

This repo borrows, deliberately. The release detector's feed-scraping approach comes from
Chris Reynolds's wpnext-test. The [preflight core probe](../method/preflight-core-probe.md)
is documented from Austin Ginder's CaptainCore. The
[update-day runbook](../fleet-operators/README.md#5-the-update-day-runbook) is Mike Miler's
sequence. None of that is a weakness — a method that only trusts what it invented is a
method with a very small corpus. But borrowing has a maintenance cost that citations alone
don't pay.

## The three ways a borrowed technique rots

1. **The attribution goes stale.** You write "MIT" once and it stays written. See the
   worked example below, which is this register's first finding and is about this repo.
2. **The technique's limits shift.** A page here says a tool "does not handle X." Upstream
   ships X. Now the honest-limits section — the part this repo values most — is a
   confidently-stated falsehood, and nobody notices because the citation still resolves.
3. **You read one file and never came back.** CaptainCore's `lib/remote-scripts/`
   held 58 scripts on the day one of them became [a method page](../method/preflight-core-probe.md).
   The other 57 include `component-hashes`, `plugin-diff`, `php-in-uploads`, `db-code-audit`,
   and a dozen `detect-*` scripts that plainly touch this repo's security and stale-file
   lanes. Not reviewing them is a choice; not *recording* that they're unreviewed is how
   the choice becomes invisible.

## The register

[`upstream-watch.csv`](upstream-watch.csv). One row per upstream path we adapt from:

| Column | What it holds |
|---|---|
| `watch_id` | Stable id, cited from wherever the technique landed |
| `upstream`, `path` | `owner/repo` and the subpath to watch (blank = whole repo) |
| `license`, `author` | **Verified from the upstream's own LICENSE file**, not from its README, not from a GitHub badge, not from memory |
| `why_we_watch` | Why this is worth a standing check, including what's *unreviewed* |
| `integrated_into` | The files here that already carry something from it |
| `baseline_sha`, `baseline_date` | The last commit a human actually reviewed |
| `status` | `active` · `paused` · `retired` |
| `notes` | Licence compatibility, corrections, and anything the next reader needs |

**`baseline_sha` means "someone looked," not "someone integrated."** A commit reviewed and
judged irrelevant still moves the baseline. That is the whole point — the register
distinguishes *checked and cleared* from *never opened*, which is the same distinction
[ecosystem-signals](../method/ecosystem-signals.md) draws for news.

## The mechanism

```bash
python3 scripts/upstream-watch.py            # what has landed since we last looked?
python3 scripts/upstream-watch.py --control  # positive + negative + unknown-baseline, offline
python3 scripts/upstream-watch.py --update   # AFTER review: move baselines, then commit
```

Exit `0` clean, `3` drift found, `2` nothing active, `1` error — the same convention as
[`check-latest-release.sh`](../scripts/check-latest-release.sh), so CI can branch on a
result without treating it as a failure.

[`.github/workflows/upstream-watch.yml`](../.github/workflows/upstream-watch.yml) runs it
weekly and keeps **one** open issue, rewriting its body as things land. A fresh issue every
Monday trains everyone to close it unread; one issue that grows is a queue.

The controls run offline against [`fixtures/upstream/`](../fixtures/upstream/) and are wired
into the workflow *before* the live check, because a watcher whose controls need the network
quietly becomes a rubber stamp the first week the network is flaky. They assert three
things: a stale baseline reports exactly the expected drift, a current baseline reports
none, and a baseline that isn't in the fetched history is flagged as **truncated** rather
than reported as full drift — because an unfindable baseline can mean a force-push, and
"100 new commits" for a rebase is a lie the register would then carry forward.

## The review question

Not "is this new upstream code good." It is:

- Does anything here **change a limit this repo has written down?**
- Does anything here **contradict an attribution** — licence, authorship, provenance?
- Does anything here **cover a lane we left `BLOCKED` or unexercised?**
- Is there a technique worth a method page, on the
  [ecosystem-signals](../method/ecosystem-signals.md) pipeline — signal → candidate →
  adjudicated → method change, with **checked-and-cleared** as a real outcome?

Then move the baseline and commit, whichever way it went.

## Licence discipline

This repo is **GPL-2.0**. That constrains what can come in:

| Upstream licence | Can we adapt from it? |
|---|---|
| MIT, BSD, Apache-2.0 | Yes — permissive into GPL is one-way compatible. Carry the copyright notice with the adapted work |
| GPL-2.0 / GPL-2.0-or-later | Yes |
| GPL-3.0-only | **No** — incompatible with this repo's GPL-2.0 |
| Proprietary, unlicensed, no LICENSE file | **No.** "It's on GitHub" is not a licence |

Two rules that are cheap and keep this honest:

1. **Read the upstream's LICENSE file yourself.** Not the README, not the badge, not
   GitHub's auto-detection — it returns `NOASSERTION` for anything it can't classify, and
   `NOASSERTION` is not a licence, it's a prompt to go look.
2. **Prefer documenting the technique to vendoring the code.** A method page with adapted
   excerpts and a link to the original credits better, stays accurate longer, and doesn't
   fork a maintenance burden onto a repo that can't test it.

## The worked example — this repo got one wrong

Building the register found it immediately, which is the argument for the register.

From 2026-08-11, `scripts/check-latest-release.sh` credited
[jazzsequence/wpnext-test](https://github.com/jazzsequence/wpnext-test) as **MIT**. It is
not. Its `license.txt` is WordPress core's **GPL-2.0-or-later** text — the repo is a
Pantheon WordPress upstream, so it carries core's licence — and there is no MIT declaration
anywhere in it. GitHub's licence API returns `NOASSERTION`, which is exactly the signal that
should have sent someone to the file.

**No compliance consequence** — GPL into GPL, and the adaptation was a technique rather than
a copy. But a stated fact was wrong for twelve days in a repo whose entire argument is that
stated facts need receipts, and it was wrong in a *header comment*, the least-read and
longest-lived place a claim can hide. Corrected 2026-08-23 and recorded in the register's
`notes`, because [a refuted claim is an asset](../method/release-audit-learning-loop.md) and
deleting the mistake would delete the reason the check exists.

## Review log — CaptainCore `lib/remote-scripts`, 2026-08-24

The first pass over the backlog the register recorded. **57 scripts** (the register previously
said 58 — miscount, corrected). Read in full: `component-hashes`, `php-in-uploads`,
`plugin-diff`, `update-core`. The rest were triaged by their header comments, which in this
codebase are unusually good — most state the invariant they rest on in the first three lines.
Triaged-by-header is a weaker reading than read-in-full and the verdicts below say which.

Nothing here is adopted yet. Per [ecosystem-signals](../method/ecosystem-signals.md), a
review produces **candidates**, not method changes; each still needs adjudication and
controls before it becomes a cell.

### Candidates — these touch a lane this repo already has

| Script | Why it's a candidate | Lands in |
|---|---|---|
| `detect-database-triggers` | *"Stock WordPress has ZERO triggers, events, and stored routines."* A clean stated invariant, and the persistence class that survives plugin reinstalls, core reinstalls, password resets and salt shuffles — file-based cleanup never touches it | [security invariants](../method/security-invariants.md) |
| `detect-binary-payloads` | *"A WordPress site is PHP + assets."* ELF binaries, `.so`, and `.socket` files in the document root break that invariant, and being non-PHP they are invisible to checksum scans and to `php-in-uploads` | [security invariants](../method/security-invariants.md) · [attack surfaces](../method/wordpress-attack-surfaces.md) |
| `component-hashes` | Deterministic per-component SHA-256 over plugins/themes/mu-plugins — and it hashes symlinks as `SYMLINK:<target>`, so a swapped symlink changes the hash. A content-only hash does not. That detail is the whole value | the stale-file and upgrade-artifact work behind `stale_file_check.py` |
| `plugin-diff` | Unified diff of an installed plugin against a clean wordpress.org copy. Explicitly the follow-up to a failed `wp plugin verify-checksums` — *what changed*, not just *something changed*. This repo needed exactly that for **core** on 2026-08-24 and had no tool for it | [release-diff method](../plugin-theme-authors/release-diff-method.md) |
| `detect-fake-dates` | Files whose `mtime` is older than their birth time — a forged timestamp, which is also a way an upgrade-artifact assertion gets quietly fooled | upgrade-artifact assertions |
| `detect-elevated-permissions` | Non-admin roles holding `manage_options`/`edit_plugins`, and capabilities injected directly into usermeta — a capability-boundary invariant, which is the shape this repo's security lane prefers | [security invariants](../method/security-invariants.md) |
| `db-code-audit` | Executable code stored in options, WPCode snippets, and widgets — bypasses every file-based scanner by construction | [attack surfaces](../method/wordpress-attack-surfaces.md) |
| `detect-user-enumeration` | Anonymous HTTP checks for username exposure via REST, oEmbed, sitemaps, `?author=N`, xmlrpc, and `wp-login.php` differential responses. Notably **testable on a disposable fixture** — no fleet required | [attack surfaces](../method/wordpress-attack-surfaces.md) |

### Interesting, but not this repo's lane

`malware-hunt` (a standalone scanner, far past release auditing), `detect-seo-spam`,
`detect-seo-cloaking`, `detect-web3-injection`, `detect-upload-probes`,
`detect-forged-registrations`, `detect-malformed-passwords`, `php-in-uploads`,
`quicksave-fingerprint`, `fetch-users-logins`, `file-manager`. Real work, aimed at
compromise response rather than at whether a release is correct. Revisit only if this repo
ever grows an incident-response lane.

### Checked and cleared — fleet operations, not testing

`activate`, `deactivate`, `apply-https`, `apply-https-with-www`, `archive-logs`, `arguments`,
`check-security-log-size`, `db-backup`, `db-convert-to-innodb`, `db-import`, `deploy-fathom`,
`deploy-helper`, `deploy-mailgun`, `email-health-check`, `fetch-database-tables`,
`fetch-error-log-size`, `fetch-folder-size`, `fetch-log-file`, `fetch-log-files`,
`fetch-site-data`, `fetch-token`, `kickstart`, `launch`, `master-db-query`, `migrate`,
`performance-monitor-deploy`, `performance-monitor-remove`, `plugins-zip`,
`prepare-wordpress`, `report-compromised-passwords`, `reset-permissions`,
`restic-cache-check`, `restic-cache-purge`, `rewrite-prep`, `update`, `vault`,
`verify-google-analytics-takeover`.

Cleared is a **result**, not an absence of one — it is what stops the next reader spending
the same afternoon. `update-core` is [already adopted](../method/preflight-core-probe.md).

### The pattern worth naming

Six of the eight candidates open by stating an invariant — *stock WordPress has zero
triggers*, *a WordPress site is PHP plus assets* — and then detect its violation. That is
[the security lane's own rule](../method/security-invariants.md) (audit broken invariants,
not dangerous sinks) arrived at independently by someone doing incident response on a fleet.
Where two practices converge from different directions, the rule is usually load-bearing.

## Review log — CaptainCore `lib/remote-scripts`, second cycle, 2026-09-01

Raised by [the watch](../.github/workflows/upstream-watch.yml) as issue #8. Seven commits
since the 2026-08-23 baseline, all on `update-core`. Read the combined diff (541 lines)
rather than the commits individually.

**Four adopted into [`core-preflight-probe.sh`](../scripts/core-preflight-probe.sh), and two
of them were live bugs in our copy:**

| Upstream | What it fixes here |
|---|---|
| `6d8feb90` *false fails from WP-CLI noise* | Our `run_wp` merged stderr into **every** captured value, so a deprecation notice could land inside `$LIVE_VERSION` or `$DB_BEFORE` and turn a comparison into nonsense. Split into `wp_value` (stdout only, last non-empty line) for state reads and `run_wp` for probe runs, which genuinely want stderr |
| `3ea666c8` / `5a06d218` *keeps THROW lines, false HTML fatals* | Our fatal pattern was `/(Fatal error\|Parse error\|Uncaught )/i` — it matches any page that merely **mentions** those words, so a post about debugging reads as a fatal. Tightened to the real shape. Also drains `ob_get_level()` and removes `wp_ob_end_flush_all`, so a `THROW:` isn't buried under flushed HTML |
| broadened `wp-settings` regex | Ours matched only `require ABSPATH . 'wp-settings.php'`. A `wp-config.php` using the `__DIR__` or `dirname(__FILE__)` form would keep its require and load core twice |
| memory-exhaustion detection | Distinguishes "the runner ran out of memory" from "the target fatals" — a harness fault, not a result |

**Not adopted:** `bd7ae051` (stores runs on CaptainCore's Manager), `9b3dad05` (WP Freighter
tenants), `df28e923`'s SSH-loopback specifics, `c60f505e` (`--version=next` picks RC → beta →
nightly; [`check-latest-release.sh`](../scripts/check-latest-release.sh) already answers that
question with its own cycle check). Checked and cleared.

**What the cycle bought beyond the fixes:** the HTTP half of the probe now exists, a
[third control](../fixtures/plugins/) guards the WP-CLI scoping artifact, and a control
failure exposed a race of our own — see
[the probe page](../method/preflight-core-probe.md#the-http-half-and-a-third-control--2026-09-01).

**Still unreviewed, and the baselines deliberately left where they are:** `WPNEXT-TEST` (1
commit) and `PTR-RUNNER` (2 commits). `--update` moves every drifted row by default, which
would have recorded a review nobody did. Moved `CC-REMOTE-SCRIPTS` alone with `--id=`. Issue
#8 stays open for the other two.

## Adding a row

1. Verify the licence from the upstream's own LICENSE file. Check it against the table above.
2. Add a row with today's HEAD for the path as `baseline_sha` — `--update` on a fresh row
   with an empty baseline reports everything as drift, which is correct but noisy.
3. Say in `why_we_watch` what is **unreviewed**, not just what was borrowed. That sentence
   is the backlog.
4. Run `python3 scripts/upstream-watch.py --control` before committing.

## Related

[Official sources](official-sources.md) · [Supply chain](supply-chain.md) ·
[Ecosystem signals](../method/ecosystem-signals.md) ·
[Preflight core probe](../method/preflight-core-probe.md) ·
[`scripts/upstream-watch.py`](../scripts/upstream-watch.py)
