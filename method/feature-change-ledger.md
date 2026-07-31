---
title: "Feature / Change-Intelligence Ledger (template)"
type: template
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - wordpress
  - security-audit
  - change-ledger
  - template
related:
  - '*index*'
  - '[change-coverage-receipt](../method/change-coverage-receipt.md)'
  - '[audit-playbook](../method/audit-playbook.md)'
---

# Feature / change-intelligence ledger (template)

No live target yet — this is the reusable structure. Fill it when applying the methodology. **Don't start from "only new files matter."** Inventory everything added / expanded / modified / default-changed / permission-changed / validation-changed / sanitization-changed / data-shape-changed / route-changed / hook-changed / lifecycle-changed / schema-changed / cache-changed / filesystem-changed / network-changed / privacy-changed / multisite-changed / serialization-changed / template-changed / build-changed / dependency-changed / hardened / shim / deprecated / soft-deprecated-still-reachable / removed / renamed / moved / reverted / feature-flagged / test-only / docs-only / generated-only / undocumented.

## Establish the comparison range
current version+branch+tag+commit · previous release · last comparably-audited version/commit · earliest supported upgrade source · relevant RCs/prereleases · distributed release artifact · source branch it was built from. When the baseline is uncertain, pick the most defensible and **state the assumption**.

## Sources to reconcile (treat release notes/changelogs as *indexes*, not truth)
git history · merged PRs · commit messages · tags/branches · release notes · changelogs · upgrade & deprecation notices · WP dev notes / Field Guides · inline `@since`/`@deprecated` · public API docs · tests added/removed/skipped · fixtures · DB migrations · REST schemas · `block.json` · `theme.json` · config defaults · feature flags · dependency manifests + lockfiles · generated/minified files · package contents · build scripts · CI/version matrices · issue/review discussion of security intent · vault notes on planned/shipped/reverted work. **Use repo diffs to catch undocumented changes.**

## Required depth per change class
- **Added/expanded:** new entry points · attacker inputs · caps · validation/normalization/sanitization/escaping · storage/cache · callbacks/lifecycle · external requests · build/release artifacts · new invariants · interactions with unchanged code · positive/negative/role/regression tests · threat-model delta.
- **Modified:** old-vs-new security semantics · changed assumptions · unchanged callers/callees still relying on old behavior · error/cleanup paths · compat branches · source vs distributed build · upgrade-from-supported tests · docs/UI vs runtime. **Review the whole trust boundary, not the changed lines.**
- **Deprecated:** deprecation version · replacement · still reachable? · who can trigger · shims · warnings · migration/fallback · old-vs-new control parity · callers still on old path · removal point · two-inconsistent-paths check. *In scope while reachable.*
- **Removed/renamed/moved:** no stale route/hook/callback/include/asset/migration/option/build-artifact reachable · cleanup/uninstall · upgrade paths · aliases/compat layers · dependency/autoload maps · docs not pointing to unsafe obsolete behavior · boundary moved elsewhere?
- **Dependency/platform:** relevant upstream changes · changed defaults/security semantics · removed compat behavior · test the *exact pinned* versions · supported-version boundaries · assumptions still valid?

## Ledger table
| Change ID | Feature/API/behavior | Classification | Baseline | Target | Source evidence | Runtime surface | Security boundary | Existing tests | New tests needed | Audit status | Finding links | Docs status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| _CHG-001_ | | | | | | | | | | inventoried | | |

**Statuses:** inventoried · source reviewed · runtime mapped · security reviewed · tested · regression protected · not-security-relevant (rationale) · blocked · out-of-scope (rationale). **No in-scope change stays unclassified.**
