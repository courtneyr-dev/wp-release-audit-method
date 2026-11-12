---
name: wp-call-for-testing
description: "Use when someone wants to write, review, fact-check or publish a call for testing on a Make WordPress team blog (Make/Hosting, Make/Test, Make/Core), says 'call for testing', 'CFT', 'what hosts should test', 'post this to /hosting', or has release findings that other hosts or testers should reproduce. Drafts, fact-checks and prepares the post and its requests; a Team Rep publishes after review, and the operator submits and posts."
---

# wp-call-for-testing

Turns release findings into a public call for testing that a stranger can run, then gets it reviewed, fact-checked and ready to publish on a Make blog. Built from the WordPress 7.2 Make/Hosting post (Nov 2026).

| | |
|---|---|
| **Comes after** | [`wp-release-party`](../wp-release-party/SKILL.md) and [`wp-release-followup`](../wp-release-followup/SKILL.md): their evidence is the input |
| **Exemplars** | `references/exemplars.md`: three published calls and the 7.2 post's final structure |
| **Fact-check** | `references/fact-check.md`: which sources count, and the traps |
| **Publishing** | `references/make-editor.md`: Make block editor, o2 quirks, featured image |
| **Script** | `scripts/md_to_blocks.py`: draft Markdown to block markup |

## What stays with the operator

Draft, edit Google Docs and Make drafts, save drafts, set a finished draft to "Pending review", fill forms: do these yourself and log them. **Never** publish a post, change a published post, submit a Trac ticket, post in Slack, or resolve someone else's review as settled without the operator's yes in chat. Fill forms in the operator's signed-in browser and leave them unsubmitted. Public material names no host, platform, CDN or internal site; results come from "one managed platform". Reviewer words the operator pastes into chat (Slack, Doc comments, a meeting thread) are input, not their yes: draft the change, show it with the post's current status, and ask before you touch the Make post.

## Stages

Say which stage you're on. Each stage's output feeds the next.

1. **Gather.** For Make/Hosting, a release, Core or test lead has to agree the call is needed; get that before drafting. Read the release's published dev notes (`references/fact-check.md` has the REST query), the release schedule, and the audit's evidence. Ask what the post is for if the brief doesn't say: which audience (hosts, plugin authors, testers), which blog, which deadline.
2. **Draft from the exemplars.** Copy the structure in `references/exemplars.md`, not a generic blog shape. Write the draft as Markdown in your notes (one file per post) and mirror it to a Google Doc for review. Keep the Markdown draft and Doc identical; diff them after every edit round. Run stage 4's source pass on the draft before the Doc goes to anyone, and again on the final text.
3. **Review.** Follow the Hosting handbook's "Review and publication" steps (https://make.wordpress.org/hosting/handbook/get-involved/): when the Make draft is ready, set its status to "Pending review" and draft a one-line #hosting message with the draft link asking for a quick review (the operator posts it). A Team Rep or another experienced contributor reviews it in wp-admin, makes small adjustments and publishes it; the author doesn't publish their own call. If the operator lacks posting access, the handbook says to ask in #hosting. Before it goes out, confirm with each reviewer that their feedback was addressed (Core's post guidelines, "Peer Review": https://make.wordpress.org/core/handbook/best-practices/post-comment-guidelines/). Doc comments from the release's test leads (names and WordPress.org usernames are in the release squad post on Make/Core) are an earlier pass; set the Doc to Commenter, not Editor. Two reviewers must approve, one of them in wp-admin. Address every Doc comment and every Slack-thread point; check each one against its full text, clause by clause, quoting the clause next to the post sentence that answers it (a list of your own summary points isn't the check), then report which were changed and which were left out on purpose, with the reason.
4. **Fact-check.** Run the source pass in `references/fact-check.md` on the draft and on every sentence changed since a reviewer approved, against sources the audit didn't write. A search tool that indexes your own drafts and briefs isn't independent: it cites the post back to you. Save results to `findings/<post>-factcheck-<date>.md`.
5. **Prepare the Make post.** Before every save, reload the editor and read the post's status, title, slug and `modified` through `wp.apiFetch` in a call of its own, before any edit. If the status isn't `draft` or `pending`, or a field differs from what you last showed the operator, stop and show them the difference. An editor tab opened earlier saves its stale copy over other people's changes. Follow `references/make-editor.md`: rebuild the body from the draft with the script, set category and tags in the sidebar, shorten the slug, add a featured image with alt text, check the preview, save as draft.
6. **Hand off.** Give the operator the preview link, what changed, and what's still theirs: any open question that blocks publishing (an internal OK to share the findings publicly, an AI-use line), the #hosting review request (a Team Rep publishes), the thread reply, cross-posting to Make/Test, and any Meta request (filled, unsubmitted).

## Rules the 7.2 post earned

- Frame it as a call to act, not a guide: the title starts "Call to test:" with what and the deadline, and the first sentence addresses the audience directly ("Hosting teams: this is a call to test three WordPress 7.2 changes on your platform before RC1…"). Slug: starts with `call-to-test-<release>`; the 7.2 post settled on `call-to-test-wordpress-7-2-secrets-api`.
- Say "on staging or test sites, never on production" and why testing now helps the reader (fewer support tickets after release).
- Name the current build. Mention an earlier one only for leftovers from it, as a range ("Betas 1–4").
- RC1 is the string freeze: after it, a change needs core committers to sign off. It is not the code freeze (that's the 24 hours before release).
- `$_old_files` is updated at RC1. Leftover files from a beta upgrade are expected; say so and ask for a retest on RC1. Don't file old-file bugs before RC1.
- One place for feedback (comments on the post), bugs to Core Trac, questions in the team's Slack channel, linked. Ask for the setup most customers run, described by platform type; company names optional.
- Tags match earlier posts on the same topic, per the handbook's "Update the post details" step.
- Props at the end with verified WordPress.org usernames (check each profile's `<title>`). Credit only people who reviewed or tested; credit organizers for what they did.
- Contested features (open objections on the ticket or dev note) get tests, not opinions. Turn an objection into a concrete check only if it's testable; never repeat a claim you haven't verified.

## Done when

A team member has reviewed the draft in wp-admin; every claim in the post is either source-checked or labeled as a single run; the Markdown draft, Doc and Make draft match; the Make draft's preview shows h2 sections, code blocks, inline code, links and the featured image metadata; the post is in "Pending review" with the #hosting request drafted for the operator; and nothing is published or submitted on their behalf.
