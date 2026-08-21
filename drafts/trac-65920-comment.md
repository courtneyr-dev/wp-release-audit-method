# Draft comment for Trac #65920 — not filed

Target: <https://core.trac.wordpress.org/ticket/65920> (plugin compatibility testing
workflow, milestoned 7.2). Review, adjust, and file manually; then log it in the
filed-issues register.

---

This workflow closes the largest part of the gap 7.1 day exposed, and it's worth
building even with the limits already noted on this ticket. Two observations from
maintaining a manual release-testing method, offered so the two approaches can divide
the work rather than duplicate it:

**The premium blind spot is structural, not incidental.** As noted in the proposal,
the plugin that actually took sites down on 7.1 release day (WP Rocket) can't be
covered here — the directory API only serves free plugins, and license-gated zips
can't be fetched in CI. That's fine if it's stated as scope: hosts and agencies
running premium-heavy stacks still need a manual pass, and knowing the workflow
covers the free top-100 tells them exactly what's left for them.

**Single-plugin activation misses the class that hit 7.1.** A clean install of
7.1 + WP Rocket alone does not crash. The fatal needed a third plugin registering a
closure on `deleted_post`/`transition_post_status` — the `_wp_filter_build_unique_id()`
key-type change (#65919) only bites when something routes execution into the string
assumption. A per-plugin activation matrix tests core × plugin pairs; this failure
lived in a triple. A cheap partial mitigation inside this workflow's scope: after
activating each plugin, also run a canary mu-plugin that registers closures on
high-traffic lifecycle hooks, so at least the "assumes string hook keys" class
surfaces without a specific companion plugin.

A manual complement covering premium plugins, co-installed pairs, and
tracker-triage (the WP Rocket fatal was on the vendor's own tracker with a proposed
fix six weeks before release day) is maintained at
<https://github.com/courtneyr-dev/wp-release-audit-method> — happy to align its lane
definitions with whatever scope lands here so the two stay complementary.

## Use of AI Tools
AI assistance: Yes
Tool(s): Claude Code
Used for: Drafting this comment from my testing notes; I reviewed and verified the
technical claims (ticket numbers, the pair-vs-triple mechanism, directory API scope)
and take responsibility for the content.
