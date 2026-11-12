# Exemplars

Match these, not a generic blog post. When a new call doesn't fit any of them (a feature plugin, a single-team audience), say so and ask the operator for a closer example.

## Published calls to model

- [Call For Action – Testing Rollback Feature](https://make.wordpress.org/hosting/2022/10/19/call-for-action-testing-rollback-feature/) (Make/Hosting, 2022). Model for: a plain "Do not test on a production site" line, step-by-step test procedures, a validation section, a thank-you.
- [Urgent: Testing request to Web hosts for collaborative editing by May 4th](https://make.wordpress.org/hosting/2026/04/29/urgent-testing-request-to-web-hosts-for-collaborative-editing-by-may-4th/) (Make/Hosting, 2026). Model for: deadline in the title, addressing hosts in the first sentence, why it matters to hosts, asking for the configuration customers actually run, how results are shared, props at the end.
- [Help Test WordPress 7.2](https://make.wordpress.org/test/2026/10/20/help-test-wordpress-7-2/) (Make/Test). Model for: the release-wide testing call that a hosting call links to.

Hosting team reps supplied the first two and set the bar: a clear space for feedback, @-props for everyone who helped and reviewed, tags such as `#7-2`, two reviewers before publishing, at least one of them in wp-admin (not Google Docs), and publish as early as possible.

## The 7.2 post's final structure

Source: the published post, https://make.wordpress.org/hosting/2026/11/12/call-to-test-wordpress-7-2-secrets-api/ (2026-11-12).

1. **Title:** "Call to test: WordPress 7.2's Secrets API, upgrades and /random/ on your hosting platform by November 17". The Hosting team's review after publishing: the first title read as a guide hosts might follow if they felt like it; a call to test asks them to act.
2. **Intro paragraph:** audience and ask with the deadline ("Hosting teams: this is a call to test three WordPress 7.2 changes on your platform before RC1 on November 17, and to post what you find in the comments."), what RC1 means, the release date, the changes in one sentence, where results came from ("one managed platform and local test fleets"), staging-only, why it helps the reader.
3. **"The short checklist":** numbered actions, one line each, verbs first.
4. **One h2 section per change:** what changed with changeset or ticket links, then numbered tests in bold ("**Test 1: count the sites without a key.**"), each with a code block when there's a command, and the result seen ("On the platform tested, …").
5. **"Other quick checks":** one-line bullets for smaller changes, each with its source.
6. **"Where to send feedback":** deadline again, comment on the post with what was tested, what was seen and the stack; test the setup most customers run; describe the platform by type; bugs to Core Trac; questions in the linked Slack channel; which configurations help most; link to the full test guide.
7. **Closing:** "Thank you for testing." then props with WordPress.org usernames.

Length: the review asked for half of the first draft; the published version landed near 1,300 words because review added tests. Cut background before cutting tests.
