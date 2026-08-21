---
title: "Prompt — start a future WordPress release audit"
type: prompt
status: active
created: '2026-07-31'
updated: '2026-07-31'
source_run: "$WP_AUDIT_ROOT/ (evidence + scripts remain there)"
tags:
  - wordpress
  - wp-audit
  - release-audit
  - template
related:
  - '[../playbooks/future-release-audit-template](../playbooks/future-release-audit-template.md)'
---

# Future WordPress release-audit prompt — phase 1, any release

> Paste the fenced block below into a fresh session to open a phase-1 audit for any future WordPress
> core release (7.2 and beyond). It carries no 7.1-specific assumptions — every version number,
> ticket number, date, `db_version`, port, fixture name, and Gutenberg range in the 7.1 corpus was
> specific to that cycle and must not be copied forward. The rules encoded here (gates, source
> universe, evidence, controls, negative-control preservation, reporting contract) are what survived
> calibration across the WP 7.1 learning loop at `$WP_AUDIT_ROOT/`
> — grounded in `learning/failure-mode-register.csv` (FM-*), `learning/method-change-proposals.csv`
> (MC-*), `learning/shadow-run-results.csv` (SR-*), and `methods/detection-rules.csv` (D-*).
> Register schemas and id definitions: [registers.md](../method/registers.md).
>
> **Path note (2026-08-21).** The fenced block is preserved as written; one path inside it has
> since moved — `deliverables/codex-feature-chain-test-generation-prompt.md` is
> [`prompts/codex-feature-chain-test-generation-prompt.md`](codex-feature-chain-test-generation-prompt.md)
> in this repo. Substitute when reusing.

## Placeholders

| Placeholder | Meaning | Fill with (do not copy the 7.1 example) |
|---|---|---|
| `$VERSION` | the release under audit | e.g. `7.2` |
| `$PRIOR_STABLE` | last released stable version before `$VERSION` — upgrade-path control | e.g. `7.1` |
| `$PRIOR_BETA` | an already-released beta of `$VERSION` — second upgrade-path control | e.g. `7.2-beta3` |
| `$TARGET_LABEL` | the exact build label under test right now | e.g. `rc1`, `beta2`, or the final version string |

## Values that must be re-derived at run time — never copied from a prior cycle

- **Version numbers** anywhere in this prompt or its output (7.1-cycle examples in the learning loop
  are historical artifacts, not templates to fill in with the new number and reuse otherwise).
- **Trac ticket numbers.** Each release has its own milestone population; a ticket number from a
  prior cycle proves nothing about `$VERSION`.
- **Dates** — announcement dates, beta/RC/final dates, register `fetched_at` timestamps.
- **`db_version`** — the option value WordPress bumps on every release; read it from the live fixture,
  never assume the prior cycle's number.
- **Ports** — `wp-env` assigns fresh ports per project; Studio assigns its own. Print, don't assume.
- **Fixture / project names** — name every Studio/wp-env fixture with `$VERSION` and `$TARGET_LABEL`
  baked in (e.g. `codex-wp72-beta2-multisite`), so a stale fixture from a prior cycle can never be
  silently reused under a new name.
- **The Gutenberg version range bundled into core** — changes every release. Look it up fresh from
  that release's Field Guide / dev notes; do not assume the 7.1 range applies.

---

## The prompt

```
<role_and_scope>
You are opening a phase-1 audit of WordPress core release $VERSION. Phase 1 builds the evidence base
(build-identity verification, four-register source universe, change ledger with challenge verdicts,
evidence records, blocker queue). Phase 2 — interaction/chain testing across features — is a separate
prompt; do not attempt it here. Read-only research only: GET requests, no logins, no form submissions,
never fight core.trac.wordpress.org's bot challenge (see known_tool_ceilings). User-Agent
"wp-release-audit ($VERSION, read-only enumeration)", ~1 request/sec on wordpress.org properties.
</role_and_scope>

<build_identity_gate priority="FIRST">
Before any pilot testing, runtime reproduction, or claim that a build "is" $TARGET_LABEL, run the
build-identity gate. Do not skip this because a build "looks" ready or a date has passed.

Procedure (generalizes scripts/rc_build_identity.sh — adapt the version/label args, keep the logic):
1. Fetch the WordPress.org release-announcement feed. Normalize both the feed titles and
   "$VERSION $TARGET_LABEL" by lowercasing and stripping spaces/dots/hyphens before comparing —
   feed titles use human forms ("WordPress 7.1 Beta 4") that a naive string match will miss
   (this exact miss produced a false WAITING verdict on a real release; see SR-05 below).
2. HEAD the expected package URL (https://wordpress.org/wordpress-$VERSION-$TARGET_LABEL.zip or
   the equivalent final-release path) and record the HTTP status.
3. Fetch wp-includes/version.php from the wordpress-develop trunk mirror as a third signal.
4. VERDICT=RELEASED only if the announcement matches AND the package returns 200. Otherwise
   VERDICT=WAITING-FOR-<TARGET_LABEL>, exit non-zero.
5. If WAITING: do source-reading and register work, but do NOT run any runtime/pilot test against
   $TARGET_LABEL, and do NOT report a result under that label. Never test the newest available build
   and call it $TARGET_LABEL — that is testing a mislabeled build. State plainly that the gate is
   holding and what signal would flip it.

This gate is calibrated, not assumed-correct: on first run it produced a false WAITING (feed title
"Beta 4" vs an un-normalized pattern "7.1beta4") until normalization was added (SR-05,
MISCALIBRATED-FIXED). Its negative control — a nonexistent version — correctly returns WAITING
(SR-06, CLEARED-SUSPECTED). Its live positive control correctly held an unreleased RC1 pilot
(SR-04, CAUGHT-REAL-ISSUE). Source: D-03 in methods/detection-rules.csv.
</build_identity_gate>

<source_universe>
Once (or while, source-only) the gate clears: build the source universe across FOUR mandatory
registers. No register may be skipped or declared "probably fine" — each needs a recorded per-unit
result, not a general impression.

1. MAKE.WORDPRESS.ORG TEAM-SITE MATRIX. Enumerate the CURRENT team-site directory live from
   make.wordpress.org — never work from a fixed/remembered list. One row per team x $VERSION, using
   that team's REST API, tags/categories, archives, and site search, across version forms
   ("$VERSION", "$VERSION" with a hyphen, "WordPress $VERSION", and any release-specific label).
   Result codes, exactly one per team: RELEVANT-HITS-REVIEWED | ZERO-HITS-VERIFIED |
   NOT-ACTIVE-IN-WINDOW | BLOCKED.
   RULE: a team is not clear because a general web search returned nothing. Clearance requires the
   recorded per-team pass (routes checked, query forms used, pages checked, pagination_complete
   yes/no+reason, hit_count, relevant_count, relevant_urls, reason, fetched_at).

2. GITHUB `WordPress` ORG REGISTER. Enumerate ALL public repos in the org (paginate to the end;
   record archived status). One relevance ruling per repo: relevant / not-relevant /
   archived-not-in-window, one-line reason. For every relevant repo, one query record per $VERSION
   covering release branches, tags, changelogs, milestones, projects, labels, issues, merged PRs,
   commits. Never assume the release-branch repo + the editor repo + the docs repo are the whole
   population — explicitly check documentation/doc-issue repos, blog content/trackers, Playground,
   performance, default themes, and test repos. Use repo source and diffs to confirm implementation,
   not API docs alone. Declare every rate-limit or pagination cap explicitly — no silent truncation.
   See known_tool_ceilings for why PR-merge status is not usable evidence here.

3. CORE TRAC CENSUS. One row per milestone ticket for $VERSION — the complete milestone population
   as far as allowed routes permit, not only highlighted/Field-Guide-cited tickets. Reconcile: total
   milestone tickets + status counts; closed/fixed with changesets; reopened/moved/duplicate/
   invalid/wontfix/future-release; component distribution; learner-relevant keywords; release-branch
   changesets that don't reconcile to the milestone list; late backports/reversions. Allowed routes
   ONLY: Trac MCP (status/milestone/owner/type are reliable; descriptions are placeholders — see
   known_tool_ceilings), SVN/Git mirror commit messages ("Fixes #NNNNN"), changeset links, official
   exports. A GitHub mirror commit proves a commit — it does not by itself prove current Trac status
   or milestone metadata; verify metadata via the MCP. Record, per row, which fields were verified
   via which route and which remain BLOCKED with reason. Expect the never-committed open-ticket tail
   to be only partially enumerable through these routes — document the gap explicitly, do not paper
   over it with an estimate.

4. SOURCE OF TRUTH REGISTER. For every available third-party or community "source of truth" edition
   covering $VERSION: record edition, publication/updated dates, stated scope, changelog deltas since
   last import, and per-claim canonical links. Cross-check each claim against primary sources
   (dev notes, Field Guide, source) rather than trusting the secondary summary. If the spec for this
   register is ambiguous or the publisher list might be incomplete, say so rather than guessing.

Also fold in, wherever they naturally attach to the four registers above: release announcements and
the release archive; the Make Core version page, Field Guide, and complete dev-note set for
$VERSION; wordpress-develop source, release branches, commits, tests; the editor's release posts,
merged PRs, and the exact bundled-plugin version range shipped in $VERSION (re-derive — see
placeholder table above); the Learn platform's REST API, sitemaps, and rendered public pages;
Training Team handbook guidance and current issues/PRs (read-only).
</source_universe>

<change_ledger_and_challenge>
Build a change ledger: one row per shipped/changed feature for $VERSION, each with a provenance
column recording where it was first observed and an import_confidence if imported from a prior pass.
Rank evidence by tier when a claim and a source disagree: tested-build behavior > canonical
source/code > dev notes/Field Guide > Trac/PR metadata > release hub > supporting summaries.
Supporting summaries (third-party roundups, SoT editions) help FIND evidence; they never outrank
primary source, code, or tested behavior.

Every ledger row (imported or freshly discovered) gets exactly one challenge verdict, earned against
the four-register universe:
- UPHELD — register/universe evidence INDEPENDENTLY CONFIRMS the row. Cite the specific register row
  or evidence record. Absence of contradiction is NOT evidence — UPHELD requires a positive citation,
  not a failed search for a counter-example.
- REVISED — the row survives but a specific field is wrong or outdated; state the exact correction
  and its evidence.
- REFUTED — counter-evidence exists; show it.
- UNVERIFIED — the universe has no bearing evidence yet; state precisely what's missing and which
  route (or which future artifact, e.g. an unpublished Field Guide) could resolve it. Do not guess
  and do not silently promote UNVERIFIED to UPHELD later without a new citation.

New material the registers surface that no prior pass saw becomes a NEW row with its own id — never
a silent edit folded into an existing row. Ledger-vs-register matching is SEMANTIC: a register keyed
on ticket numbers and a ledger keyed on dev-note titles will not join cleanly by key alone, and a
blank key-join does not mean the change is missing from the ledger (this exact key-join overstated a
"delta" by an order of magnitude in the 7.1 loop — see known_tool_ceilings / FM-22 in the summary
deliverable).

Close phase 1 only when: every team in the Make matrix has a result; every org repo has a ruling;
the Trac census reconciles or documents its exact gap; the SoT register is current; and every ledger
row has a challenge verdict.
</change_ledger_and_challenge>

<evidence_records>
Every non-trivial claim — every UPHELD/REVISED/REFUTED verdict, every confirmed finding, every
detector positive/negative control result — gets a written evidence record, not just a narrative
sentence. Record: URL, fetch timestamp, HTTP status, extraction locator (what selector/field/line
you read), excerpt (≤200 characters, quotes throughout this audit stay ≤15 words), the body's
SHA-256, and the exact replay command. A finding without one of these is not yet a finding — it is a
narrative assertion, and narrative assertions without an underlying payload record do not survive
review.
</evidence_records>

<method_rules>
- RUNTIME DECIDES. Source reading and cross-model/cross-agent agreement raise a claim's priority for
  investigation; only executed output in an authorized local environment confirms it. Do not let
  static analysis, a single benchmark run, or agreement between two models stand in for proof.
- CONTROLS ARE MANDATORY. Before any detector, script, or repeatable check counts as calibrated,
  it needs a positive control (a case it must catch) and a negative control (a case it must clear
  cleanly). A check with only a positive control is unproven — it may be flagging everything.
- HARNESS-HEALTH PRECHECK before each test batch: verify daemon/socket/container/filesystem health
  and fixture-file ownership BEFORE classifying any result as a product finding. A harness fault
  (storage corruption, a tool silently deleting its own fixture, a container daemon in a bad state)
  is an INVALID batch, not a product failure — exclude it from all counts and record the diagnosis.
- Do not claim a "reproduction" from a fixture whose deviation from expectation is undiagnosed.
  Diagnose invocation-vs-fixture before calling anything reproduced.
</method_rules>

<threat_model_gate>
For any finding touching authorization, sanitization, upload, or deletion, state before reporting:
attacker position (unauthenticated / subscriber / contributor / admin / super admin / code already
executing inside WordPress), the boundary crossed, and default-configuration reachability.
- An API or code path reachable only by code already executing inside WordPress is an INTERNAL
  FOOTGUN, not a vulnerability — do not inflate its severity.
- A result that only appears under a CUSTOM capability grant or non-default configuration is
  CONFIGURATION-DEPENDENT — state the exact configuration required; do not report it as a
  default-install finding.
Sensitive detail (anything that could function as an exploit writeup, and any credential that
surfaces during testing) goes to a private/security-only location — never into a general report,
memory, or summary. Credentials in particular never enter any report or memory file, full stop.
</threat_model_gate>

<a11y_calibration_rule>
For any claim about keyboard or focus behavior, a NATIVE HTML control (a plain button/link/input) in
the SAME harness must respond correctly to the SAME synthetic input BEFORE any product verdict is
recorded. If the native control does not respond as expected, the result is an AUTOMATION FAILURE,
not a product failure, and no verdict is recorded until the automation is fixed and re-run. This
single rule has previously reversed a wrong verdict: an initial run reported a keyboard defect as
INCONCLUSIVE partly because its own native-control check ALSO failed (an automation fault), and only
a rerun with a passing native control correctly reached CONFIRMED.
</a11y_calibration_rule>

<performance_rule>
Treat any performance/timing claim as unproven from a single run. Require repeated runs (not fewer
than 3, more if variance is high) against a FIXED, versioned dataset/fixture that does not change
between runs — a performance comparison against a dataset that drifted between runs proves nothing
about the release. Report the raw per-run numbers, not only an aggregate; a single benchmark run
never counts as proof, no matter how large the delta looks. (This is a standing operating rule
carried into phase 1; no performance detector has yet been built or calibrated in this loop's D-01
through D-07 — treat any performance finding here as INCONCLUSIVE until a comparable detector is
calibrated with its own positive and negative control.)
</performance_rule>

<fixture_and_denominator_rule>
Before reading ANY result — an "N/N succeeded" message, a count, a pass/fail — print and record the
fixture's actual state: full site inventory (not the number you expect), status flags (archived/
spam/deleted or equivalent), db_version, active plugins, PHP/WP versions, and single-site vs
multisite mode. An "N/N success" on a multisite network is only as informative as N is complete —
sites excluded by status flags from a network operation will silently stay on the old db_version
while the operation still reports success, and a network's site count can silently drift between
when a claim is written and when it's tested. Never read a numerator without asserting its
denominator first.
</fixture_and_denominator_rule>

<negative_controls>
Preserve every refuted or narrowed claim as a PERMANENT negative control — do not delete disproven
findings, re-file them under a new mechanism without re-deriving it, or quietly drop them from the
suite. Do not resurrect a refuted claim without a genuinely NEW mechanism and a fresh reproduction;
"it might still be true in some other configuration" is not a new mechanism. If a preserved negative
control starts failing on a later release, treat that as a signal the harness or the assumption is
wrong before treating it as a new product defect — re-derive from first principles rather than
assuming the old refutation still holds. (See the loop's own set of 9 preserved negative controls in
the method-improvements-summary deliverable for the shape this should take.)
</negative_controls>

<blocker_remediation_queue>
Every finding marked BLOCKED — not just noted as blocked in passing — gets a queue row: remedy tier
(what unblocks it: a fixture that needs building, an owner's approval, a human browser session, a
future build), owner, the exact access/artifact requirement, and closure condition (the specific
observable event that would let it be retried). A BLOCKED row with no queue entry is a dropped
finding, not a documented one.
</blocker_remediation_queue>

<reporting_contract>
Report mechanism FIRST, then proof — explain WHY something happens before citing the evidence that
it does. Keep separate counts for CONFIRMED / REFUTED / INCONCLUSIVE / BLOCKED / INVALID; never
collapse them into a single "issues found" number. These five words are the only verdicts — do not
invent synonyms. Never present any of the following as proof on their own: agreement between two
models or two agents (raises priority only), a static-analysis warning with no runtime confirmation,
or a single benchmark/timing run. List every planned check you did NOT run, with the exact blocker,
rather than omitting it silently.
</reporting_contract>

<known_tool_ceilings>
- Trac's bot challenge on core.trac.wordpress.org: NEVER attempt to bypass it. If it blocks a route,
  record the route as blocked and use an allowed alternative (Trac MCP, SVN/Git mirror, official
  exports) instead.
- Trac MCP: searchTickets CANNOT filter by milestone (both `milestone=X` and `milestone:X` forms
  fail) — you must enumerate and filter client-side. getTicket's `component` field is blank on every
  call regardless of the ticket — do not report component distribution as MCP-sourced; it is
  unrecoverable via this route. At scale (400+ tickets), the never-committed/open-ticket population
  remains only partially enumerable through allowed automated routes — closing that gap requires a
  human browser session against Trac's query UI. Do not claim full open-ticket coverage without one.
- GitHub mirror PR-merge status on wordpress-develop (and similar SVN-mirrored repos) is
  STRUCTURALLY MEANINGLESS: the mirror bot-closes PRs rather than merging them, so an org-wide
  `is:pr is:merged` query can legitimately return zero even when hundreds of changes shipped. Never
  use PR-merge status as evidence of what shipped on a mirrored repo — use the commit/changeset
  trail instead.
- Version-string text search structurally MISSES posts/pages whose body never contains the literal
  version string (a canonical test-call post for a prior release scored zero literal hits on its own
  version number, and was findable only through a cross-team redirect). Supplement any version-form
  search with a date-window pass and cross-post-redirect enumeration — do not treat a zero-hit
  version-string search as clearance.
</known_tool_ceilings>

<phase_2_pointer>
When phase 1 closes (coverage gate met per change_ledger_and_challenge, and build_identity_gate has
verified $TARGET_LABEL), move to interaction/chain testing:
deliverables/codex-feature-chain-test-generation-prompt.md
It composes two or more shipped features and tests their INTERACTION rather than each feature alone
— every confirmed defect in the source cycle lived in an interaction, not a single feature. Its chain
seeds (C-01 through C-10) are 7.1-specific; a new cycle needs fresh chain seeds drawn from THIS
release's UPHELD/REVISED ledger rows, but the machinery — fixture/denominator assertion, mandatory
controls, harness-health precheck, threat-model gate, a11y native-control calibration, and the same
five-verdict reporting contract — carries forward unchanged. Do not run chain tests against a build
this phase's gate has not verified as $TARGET_LABEL.
</phase_2_pointer>
```

---

## Rule provenance

| Prompt section | Traced to |
|---|---|
| `build_identity_gate` | D-03; SR-04, SR-05, SR-06; FM-16 |
| `source_universe` | run-spec's four-register requirement (Make matrix, GitHub org register, Trac census, SoT register); FM-20, FM-21, FM-26 |
| `change_ledger_and_challenge` | FM-22; the r2 challenge protocol's UPHELD/REVISED/REFUTED/UNVERIFIED verdicts |
| `evidence_records` | FM-23; MC-13 |
| `method_rules` | MC-17; MC-09 (H-01, H-02); FM-13, FM-14, FM-16, FM-17 |
| `threat_model_gate` | FM-07, FM-12, FM-18; MC-11 |
| `a11y_calibration_rule` | FM-06; MC-10; D-07 |
| `performance_rule` | Standing operating rule requested for this prompt — not yet exercised by any FM/SR case; no performance detector exists in D-01–D-07 |
| `fixture_and_denominator_rule` | FM-03, FM-15; MC-08; D-04 |
| `negative_controls` | FM-08, FM-09, FM-10, FM-11, FM-12, FM-25, FM-27 (+ FM-03, FM-07 — the full 9-row negative-control set); MC-12 |
| `blocker_remediation_queue` | FM-24, FM-10, FM-17; MC-15 |
| `reporting_contract` | MC-17; the chain-test prompt's five-verdict contract |
| `known_tool_ceilings` | FM-21 (Q-01), FM-22 (Q-02), FM-26, FM-27; MC-19 (REJECTED), MC-20 (DEFERRED) |
