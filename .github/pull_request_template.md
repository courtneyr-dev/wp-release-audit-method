<!--
Thanks for contributing. Delete any section that doesn't apply.

Security vulnerabilities in WordPress go to https://hackerone.com/wordpress —
never in a pull request here.
-->

## What this changes

<!-- One or two sentences. -->

## Why

<!-- What went wrong, or what was missing. If you hit this in practice, say what happened. -->

## How you know it works

<!--
This repo's own rule: a finding is a claim until something runs.
Paste the run, not a description of it.
-->

```
$ python3 scripts/check-repo.py

```

## If this adds or changes a detector or check

- [ ] Positive control — the thing it should catch, caught
- [ ] Negative control — the thing it shouldn't flag, not flagged
- [ ] It failed a control during development and I've said which, or it never did and I've said that too

<!--
A detector that has never failed a control has never been calibrated. Three of
this repo's five original detectors failed one on first run.
-->

## If this touches documentation

- [ ] Every factual claim about WordPress traces to an [official source](../sources/official-sources.md)
- [ ] No absolute paths, no credentials, no local directory layouts
- [ ] Internal links and anchors resolve (`python3 scripts/check-repo.py` covers this)

## Evidence ceiling

<!--
What you proved, what you didn't, what would change your mind. Optional for a
typo fix; expected for anything that asserts WordPress behaves a certain way.
-->
