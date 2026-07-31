# Feature-chain test report

## Build identity

Target: WordPress 7.1 RC1.

The mandatory identity gate returned `WAITING-FOR-RC1`. Runtime work is labeled
WordPress 7.1-beta4. RC1 cells remain blocked until the same gate succeeds.

## Current batches

- X-PERS-03r, `REFUTED` on the tested corpus: beta4 preserved every
  legacy safe background value in both the direct parser and an author-level
  full-content re-save. It accepted the new gradient-plus-URL form, while
  7.0.2 removed that form; both builds removed JavaScript URLs. Temporary
  users and drafts were deleted on both fixtures.
- C-02, `CONFIRMED` on beta4: the Core-upgrader fixture has 243 extra files
  under `wp-includes/images/icon-library`; the WP-CLI-upgrader fixture matches
  the clean beta4 core file set. The prior-beta cells are blocked by fixture
  identity and absence.
- C-03, `INCONCLUSIVE`: first load after temporarily restoring the archived
  site returned 200 but left its `db_version` at 61832 while eligible sites are
  at 61833. The archived flag was restored. No functional verdict is valid
  until the chain names a feature that requires the newer schema.
- C-04, `CONFIRMED` on beta4: with the dependency network-active,
  `is_plugin_active()` returns true and the dependency registry reports no
  unmet dependency, but both the site and network plugin-card action buttons
  are disabled. The site administrator permission boundary held: no action
  button and REST GET returned 403. The original activation state was restored.

Two harness attempts were invalidated and excluded: C-03 initially called
unsupported WP-CLI site subcommands, and C-04 initially omitted explicit
dependency-registry initialization in WP-CLI. Both attempts left or restored
the fixtures to their verified baseline before the clean reruns.

All four valid batches were rerun from the restored baseline. Their cell
observations and verdicts matched the first valid runs.

## Suite-wide blockers

The remaining corrected and internal chains need their chain-specific fixtures,
controls, and source-backed premises frozen before runtime work. RC1-only cells
remain blocked by build identity. Browser accessibility claims need native
keyboard calibration; performance claims need repeated runs and variance.
