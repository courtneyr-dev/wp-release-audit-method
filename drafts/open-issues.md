# Issue drafts for the self-declared gaps — not filed

CONTRIBUTING.md ranks these as the highest-value open contributions, but the repo has had
no issues for anyone to claim — someone wanting to run the Lando driver or the performance
benchmark had no ticket to comment on. One body per gap below, ready to open with
`gh issue create`. The operator files them; delete each from here once opened.

**AI-disclosure — append this to every issue you file from here.** These bodies were
AI-drafted (reviewed by you before filing), which meets the "meaningful contribution" bar in
the [WordPress AI Guidelines §1.2](https://make.wordpress.org/ai/handbook/ai-guidelines/), so
disclosure is required — in the issue body (or the PR description / Trac ticket comment, the
locations the guideline names). Paste this at the end of each and edit `Used for:` to match:

```
## Use of AI Tools
AI assistance: Yes
Tool(s): Claude Code
Used for: Drafting this issue from the repo's own CONTRIBUTING notes and known gaps;
I reviewed it, verified the file paths and claims, and take responsibility for it.
```

---

## 1

**Title:** Run the Lando driver once — either result removes the unverified banner

**Body:**

`scripts/env/lando.sh` has never been executed. Not one line. It was written against
docs.lando.dev on a machine with no Lando installed, its header says exactly that, and by
this repo's own standard every capability it reports is a hypothesis.

If you run Lando, this is a genuinely useful hour:

```
bash scripts/env/conformance.sh lando       # contract checks, no WordPress needed
bash scripts/crud-suite.sh --env=lando ~/my-lando-site
```

The file header carries a verification checklist, one line per claim, naming what each
command settles. "I ran it and it worked" is as valuable as a bug report — either one
removes the banner. If the driver over-claims a capability, that's the exact failure the
design exists to prevent, and we especially want to hear it.

Done when: both commands have run against a real Lando site and the header's checklist
lines each carry a result.

---

## 2

**Title:** Exercise the performance playbook — one benchmark with its noise floor

**Body:**

`playbooks/performance-release-audit-playbook.md` is titled UNEXERCISED and means it: no
benchmark has ever been run against it, and release-day reporting deliberately carries no
performance line because of that. The shortest path out is in the playbook's own "How to
exercise this playbook" section — two fixtures differing only in WordPress version, one
workload the release actually changed, twenty same-build runs to establish the noise
floor, then interleaved comparison runs, reported as median and spread.

The negative control is the credibility step: benchmark two identical builds and confirm
the method reports "no difference."

Done when: one benchmark exists with its noise floor recorded, and the playbook's
UNEXERCISED banner can honestly change.

---

## 3

**Title:** A worked example for a plugin or theme author

**Body:**

`examples/` is all core testing. `plugin-theme-authors/` explains the method for
extension authors but shows nobody actually doing it. One worked investigation — a real
plugin, the release-diff method applied, a surface inventory, a finding or an honest
"checked and cleared" — would be the missing bridge between the two halves of the repo.

A refuted or inconclusive result is welcome and gets merged; it becomes a negative
control. Follow the evidence shape in `examples/chains/C-02/` (register row, run script,
both controls, evidence file).

Done when: one `examples/` entry exists whose subject is an extension rather than core.

---

## 4

**Title:** `wp menu` coverage in crud-suite.sh — the known scripted-coverage hole

**Body:**

Nav menus (classic and Navigation block) are on the browser checklist and have no script
asserting them — the README and the party skill both call this out as the known hole.
`crud-suite.sh` needs a menu section: create a menu, add items, assign to a location,
assert front-end render, delete, verify cleanup. The Navigation-block half may only be
REST-assertable; saying exactly which half a script can prove is part of the value.

Done when: crud-suite has menu cells with a positive and negative control, and the
"browser only — no script yet" caveats come out of the docs.

---

## 5

**Title:** Exercise the core-rollback mechanics on a disposable fixture

**Body:**

`method/rollback.md` now exists. Its two plugin escape hatches are exercised; the
core-rollback section (old zip over a new tree, what happens to `db_version` and content)
is written and has never been run — it says so in its own header. One afternoon: seed a
fixture with real content on the current stable, upgrade it to the newest release, then
roll the files back and document what the old code does with the new data. The interesting
result is the content diff, whatever it shows.

Done when: the section's UNEXERCISED marker is replaced with dated evidence, in either
direction.

---

## 6

**Title:** The `cli` driver over SSH — the written-but-unproven remote path

**Body:**

The `cli` driver is tested against local paths. Pointed at a remote `wp @alias` it is
written to fail safely — dropping `hostfs` and `shell` rather than guessing — but that
path has never run. If you have a staging box behind an alias: run the CRUD suite through
it and report which capabilities it declared. Over-claiming is the bug we're fishing for;
under-claiming costs a few BLOCKED cells and is fine.

Done when: one run against a real `wp @alias` target is recorded, and the known-gaps line
about it comes out of the README.

---

## 7

**Title:** Run the ecosystem pair block against a premium-plugin stack

**Body:**

The T1 sweep now carries an ecosystem block (`method/ecosystem-compatibility-lane.md`):
co-installed pairs upgraded across the release boundary, the closure-trigger probe, and
fleet tracker triage. The pair cells have a structural limit — premium plugins can't be
fetched from the directory API, so a tester without licenses records
`BLOCKED(premium-license)`. That is exactly the blind spot that made the WP Rocket 7.1
outage invisible to automated compatibility testing (see Trac #65920, which its own author
notes wouldn't have caught it).

If you hold licenses for premium plugins in the top co-installed categories (caching, SEO,
page builders, eCommerce): build the pair fixture, run the block across the next
prerelease boundary, and report — including "no new fatals," which is a real result.

Done when: one recorded run of the pair block includes at least one premium plugin.
