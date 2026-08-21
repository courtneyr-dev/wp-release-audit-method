# Pilots — the run-root contract

Skills, playbooks, and prompts in this repo tell you to open files under `pilots/` — the
sweep matrix, the upgrade ladder, the filed-issues register. Until now those files existed
only in the author's private run root, which meant a fresh clone broke at step 2 of
`wp-release-party`. This directory closes that gap.

## What lives here vs the run root

| Here (in the repo) | In your run root (`$WP_AUDIT_ROOT`, private) |
|---|---|
| Schema contracts — every CSV with its real header row | The same files, with populated rows |
| Generated T1 matrices with empty verdict columns | The matrices with verdicts, evidence paths, and fixture hashes filled per run |
| The deterministic generator (`scripts/build_release_day_matrices.py`) | Evidence files, screenshots, logs |
| — | Per-release directories (`pilots/wp71-rc1/`, `pilots/<release>/build-manifest.json`) |

The schema is the portable asset. Verdicts, evidence, and anything that could carry a
credential or a local path stay in the run root — the same boundary `.gitignore` already
draws for `private/` and `evidence/`.

If you have no run root yet: copy this directory's CSVs somewhere disposable, point
`WP_AUDIT_ROOT` at it, and fill the verdict columns there. The in-repo copies stay blank.

## The files

| File | What it is |
|---|---|
| [`release-day/sweep-matrix.csv`](release-day/sweep-matrix.csv) | The T1 sweep — one row per cell, 51 wp-cli + 10 browser. Generated; regenerate rather than hand-editing |
| [`release-day/upgrade-ladder.csv`](release-day/upgrade-ladder.csv) | The upgrade ladder — 9 T1 cells of the 88-cell full ladder. Generated |
| [`release-day/php-axis.csv`](release-day/php-axis.csv) | Which chains PHP genuinely multiplies, and why. Hand-maintained; the reasoning is in the [sweep playbook](../playbooks/release-day-sweep-playbook.md#where-php-versions-belong-in-phase-2) |
| [`filed-issues-register.csv`](filed-issues-register.csv) | Everything filed upstream, with its retest status. Schema only here — populated rows live in the run root, because rows carry pre-publication verdicts |

Regenerate the two matrices:

```bash
python3 scripts/build_release_day_matrices.py
```

The browser tier-1 entity set is the one input that must never carry forward between
releases — see the generator's `--browser-t1` flag and the warning it prints.
