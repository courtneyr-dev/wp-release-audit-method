---
title: "WordPress Attack-Surface Model"
type: reference
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - wordpress
  - security-audit
  - attack-surface
related:
  - '*index*'
  - '[security-invariants](../method/security-invariants.md)'
  - '[audit-playbook](../method/audit-playbook.md)'
---

# WordPress attack-surface model

Enumerate every entry point and state transition. For each surface record: **entry point · attacker-controlled input · expected type · validation · sanitization · authorization · storage/cache · callback/state change · sink/effect · assumptions.**

## Request & execution surfaces
REST routes · **REST batch / recursive request handling** (article's entry) · AJAX (auth + `nopriv`) · form handlers · `admin-post` actions · front-controller parsing · rewrites & query vars · XML-RPC · WP-CLI · cron events · Action Scheduler / custom queues · webhooks · block render callbacks · shortcodes · embeds & oEmbed processing · template loading · dynamic includes · upload handlers · archive extraction · import/export · media processing · update/install paths · activation/deactivation/uninstall · inter-plugin integrations · theme switching · multisite network admin · signup & account-recovery · application passwords · external-service callbacks.

## Data & state surfaces
options / site options · transients · **object cache** · **persistent object cache** · post cache · user cache · term cache · metadata · custom tables · serialized values · JSON values · post types & statuses · revisions & autosaves · **Customizer changesets** · sessions/session-like data · background jobs · temp files · uploaded files · logs · debug output · generated CSS/JS · build manifests · dependency autoloaders.

## Dynamic behavior
hooks & filters · **dynamic hook names** · callbacks supplied as data · closures · callable arrays · magic methods · autoloading · reflection · **recursion / re-entry** · nested REST requests · **temporary user changes** · global-state changes · locale switching · blog switching (multisite) · DB transaction boundaries · error & cleanup paths.

## Organized by component (report §9)
| Layer | Highest-signal surfaces | Cross-links |
|---|---|---|
| **Core** | Batch/recursive REST, `class-wp-rest-server` validation pipeline, object cache, post lifecycle, changesets, dynamic `do_action`, multisite, `wpdb` | inv #1–4,14–18,25 |
| **Plugins** | custom REST/AJAX/admin-post, nonces vs caps, custom tables, uploads, cron/queues, activation/uninstall, dependency loading | inv #7,8,16,20,24 |
| **Classic themes** | template inclusion, output escaping, Customizer, app-logic in `functions.php`, switching | inv #9,12,26 |
| **Block themes** | `theme.json`, patterns, dynamic blocks, starter content, source-vs-build | inv #22,23 |
| **Blocks / editor** | `block.json` schemas, serialization, server render, editor-only gates, REST preload, Interactivity API, client/server drift | inv #5,9,22,26 |
| **Shared deps** | Composer/npm pinned versions, bundled libs, autoloaders, generated assets | inv #22,23,24 |
| **Multisite** | blog/network scoping, super-admin, switch_to_blog restore | inv #12,25 |
| **External services** | webhooks, provider callbacks, SSRF, secrets | inv #6,7,24 |
| **AI components** | invocation authz, prompt-injection boundary, model-output-as-instructions, provider egress, tenant isolation | inv #7,18,26 |
| **Cross-component** | cache↔DB, direct↔background, source↔build, single↔multisite parity | inv #14,15,20,22,25 |

## Environment fidelity note (important)
Reproduction fidelity gates which surfaces are testable:
- **DB engine is a hard gate, not a convenience.** WordPress Playground defaults to **SQLite-on-WASM**; the article's crux is a **MySQL-dialect UNION/scalar-interpolation SQLi**. A DB-layer primitive can silently fail to fire or fire differently under SQLite and be wrongly downgraded. **Forbid Playground/SQLite for any `wpdb`/SQL/collation finding** — require real MySQL/MariaDB at a supported version with the target's charset+collation pinned in the matrix. Playground is fine for routing/logic/UI repro only.
- **Playground / Studio** are great for portable repro **but may not model** persistent object cache, unusual filesystem permissions, external queues, or production proxies. The article's chain depends on **per-request object cache + DB reconciliation** — reproduce that on an environment that actually runs the relevant cache, and **record the limitation** if the chosen env can't. (Cross-link: `*docker_desktop_broken_colima*`, `*wp71_screenshot_rig*`.)
- **Concurrency:** a single-request, sequential proof harness *cannot* reproduce race/TOCTOU (invariant #32). Any check-then-act finding needs a concurrent-request harness; if you can't run one, the finding is a **hypothesis**, stated as such.
- Always test both **object cache on and off**, and **single-site and multisite**, because the same code can enforce different controls per path (inv #20, #25).
