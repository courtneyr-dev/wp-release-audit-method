# Draft comment for the plugin-compatibility workflow — not filed

**Target:** [WordPress/wordpress-develop#13198](https://github.com/WordPress/wordpress-develop/pull/13198)
(the PR, where the full-scale run and the `Requires Plugins` discussion are). The scope
paragraphs also work on [Trac #65920](https://core.trac.wordpress.org/ticket/65920) if you'd
rather put the lane-division framing there — see *Trimming for Trac* at the bottom.

**Rewritten 2026-08-23** against Adam Silverstein's full-scale run and Adrian Duffell's
dependency proposal. The previous draft predated both and argued the workflow was "worth
building" — it's built and it caught something, so that framing is gone.

Review, adjust, file manually, then log it in `pilots/filed-issues-register.csv`.

---

The 200-plugin run answers the question the ticket opened with, so most of this is about
scope rather than whether to build it.

**The load step is why the run found anything — worth naming in the scope so it doesn't get
optimized away later.** `eps-301-redirects` 2.85 installs and activates cleanly and only
fatals once WP-CLI actually loads WordPress with it active. If this check ever gets trimmed
to install-and-activate for speed, it goes back to passing that plugin. Activation runs a
narrow path, usually before the hooks and globals a plugin's real code assumes are there, so
"activated" and "boots" are genuinely different results and this workflow is currently
measuring the useful one.

**Strong +1 to pre-installing `Requires Plugins` dependencies, and please report skips
separately from passes in the summary.** 13 of 200 is 6.5% of the run untested, and it isn't
a random 6.5% — it's the WooCommerce add-ons, which are a large share of what the popular
list actually is. A summary line reading "186 passed" is easy to read as a clean ecosystem.
"186 passed / 1 failed / 13 skipped (unmet dependency)" says the true thing at the same
length, and it keeps the skip count visible as the number that should shrink once dependency
pre-install lands.

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

**Evidence ceiling for the above:** the run numbers and the `eps-301-redirects` failure are
yours, quoted back, not independently reproduced by me. The 7.1 / WP Rocket mechanism is
from public sources (#65919, the vendor's own issue and fix PR) and I haven't reproduced
that fatal either. The canary mu-plugin idea is untested — it's a suggestion, not a measured
result. The preflight-probe technique is documented from Austin Ginder's CaptainCore
implementation and my write-up of it is explicitly marked unexercised.

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
