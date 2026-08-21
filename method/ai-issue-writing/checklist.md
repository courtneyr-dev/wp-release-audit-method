# Pre-filing checklist — AI-assisted issues & Trac tickets

**One page to run before you hit submit.** Distilled from the two research notes in this folder:
`research-wordpress-and-canon.md` (WordPress policy + reporting canon) and
`research-wider-oss-community.md` (cross-ecosystem norms). Full citations live there; source
tags here are shorthand.

**Why this exists.** In real WordPress 7.1 testing, well-received reports (e.g. the KSES and
icon-library tickets) and criticized ones (theme.json viewport breakpoints) differed by
*presentation ordering*, not rigor — a core committer called the criticized ones "excessively
verbose and difficult to read." The whole community converges on the same fix:
lead with the harm, verify every reference, keep the human insight visible, disclose the tool.
The bar is not "don't use AI" — it's "a human owns it, verified it, and made it readable."

How to use: walk the phases top to bottom. Every box is a gate. If a box fails, fix it before the
next phase. The copy-paste template and the red-flag stop-list are at the bottom.

---

## Phase 0 — Calibrate to the target project (30 seconds, do it first)

Different projects have opposite rules. Filing an AI-assisted report to the wrong one is an
instant reject regardless of quality.

- [ ] **Read the target's own AI policy** (`CONTRIBUTING`, `AI_POLICY.md`, contributor handbook)
      before writing. Where does it sit?

| Regime | Examples | What it means for you |
|---|---|---|
| **Ban all AI-assisted content** | Gentoo, NetBSD ("tainted"), QEMU (pre-2026), many GNOME projects | Do **not** file AI-assisted. File hand-written or not at all. |
| **Disclose-and-allow (required)** | **WordPress**, Django, Fedora, Rust, Kubernetes | Allowed — disclosure block **mandatory**, human accountable. |
| **Disclose appreciated, optional** | CPython | Allowed — disclose as courtesy. |
| **Contested / none** | Debian, GitLab (no primary policy found) | Default to WordPress-style disclosure + a human-owned, verified report. |

- [ ] **WordPress specifically:** disclose-and-allow. The official policy (Make/AI §1.2) defines
      **exactly three** fields — `AI assistance:` / `Tool(s):` / `Used for:` — with no `Model(s):`
      field and no mandated heading (re-verified against the live handbook 2026-08-21; the full
      sourcing is in `research-wordpress-and-canon.md`). A `## Use of AI Tools` heading with a
      fourth `Model(s):` line circulates as a committer convention on live tickets — adding it is
      harmless and often helpful, but it is a convention layered on top of the policy. **Never
      cite the four-field form as required.**
- [ ] **Security reports:** never paste embargoed / non-public data into a model (Debian draft norm;
      applies to any coordinated disclosure — e.g. an unpatched flaw under embargo).

---

## Phase 1 — Is it real? (before you write a word)

The #1 maintainer complaint across every ecosystem is **plausible-but-wrong content**. Pass these
or don't file.

- [ ] **Reproduced it yourself**, this cycle, on the build you're reporting. Not "the model says."
      (Operating rule: a finding is a claim until something runs.)
- [ ] **Ran a control** — proved the check can *see* the failure and that a known-good case passes.
      A result with no negative control is not evidence.
- [ ] **Confirmed it's core, not a plugin/theme** — tested on a clean install. [WP Core Handbook]
- [ ] **Searched for an existing ticket/issue** — Trac keyword search + GitHub. If one exists,
      comment on it; do not open a new one. [WP Core Handbook; Mozilla one-bug-per-report]
- [ ] **One bug = one ticket.** No omnibus reports. **No re-filing a near-duplicate** to say the
      same thing differently — a re-file predictably draws "how is this different from the first
      ticket?" and doubles triage load.

---

## Phase 2 — Structure it so the harm is unmissable (as you write)

Order matters as much as content. The lede is the harm, not the mechanism.

- [ ] **Title (~10 words): name the breakage, not your fix.** Specific enough to be unique.
      Bad: "viewport bug." Good: "block hidden on tablet renders visible when reader enlarges font."
      [Mozilla]
- [ ] **First 1–3 sentences = what breaks, for whom, one-line cause. Plain language.** A committer
      must understand the harm without reading any mechanism. This single move is the difference
      between welcomed and criticized reports.
      Shape: *"On <config>, <feature> does <wrong thing> instead of <right thing>. This affects
      <who>. It appears to come from <one-line cause>."*
- [ ] **One minimal reproduction.** The shortest path that makes it fail. This is the highest-value
      element in the whole report. [Mozilla: "the most important part"]
- [ ] **Expected vs. actual, stated separately and explicitly.** [Mozilla]
- [ ] **Environment:** only what's needed to reproduce (version, theme, browser).
- [ ] **Mechanism / source notes go BELOW THE FOLD**, under a `## Mechanism` heading — line refs,
      resolution tables, internals. Keep them (they're facts) but they are never the lede.
- [ ] **Proposed fix = the least-controversial option, phrased as a suggestion**, and state the
      symptom independently of your proposed cause. Prefer "warn" over "reject/re-architect" when a
      committer has to be persuaded. [WP §1.5; Tatham: state symptoms even when you diagnose]

---

## Phase 3 — Reference-integrity pass (the anti-hallucination gate)

This is the pass that most separates a trusted human report from slop. Do it deliberately.

- [ ] **Every line number, file path, function, hook, API, and constant you cite — open the source
      and confirm it exists and says what you claim.** Hallucinated refs are the emblematic slop
      failure (curl's non-existent function; Django "do not invent APIs or citations"). [WP §1.5;
      Django; HackerOne]
- [ ] **Every ticket/PR/CVE number you cross-reference resolves** to the thing you say it is.
- [ ] **Every quoted error string / output is copied from a real run**, not paraphrased from memory.
- [ ] **Numbers are measured, not estimated** ("331 vs 88 = 243", not "~hundreds").

---

## Phase 4 — Slop self-audit (would a maintainer call this AI slop?)

- [ ] **The 80% cut:** delete ~80% of the visible mechanism from the top. If the harm + repro +
      expected/actual survive on their own, you're done. AI is fine for the mechanism section; your
      job is the top sentence and the deletion.
- [ ] **One table, not three.** If you have multiple tables, keep the one that proves the harm; move
      or drop the rest.
- [ ] **Human insight is visible** — what *you* concluded and verified, not a raw model dump.
      [WP §1.5: rejects "little added human insight"]
- [ ] **No generic filler, no over-architected fix, no "as an AI…" hedging.** [WP §1.5]
- [ ] **Read it as the maintainer:** in 20 seconds, can they state what breaks and for whom? If not,
      the lede is still buried.

---

## Phase 5 — Disclosure block

- [ ] **WordPress** — the official policy is the three fields below; the bracketed heading and
      `Model(s):` line are an optional committer convention, fine to add, never required:
```
[## Use of AI Tools]          <- optional heading, convention not policy
AI assistance: Yes
Tool(s): Claude Code
[Model(s): Claude Opus 4.8]   <- optional line, convention not policy
Used for: Investigation, runtime reproduction, and drafting; I reviewed, tested,
and take responsibility for everything here.
```
  (Official field set re-verified 2026-08-21: three fields, no heading, no Model(s). Disclosure is
  required when AI "meaningfully contributes… beyond trivial reformatting.")
- [ ] **Other ecosystems** — use their trailer if they have one: `Assisted-by:` (Fedora),
      `AI-used-for:` (QEMU), or a plain "written in part with the assistance of generative AI"
      (Kubernetes). CPython: appreciated, optional.
- [ ] **The disclosure is honest about the division of labor** — say what the human did, because
      "disclosure helps reviewers understand how to evaluate the change," it is "not a negative
      signal." [WP §1.2]

---

## Phase 6 — After you submit (you still own it)

- [ ] **Respond to review as a human, in your own words.** If you can't personally explain a claim,
      it will be closed. Never route reviewer questions back through a model. [Kubernetes]
- [ ] **Expect `reporter-feedback`** and answer it; involvement doesn't end at submit. [WP Handbook]
- [ ] **If told it's hard to read, rewrite — don't re-file.** Post a short human summary on the
      existing ticket. A duplicate multiplies triage load. [curl; Mozilla]
- [ ] **If the conclusion is contested, engage the objection on its merits** — offer the
      lower-friction fix (warn, not prohibit) rather than restating the original.

---

## Copy-paste template

```
Title: <specific problem, ~10 words, names the breakage not the fix>

<1–3 plain sentences: what breaks, for whom, one-line likely cause.>

## Steps to reproduce
1. …
2. …
3. …

## Expected vs actual
- Expected: …
- Actual: …

## Environment
<version / theme / browser — only what's needed to reproduce>

## Mechanism (optional, below the fold)
<line refs, tables, internals — verified against source>

## Suggested fix
<least-controversial option, as a suggestion; symptom stated independently>

## Use of AI Tools          <- heading and Model(s) line are optional convention;
AI assistance: Yes             the official policy requires only the other three
Tool(s): …
Model(s): …
Used for: … (and what I, the human, reviewed/tested/verified)
```

---

## Red flags — STOP and fix before submitting

- ✋ A committer would have to read past a table or a line-ref to learn **what breaks**.
- ✋ Any cited line/function/API/ticket you have **not** re-opened and confirmed this session.
- ✋ Three tables where one proves it.
- ✋ The report restates a ticket you (or someone) already filed.
- ✋ The proposed fix is a re-architecture you're asking a maintainer to accept, not the smallest change.
- ✋ You couldn't, in your own words and without the model, defend every sentence in review.
- ✋ It reads like it was generated: filler, hedging, no visible human judgment, no real testing.

---

## Worked example — a verbose report vs. a welcomed one

**Before (a real, criticized 7.1 report):** buried lede, three font-size resolution tables up top, heavy `:line-number`
refs before the harm, 500+ words before "a hidden block becomes visible," and a re-filed duplicate.
Result: "excessively verbose and difficult to read," milestone bumped to Future Release.

**After (what the checklist produces):**
> *A block an author set to "hide on tablet" becomes visible for readers who enlarge their browser
> font, on themes that mix units in `theme.json` viewport breakpoints (e.g. mobile in `em`, tablet
> in `px`). The ordering is validated at a fixed 16px but the media query keeps the authored unit,
> so it can invert at larger font sizes.* — then one repro, expected/actual, and the tables moved
> under `## Mechanism`. Fix suggested as a **warning** (matching `spacingScale`), not a prohibition.

The difference is entirely ordering, length, dedup, and framing the fix as the low-friction option.
The rigor was never the problem — and the community research says rigor is exactly what they want,
*if they can read it.*
