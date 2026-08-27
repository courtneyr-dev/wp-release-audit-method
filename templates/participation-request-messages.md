# Participation request messages — copy, fill in, send it yourself

Two standing messages for the two gaps this method keeps finding: a host with no public
core-test participation, and a plugin or theme whose "Tested up to" doesn't reflect the
release you just tested it on. Both follow this repo's boundary: **you send them, from your
own account** — nothing here posts anywhere on its own.

They're written to be easy to say yes to: specific ask, public link, no blame. Fill every
`<placeholder>`, delete what doesn't apply, and keep them short — the recipient's next step
should be obvious in one read.

## 1. Asking a host to join the distributed hosting tests

Use when [`hosting-test-participation.py`](../scripts/hosting-test-participation.py) reads
`NO_PUBLIC_MATCH` or `STALE_REGISTRATION` for a host or one of its tiers — including your
own employer's. Send to the host's support, developer relations, or engineering contact;
as a customer, a support ticket with this text is a fine route.

```markdown
Subject: Request: run WordPress's distributed hosting tests on <HOST> (<TIER, if known>)

Hi — I'm <a customer on your <TIER> product / auditing a site hosted on your <TIER>
product / evaluating hosts for a fleet of <N> sites>.

WordPress publishes per-host core test results at
https://make.wordpress.org/hosting/test-results/ — hosts run the core PHPUnit suite on
their own infrastructure and submit results, so compatibility problems surface before a
release ships rather than after it auto-updates onto customer sites.

As of <DATE>, I couldn't find a current public result for <HOST>
<— or: your account "<REPORTER>" last reported at <rNNNNN>, which the dashboard now
lists under "Registered, but no reports in >25 Revisions">.

Would you consider <starting / resuming> participation? Setup is documented at
https://make.wordpress.org/hosting/test-results-getting-started/ and runs the standard
WordPress/phpunit-test-runner on a schedule. If you already test privately or report
under another account name, I'd love to know which, so I can count it.

One request beyond the basics: if <HOST> has distinct hosting products (shared, managed
WordPress, VPS…), a separate reporter account per product would make the results usable
per tier — the dashboard doesn't distinguish environments within one account.

As a customer, this is the difference between "trust us" and public evidence. Thanks for
considering it.
```

Why the per-product ask matters: the dashboard's public data carries no environment
label, so one account's results cannot be attributed to a specific tier — see
[the participation lane](../fleet-operators/README.md#9-distributed-core-test-participation--public-evidence-scoped-honestly).

## 2. Asking a plugin or theme developer to update "Tested up to"

Use when you've tested someone else's plugin or theme against a release — a
[preflight probe](../method/preflight-core-probe.md) pass, an
[ecosystem-lane cell](../method/ecosystem-compatibility-lane.md), or a manual check — and
their published compatibility claim doesn't reflect it. Send via the plugin's support
forum, the vendor's support channel, or the repo's issue tracker. Report what **you**
observed; the bump itself is theirs to make, after their own testing — the
[nine boxes](../plugin-theme-authors/README.md#bump-it-only-when-this-is-true) apply to
them, not to your single result.

```markdown
Subject: <PLUGIN/THEME> on WordPress <VERSION> — test result, and a "Tested up to" request

Hi — I tested <PLUGIN/THEME> <ITS VERSION> against WordPress <VERSION / RC BUILD> on
<DATE> (<PHP VERSION>, <single site / multisite>, <how: activated + primary workflow /
preflight boot probe / full test pass>).

Result: <it worked — no fatals, no deprecation notices, primary feature intact /
specific problem: EXACT ERROR, STEPS>.

The directory listing currently says "Tested up to: <OLD VERSION>", so every user on
<VERSION> sees an "untested" compatibility warning next to it. If your own testing
agrees it's compatible, would you bump "Tested up to" — in the readme on wordpress.org
(both trunk and the stable tag) and in your source repo, so they don't drift? The
mechanics: https://github.com/courtneyr-dev/wp-release-audit-method/tree/main/plugin-theme-authors#bump-every-copy--the-field-lives-in-more-than-one-place

<For a premium product not on wordpress.org:> Since <PRODUCT> isn't in the directory,
could you state the supported WordPress version publicly on <THE PRODUCT SITE /
changelog / documentation> where customers can check it before release day?

One tested configuration is one data point, not a compatibility guarantee — treat this
as a report to fold into your own testing, not a substitute for it. Happy to share the
exact environment details or re-run against an RC if useful.
```

Route real breakage to the vendor's tracker as a bug report first — the
[ecosystem lane](../method/ecosystem-compatibility-lane.md#a-dependencys-public-tracker-is-a-release-readiness-input)
covers that; this message is for the claim, not the defect. If the developer maintains the
plugin on GitHub, [`plugin-theme-authors/`](../plugin-theme-authors/README.md) is the
guide to point them at.

## The line both messages walk

You are reporting evidence and requesting a public claim — not certifying anything.
Neither message promises that your test proves fleet safety or full compatibility, and
neither asks the recipient to claim more than their own testing supports. That's the same
[evidence discipline](../method/validation-and-proof.md) as the rest of this repo, applied
to outreach.
