# Sources and traps

Where each fact comes from, and what misled the WordPress 7.2 run (Nov 2026). Every trap below cost a wrong or missing line in the first draft of the audit.

## Trac: use the MCP, never the site

Core Trac answers scripts and browsers with a "Checking your browser" page and then an interactive "I am human" challenge. Don't click it and don't change the user agent. Use the Trac MCP (`mcp__wordpress-trac__searchTickets`, `getTicket`, `getChangeset`).

- **Closed, fixed, in the milestone:** `searchTickets` with `milestone` `7.2`, `status` `closed`, `resolution` `fixed`, `query` `type!=task (blessed)&component!=Build/Test Tools&order=component`, `limit` 50, then `page` 2, 3 and so on. The 7.2 total was 346 tickets (7 pages, about 15k tokens a page), so fan the pages out to subagents.
- **Blessed tasks, as their own query:** `query` `type=task (blessed)`, same milestone. The 7.2 total was 60, mostly build and test work. The blessed type is also where features that arrive as umbrella tasks live: the Random content redirect (#64498), the recommended MySQL version (#66637), the Ipsum theme (#66352), the jQuery Migrate bump (#66203). The checklist's own source query excluded them, so it missed the first two.
- **Reopened and reverted tickets aren't closed.** #65116 (On This Day, reverted in r65732) and #66208 were reopened with milestone 7.2, so a `status=closed` query never lists them. Also query the `milestone` with `status!=closed` (52 tickets on 2026-11-23) and re-open each feature you describe.
- **`getTicket` is large.** About 35 KB for #65116 and for #66208, half of it linked PR bodies, and `commentLimit` trims only comments. Check a cited number with `searchTickets` (about 700 characters), read a commit with `getChangeset` and `includeDiff` false, and spend `getTicket` only on a ticket whose newest comments or changesets you need.
- **`searchTickets` with `order=changetime` returns no change date**, so it can't answer what changed since the last audit.
- `getTicket` returns type, milestone, comments (human only), changesets and linked PRs. `getChangeset` with `includeDiff` false is cheap and carries the commit message.

## Check the ticket behind every number

- **Feature versus follow-up.** The checklist cited #66625 for the Random base field. That ticket is a bug about cache headers; the feature is #64498. Read the ticket's type and title, and its "Follow-up to" line.
- **Reverts.** The Secrets API was reverted from 7.2 on the day RC1 shipped ([r65538](https://core.trac.wordpress.org/changeset/65538)), and "On This Day" had a proposal to move to 7.3 with an open revert PR. A merged feature and its dev note can both be wrong a week later. Search the milestone for the feature's name, read the newest comments, and write the date you checked.
- **Read the last changeset.** Opening the changeset you cited proves only what it says. In 7.2 the first comment said `CONCATENATE_SCRIPTS` "defaults to off" ([r64320](https://core.trac.wordpress.org/changeset/64320)). [#57548](https://core.trac.wordpress.org/ticket/57548) is titled "Stop concatenating scripts and stylesheets in wp-admin and retire load-scripts.php and load-styles.php", and [r64585](https://core.trac.wordpress.org/changeset/64585) (Oct 19) says the constant "is no longer read". Read the ticket's title and every changeset on it before writing "now defaults to". If the operator keeps a claim ledger for the release, search it for each ticket number you cite.
- **Dev notes lag.** A note can describe code a later commit changed (the Random note still said `ORDER BY RAND()` after [r65542](https://core.trac.wordpress.org/changeset/65542)). Read the ticket's changesets dated after the note.

## Dev notes

`scripts/devnotes.py dev-notes+7-N --out DIR` lists the notes on the Make Core tag feed (paged) and saves each body. Make isn't bot-protected. Read the bodies: a heading names a change and its body carries the limits and opt-outs. In 7.2 the media dev note's headings already named the multisite upload-space change and auto-attach, so a heading-only pass finds the topics but not their limits. A post tagged for the release can also be a roadmap or announcement post; look at what it changes for a reader.

## Gutenberg

Most editor changes arrive as Gutenberg PRs, not Trac tickets. `scripts/check-gutenberg-refs.sh` resolves every cited number and flags anything that isn't a merged PR. In 7.2, two cited numbers were issues, not PRs: #43241 (a tracking issue) and #76076 (still open). The release-post list in a checklist usually stops at the last release someone read; PRs merged after it still ship through later syncs, so add the later release posts.

## The release's source

- Find the RC commit. The 7.2 run found no RC tag in the `WordPress/wordpress-develop` mirror (SVN tags aren't mirrored) and used the commit titled "WordPress 7.2 RC 1", then read the Gutenberg version that commit pins. Check for a tag first.
- Settle "(verify)" items from source: UI strings in the built package, defaults in `user.php` and `default-constants.php`, the theme folder list.
- "Not new in this release" is a finding. Compare against the previous release's Gutenberg pin: Ctrl+Alt+M for notes was in 7.0.

## Doc URLs

`scripts/check-doc-urls.sh` reports status, final URL and title. Expect three kinds of flag:

- **Redirects.** The HelpHub Network Admin Settings page now redirects to Advanced Administration. Link the final URL and name the move.
- **"(Deprecated)" titles.** The HelpHub Button block page is deprecated; Buttons is the live page.
- **404 on `developer.wordpress.org/reference/...`.** New hook and function pages appear after the post-release build. These go on the list as "create after release", not as broken links.

## Where the tracker sends work (read its README each cycle)

The [Documentation-Issue-Tracker README](https://github.com/WordPress/Documentation-Issue-Tracker) says it covers DevHub, HelpHub and the Docs team handbook. Gutenberg-specific documentation goes to the Gutenberg repo. Code Reference descriptions, parameters and hooks are generated from source and go to Core Trac; Code Reference layout goes to Meta Trac. It also lists HelpHub pages that the editor links to, with a warning not to change their titles or anchors (the Math block page in 7.2). It changes between releases.
