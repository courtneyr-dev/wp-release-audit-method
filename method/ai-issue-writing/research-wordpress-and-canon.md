# AI-Assisted Issue & Trac Ticket Writing — How To Not Ship "Slop"

Researched 2026-08-14. A source-grounded rulebook for using AI to help draft GitHub issues and WordPress Trac tickets that maintainers welcome. The worked example at the end is anonymized — no committers or ticket numbers named.

Purpose: a source-grounded rulebook for using AI to help draft GitHub issues and WordPress Trac tickets that maintainers *welcome* — short, human-readable, one clear claim — instead of the verbose table-and-line-ref walls that get told "please provide a human-readable summary."

---

## TL;DR — the rules, each tied to a source

### DO

| Rule | Source |
|---|---|
| **Lead with what breaks, for whom, in one plain sentence — before any mechanism.** State the observable failure first. | Tatham: "the aim of a bug report is to enable the programmer to see the program failing in front of them." [T] |
| **Give expected result vs actual result, explicitly and separately.** | Mozilla: reports must "precisely describe the observed (actual) result and the expected result." [M] |
| **Provide one minimal reproduction** — the steps to make it fail. This is the single highest-value element. | Mozilla calls steps to reproduce "the most important part of any bug report … if a developer is able to reproduce the bug, the bug is very likely to be fixed." [M] |
| **Separate facts from your theory of the cause. Always state the symptom even when you also offer a diagnosis.** | Tatham: "Providing your own diagnosis might be helpful sometimes, but always state the symptoms." Mozilla: "clearly separate facts (observations) from speculations." [T][M] |
| **One bug per ticket.** No omnibus tickets, no re-filed near-duplicates. | Mozilla: "Open a new bug report for each issue!" [M] |
| **Write a specific, self-identifying title (~10 words) that names the problem, not your fix.** | Mozilla: summary should "quickly and uniquely identify a bug report" and "explain the problem, not your suggested solution," ~10 words / <60 chars. [M] |
| **Search for an existing ticket first.** | WP Core Handbook: "it's very important to check to ensure it's not already in the system before you submit it." [W] |
| **Confirm the bug is core, not a plugin/theme, by testing on a clean install.** | WP Core Handbook: verify "the bug is actually caused by WordPress core." [W] |
| **Disclose meaningful AI assistance** in the PR description and/or Trac comment. | WP AI Guidelines §1.2. [A] |
| **Keep human insight visible.** The value you add over the raw model output is the point; make it legible. | WP AI Guidelines §1.5 warns against dumps "with little added human insight." [A] |

### DON'T

| Anti-pattern | Source |
|---|---|
| **Don't bury the lede under mechanism.** Line-refs, resolution tables, and source dives up top are exactly what maintainers reject as unreadable. | Tatham on excess: "If you say too much, the programmer can ignore some of it" — but the *ordering* failure (facts buried) is what draws "hard to read" feedback; see case section. [T] |
| **Don't paste large unreviewed dumps with minimal explanation.** | WP AI Guidelines §1.5 lists "Large, unreviewed code dumps with minimal explanation or tests" as a to-avoid. [A] |
| **Don't include hallucinated references** — APIs, hooks, functions, tickets, links, CVEs, line numbers that don't actually exist. Verify every ref against source. | WP AI Guidelines §1.5. curl: slop reports "reference a function that does not exist in curl at all." [A][C1][C2] |
| **Don't file generic, context-free descriptions without real testing.** | WP AI Guidelines §1.5. [A] |
| **Don't over-architect the proposed fix.** Offer the least-controversial change. | WP AI Guidelines §1.5: avoid "Over-architected code when simpler solutions would suffice." [A] |
| **Don't be vague** ("it doesn't work," "displays incorrectly"). | Mozilla explicitly warns against these phrasings. [M] |
| **Don't make maintainers do triage archaeology.** Every low-signal report "engages 3-4 persons … 30 minutes, sometimes up to an hour or three. Each." | curl / Stenberg. [C1] |
| **Don't re-file a near-duplicate** to restate the same issue differently. | Mozilla one-bug-per-report [M]; and it compounds the triage-burden problem [C1]. |

---

## The structural template maintainers actually want

Order matters as much as content. Put the human-readable harm at the top and push mechanism below the fold.

```
Title: <specific problem, ~10 words, names the breakage not the fix>

## What breaks (1–3 sentences, plain language)
<Who is affected + the observable failure + one-line likely cause.>
Example shape: "On <config>, <feature> renders <wrong thing> instead of
<right thing>. Affects <who>. Appears to come from <one-line cause>."

## Steps to reproduce (minimal)
1. …
2. …
3. …

## Expected vs. actual
- Expected: …
- Actual: …

## Environment
<WP/core version, theme, browser — only what's needed to reproduce>

--- below the fold ---

## Mechanism / source notes (optional)
<Line refs, resolution tables, block-editor internals go HERE, not up top.>

## Proposed fix
<The least-controversial option. State it as a suggestion, not a mandate.>

## Use of AI Tools  (see exact WP fields below)
AI assistance: Yes
Tool(s): …
Used for: …
```

Why this order: Tatham's whole thesis is that the report exists to let the programmer *see the failure* — the failure goes first. [T] Mozilla ranks steps-to-reproduce and expected-vs-actual as the load-bearing parts. [M] The mechanism/line-refs are the part maintainers explicitly ask to be moved out of the way when they're on top (see case section). Keeping them below the fold satisfies Tatham's "don't leave out facts" [T] while not making the reader wade through them to find the harm.

---

## WordPress "Use of AI Tools" disclosure — verbatim + an accuracy correction

**Authoritative source:** WordPress AI Guidelines, Make/AI handbook, authored by James LePage, published/updated 2026-01-27; announced on Make/AI 2026-02-01. [A][A2]

The actual policy heading is **"1.2 Transparency: disclose when AI was used."** The required disclosure block, quoted verbatim from the example the guidelines give:

```
AI assistance: Yes
Tool(s): GitHub Copilot, ChatGPT
Used for: Initial code skeleton and test suggestions; final implementation
and tests were reviewed and edited by me.
```

Fields, exactly as they appear: **`AI assistance:`**, **`Tool(s):`**, **`Used for:`**. That's it — three fields.

> ⚠️ **Correction to a common assumption.** It is sometimes described as a "## Use of AI Tools" block with four fields including a **`Model(s):`** line (e.g. GPT-4, Claude). **The primary source does not define that.** (Re-verified against the live handbook 2026-08-21: still three fields, no heading, no `Model(s):`. The sibling `checklist.md` now states the same — the four-field form is an optional convention, never cited as required.) As of this research the official guidelines use the three fields above, under the heading "1.2 Transparency," with no `Model(s):` field and no mandated `## Use of AI Tools` markdown heading. If a `Model(s):` line or a `## Use of AI Tools` header is circulating on recent tickets, it's either a community/tooling convention layered on top of the policy or a newer revision there is no primary source for — do not cite it as the official field set. Add a model line if you like (it's harmless and helpful), but don't represent it as required.

**When disclosure is required vs optional (verbatim):** "When AI meaningfully contributes to your work (beyond trivial reformatting)" you must disclose in your "Pull request description, and/or Trac ticket comment." For "trivial assistance (for example, AI suggests a variable name or reorders imports), disclosure is optional." [A]

**Rationale (verbatim):** "Disclosure is not a negative signal. Instead, it helps reviewers understand how to evaluate the change." [A]

**What the guidelines call slop and let maintainers reject (§1.5, verbatim list of what to avoid):** [A]
- "Generic, context-free PR descriptions or issues without real testing"
- "Large, unreviewed code dumps with minimal explanation or tests"
- "Hallucinated references (APIs, hooks, functions, tickets, links that don't exist)"
- "Over-architected code when simpler solutions would suffice"

And: **"Maintainers may close or reject contributions that appear to be 'AI slop' with little added human insight."** [A]

---

## Primary-source digest (what each source actually says)

**[A] WordPress AI Guidelines** — the only WP-official document that defines the disclosure fields and names "AI slop" as a rejectable category. Lightweight by design; "you are responsible for your contributions (AI can assist, but it isn't a contributor)." Requires human review/understanding/testing of all contributions.

**[W] WordPress Core Contributor Handbook — Reporting Bugs.** Procedural, not a style guide. Load-bearing points: check for duplicates before filing; confirm the bug is core (test a clean install); fill title/summary/fields; and "Your involvement doesn't end after you've submitted a ticket" — expect `reporter-feedback` requests. It does *not* prescribe an explicit expected-vs-actual section, so borrow that structure from Mozilla/Tatham.

**[T] Simon Tatham, "How to Report Bugs Effectively" (1999).** The canonical essay. Core quotes: report exists so the programmer can "see the program failing in front of them"; separate "actual facts" from "speculations" — "Leave out speculations if you want to, but don't leave out facts"; "Tell them exactly what you saw … tell them exactly what you expected to see"; "Be specific"; "always state the symptoms" even when you diagnose; on length — "If you say too much, the programmer can ignore some of it. If you say too little, they have to come back and ask more questions." Note: Tatham tolerates *over-inclusion* of facts; the modern slop problem is over-inclusion of *unverified mechanism and bad ordering*, which the WP and curl sources address.

**[M] Mozilla Bug-Writing Guidelines.** The concrete structural rules: summary ~10 words that identifies the bug and "explain[s] the problem, not your suggested solution"; one bug per report; steps to reproduce = "the most important part"; precisely describe actual vs expected; "clearly separate facts (observations) from speculations"; avoid vague phrasings.

**[C1] Daniel Stenberg (curl), "Death by a thousand slops" (2025-07-14).** Maintainer's-eye view of the failure mode. Every report "engages 3-4 persons. Perhaps for 30 minutes, sometimes up to an hour or three. Each." ~20% of 2025 submissions were AI slop; genuine-vulnerability rate fell to ~5%. Notes "human slop" too — the tell isn't the tool, it's the low signal. Emotional/triage toll is the cost being externalized onto maintainers.

**[C2] Stenberg, "AI slop attacks on the curl project" (2025-08-18) + press coverage.** The emblematic example: a report on an HTTP/3 "stream dependency cycle exploit," dressed up "with GDB sessions and register dumps," that "turned out to reference a function that does not exist in curl at all." This is the hallucinated-reference failure the WP guidelines name — convincing-sounding mechanism attached to code that isn't real. curl's response escalated to removing HackerOne as the recommended channel and adding a low-effort-screening checkbox. (By March 2026 curl returned to HackerOne and reports sla: "the slop situation is not a problem anymore," with confirmed-vuln rate back to the pre-AI ~15–16%.)

**[G] GitHub Docs — creating an issue.** Thin. GitHub's own product docs are procedural ("type a title," "type a description") and offer essentially no content-quality guidance; they defer to repo-level issue templates. Practical implication: for GitHub issues the substantive standard comes from Tatham/Mozilla and the target project's `CONTRIBUTING.md` / issue template, not from GitHub itself.

---

## A worked example: a verbose report vs. a welcomed one (the "before")

Context: in real WordPress 7.1 testing, two reports were **well received** (fixed, "Props") — breakage stated in sentence 1, one evidence table, real-install numbers, concrete fix, ~one paragraph. Two others (theme.json viewport breakpoints) were **criticized** — maintainers asked, in substance, for "a human-written summary of what the actual breakage is" and called the explanation "excessively verbose and difficult to read." The style that drew it: buried lede, three font-size-resolution tables, heavy line-number citations up top (`:790-810`, `block-editor.js:11793-11862`), 500+ words before the actual harm, and a re-filed near-duplicate.

Concrete edits that would have prevented the criticism:

1. **Open with one plain sentence of harm.** Replace the top-of-ticket tables with: "On <viewport range>, `theme.json` font sizes resolve to <wrong value>, so <who> sees <visible breakage>." Everything the well-received tickets did in sentence 1. [T][M]
2. **Move all three resolution tables and every `:line-number` ref below the fold**, under a `## Mechanism` heading. Keep them — they're facts [T] — but they are not the lede. The maintainer feedback was explicitly about *ordering/readability*, not about the tables being wrong.
3. **Cut to one minimal reproduction + expected-vs-actual.** One repro path, "Expected: … / Actual: …". That's the part that gets bugs fixed. [M]
4. **Collapse the two near-duplicate tickets into one; don't re-file.** One bug per report; a re-file multiplies triage load. [M][C1]
5. **State the fix as the least-controversial option, phrased as a suggestion** ("simplest fix appears to be X") rather than a mandated re-architecture — and keep the symptom stated independently of the proposed cause. [A §1.5][T]

Net: the difference between the welcomed and criticized reports was **not** rigor or correctness — it was *lead-with-harm ordering, one table not three, mechanism below the fold, and one ticket not two.* AI is fine for generating the mechanism section; the human job is to write the top sentence, verify every reference, and delete 80% of the mechanism from the visible top.

---

## Where sources disagree / gaps I couldn't close

- **Tatham vs. the modern slop norm on verbosity.** Tatham (1999) says over-inclusion of *facts* is harmless — "the programmer can ignore some of it." The 2025–26 maintainer reality (curl, and the WP guidelines' "difficult to read" pattern) is that over-inclusion of *unverified mechanism* is actively costly. These aren't contradictory once you separate "facts" from "speculative mechanism," but if you cite Tatham to justify a long ticket, you're misreading him — his facts are reproduction facts, not source-dive line-refs.
- **The `Model(s):` field and `## Use of AI Tools` heading could not be confirmed in any primary source.** The official policy is three fields under "1.2 Transparency." Flagged above; don't present a four-field block as canonical.
- **GitHub has no real first-party issue-writing standard.** The guidance vacuum is genuine; the canon lives in Tatham, Mozilla, and per-project templates.
- **WP Core Handbook doesn't prescribe expected-vs-actual.** That structure is imported from Mozilla/Tatham, not WP-native — fine to use, just don't attribute it to WP.
- **curl is a C project, not WordPress.** Its numbers (20% slop, 3-4 people per report) are illustrative of the failure mode and the maintainer cost, not WP metrics.

---

## Sources

- **[A]** WordPress AI Guidelines (handbook) — https://make.wordpress.org/ai/handbook/ai-guidelines/ (James LePage, updated 2026-01-27)
- **[A2]** "AI Guidelines for WordPress" announcement — https://make.wordpress.org/ai/2026/02/01/ai-guidelines-for-wordpress/
- **[W]** WordPress Core Contributor Handbook, Reporting Bugs — https://make.wordpress.org/core/handbook/testing/reporting-bugs/
- **[T]** Simon Tatham, "How to Report Bugs Effectively" — https://www.chiark.greenend.org.uk/~sgtatham/bugs.html
- **[M]** Mozilla Bug-Writing Guidelines — https://bugzilla.mozilla.org/page.cgi?id=bug-writing.html
- **[C1]** Daniel Stenberg, "Death by a thousand slops" — https://daniel.haxx.se/blog/2025/07/14/death-by-a-thousand-slops/
- **[C2]** Daniel Stenberg, "AI slop attacks on the curl project" — https://daniel.haxx.se/blog/2025/08/18/ai-slop-attacks-on-the-curl-project/ ; corroborated by The New Stack (https://thenewstack.io/curl-fights-a-flood-of-ai-generated-bug-reports-from-hackerone/) and The Register (https://www.theregister.com/security/2025/05/07/curl-takes-action-against-time-wasting-ai-bug-reports/)
- **[G]** GitHub Docs, Creating an issue — https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue
