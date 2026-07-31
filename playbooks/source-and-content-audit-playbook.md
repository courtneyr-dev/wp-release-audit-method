---
title: "Source and content audit playbook"
type: playbook
status: active
created: '2026-07-31'
updated: '2026-07-31'
source_run: "$WP_AUDIT_ROOT/ (evidence + scripts remain there)"
tags:
  - wordpress
  - wp-audit
  - source-universe
  - content-audit
related:
  - '*../index*'
  - '*llm-wiki-wp-training/wiki/index*'
---

# Source-and-content audit playbook

Operator-grade procedure for source-of-record and content-claim verification. Every rule cites the FM-/MC-/SR- row it comes from; where the task scope named something this loop's four registers don't define, that gap is called out rather than invented.

## The four-register source universe

Content and source-of-record claims are checked against four independent registers, not one search. Each register carries its own per-item result code so a "zero hits" claim is distinguishable from "not checked."

| Register | What it covers | Result codes |
|---|---|---|
| Make team-site matrix | Per-team WordPress.org Make blog (Core, Hosting, Docs, Themes, Plugins, etc.) | RELEVANT-HITS-REVIEWED / ZERO-HITS-VERIFIED / NOT-ACTIVE-IN-WINDOW / BLOCKED |
| GitHub org register | Per-repo relevance ruling across the WordPress GitHub org | Relevance ruling per repo, with a mirror caveat where the repo is an SVN mirror (see below) |
| Trac census | Ticket-level census via allowed MCP routes only | Subject to a documented ceiling (see below) |
| Source-of-Truth (SoT) register | Canonical per-feature reference used to settle disputes between sources | — |

ZERO-HITS-VERIFIED is a distinct code from "not checked" for the same reason the content-claim guard exists below: absence of a hit is only evidence of absence once you've confirmed you were looking at content, not chrome. [MC-06 principle, applied here to source-register discipline]

Per-repo GitHub rulings must account for mirror status before treating merge signals as evidence. `wordpress-develop`'s GitHub mirror bot-closes PRs against the canonical SVN commit — an org-wide `is:pr is:merged` search returned 0 across 12,734 PRs, 9,519 of them closed. PR-merge status is never usable as evidence on a mirror repo. [FM-27; MC-19 REJECTED]

The Trac census runs through allowed MCP routes only — no fallback to unauthenticated scraping or an ad hoc browser session to fill gaps mid-pass. Its documented ceiling: `searchTickets` cannot filter by milestone (both `milestone=7.1` and `milestone:7.1` failed) and `getTicket`'s component field was blank on all 430 calls at that scale. A full open-ticket census — roughly 84 tickets remained unenumerable in the r2 pass — needs a human browser session on Trac's query UI; that path is DEFERRED, not attempted by the automated census. [FM-26; MC-20 DEFERRED]

## Query rules

| Rule | Statement | Grounding |
|---|---|---|
| Q-01 | Version-form search (searching for the literal version string, e.g. "7.1") structurally misses posts whose text never contains it. Supplement with a date-window search plus cross-post-redirect enumeration. | FM-21 — Hosting's canonical RTC test post had zero literal "7.1" occurrences in `content.rendered`; it surfaced only via a cross-team redirect. |
| Q-02 | Coverage comparison against the change ledger is semantic, never a key-join on ticket number alone. | FM-22 — a ticket-number join produced a 247-ticket "not covered by the ledger" delta that was partly already covered; ledger rows cite dev notes and announcements, not ticket numbers, so the join overstated the gap. Corrected via semantic matching. [MC-14] |

## Content-claim rules

Content claims — does this page's body actually contain X — run through the D-01 extractor, with one accepted path and one rejected fallback.

**REST path (accepted).** For `learn.wordpress.org` lesson/course/tutorial URLs, pull `content.rendered` from the REST API as ground truth and compare it against raw-page text. This is the only path that cleared both its positive control (the audit's sole P0 finding survived extraction) and its negative control (a sidebar `aria-label` term was correctly killed as chrome-only). [D-01; SR-07; SR-08; MC-04 ACCEPTED-WITH-LIMIT]

**Structural-strip fallback (rejected).** For non-REST pages, an earlier design stripped `nav`/`aside`/`header`/`footer` tags and treated what remained as content. It failed its own negative control — an in-body Table of Contents widget on a developer.wordpress.org page isn't inside any of those stripped tags, so it read as a false CONTENT-HIT. [SR-09 NOISE; MC-05 REJECTED] The fallback path stays in the tool, but only as advisory output — the script itself prints a warning that the fallback path is not accepted.

Two guards sit on top of the extractor:

- **GATED-OR-EMPTY guard.** Content under roughly 200 characters is reported as GATED-OR-EMPTY (enrollment gate or JS-only render), never as "term absent." Before this guard existed, every gated lesson silently read as a clean, collision-free page — 42 gated items in the r1 BLOCKED population were affected by exactly this. [D-01; MC-06 ACCEPTED; SR-10]
- **Retired title-term selection.** Choosing which pages to check by keyword-in-title had a 3/25 true-hit rate on the first pass and 0/17 on the next. It's retired, replaced by version-taxonomy and change-surface selection, and kept as a permanent negative control — do not reintroduce it. [MC-16; FM-25]

## Disposition vocabulary and the announcement-level vs. polish-level bar

**Grounded elsewhere — provenance supplied by the orchestrator 2026-07-30.** The drafting pass correctly reported that none of this loop's four registers define these concepts, and declined to invent them. They are real, and their evidence lives one run over in the frozen content audit: `$WP_LEARN_AUDIT_ROOT/import/imported-inventory.csv` (136 rows carrying the dispositions) and `$WP_LEARN_AUDIT_ROOT/manifest.json` (the bar, recorded at shard-D1 acceptance).

- **Disposition vocabulary** (content lane only): `REVISE-P0` (wrong when the release ships) · `REVISE-P1` (usable but omits an important workflow) · `VERIFY-RC` · `CREATE` · `MERGE` (superseded; target must be named and fetched) · `RETIRE` · `NO-CHANGE` (reviewed and accurate — never "unexamined") · `BLOCKED` · `PROVISIONAL` · `TRANSLATION-REFRESH`. Final r2 distribution: 60 NO-CHANGE / 42 BLOCKED / 15 MERGE / 12 REVISE-P1 / 6 PROVISIONAL / 1 REVISE-P0.
- **The announcement-level vs. polish-level bar:** omitting an *announcement-level* additive feature is `REVISE-P1`; omitting a *polish-level* change (one sourced only from a Trac ticket or a compiled summary) is `NO-CHANGE` with a note. Without this bar every page fails on trivia. It was formulated mid-run and then applied retroactively — the D1 delta re-screen re-graded 24 previously-cleared items against 54 later-added changes and upheld all 24, which is the closest thing to a control this rule has.
- **Standing caveat:** this bar has a positive control (the gallery-omission P1 it was derived from) but no true negative control. Treat it as ACCEPTED-PROVISIONAL and give it a control pair before it governs disposition in a new release.

Alongside these, keep the runtime verdict vocabulary — CONFIRMED / REFUTED / INCONCLUSIVE / BLOCKED / INVALID (security-release-audit-playbook.md) — plus the GATED-OR-EMPTY state the extractor emits. [D-01; MC-06]

- Resolve every content claim to the existing verdict vocabulary — CONFIRMED / REFUTED / INCONCLUSIVE / BLOCKED / INVALID (security-release-audit-playbook.md) — plus the GATED-OR-EMPTY state where the extractor emits it. [D-01; MC-06]
- If an announcement-level-vs-polish-level severity split is adopted later, give it a positive and negative control before it governs a real disposition — the same control-discipline standard every other rule in this loop is held to before it's marked ACCEPTED.

## Blocker-remediation queue

Every BLOCKED row gets a tier, an owner, an access requirement, and a closure condition — not just the word "BLOCKED." Before this rule existed, 28 of 42 BLOCKED rows in the r1 pass had no route to remedy; an independent Codex set-join surfaced the gap. [FM-24; MC-15 ACCEPTED] The r2 pass produced a 53-row queue under this rule.

The drafting pass flagged that the three content-gate tiers weren't defined in the four registers. Correct — and the orchestrator supplies the missing provenance here, because all three were reproduced live on 2026-07-30 against learn.wordpress.org (captured in `evidence/SR-08-SR-10-content-chrome-and-gated.txt` and the r2 run's shard evidence):

| Gate tier | Reproduced signal | Does authentication alone fix it? |
|---|---|---|
| Self-register text gate | Page renders the string "Please register or sign in" | **Yes** — a logged-in enrolled account can read it |
| Admin-only enrollment gate | Page renders "contact the course administrator" | **No** — needs Training-Team-granted enrollment |
| JS-only Course Theme player | Title renders, zero non-script body markup, REST `content.rendered` = 0 chars, no gate text at all | **No** — needs a JS-executing browser regardless of session |

The distinction is operational, not taxonomic: it tells you whether a blocked item is unblocked by a login, by someone else's permission grant, or by a different fetching technology. A single "BLOCKED" label hides that. The table below applies the MC-15 schema to this loop's own blocked rows; owner values are illustrative role labels, not entries copied from the r2 queue.

| Blocker tier | Example | Owner (illustrative) | Closure condition |
|---|---|---|---|
| Enrollment gate | Learn lesson content gated behind course enrollment — reads as GATED-OR-EMPTY, not absence | Content-audit lane | Enroll a test account, or accept GATED-OR-EMPTY as the final disposition |
| JS-only render | Content rendered client-side only (interactive/video embeds) — same GATED-OR-EMPTY signal from the extractor | Content-audit lane | Headless-browser render, or accept GATED-OR-EMPTY |
| Upstream-ticket ownership | A CONFIRMED defect maps onto an existing, currently-open Trac ticket (#65517, REOPENED) | Operator | Operator approval to comment; never a new filing [FM-04; MC-18 REJECTED] |
| Fixture/infrastructure gap | wp-env's `.htaccess` lacks the legacy ms-files rewrite, so the public-serving path can't be exercised | Harness owner | Build FX-09 (legacy rewrite fixture, currently PROPOSED) [FM-10] |
| Tooling availability | Studio HTTP unavailable or CLI not installed in a given run | Harness owner | Studio CLI path now recorded (`/Applications/Studio.app/Contents/Resources/bin/studio-cli.sh`); start the site before the pass [FM-17] |
| Tool/API ceiling | Trac MCP route can't filter by milestone; component field blank at scale | Operator | Human browser session on Trac's query UI (DEFERRED) [FM-26; MC-20] |
