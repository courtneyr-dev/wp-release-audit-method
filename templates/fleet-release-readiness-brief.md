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

### 3. Host core-test participation

Does the infrastructure under this fleet publicly run core's PHPUnit suite?
Check [Host Test Results](https://make.wordpress.org/hosting/test-results/) — or run
`python3 scripts/hosting-test-participation.py --host "<HOST>" … --format markdown`
([method](../fleet-operators/README.md#9-distributed-core-test-participation--public-evidence-scoped-honestly))
— and record it per host/tier this fleet actually uses:

| Host | Tier we're on | Reporter account | Evidence for <TARGET> | Freshness | Outcome | Participation |
|---|---|---|---|---|---|---|
| <host> | <tier> | <account or "none found <date>"> | <rN / none / unmapped> | <last observed rN> | <passed/failed/…> | <classification> |

Scope honestly: this table covers the tiers this fleet runs, not the host's whole fleet.
Participation is not passing, and a passing core suite is not release readiness — it is
one input to §4's auto-update decision, nothing more. "None found" records the date
searched; it is not proof the host doesn't test. If a host isn't participating (or went
stale), send [the participation request](participation-request-messages.md) and note it
here as sent/answered.

### 4. Auto-update decision for this release

- Policy applied: <e.g. "minors auto, majors held N days, plugins manual">
- Inputs behind N: detection time <minutes/hours>, fleet-wide fix rollout time <hours>,
  open CVEs waiting on this update: <yes/no, which>
- Declared regressions in the release notes, and our per-regression decision
  (accept / filter off / hold): <list — see the Act I declared-regressions gate>

### 5. Update-day runbook confirmation

The [ordered runbook](../fleet-operators/README.md#5-the-update-day-runbook) will run
as written · deviations for this release: <none / list>.
Baselines captured (visual + console): <where> · backup verified restorable: <when last
actually restored — "we take backups" is not this line>.

### 6. Monitoring

- Keyword monitors active on: <N of N sites> · string checked: <what>
- PHP error logging: enabled at step 8, disabled and deleted at step 14 — owner: <who>
- Action Scheduler manual check owner: <who>

### 7. Post-update failure watch (72h)

| Class | Watch | Owner |
|---|---|---|
| Fatal / obvious | keyword monitor alerts | <who> |
| Visible but subtle | visual-regression diff review | <who> |
| Quiet / invisible | form + checkout re-exercise at <T+24h>, Action Scheduler at <T+48h> | <who> |

### 8. Known holes accepted for this release

- Staging→live database promotion remains unsolved; live update re-runs the runbook rather
  than promoting staging. <anything else accepted, stated plainly>
