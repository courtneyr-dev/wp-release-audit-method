---
title: "Validation, Proof & Finding Templates"
type: reference
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - security-audit
  - verification
  - evidence-standard
  - templates
related:
  - '*index*'
  - '[loop-engineering-ledger](../method/loop-engineering-ledger.md)'
  - '[audit-playbook](../method/audit-playbook.md)'
---

# Validation, proof & finding templates

## Evaluation-gate ladder (report §11)
A model may *propose* a transition; **evidence** justifies it.
| Status | Evidence required to enter |
|---|---|
| **idea** | a named surface + a guessed weakness |
| **hypothesis** | a falsifiable statement: source, sink, broken invariant, required access/config, and a test that would support it + one that would disprove it |
| **suspicious path** | source trace showing the invariant *can* break; no runtime yet |
| **verified primitive** | dynamic repro of attacker control over the effect, **with a passing negative control** and a role/capability control |
| **verified vulnerability** | primitive crosses a real security boundary in a supported config; independent (fresh-context) verifier reproduced it from claim+evidence |
| **chain candidate** | ≥2 primitives linked on paper; ≥1 edge still lacks runtime proof |
| **verified chain** | **every** edge has source/runtime/test evidence end-to-end |
| **remediated** | fix present; the failing-first regression test now passes; whole suite green on the shipped tree |
| **regression protected** | test in CI, asserts absence of side effects, covers the version matrix |

## The 20-step dynamic-validation loop (report §11)
State: 1 source · 2 sink/effect · 3 broken invariant · 4 attacker access · 5 required config · 6 exact supported versions · 7 execution path · 8 instrumentation · 9 smallest safe test · 10 expected result · 11 run in isolated env · 12 actual result · 13 **negative control** · 14 **role/capability control** · 15 normal valid request · 16 patched/safe behavior · 17 repeat in clean env · 18 version-difference test · 19 **independent agent tries to disprove** · 20 store regression evidence.

Guardrails (from vault prove-by-firing lessons — [prior-knowledge](../method/prior-knowledge.md)):
- **Prove-by-firing** — a suspected vuln is not a vuln until an exploit fires against a disposable install. Model opinions set priority, never truth.
- **No third door** — nothing is "not exploitable" from reasoning; refutation needs *fired-and-blocked* evidence.
- **Controls per run** — fire known-vuln / known-safe / known-chain fixtures first; miscalibration aborts and discards findings.
- **Consensus ≠ truth** — agreement deprioritizes firing, disagreement escalates; only firing writes CONFIRMED/REFUTED.
- A static observation is not a vuln; a dynamic anomaly is not automatically exploitable; a screenshot is not runtime proof; a model-generated payload is not evidence until reproduced and understood.

## Controls need an external corpus (a model-authored control is not calibration)
The known-vuln / known-safe / known-chain fixtures MUST come from a **pre-registered, human-curated corpus**, not fixtures the same model wrote this run — a model that misunderstands the mechanism will write a control that passes for the wrong reason. A model-authored negative control **cannot promote** a finding by itself; it only supports one once the corpus fixtures calibrated the run.

## Executable vs. model-attested (say which)
For **owned repos**, the prove-by-firing loop is genuinely executed (`wp-audit` + `wp-audit-pipeline` Workflow fire against a disposable Studio site). For **third-party targets you can't safely build**, the 20 steps and the gate ladder are a **checklist a model attests**, not a harness a system enforces. Label each finding `fired` vs `source-attested`; never imply a harness where there is a checklist.

## Closing a surface without infinite firing (null-result rule)
"No third door" forbids reasoning a bug away — but you can't fire every config, so a clean surface needs a defined exit or the audit never ends. A surface closes as **no-finding** when: (a) every attacker-input path was traced in source to a correct control, **and** (b) the bounded, enumerated supported-config set was fired with controls and none crossed a boundary. Record the exact config set fired; anything outside it is an **untested area** in [open-research](../method/open-research.md), not a clean bill.

## Bounded-environment escape hatch
If a real primitive only fires under a production-like config that can't be safely or legally reproduced, do **not** force a firing and do **not** refute-by-reasoning. Report it as a **hypothesis with a stated environmental limitation** — this is the one sanctioned exit from the "no third door" rule, and it keeps the bounded-proof authorization intact.

## Safe-proof standard (report §12)
Prove **only**: reachability · attacker control · required privilege · boundary violation · affected versions · practical impact · remediation · regression need. Prefer the least-harmful proof:
| Finding class | Minimal proof |
|---|---|
| Auth/authz bypass | show a capability check failed / wrong subject authorized, with an inert marker |
| Validation desync | show the handler processed the *other* request's validated representation |
| SQLi (read) | read one **synthetic** sentinel value; do not dump real data |
| Unauthorized write | create/alter one **disposable synthetic** record |
| Unauthorized callback | fire with an **inert marker**, not a payload |
| File write | controlled write inside a **disposable** dir |
| Resource amplification | bounded, rate-limited local measurement; no service disruption |

**Never** add persistence, stealth, destructive actions, credential theft/spraying, public-target compatibility, reverse/web shells, C2, mass exploitation, or unnecessary post-compromise steps. **Stop once the boundary is proven.**

## Finding-reporting standard
Report, mechanism-first then proof: title · component · affected versions · target revision · distributed-artifact status · attacker access · required privileges · realistic prerequisites · uncommon-config requirements · source · sink/effect · broken invariant · exact execution path · boundary crossed · safe reproduction · negative control · role control · expected vs observed · independent verification · impact · severity rationale · confidence · remediation · regression test · related code · disclosure status. Avoid "it is possible that" when evidence exists; label as **hypothesis** when it doesn't.

---

# Reusable templates

### Hypothesis
```markdown
### Hypothesis: [name]
- Research family / Target surface:
- Source / Sink or effect / Broken invariant:
- Required attacker access / config:
- Why it may work / Evidence so far:
- Test that would support it / Negative control / Evidence that would disprove it:
- Status:
```

### Blocked route
```markdown
### Blocked route: [name]
- Research family / Mechanism tested / Evidence gathered:
- Blocking condition — guaranteed or merely typical?
- New evidence required to reopen / Related route worth testing:
```

### Disproved hypothesis
```markdown
### Disproved hypothesis: [name]
- Original claim / Test / Expected / Actual:
- Why the mechanism fails / Scope of disproof / Related assumptions still untested:
```

### Verified primitive
```markdown
### Verified primitive: [name]
- Source / Attacker control / Transformation / Security-sensitive effect:
- Persistence / Required privilege / Config:
- Reproduction / Negative control / Observed result / Boundary crossed:
- Standalone impact / Potential chain edges / Independent verification:
```

### Verified vulnerability
```markdown
### Finding: [title]
- Component+version / Revision / Artifact:
- Attacker access / Prerequisites:
- Source / Sink / Broken invariant / Execution path / Boundary crossed:
- Reproduction / Negative control / Actual result:
- Impact / Remediation / Regression test / Independent review / Disclosure status:
```

### Chain candidate
```markdown
### Chain candidate: [name]
| Edge | Primitive | Evidence | Missing proof | Stop condition |
|---|---|---|---|---|
- Proposed final impact / Weakest edge / Smallest test that resolves it / Status:
```

### Compliance concern
```markdown
### Compliance concern: [title]
- Guideline/policy / Affected file or behavior / Evidence:
- Security / Privacy / Licensing relevance:
- Required change / Not a vulnerability because:
```

### Performance concern
```markdown
### Performance concern: [title]
- Operation / Trigger / Realistic scale / Cached vs uncached:
- Measured cost / Bounded impact / Why not a vulnerability / Fix:
```

### Accessibility concern
```markdown
### Accessibility concern: [title]
- Security-critical workflow / WCAG criterion / Barrier:
- Operational risk raised / Why not itself a vulnerability / Fix:
```

### Regression test
```markdown
### Regression test: [name]
- Finding covered / Test layer / Fixture / Environment:
- Setup / Action / Expected safe behavior (assert absence of side effects) / Failure signal:
- Negative control / Version matrix / CI location:
```
