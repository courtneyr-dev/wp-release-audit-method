---
title: "Cross-release feature chains — 6.3 to 7.1 ledger and chain adjudication"
type: method
status: active
created: '2026-07-30'
updated: '2026-07-30'
tags:
  - wordpress
  - security-audit
  - methodology
  - chain-testing
  - release-audit
related:
  - '*index*'
  - '[release-audit-learning-loop](../method/release-audit-learning-loop.md)'
  - '[validation-and-proof](../method/validation-and-proof.md)'
  - '*WordPress 7.1/testing/codex-chain-test-handoff*'
---

# Cross-release feature chains

> **Applied in:** [`wp-release-followup`](../skills/wp-release-followup/SKILL.md) §3.
> Worked examples: [`examples/chains/`](../examples/chains/). Generator prompt:
> [chain test generation](../prompts/codex-feature-chain-test-generation-prompt.md).

Method page. Data lives at `$WP_AUDIT_ROOT/learning/` — `cross-release-feature-ledger.csv` (200 features, 6.3–7.0) and `cross-release-chain-register.csv` (36 adjudicated chains). Not duplicated here.

## Why chain at all

Every confirmed defect in the WordPress 7.1 Beta 4 pass lived in an **interaction**, not in a feature:

- validation order differing across single-site and Multisite,
- a UI counter reading site-local `active_plugins` while another path read the network option,
- an updater's `$_old_files` list disagreeing with the tree it shipped.

A per-feature test suite cannot see any of those. Chains are the structural fix.

## The two fields that make chaining possible

The 6.3–7.0 ledger records, per feature, beyond the usual metadata:

- **`persistence_surface`** — where the feature's state actually lives (post content, post meta, `theme.json`, options, user meta, attachment metadata, uploads, db schema), or `none` if purely runtime.
- **`chain_affinity`** — which other subsystems it must touch to work.

Two features chain when they share a surface. That is the whole selection heuristic, and it is mechanical rather than intuitive.

## The shape that finds real bugs

**An older release wrote data or set an expectation that a newer release changes.** That is what real upgrades hit, and what greenfield tests never construct. The strongest surviving example: restoring a Global Styles revision silently reverts Font Library activation, because font activation lives inside the same `wp_global_styles` payload that revisions snapshot wholesale. Blast radius crosses the post, `wp_font_family`/`wp_font_face` rows, uploaded font files, and front-end `@font-face`. Revision tests never build font state; font tests never restore a revision.

## The adjudication result — the actual method lesson

Four lenses (persistence, authorization, lifecycle, render) proposed **36** cross-release chains from the catalog. Independent judges **with source access** then reviewed each one.

**Zero survived unchanged. 16 refuted, 20 corrected.**

The refutations came from reading code, not from reasoning about it:

| Refutation | How it was proven |
|---|---|
| A chain premised on `edit_css` and `unfiltered_html` being two independent gates | `map_meta_cap()` resolves both in the same switch arm — one gate |
| A chain premised on Block Bindings writing to post content | `block-bindings/post-meta.php` shows otherwise |
| Two more premised on invented supports keys | Extracting the beta4 package and reading source |

**Rule:** a proposer working from a catalog *without source access* invents plausible surface names, capability relationships, and storage locations. Chain proposal must cite source per leg, and an independent source-reading judge must adjudicate before any chain becomes a test. The judge lane is not review polish — it is what made the output usable.

**Corollary for reading any chain register:** use the `corrected_chain` column, never `proposed_hypothesis`. The 16 dropped chains stay in the file with their refutations so nobody re-proposes them — same negative-control discipline applied to method artifacts instead of findings.

## Calibration note

A 0-of-36 clean-pass rate looks like a miscalibrated judge, and the standing rule is to check the instrument on an extreme reading. Reading the verdicts settled it the other way: the judges were right and the proposers were wrong. **Check the instrument, then believe it when it survives the check.**

## Provenance caveats

- The 6.4 ledger rows carry a disclosed deviation: that agent could not set the required User-Agent or pace requests (tooling outage) and said so. Re-run 6.4 if exact provenance matters.
- The 7.0 agent returned a release title string instead of a version key; normalized on write.
- No Trac queries were made — the bot challenge was respected. Ticket numbers in these rows come from Field Guides and dev notes, not from Trac itself.
