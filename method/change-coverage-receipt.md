---
title: "Change-Coverage Receipt (template)"
type: template
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - wordpress
  - security-audit
  - coverage
  - template
related:
  - '*index*'
  - '[feature-change-ledger](../method/feature-change-ledger.md)'
---

# Change-coverage receipt (template)

Produced before declaring the change review complete. It is the deterministic check that the change ledger is actually covered — not a model's opinion that it looked at everything.

## Completeness reconciliation checklist
- [ ] git changes reconciled with release notes
- [ ] source reconciled with release packages (ZIP)
- [ ] documented deprecations reconciled with `@deprecated` + runtime behavior
- [ ] API changes reconciled with tests
- [ ] dependency changes reconciled with lockfiles
- [ ] feature flags reconciled with shipped defaults
- [ ] vault plans reconciled with what actually shipped
- [ ] shipped changes absent from public notes — identified
- [ ] announced changes that did not ship — identified
- [ ] reverted / partially reverted work — identified
- [ ] changes present only in generated artifacts — identified

## Receipt (fill on application)
| Field | Value |
|---|---|
| Baseline → target | |
| Commits / tags reviewed | |
| Releases reviewed | |
| Files changed | |
| Public APIs changed | |
| Hooks changed | |
| Routes changed | |
| Schemas changed | |
| Dependencies changed | |
| Deprecations reviewed | |
| Removals reviewed | |
| Undocumented changes found | |
| **Entries NOT fully reviewed + why** | |

## Gate
If any row above is blank or any checklist box is unchecked, the change review is **not** complete — record it in [open-research](../method/open-research.md) as an untested area, don't paper over it. (Loop rule: a nondeterministic "looks done" is not a stop condition.)
