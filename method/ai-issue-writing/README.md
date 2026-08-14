# Filing findings maintainers welcome (AI-assisted or not)

A finding is only as useful as the report that carries it. These notes are about the *report* —
how to write an issue or Trac ticket, especially with AI help, that a maintainer reads, trusts, and
acts on, instead of one that gets closed as "excessively verbose" or "AI slop."

The bar across the open-source community is not "don't use AI." It's **a human owns it, verified it,
and made it readable.** Rigor is welcome — buried rigor is not.

## Start here

- **[`checklist.md`](checklist.md)** — the one-page pre-filing checklist. Run it top to bottom
  before you submit: calibrate to the project's AI policy, verify it's real, lead with the harm,
  kill hallucinated references, self-audit for slop, disclose the tool. Includes a copy-paste
  template and a red-flag stop-list.

## The research behind it

- **[`research-wordpress-and-canon.md`](research-wordpress-and-canon.md)** — WordPress's own AI
  Guidelines and disclosure policy, the Core Handbook, and the reporting canon (Simon Tatham,
  Mozilla), plus maintainer-side accounts of the failure mode (curl).
- **[`research-wider-oss-community.md`](research-wider-oss-community.md)** — the cross-ecosystem
  view: explicit AI-contribution policies from Gentoo, NetBSD, QEMU, Rust, Django, CPython, Fedora,
  Godot, Kubernetes and more; bug-bounty platform rules (HackerOne, Bugcrowd); OpenSSF guidance;
  and the one empirical study. Every claim is tagged for whether a primary source was read directly.

## The short version

1. **Calibrate first** — some projects ban AI-assisted contributions outright; most that allow them
   require disclosure and a human who can defend every line. Check the target's policy before writing.
2. **Verify before filing** — reproduce it, run a control, and confirm every line/function/API/ticket
   you cite actually exists. Fabricated detail is the #1 thing maintainers reject.
3. **Lead with the harm** — what breaks, for whom, in one plain sentence, before any mechanism.
4. **One minimal repro + expected vs. actual.** Push line-refs and tables below the fold.
5. **Disclose the tool**, and make the human insight visible.
6. **One bug, one ticket.** Don't re-file near-duplicates; rewrite in place if asked.
