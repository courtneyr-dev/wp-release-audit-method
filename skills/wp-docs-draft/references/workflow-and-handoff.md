# Workflow and hand-off

How a documentation change gets from a draft to a live WordPress.org page, and what an assistant may and may not do on the way. Read 2026-11-17 from the Docs team handbook and the [Documentation-Issue-Tracker](https://github.com/WordPress/Documentation-Issue-Tracker) repo. Several handbook pages date from 2023 to 2024; where they disagree with the repo's workflow files, the workflow files are ground truth.

## What stays with the operator

Draft in Markdown and hand it over. **Never** post or edit an issue or comment, run `/assign` or `/review`, apply a label, upload to a Media Library, edit HelpHub, DevHub or a handbook, or open a Gutenberg PR. Every one of those is the operator's act, under their own account.

## Where each kind of change goes

- **HelpHub (end-user docs, wordpress.org/documentation):** a Documentation-Issue-Tracker issue with the `user documentation (HelpHub)` label. The text lives only on the live site; GitHub holds issues and automation, not article text.
- **Developer handbooks (Plugins, Themes, Common APIs):** the same tracker, `developer documentation (DevHub)` and the project label. A rep or trusted contributor with dashboard access edits the live page.
- **Code Reference descriptions, parameters, returns, hooks:** generated from PHP source. Change the source through Core Trac, not the tracker. Code Reference layout goes to Meta Trac. "More Information" and User Notes are the only parts edited on the site.
- **Block Editor Handbook:** Markdown in `docs/` of `WordPress/gutenberg`. A pull request, merged by a Gutenberg committer. New page: lowercase dash-separated `.md` with one H1, an entry in `docs/toc.json`, `npm run docs:build`, commit the updated `manifest.json`. Images must be hosted on developer.wordpress.org, not GitHub. Problems go in the Gutenberg tracker, not this one.
- **Advanced Administration:** Markdown in `WordPress/Advanced-administration-handbook`, by pull request.
- **Docs team handbook (make.wordpress.org/docs/handbook):** the `contributor documentation` label.
- **Other teams' handbooks (REST API, WP-CLI, Coding Standards):** not the Docs team's. Ask that team.

## The path to live (HelpHub)

1. Search the tracker first. Open an issue from a template: **Fix Doc Issue Report** (page URL, section, why it's a problem, suggested fix; incomplete reports are closed), **New Doc Request** (adds `new document`), **New release end-user issue** (a per-article release checklist), or a feedback report. Each starts with `[Status] To do`.
2. Draft in the issue (best for a small edit) or in a Google Doc linked from the issue (recommended for a new page). Include screenshots and a changelog line.
3. A comment containing `/assign` assigns the commenter and moves the issue to In progress. A comment containing `/review` adds `[Status] Review`, removes In progress and every assignee, and pings `@docs-reviewers`.
4. A second Docs team member reviews. The first reviewer checks screenshots, grammar, structure and style; the second fact-checks and approves (agreed in a Nov 2025 team meeting).
5. A team member **with HelpHub dashboard access** publishes, timed to the release (within about 30 minutes) for release work, then closes the issue.

A non-member can't edit HelpHub directly. Access comes from steady contribution; the current page says to keep contributing and join #docs, with no form.

## Release work

- Candidate updates come from the release roadmap, narrowed at Beta 1 and again at RC1. Open issues early or at those points, labeled with the release (for example `7.2`) so automation adds them to the release project.
- Confirm behavior on a real install (Playground or InstaWP), not from PR text.
- Updates go live with the release. Draft in advance; publish after the official announcement.
- Release-day pages (HelpHub version page, WordPress Versions, Roadmap, History, origins article) belong to the Release Documentation Lead. Others can help in #docs.
- Dev notes and the Field Guide feed the developer docs side. The sources don't say they feed HelpHub articles; HelpHub input comes from the roadmap, the betas and RC1, and Gutenberg PRs.
- The tracker's release template says not to detail the shared settings (Typography, Color, Layout, Dimension, Border, and the block toolbar's More options) in each block's article. Name the settings the block has and link to the shared settings page.

## Hand-off package

Give the operator, in one message:

1. The issue to use (existing link, or the template and title for a new one) and its labels.
2. The draft as Markdown, with the changelog line and every link.
3. The screenshot plan: which images to replace, which are new, one `ALT:` line each (`screenshots.md` has the comment format).
4. What you checked and how, and what you couldn't verify.
5. Open questions only the Docs team can answer: governing picks where sources conflict, terms no page defines.
6. An AI-assistance disclosure line. The Docs handbook states no policy on AI-drafted content. The WordPress project's [AI Guidelines](https://make.wordpress.org/ai/handbook/ai-guidelines/) ask contributors to disclose AI use. Ask the operator; default to including one line.

## Not stated anywhere

Review turnaround and the number of required reviewers; Google Doc sharing and naming conventions; taxonomy, slug and navigation rules for a new article; changelog format beyond "include one"; how a non-member learns the page was published; how to request HelpHub access today; the board's current columns.

## Where the pages disagree

Contributors "can't self-assign" (handbook prose) versus `/assign` and `/review` (the workflow files). Label names (`user documentation` versus `user documentation (HelpHub)`). Weekly versus bi-weekly meetings. The Slack-only route for Plugins, Common APIs and More Information issues versus tracker labels. Use the workflow files and the repo's labels.
