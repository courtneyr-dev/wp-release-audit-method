---
title: "Article Methodology — Searchlight/Sol WordPress RCE"
type: analysis
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - wordpress
  - security-audit
  - methodology
  - loop-engineering
related:
  - '*index*'
  - '[audit-playbook](../method/audit-playbook.md)'
  - '[security-invariants](../method/security-invariants.md)'
---

# Article methodology — analysis and critique

Source: Adam Kues, Searchlight Cyber, "Exploit brokers pay $500,000 for a WordPress RCE. I found one with GPT5.6 Sol Ultra and $25", published 2026-07-20. Read in full (not just the exploit narrative). Vendor blog; ends in an Assetnote ASM product pitch — treat framing accordingly.

## What actually happened (mechanism, compressed)

- **Setup:** cloned latest stable WordPress into `main/`, deleted `.git`, provided an empty `third_party/` for the model to clone dependencies (PHP, MySQL, libraries) and read their **source**. Prompt adapted from OpenAI's Cycle-Double-Cover math prompt. Constraints: "from first principles by analysis of the code," **no changelogs/git/internet diffing**, "pre-authentication to RCE in a **typical production deployment with MySQL**," success = read `/flag`. Up to 4 agents, ≥6 hours.
- **Bug (validation/execution desync):** the Batch REST API (`/wp-json/batch/v1`, since WP 5.6) validates all subrequests in one loop, then executes in a second loop. In `class-wp-rest-server.php`, the `is_wp_error( $single_request )` branch appends to `$validation[]` but hits `continue` **without** appending to `$matches[]`. One malformed early request shifts `$matches` out of alignment with `$validation`, so a request is validated against one handler and executed against the **next** request's handler.
- **Sink (scalar-vs-array SQLi):** `GET /wp/v2/posts` maps `author_exclude` → `author__not_in`; if the value is an **array** it is `absint`-mapped, but a **scalar** string is interpolated raw into SQL. Public validation forces an int array; the desync bypasses that validation. Batch API rejects `GET`, so they **recursively** re-enter batch to desync the method check itself (method validation is just parameter validation). Result: **pre-auth read-only SQLi**.
- **Escalation to RCE (cross-subsystem chain):** UNION injection fakes `WP_Post` rows → poisons the **per-request object cache** → `[embed]/?p=…[/embed]` fabricates `oembed_cache` DB rows → cache/DB reconciliation in `wp_update_post` prefers **in-memory** fields, "popping" fake posts into real ones → a forged `customize_changeset` with `user_id:1` makes WordPress `wp_set_current_user()` to **admin temporarily** → the **cycle-detection** gadget (`wp_insert_post_parent` sets `post_parent=0`) is the one write path that doesn't overwrite `post_content`, so attacker controls the changeset JSON → dynamic action `"{$new_status}_{$post->post_type}"` lets any underscore-containing action fire; targeting **`parse_request`** replays the entire batch request **as admin** → a create-admin subrequest that failed on pass 1 succeeds on pass 2 → login → upload plugin ZIP → **RCE**. Independently reproduced (Calif, Hacktron) before public PoCs.

## Separation of practices

### Strong, transferable practices (adopt)
| Practice | Why it transfers to defensive audits |
|---|---|
| Portfolio of **research families grouped by idea, not wording**, in an explicit registry | Prevents 5 agents "rephrasing" the same hypothesis; forces real breadth. Becomes *research-families* in this system. |
| **Anti-convergence**: redirect agents off crowded families; don't let the most "suspicious" route consume the search | Directly counters the single biggest LLM-audit failure (tunnel on first lead). |
| Explicit **blocked** state; reopen only on a *materially new mechanism* | Stops thrash and repeated dead-ends under new phrasing. |
| Keep **incompatible hypotheses alive across rounds**; cross-pollinate only after independent development | Preserves genuine independence; avoids premature groupthink. |
| **Adversarial double-checking** of every concrete bug | Kills plausible-but-wrong findings before they ship. |
| **First-principles source reading**, including **dependency source** (`third_party/`) | The technical crux: the scalar-vs-array bug is invisible to API-memory reasoning; only reading source surfaces it. Models default to "search the API" — forcing source reading is what worked. |
| **Invariant-breaking mindset** over sink-hunting: representation mismatch, array/handler desync, cache↔DB disagreement, temporary identity, dynamic dispatch | This is the whole chain. It maps 1:1 onto [security-invariants](../method/security-invariants.md). |
| **Realistic-config discipline** ("typical production, MySQL," pre-auth, no fabricated preconditions) | Prevents the model from "cheating" via absurd configs; becomes our negative-control + supported-config gate. |
| Root agent that **synthesizes, challenges, redirects, launches new rounds**, and does not stop after the first failed wave | The orchestrator contract in [orchestration](../method/orchestration.md). |

### Useful but unproven (adopt cautiously, don't cargo-cult)
- **"4 agents, ≥6 hours"** — arbitrary constants presented as a recipe; no calibration evidence. Do not treat as a target.
- **"Use multiagents aggressively"** — in tension with the user's own rule that *activity ≠ coverage*. Unproven that aggressive fan-out beats fewer agents doing more source reading. Cap per project.
- **Porting a math prompt to security** — clever, but "it transfers" is anecdotal.

### Target-specific techniques (instances, not methods)
- The exact desync, `author__not_in` scalar bug, `oembed_cache` popping, `customize_changeset` `user_id` gadget, and `parse_request` replay are **version-specific exploitation instances**. Keep them as **invariant exemplars**, not as steps to repeat.
- **Removing `.git` and blocking the internet** is correct for *novel zero-day discovery* (stops the model diffing against a patch). It is **wrong for maintenance/regression audits**, where diffs and changelogs are first-class evidence. This system uses first-principles first, then diffs for regression (see [audit-playbook](../method/audit-playbook.md) Phase 7).

### Claims needing stronger evidence / biases / rhetorical framing
- **Survivorship & selection bias:** one dramatic win, no denominator. Unknown how many targets/runs produced nothing.
- **No rates reported:** no false-positive, false-negative, coverage, severity-distribution, or "null-result on a clean target" data.
- **Outcome & hindsight bias:** method praised because it worked; "Do you spot the vulnerability?" makes the desync look obvious post-hoc.
- **Cost framing ($25 vs $500k):** headline anchors on exploit-market price to dramatize ROI; excludes failed runs, a human day+ untangling the chain, and the expert steering. True cost is undercounted; the $500k figure is marketing, not a measured value of *this* method.
- **"Superhuman" / "no researcher could in 10h":** unfalsifiable, single data point.
- **Independent reproduction ≠ methodology repeatability:** Calif/Hacktron reproduced the **known chain**; they did not independently *rediscover* it via the same process. Corroborates the vuln, not the method.
- **No controlled comparisons:** 5.5-vs-5.6 is impressionistic; no human baseline; no time-to-verification distribution.
- **Vendor incentive:** post sells Assetnote ASM. Weight promotional claims down.

### Where human judgment stayed essential (the article concedes this)
Steering the realistic-production constraint; **disbelief-then-verify** (installed stock WP, asked it to steal the admin email before trusting the SQLi); a human day understanding the chain; disclosure timing. The article's own closing: meta-skills — *what/where/how-long to investigate, steering, nudging back on track* — remain human. That is the correct division of labor for this methodology.

## Falsification / strengthening evidence this system should demand
To move the article's broad claims from anecdote to method, an audit program needs: repeatability across runs, FP/FN rates against a known-bug corpus, coverage measurement, honest cost accounting, and behavior on **targets with no major vuln** (the null result). This system bakes those in via evaluation gates and the change-coverage receipt ([loop-engineering-ledger](../method/loop-engineering-ledger.md), [change-coverage-receipt](../method/change-coverage-receipt.md)).

## One-line takeaway for §1
Reframe audits around **broken cross-subsystem invariants** (representation, alignment, identity, cache/DB, dynamic dispatch), hunted by a **diverse research-family portfolio**, proven with **negative controls + fresh-context adversarial verification**, grounded in **first-principles source (incl. dependencies) and source-vs-build reconciliation** — not sink-hunting that stops at the first finding.
