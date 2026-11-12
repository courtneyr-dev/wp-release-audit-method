# Fact-check

The post is public and hosts will act on it. Check every factual sentence against a source the audit didn't write. If a source contradicts training or memory, the source wins. If no public source exists, label the claim as a single run ("on the platform tested", "tested on one site") instead of dropping or upgrading it.

## Trusted sources, in order

1. **The official package** for the build the post names: `https://wordpress.org/wordpress-<version>.zip`, unpacked into the scratchpad and read, never run. Download the previous stable too when a claim compares versions (file lists, `$_old_files`).
2. **Core Trac** through the Trac connector (`getTicket`, `getChangeset`). The web query page is behind a bot check; don't fight it.
3. **Make/Core** through its REST API: dev notes by tag, the release schedule ("release party schedule" post), the release squad post (test leads and their profile usernames).
   ```bash
   curl -s "https://make.wordpress.org/core/wp-json/wp/v2/tags?slug=dev-notes-<x-y>&_fields=id"
   curl -s "https://make.wordpress.org/core/wp-json/wp/v2/posts?tags=<id>&per_page=50&_fields=date,link,title"
   ```
   The comments endpoint returns an error object; read comments from the post page instead.
4. **WP-CLI source** on GitHub (`wp-cli/core-command`, `wp-cli/checksum-command`) via `gh api ... -H "Accept: application/vnd.github.raw"`.
5. **WordPress.org profiles** for usernames: `https://profiles.wordpress.org/<username>/`, check the `<title>`.

Runtime evidence (our test sites, reviewers' reports) backs claims about behavior on a platform. It's evidence, not a source check; say which kind each claim has.

## Not independent

- **Search tools over your own documents.** An internal search index includes the post and your own briefs, so it cites them back and returns "supported". Use it to find context, not to check facts.
- **Our own Trac comments and tickets.** A comment the operator wrote is a restatement; confirm it in code.

## Traps that nearly produced wrong corrections

- **Defaults set elsewhere.** `wp_kses()` defaults `wp_kses_force_legacy_parser` to `true`, which reads as "legacy parser by default", but `default-filters.php` adds `__return_false`, so the HTML API is the default. Before calling a default, grep `default-filters.php` and `default-constants.php` for the hook or constant.
- **Version-dependent messages.** WP-CLI's cleanup warning differs between versions. Describe the behavior ("skips them with a warning and still reports success"), not the exact message.
- **Marketing words for milestones.** RC1 is the string freeze; the code freeze is the 24 hours before release. Check the schedule's own labels.
- **"Unchecked".** Read the loader before saying core doesn't validate something; `wp_load_secrets_dropin()` checks types and fails closed.
- **Shell globs.** In zsh, quote `--include='*.php'` or grep silently runs nothing.

## Output

Write `findings/<post>-factcheck-<date>.md` next to the draft: needs a fix (with suggested wording), supported (with the source line or file and line), not checkable publicly, and context that isn't for the post (open objections to the features). Apply fixes only after the operator says which.
