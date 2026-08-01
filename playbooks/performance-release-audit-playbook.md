---
title: "Performance release-audit playbook (UNEXERCISED)"
type: playbook
status: active
created: '2026-07-31'
updated: '2026-07-31'
source_run: "$WP_AUDIT_ROOT/ (evidence + scripts remain there)"
tags:
  - wordpress
  - wp-audit
  - performance
  - release-audit
related:
  - '*../index*'
  - '*../release-audit-learning-loop*'
---

# Performance release-audit playbook

> **Where this fits:** the performance axis of [`wp-release-followup`](../skills/wp-release-followup/SKILL.md) §3.
> **This playbook is unexercised** — it states acceptance criteria; no benchmark has been run against it.
> Hand it to an SRE as a design to execute, never as a result — see
> [handing off performance work](../skills/wordpress-audit-handoff/SKILL.md#performance).
> Until baselines exist the correct posture word is **unverified**, not *good*.

## Status: design only — UNEXERCISED

No performance benchmark has been run in this loop. All 15 shadow-run rows (SR-01–SR-15) and all 27 failure-mode rows (FM-01–FM-27) were reviewed for this document: none carries a performance category, a timing measurement, or a throughput measurement. SR-14 and SR-15 are the loop's only UNEXERCISED rows, and both are blocked on an RC1 build for the upgrade-lane detector (D-06) and the accessibility calibration harness (D-07) — neither is a performance test.

This playbook is therefore a design with acceptance criteria, not a calibrated method. Nothing below has cleared a positive/negative control pair the way D-01 through D-05 have. Every number in this document is a proposed default, not a validated threshold, until it clears its own shadow run and gets promoted into detection-rules.csv and test-and-fixture-registry.csv the way the other detectors did.

## Repeatable dataset definition

A performance claim is only as good as the dataset it ran against. Define and record a fixed-scale, seeded dataset with a `dataset_id` before any run:

- Post count, attachment count, and block count per post — fixed and reproducible, not "representative."
- Taxonomy/term counts if the surface under test touches term queries.
- The exact seeding script or command and its checksum, so the dataset can be rebuilt identically on a second machine or a later date.

Scale target: the loop's one existing signal on content scale at volume is the r1 content audit's attachment-count discrepancy — the REST API reported 3,437 attachments while returning only 3,305 to an anonymous client (attachment visibility filtering). That is a content-audit finding, not a performance one, but it establishes that visibility/paging effects are real at that scale. The chain-seed hypothesis for Media Library scale names 5k+ attachments as the point where infinite-scroll paging, the REST total, and per-role visibility can disagree — treat 5k+ as the dataset size to validate against, not as an established benchmark number. [deliverables/codex-feature-chain-test-generation-prompt.md, chain C-10]

## Baseline-vs-change comparison: repeated runs required

A single benchmark run is never proof. No performance shadow run exists to calibrate this from directly, but the rule generalizes a pattern this loop has hit repeatedly: first-run output has been wrong in ways only a second, controlled run caught.

- The build-identity gate's first calibration run reported it would never fire RELEASED, because the release-feed title format didn't match the comparison pattern; only a second run, after fixing label normalization, was trustworthy. [D-03; SR-05 MISCALIBRATED-FIXED]
- The Playground-blueprint decoder's first run flagged a false embed-present on a page with no Playground block, because it matched the plugin's site-wide enqueued script instead of the block itself; only a tightened second run was trustworthy. [D-02; SR-12 MISCALIBRATED-FIXED]
- The content extractor's gated-content guard needed a dedicated negative-control run before "empty content" stopped silently reading as "clean." [D-01; SR-10]

Proposed acceptance criteria — design defaults, UNEXERCISED until run:

- Minimum 5 timed runs per condition (baseline, change), after 1 discarded warm-up run.
- Report the median and interquartile range (IQR) per condition, not the mean — shared-machine timing distributions are right-skewed and mean is sensitive to the tail.
- A comparison is reportable only if IQR/median stays under 10% for both conditions. If either exceeds that, the result is INCONCLUSIVE — add runs or fix the harness; do not report the delta.
- Claim a regression only if the two conditions' IQRs do not overlap AND the median delta exceeds a stated practical-significance floor set per metric before running (for example, a page-load metric's floor stated in milliseconds up front, not chosen after seeing the numbers).

## Machine-state controls

Apply the same harness-health discipline that governs every other lane in this loop before trusting any measurement:

- No other load: confirm no concurrent build, sync, or backup process is running before starting a batch.
- Thermal state: avoid starting a batch immediately after sustained CPU load, since thermal throttling skews later runs low relative to earlier ones. Insert and record a cool-down pause if thermal state can't be checked directly.
- Background daemons: a Colima/Docker storage fault corrupted an entire beta4 batch and was initially misread as a product failure. [FM-13] The same daemon/socket/container precheck applies before a performance batch — a daemon fault invalidates the batch; it does not produce a valid slow number. [MC-09]
- Serialize execution: never run concurrent commands against one wp-env or Studio fixture. This is a standing rule for every mutation in the loop, and a timed page load or write is a mutation for this purpose just as much as a functional test is.

## What a valid comparison requires

- Same fixture, same `dataset_id`, on both sides. Never compare a baseline run on one fixture against a change run on a freshly rebuilt one without re-asserting the two match.
- Same PHP/WP build identity on both sides, confirmed through the build-identity gate before either run. A performance comparison against a mislabeled or absent build is not a comparison. [D-03; FM-16]
- Same multisite/site-mode state, asserted the same way the multisite denominator check asserts it for functional tests — print site count, status flags, and db_version before trusting a network-wide number. [D-04; FM-03; FM-15]
- Serialized execution — one mutation stream at a time against the fixture, on both the baseline and change side.

## Change-specific benchmark targets

Four surfaces are named in this loop's own chain-seed corpus as the release's high-exposure areas. None is benchmarked; all are UNEXERCISED.

| Target surface | Why it's named | Source |
|---|---|---|
| Media Library at scale + infinite scroll | Infinite scroll ships default-on; a per-user opt-out exists; the r1 audit already found a REST-vs-visible attachment-count gap at moderate scale | Chain C-10 |
| Editor iframe load | Iframed editor with Block API v3 enforced; toolbar/mode-matrix behavior disputed between sources | Chain C-06 |
| Global Styles / theme.json resolution | Per-breakpoint controls, theme-defined viewport breakpoints, Global Styles revisions | Chain C-09 |
| REST sideload | Media validation order across site modes and transport; the CONFIRMED FM-04 defect already shows the full file downloads before the multisite rejection fires on this path | Chain C-01; FM-04 |

These are chain-test hypotheses, not benchmark results — none has a timing number attached in this loop. A performance pass against any of them still needs its own `dataset_id`, run count, and variance rule from this playbook before a number from it means anything.

## The single-run rule

Stated explicitly because it is the one rule this playbook cannot skip even while UNEXERCISED: a single benchmark run is never proof of a regression or an improvement. Report every performance claim as "N runs, condition X, median/IQR," or don't report it. A benchmark result with n=1 is not a finding — it is an anecdote with a stopwatch attached.
