# Fleet release-readiness brief — template

One document, filled per release, answering: **do we let WordPress <TARGET> onto the fleet,
when, and how do we find out fast if that was wrong.** Method behind each section:
[`fleet-operators/`](../fleet-operators/README.md). The SRE-grade variant with rollout
posture and gates is [`wordpress-audit-handoff` Mode B](../skills/wordpress-audit-handoff/SKILL.md#mode-b--sre-fleet-brief).

Replace every `<placeholder>`. Delete no section — an empty section is a finding about your
process.

---

## Fleet release-readiness brief — WordPress <TARGET>

Prepared <DATE> by <NAME> · fleet: <N> sites · decision: <ship / hold until DATE / ship to canary tier first>

### 1. Inventory and denominator

| Plugin | Version(s) in fleet | Sites | Auto-update? |
|---|---|---|---|
| <plugin> | <versions> | <count> | <on/off> |

Sites not covered by this table: <count and why — these are unknowns, not passes>.

### 2. Tracker triage

Per inventory plugin: open issues on its public tracker naming <TARGET>.

| Plugin | Tracker hit | Status | Our exposure |
|---|---|---|---|
| <plugin> | <link or "none found <date>"> | <open/triaged/fixed-in-X> | <sites affected if it's real> |

"None found" rows record the date searched — absence of an issue today is not absence of a
bug on release day.

### 3. Auto-update decision for this release

- Policy applied: <e.g. "minors auto, majors held N days, plugins manual">
- Inputs behind N: detection time <minutes/hours>, fleet-wide fix rollout time <hours>,
  open CVEs waiting on this update: <yes/no, which>
- Declared regressions in the release notes, and our per-regression decision
  (accept / filter off / hold): <list — see the Act I declared-regressions gate>

### 4. Update-day runbook confirmation

The [ordered runbook](../fleet-operators/README.md#4-the-update-day-runbook) will run
as written · deviations for this release: <none / list>.
Baselines captured (visual + console): <where> · backup verified restorable: <when last
actually restored — "we take backups" is not this line>.

### 5. Monitoring

- Keyword monitors active on: <N of N sites> · string checked: <what>
- PHP error logging: enabled at step 8, disabled and deleted at step 14 — owner: <who>
- Action Scheduler manual check owner: <who>

### 6. Post-update failure watch (72h)

| Class | Watch | Owner |
|---|---|---|
| Fatal / obvious | keyword monitor alerts | <who> |
| Visible but subtle | visual-regression diff review | <who> |
| Quiet / invisible | form + checkout re-exercise at <T+24h>, Action Scheduler at <T+48h> | <who> |

### 7. Known holes accepted for this release

- Staging→live database promotion remains unsolved; live update re-runs the runbook rather
  than promoting staging. <anything else accepted, stated plainly>
