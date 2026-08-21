---
name: wordpress-audit-handoff
description: Hand off WordPress audit or testing work as ONE coworker-ready or SRE-ready markdown document, with privately-disclosed findings scrubbed to a bare acknowledgment. Use when asked to "hand off" a WordPress audit, make a handoff/shareable doc from testing findings, package audit results for a coworker/SRE/stakeholder, or write a fleet release-readiness brief.
---

# WordPress audit handoff

Turn testing work into **ONE self-contained markdown file** somebody else can act on.

| | |
|---|---|
| **Upstream** | [`wp-release-party`](../wp-release-party/SKILL.md) · [`wp-release-followup`](../wp-release-followup/SKILL.md) |
| **Evidence shape** | [`examples/chains/C-02/`](../../examples/chains/C-02/) — mechanism, evidence, both controls, cleanup |
| **Proof standard** | [validation and proof](../../method/validation-and-proof.md) |
| **Method index** | [the whole method in one screen](../wp-release-followup/SKILL.md#where-this-fits--the-whole-method-in-one-screen) |

## Pick the mode first

| Mode | Recipient | They need to decide |
|---|---|---|
| **A — coworker handoff** *(default)* | A peer tester, a maintainer, a stakeholder | Is this real, and what do I do about it? |
| **B — SRE fleet brief** | Someone who runs hosting for many sites | Do we ship this to the fleet, when, and what breaks if we do? |

**Mode B is not Mode A with more words.** An SRE does not need your finding narrative; they need a
posture, a blast radius, a gate list, and a monitoring change. Findings are evidence for the
posture, not the point. If the recipient runs infrastructure, use Mode B.

**The "fleet release-readiness brief" this skill's description promises is Mode B's output.**
For an agency or site-owner fleet (rather than a hosting platform), start from the fill-in
template at [`templates/fleet-release-readiness-brief.md`](../../templates/fleet-release-readiness-brief.md)
— inventory and denominator, tracker triage, the auto-update decision with its inputs, the
ordered update-day runbook, keyword monitoring, and the 72-hour failure watch. The method
behind each section is [`fleet-operators/`](../../fleet-operators/README.md). Mode B below is
the same evidence reorganized for someone who runs hosting infrastructure.

---

## Output rules (both modes)

- **One file, fully self-contained.** NO wikilinks, NO local filesystem paths — the recipient has
  neither your vault nor your machine. Inline the content, or link a public URL. Acceptable links
  are public: wordpress.org, make.wordpress.org, core.trac.wordpress.org, github.com.
- **Verify every GitHub link is PUBLIC before including it.** Check with
  `gh repo view <owner>/<repo> --json isPrivate` (or an anonymous `curl` → expect 200, not 404).
  Never link a private repo — the recipient gets a 404. Describe private or local tooling by
  **name + author** instead.
- **Confidentiality banner** at the top, matched to the audience.
- **Re-verify findings live** if the target is reachable, so it's current rather than logged.
- **Name the build actually tested**, and the upgrade lane used. Beta ≠ RC. Core's updater ≠ WP-CLI's.

---

## Mode A — coworker handoff

1. **Intro + context** — target, environment/stack, versions, verification date.
2. **Findings** — one per finding as **Mechanism → Evidence → Fix**, plus a **Sources** line
   linking each to its authoritative WordPress source: the Make/Core dev note or news post, the
   GitHub issue/PR, the Trac ticket.
3. **Stack facts** — verified environment details.
4. **Tested and cleared** — non-issues, so nobody re-chases them.
5. **Not covered (honest gaps).**
6. **How this was tested** — methods in prose; prompts verbatim in code blocks; skills and tooling
   labeled by actual use.
7. **Consolidated sources** — every public link in one list.

---

## Mode B — SRE fleet brief

Same evidence, reordered around a rollout decision.

### 1. Rollout posture — first line of the document

State one of three, and what would move it:

| Posture | Means |
|---|---|
| **READY** | No operational gate outstanding. Ship on the normal schedule. |
| **READY WITH CONDITIONS** | Functionally sound; specific operational gates must close first. List them, numbered, with owners and dates. |
| **HOLD** | A gate cannot close inside the release window, or a regression exceeds budget on a real customer segment. |

Always write the *movement* conditions: "would move to READY once gates 1–3 close; would move to
HOLD if disclosure disposition slips past the RC window." A posture without movement conditions is
an opinion. A posture with them is a decision aid.

> Note that "functionally sound" and "ready to ship to a fleet" are different claims. Most releases
> pass the first and fail the second on operational grounds — monitoring, capacity, support load —
> that no amount of feature testing surfaces.

### 2. What's new *operationally*

Only changes touching **configuration, capacity, compatibility, observability, security,
deployment, rollback, or support**. Feature polish with no operational surface is noise here —
omit it and say you omitted it.

For each: the mechanism, the fleet-config consequence, and which hooks or filters change behavior.

### 3. Fleet variance matrix

**This is the section SREs actually need**, and the one most testing reports lack. The same release
behaves differently across tiers. Enumerate where yours differ:

| Axis | Why it changes the answer | Check with |
|---|---|---|
| **PHP versions offered and defaulted** | Feature floors, deprecations, and which of your tiers can even run the target | `wp cli info`, tier provisioning defaults |
| **Image stack** — GD (`php-gd`) vs Imagick (`php-imagick`), and **which delegates** | Format support is a *delegate* question, not an extension question. A tier with Imagick but no HEIC delegate behaves like GD for HEIC | `wp eval` on `Imagick::queryFormats()` |
| **Object cache** — none / Redis / Memcached | Cache-vs-DB reconciliation bugs only appear where a persistent cache exists | `wp cache type` |
| **Page cache and edge** — none / server / CDN | Determines whether front-end changes are even visible to a visitor | Response headers |
| **Edge and proxy header handling** | Whether security and isolation headers survive to the browser (see the silent-fallback class below) | `curl -I` from outside the edge |
| **Cron** — WP pseudo-cron vs system cron | Scheduled-publish and cleanup behavior after upgrade | `wp cron event list` |
| **Multisite** — single / subdirectory / subdomain | Whole code paths exist only here | `wp core is-installed --network` |
| **Pre-installed plugins per provision** | Your actual compatibility exposure. **Ask for the canonical list** — it usually isn't written down anywhere you can read | Provisioning templates |
| **Core patching** — stock vs patched core | Determines whether checksum verification is even meaningful | `wp core verify-checksums` |
| **Auto-update policy per tier** | Who receives this, when, and whether they chose to | Fleet config |

For each axis, say which tiers you **actually tested** and which you inferred. An untested tier is a
gap, not a pass.

> **Divergence between your own tiers is a finding.** If the same customer action succeeds on the
> managed tier and fails on the shared tier, that's a support-visible inconsistency worth reporting
> even when neither behavior is a WordPress bug. It usually means one tier already ships the fix —
> which makes the remedy a known-good config rollout rather than new engineering. Say that
> explicitly; it changes how the work gets prioritized.

### 4. Findings, in three tiers

Label every finding. The tiers exist so nothing gets mistaken for cleared:

1. **CONFIRMED on a real platform, with a reproduction.** Name the platform and the build.
2. **Platform config observations worth attention.** Not defects — facts about your stack that
   change the release's behavior.
3. **Risk areas still under test.** Listed *so they are not mistaken for clear.* This tier is the
   one people delete to make a report look finished. Keep it.

For each CONFIRMED finding, add the two lines SREs need and testers usually omit:

- **Blast radius** — how many sites, which tiers, and on what trigger. "Every site that *upgrades*
  (not fresh-installs), on every tier, as auto-update reaches it" is actionable. "Some sites may be
  affected" is not.
- **Is this a WordPress bug or our config?** Route accordingly. A core bug goes upstream to Trac and
  you carry a mitigation; a config gap is yours to fix and there's no upstream to wait for.

### 5. Where to continue testing

The handoff is not the end of testing — it's the point where testing moves to people with a fleet.
Tell them where to look next, split by discipline.

#### Performance

> The [performance playbook](../../playbooks/performance-release-audit-playbook.md) in this repo is
> **unexercised** — it states acceptance criteria; no benchmark has been run against it. Hand it
> over as a design to execute, never as a result. Saying "performance is fine" without baselines is
> the single easiest way to lose an SRE's trust.

Point them at:

- **Baselines before verdicts.** No comparative benchmark against the *previous stable* means the
  performance posture is **unverified**, not good. Say "unverified."
- **The workload that changed.** Identify which subsystem the release actually moved — media
  processing, query patterns, generated CSS/JS payload, new front-end scripts — and benchmark
  *that*, not a generic page-load average that will dilute the signal to nothing.
- **Repeated runs, one variable.** A single run is not a regression. PHP-matched pairs only —
  never compare across PHP versions and site modes at once ([lie #5 and the fixture
  rules](../wp-release-followup/SKILL.md#where-this-fits--the-whole-method-in-one-screen)).
- **Per-tier resource shifts.** Work moving client-side only saves server CPU on tiers where the
  client path actually engages. See the silent-fallback class below.
- **Capacity questions worth asking:** does this change peak CPU during bulk operations? Does it
  change storage growth per upload? Does it add queries per page on content-dense pages? Does it
  change cron duration?

#### Security

- **New authenticated surfaces.** Every new REST route, comment type, or capability check is new
  attack surface. Enumerate them and check each against
  [the invariant catalog](../../method/security-invariants.md).
- **The neighborhood of the last security release.** If a recent point release fixed something in a
  subsystem, that subsystem deserves first-principles review this cycle — the fix proves the area
  was reachable.
- **Capability boundaries on multi-author and multisite.** Roles below administrator are where
  cross-user bugs live, and where a single-admin test site is structurally blind. Use
  [User Switching](https://wordpress.org/plugins/user-switching/) and test as an Author.
- **Header and isolation posture per tier**, as a security decision and not only a performance one.
- **Integrity monitoring** — see gates, below.
- **Route security findings privately.** Never a public ticket, never this document. See the
  scrubbing rule at the bottom.

### 6. Pre-GA gates

Numbered, each with an owner and a date, each tied to the release calendar. Typical gate classes:

- **Re-baseline core-integrity monitoring.** Anything keyed to WordPress.org checksums will
  false-positive across the fleet when either (a) you ship patched core, or (b) the release leaves
  orphaned files behind. Both are benign; both look identical to compromise. This is usually the
  highest-impact operational item on a release, and it is invisible to feature testing.
- **Close any coordinated-disclosure item** to a release disposition.
- **Establish performance baselines** before asserting a performance posture.
- **Plugin-compat sweep** against the canonical pre-installed list per provision.
- **Support-KB articles** for behavior that changes visibly for customers, especially where the
  change is browser-dependent and support will see it as "works for me."

### 7. Monitoring, rollback, support

- What alerts change meaning after this release, and what to re-baseline before rollout.
- What rollback looks like — and be honest when there isn't one. There is no supported downgrade
  from a major WordPress version; rollback means restore-from-backup, which is a different
  conversation about RPO than "we'll roll it back."
- What support will see, phrased the way a customer would report it.

---

## The silent-fallback class — worth its own habit

The most expensive fleet bugs are the ones that produce **no error**.

A feature that requires specific response headers, a browser capability, or a per-request resource
check will often **fall back silently** when the requirement isn't met. Nothing logs. Nothing
alerts. The expected benefit simply never appears, and no dashboard shows its absence.

If a release adds a capability-gated or header-gated feature, add three questions to the brief:

1. **What are the exact gates?** Browser and version, required response headers, CSP directives,
   device or resource thresholds, and the filter that force-disables it.
2. **Does the gate survive your edge?** A CDN, proxy, or security plugin that strips a header turns
   the feature off silently for every site behind it. Verify from *outside* the edge, not from the
   origin.
3. **How would you know it engaged?** If there's no way to observe it, say so — that's an
   observability gap to file, not a passed test.

This class is why "we tested it and it worked" and "it works for our customers" are different
claims. Your test box may satisfy gates that most of the fleet does not.

---

## Two rules that are easy to get wrong

- **Confidential / privately-disclosed findings** (coordinated disclosure, unpatched): reduce to a
  **bare acknowledgment** — *"a separate security issue was identified and responsibly disclosed
  through a private channel; details withheld."* Scrub every trace: mechanism, endpoint and function
  names, CVSS, reproduction, the specific PR or commit, and the name of the disclosure program.
  **Then grep the file to prove zero traces remain** before sending. If it's unclear which findings
  are confidential, ask.

  In an SRE brief this still belongs in the gate list — *"coordinated-disclosure item must reach a
  release disposition"* is an operational gate a fleet owner needs to plan around, and it can be
  stated without a single detail about the finding.

- **Accuracy labels.** Label every skill, tool, and method by ACTUAL use — `used` / `staged` /
  `available` — and never imply a tool did work it didn't. Add a one-line accuracy note.

## Done when

The recipient can act without asking you a follow-up question: Mode A has a fix per finding and its
authoritative source; Mode B has a posture with movement conditions, a blast radius per finding, a
tier-by-tier variance picture that marks untested tiers as gaps, numbered gates with owners and
dates, and a named next step for performance and security testing.
