---
title: "Slack test-report template — release-day checklist"
type: template
status: active
created: '2026-07-31'
updated: '2026-07-31'
source_run: "$WP_AUDIT_ROOT/scripts/render_slack_checklist.py (generator)"
tags:
  - wordpress
  - wp-audit
  - release-audit
  - slack
  - reporting
related:
  - '[release-day-sweep-playbook](../playbooks/release-day-sweep-playbook.md)'
  - '*../index*'
---

# Slack test-report template

> **This is the blank form — 64 checks, all unmarked.** For a *filled-in* version with
> realistic mixed verdicts, a threaded finding, and the rules for what to say in the thread,
> see [`skills/wp-release-party`](../skills/wp-release-party/SKILL.md#example-output). That
> skill also carries the [entity × operation coverage matrix](../skills/wp-release-party/SKILL.md#what-gets-checked--entity--operation)
> showing which of these checks a script covers and which are browser-only.
>
> Where this sits in the cycle: [Act II](../README.md#act-ii--the-party) ·
> [release-day sweep playbook](release-day-sweep-playbook.md) · next step is
> [`wp-release-followup`](../skills/wp-release-followup/SKILL.md).

Generated, not hand-maintained. Regenerate rather than editing this note:

```bash
python3 $WP_AUDIT_ROOT/scripts/render_slack_checklist.py --from-results --tier T1 \
  --source "7.1-Beta 3" --target "7.1-Beta 4" --method "Beta Tester plugin" \
  --env "single-site" --php "8.4" --theme "Twenty Twenty-Five" --browser "Chrome" \
  --site-mode single
```

64 checks / 9 sections; `--site-mode single` drops the Multisite section (58 checks). Emoji fill from `verdict` in `pilots/release-day/sweep-matrix.csv`.

**Three rules before posting.** The header must name the build *actually tested* (beta is not RC) and the upgrade lane used (Beta Tester / WP-CLI / manual zip produce different results — the stale-file finding exists only because Core and WP-CLI differ). Invalid batches are counted and excluded, never reported as findings. No local paths, no credentials; confidential findings reduce to a bare acknowledgment.

**The assistant drafts; you post.** Making WordPress Slack is read-only under the standing source rules.

Smoke verdicts are `PASS`/`FAIL`/`PARTIAL`/`BLOCKED`/`SKIP`/`INVALID`. The `CONFIRMED`/`REFUTED`/`INCONCLUSIVE` vocabulary belongs to findings and chains, reported separately — mixing them makes "I couldn't create a post" sound like "I confirmed a defect".

## Rendered template

```
*WordPress <TARGET>* — upgraded from *<SOURCE>* via *<lane>*

Environment: <env> · PHP <PHP> · <theme> · <browser>
Result: 0 passed · 0 failed · 0 partial · 0 blocked · 64 not tested

*Upgrade*
• Upgrade completed without error :white_large_square:
• Version and db_version correct after upgrade :white_large_square:
• No PHP fatals or new deprecations in debug.log :white_large_square:
• wp-admin loads (dashboard + all core screens) :white_large_square:
• Front end loads :white_large_square:
• File tree matches a clean install of the same build :white_large_square:
• Rollback / reactivate previous version :white_large_square:

*Content*
• Create, update, and delete Posts :white_large_square:
• Create, update, and delete Pages :white_large_square:
• Trash and restore Posts :white_large_square:
• Post revisions save and restore :white_large_square:
• Create, update, and delete Custom Post Types :white_large_square:
• Add and delete Comments on Posts :white_large_square:
• Edit comment parent :white_large_square:
• Add and remove Categories and Tags :white_large_square:
• Add and remove custom taxonomy terms :white_large_square:
• Bulk edit and quick edit :white_large_square:
• Scheduled post publishes :white_large_square:

*Media*
• Upload, edit, and delete media (JPEG/PNG) :white_large_square:
• Upload HEIC / AVIF / WebP :white_large_square:
• Media Editor Modal: crop, rotate, flip :white_large_square:
• Media Library infinite scroll and per-user opt-out :white_large_square:
• Gallery block: attached-images inserter :white_large_square:
• Regenerate thumbnails / subsizes :white_large_square:
• Alt text and 'mark as decorative' :white_large_square:

*Editor*
• Block editor loads (iframed) :white_large_square:
• Persistent toolbar in Post Editor and Site Editor :white_large_square:
• Distraction Free and Fullscreen toggles :white_large_square:
• Notes: add, @mention, resolve, delete :white_large_square:
• Responsive per-breakpoint styling :white_large_square:
• Interactive (hover/focus) state styling :white_large_square:
• Command palette :white_large_square:
• Patterns and reusable blocks :white_large_square:
• Copy/paste and undo/redo across blocks :white_large_square:

*Themes and Site Editor*
• Switch between block themes :white_large_square:
• Switch block theme to classic theme and back :white_large_square:
• Install, update, and delete themes :white_large_square:
• Edit and revert templates and template parts :white_large_square:
• Global Styles: edit and restore a revision :white_large_square:
• theme.json viewport breakpoints :white_large_square:
• Classic and Navigation-block menus :white_large_square:

*Plugins*
• Install plugin :white_large_square:
• Activate, deactivate, and delete plugin :white_large_square:
• Update plugins and themes :white_large_square:
• Auto-update toggle :white_large_square:
• Plugin dependencies (Requires Plugins header) :white_large_square:
• WooCommerce: create, update, delete Products :white_large_square:
• WooCommerce: cart and checkout smoke :white_large_square:

*Users and roles*
• Create, update, and delete Users :white_large_square:
• Change user role :white_large_square:
• Login, logout, and password reset :white_large_square:
• Application passwords :white_large_square:
• Personal data export and erase :white_large_square:

*Settings and tools*
• Save General / Reading / Writing / Discussion settings :white_large_square:
• Save permalinks and verify front-end routing :white_large_square:
• Export and import (WXR) round-trip :white_large_square:
• Site Health reports no new critical issues :white_large_square:
• Widgets screen :white_large_square:

*Multisite*
• Network upgrade completes; report the full site count :white_large_square:
• Create, archive, spam, and delete a site :white_large_square:
• Held-back sites report correctly (archived/spam/deleted) :white_large_square:
• Network-activate and site-activate a plugin :white_large_square:
• Per-site admin and front end load :white_large_square:
• Network user vs site user management :white_large_square:
:white_check_mark: pass  ·  :x: fail  ·  :warning: partial or unexpected  ·  :no_entry_sign: blocked  ·  :heavy_minus_sign: not tested  ·  :recycle: invalid batch, rerun needed

Findings and evidence in thread. Invalid batches are excluded from the counts above.
```
