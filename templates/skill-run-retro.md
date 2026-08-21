# Skill-run retro — fill in per run

Two minutes after any act (prep / party / followup) or playbook run. The method behind it:
[`method/retro.md`](../method/retro.md). Keep it short and honest; a retro nobody runs is
worse than none.

---

## Retro — <skill/playbook> · WordPress <TARGET> · <date>

**Run context:** driver <ddev/wp-env/studio/…> · site mode <single/multisite> · PHP <x.y>

### 1. KEEP — what worked and is worth protecting
<!-- The wins are data too. What would you be annoyed to lose in a future cleanup? -->
-

### 2. FRICTION — what slowed you down but you got through
<!-- A confusing instruction, a slow step, a manual thing that should be scripted. -->
-

### 3. GAP — what was missing
<!-- A cell, a lane, a driver, a doc that should exist and didn't. -->
-

### 4. WRONG — what the tool told you that was wrong or misleading
<!-- A script that errored, a count that didn't match the matrix, a path that didn't
     resolve, an instruction that assumed the wrong environment. Highest priority. -->
-

---

### Sort each item

For every FRICTION / GAP / WRONG above:

- [ ] **Tool or WordPress?** If WordPress misbehaved, it's a finding — file a
      [test report](../.github/ISSUE_TEMPLATE/test-report.yml), not a retro item. Only
      tool problems continue below.
- [ ] **Durable, or just this run?** A one-off (your Docker hiccuped) stays in the run log.
      A durable one becomes a candidate register row.
- [ ] **Candidate rows** (status `PROPOSED`, in your run root's registers):
      - `learning/failure-mode-register.csv` — the way the method was blind
      - `learning/method-change-proposals.csv` — the fix (only `ACCEPTED` after controls)
- [ ] **Worth sharing?** If it would help the next stranger, open a
      [field report](../CONTRIBUTING.md#suggesting-improvements-from-real-use) — the two-minute
      path. Prefilled command:

```bash
gh issue create --repo courtneyr-dev/wp-release-audit-method \
  --title "[Field report] <what, in a few words>" \
  --label field-report \
  --body "Ran <skill> on <build>, <driver>. <what happened / what's missing>."
```

Nothing here is filed without you deciding to. The retro lowers the cost of *noticing*; it
never lowers the bar for *accepting* — the adjudication gate still applies.
