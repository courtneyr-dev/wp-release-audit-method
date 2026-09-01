# Draft comment for the plugin-compatibility workflow — not filed

**Target:** [WordPress/wordpress-develop#13198](https://github.com/WordPress/wordpress-develop/pull/13198)
(the PR, where the full-scale run and the `Requires Plugins` discussion are). The scope
paragraphs also work on [Trac #65920](https://core.trac.wordpress.org/ticket/65920) if you'd
rather put the lane-division framing there — see *Trimming for Trac* at the bottom.

**Rewritten 2026-08-23** against Adam Silverstein's full-scale run and Adrian Duffell's
dependency proposal. **Revised again 2026-08-24**: the dependency pre-install shipped in
`67005f527b`, so the paragraph that argued for it is gone — arguing for something already
merged into the PR is the fastest way to look like you skimmed the thread.

Review, adjust, file manually, then log it in `pilots/filed-issues-register.csv`.

---

The 200-plugin run answers the question the ticket opened with, so most of this is about
scope rather than whether to build it.

**The `eps-301-redirects` retraction and the fix for it both look right.** Demoting the
WP-CLI boot to a note, running it last so its fatal can't poison the debug-log check, and
letting the HTTP checks decide is the correct shape — a CLI-only fatal really can be the
`wp-settings.php`-inside-a-method scoping artifact rather than anything a visitor could reach.
Worth stating the reasoning in the workflow's own docs rather than only in this thread, since
the next person to look at a red CLI step will otherwise reach the same wrong conclusion.

Two things that seem worth keeping visible in the scope, since the retraction narrows what the
run demonstrated: **activation is still not a boot** — an HTTP request with the plugin active
is doing real work that `wp plugin activate` isn't — and the run's headline now reads as zero
confirmed core-related fatals out of 200, with `instagram-feed` as the remaining candidate. A
workflow that finds nothing is still worth having. It is just a different claim from the one
the first summary supported, and the difference is worth being explicit about before anyone
cites the run.

**The dependency pre-install looks right, and the isolation guard is the good part.**
Baselining the front page and login screen after the dependencies are active but before the
plugin under test is, then recording "broken already" as a skip against the dependency
rather than a failure of the subject, is the thing that makes multi-plugin testing readable
at all. The "Also active" column is what lets someone else audit the verdict afterwards.
Reading the header with `get_plugin_data()` rather than a grep seems worth keeping too, so
the workflow's notion of "requirements met" can't drift from core's.

**One loose end from the earlier numbers, offered as a question rather than a request.** The
first full run reported *186 passed / 1 failed / 13 skipped*, with the skip reason given as
add-ons with an unmet `Requires Plugins` header. The fix names four such plugins. If the
other nine were skipped for some other reason, it'd be useful to have that in the output —
one reason per skip rather than one reason beside the count. A count with a single plausible
cause written next to it is easy to read as solved, and nine units would still be untested.
Entirely possible this is already in the per-shard logs and only the summary flattens it.

**On the 45-minute timeout question:** capping the number of dependencies pulled in trades a
known cost for an unknown blind spot, and the blind spot is the thing this workflow exists
to remove. If the wall-clock becomes a problem, sharding harder seems less lossy than
capping — but you have the runner budget and I don't.

**One class this can't reach even with dependencies resolved, and a cheap partial
mitigation.** The fatal that took sites down on 7.1 day needed three parties, not two: the
`_wp_filter_build_unique_id()` key-type change (#65919), WP Rocket's string operation on a
hook key, and *a third plugin registering a closure* on `deleted_post` or
`transition_post_status`. A clean install of 7.1 plus WP Rocket alone doesn't crash. A
one-plugin-at-a-time matrix tests core × plugin; that failure lived in a triple. Inside this
workflow's existing scope you could get a useful slice of it without any companion-plugin
combinatorics: activate each plugin alongside a small canary mu-plugin that registers
closures on a handful of high-traffic lifecycle hooks. That won't find every triple, but it
turns the whole "assumes hook keys are strings" class into something one extra file catches.

**On premium plugins, treating it as stated scope is the right call.** Saying plainly that
this covers the free directory is more useful than trying to stretch it, because it tells
hosts and agencies exactly what's left for them — and that remainder now has somewhere to
go. Fleet operators can run a preflight probe (sideload the new core, boot it against a real
site's live database and plugin set, check for fatals, don't apply) across their sites
against an RC, which reaches premium plugins, dependency-gated plugins, and bespoke client
code in the combinations real sites actually run, without enumerating anything. If that
produces RC-stage fatal reports, the natural home for them is Make/Test and the plugins'
own trackers. Happy to align lane definitions with whatever scope lands here so the two stay
complementary rather than overlapping.

Method and lane definitions:
<https://github.com/courtneyr-dev/wp-release-audit-method>

**Evidence ceiling for the above:** the run numbers, the `eps-301-redirects` failure and the
`instagram-feed` one are yours, quoted back, not independently reproduced by me. The
7.1 / WP Rocket fatal itself I have not reproduced — WP Rocket is premium and I don't hold a
licence.

Two things I *have* run, on a disposable DDEV fixture (7.0.4 → 7.1), so you can weigh the
canary suggestion accordingly: a plugin doing a string operation on a `$wp_filter` key under
`strict_types`, plus a second plugin registering a closure on `deleted_post`, reproduces the
mechanism — the pair is green and the triple fatals on `init`. That's a reconstruction of WP
Rocket's code shape rather than WP Rocket, and it says the closure is the trigger the canary
would supply. It does **not** show that a canary inside your workflow would catch a real
plugin; nobody has run that.

The preflight-probe technique is documented from Austin Ginder's CaptainCore implementation.
My CLI-only adaptation of the probe half is exercised with both controls; the HTTP half and
the apply path are not.

## Use of AI Tools
AI assistance: Yes
Tool(s): Claude Code
Used for: Drafting this comment from my testing notes and from the run results posted on
this PR. I reviewed and verified the technical claims (ticket and PR numbers, the
pair-vs-triple mechanism, the activation-vs-load distinction, the directory API's scope) and
take responsibility for the content.

---

## Trimming for Trac

For a Trac comment on #65920, keep the premium-scope paragraph and the triple/canary
paragraph and drop the two about the run itself — the run results live on the PR, and Trac
readers arriving at the ticket want the scope boundary, not the changelog. Drop the
`Requires Plugins` paragraph entirely there; it's a code-review point.
