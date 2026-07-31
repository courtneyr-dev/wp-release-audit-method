---
name: wordpress-audit-handoff
description: Produce a coworker-ready handoff document from WordPress audit/testing work. Use when asked to "hand off" a WordPress audit, make a handoff/shareable doc from testing findings, or package audit results for a coworker/SRE/stakeholder. Returns ONE self-contained markdown file — findings (mechanism→evidence→fix, each linked to its authoritative WordPress source), the methods + verbatim prompts + linked agent skills used, and a consolidated source list — with any privately-disclosed finding scrubbed to a bare acknowledgment.
---

# WordPress audit handoff

When asked to hand off / share / package a WordPress audit or testing result, return **ONE self-contained markdown file** in this format. For a worked example of the evidence structure this expects, read [`examples/chains/C-02/`](../../examples/chains/C-02/) — mechanism, evidence, both controls, and cleanup for one confirmed finding.

## Output rules
- **One file, fully self-contained.** NO `*wikilinks*`, NO local filesystem paths — the recipient has neither the vault nor the machine. Inline the content, or link a public URL. The only acceptable links are public (wordpress.org, make.wordpress.org, core.trac.wordpress.org, github.com, etc.).
- **Verify every GitHub link is PUBLIC before including it.** Check with `gh repo view <owner>/<repo> --json isPrivate` (or an anonymous `curl` → expect 200, not 404). **Never link a private repo** — a coworker gets a 404. Some skill repos are private. If a skill/tool lives in a private repo, describe it by name + author instead of linking it.
- **Confidentiality banner** at the top, matched to the audience.
- Re-verify findings live if the target is reachable, so it's current, not just logged.

## Required sections (in order)
1. **Intro + context** — target, environment/stack, versions, verification date.
2. **Findings** — one per finding, each as **Mechanism → Evidence → Fix**, plus a **Sources** line linking every feature to its authoritative WordPress source: the Make/Core dev note or news post, the GitHub issue/PR, and the Trac ticket.
3. **Stack facts** — verified environment details.
4. **Tested and cleared** — non-issues, so nobody re-chases them.
5. **Not covered (honest gaps).**
6. **How this was tested:**
   - **Methods** (prose): the multi-model panel + adversarial verification, reproduce-before-final / prove-by-firing, live SSH/WP-CLI verification.
   - **Prompts** (verbatim, in code blocks — reusable by the recipient).
   - **Skills & tooling** — link an agent skill only if its repo is **verified public** (see the link rule above); describe private-repo, custom, or local skills by **name + author** instead (no links). Label each by actual use.
7. **Consolidated sources** — every public link in one list at the bottom.

## Two rules that are easy to get wrong
- **Confidential / privately-disclosed findings (HackerOne, coordinated disclosure, unpatched):** reduce to a **bare acknowledgment** — "a separate security issue was identified and responsibly disclosed through a private channel; details withheld." Scrub ALL traces: mechanism, endpoint/function names, CVSS, reproduction, the specific PR/commit, and the word "HackerOne." **Then grep the file to prove zero traces remain** before handing it off. If it's unclear which findings are confidential, ask.
- **Accuracy labels:** label every skill/tool/method by ACTUAL use — `used` / `staged` / `available` — and never imply a skill or model did work it didn't. Add a one-line accuracy note. (The real work usually ran through the custom multi-model harness + Workflow, not a named skill.)
