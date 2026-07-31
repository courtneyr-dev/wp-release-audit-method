---
title: "Reusable Repository Audit Prompt"
type: template
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - wordpress
  - security-audit
  - prompt
  - template
related:
  - '*index*'
  - '[audit-playbook](../method/audit-playbook.md)'
  - '[validation-and-proof](../method/validation-and-proof.md)'
---

# Reusable repository audit prompt

Paste this to apply the methodology to **one authorized repository**. Fill every `{{placeholder}}`. Leave the standing rules verbatim.

---

```markdown
## Standing rules (verbatim)
- Authorized defensive security research on software I own/maintain/have written permission to test. Local, disposable, isolated environment only. Synthetic users/data/secrets only.
- Do NOT: scan public sites, enumerate real users/creds, create persistence/stealth/backdoors/shells/C2, run destructive actions, exfiltrate real data, DoS beyond bounded local measurement, or operationalize an unpatched exploit. Stop each proof once the boundary is demonstrated.
- Distinguish: verified findings · hypotheses · disproved hypotheses · blocked routes · environmental assumptions · untested areas · compliance/perf/a11y concerns (not vulnerabilities).
- Mechanism-first reporting. Model agreement is NOT evidence. A scanner hit, suspicious function, screenshot, or model-generated payload is NOT proof by itself. Prove by firing against the disposable install, with a negative control and a role control.
- Preserve disagreement until evidence resolves it; resolve by source/test, never by vote.

## Target
- Repository path: {{repo_path}}
- Target type: {{core | plugin | mu-plugin | classic-theme | block-theme | block-package | editor-extension | composer-lib | npm-package | multisite-component | AI-component}}
- Release artifact / ZIP: {{artifact_path_or_url}}
- Source branch/tag/commit (target): {{revision}}
- Baseline for comparison: {{last_audited_version_or_commit}}
- Baseline→target comparison range: {{range}}
- Release notes / changelog: {{locations}}
- Deprecation sources: {{@since/@deprecated, dev notes, Field Guide}}

## Environment
- Authorized env: {{Studio | wp-env | Playground | container}} at {{url_or_path}}
- Supported WordPress: {{versions}} · PHP: {{versions}} · DB: {{MySQL/MariaDB versions}} · Node/npm: {{versions}} · browsers: {{list}}
- Single-site / multisite: {{which}}
- Object cache: {{none | persistent impl}} · filesystem method: {{direct/ftp/ssh}}
- External services / webhooks: {{list}}
- Credentials & roles available (synthetic): {{admin/editor/author/subscriber/anon + app-passwords?}}

## Scope
- In scope: {{surfaces/components}}
- Excluded systems (with reason): {{list}}
- Known concerns / prior findings: {{list or path}}
- Disclosure status: {{owned-private | coordinated-disclosure-active | public-ok}}
- Relevant vault notes: *Plugin Security Audit/index*, *wordpress-security-audit-methodology/index*, {{others}}
- Output path: {{vault_project_folder}}

## Task
Run the methodology in [audit-playbook](../method/audit-playbook.md) end to end for the range above:
1. Skill-provenance pass (dedupe; scope-override offensive skills).
2. Environment + test matrix; verify reset.
3. Feature/change ledger + change-coverage receipt for {{range}} — classify EVERY change; reconcile git ↔ notes ↔ tests ↔ deps ↔ ZIP; flag undocumented/reverted/generated-only.
4. Architecture + trust-boundary map; attack-surface inventory; invariant registry (use [security-invariants](../method/security-invariants.md)).
5. Research-family registry ([orchestration](../method/orchestration.md)); independent rounds; keep incompatible hypotheses alive; mark blocked routes.
6. For each promising claim: static trace (incl. dependency source + the distributed build) → 20-step dynamic proof with negative + role controls → fresh-context adversarial verify → chain analysis.
7. Bounded proof of impact only; then stop.
8. Remediation + failing-first regression test (assert absence of side effects); run the full suite on the shipped tree.
9. Perf/a11y/compliance labeled separately.
10. Bank findings using the [validation-and-proof](../method/validation-and-proof.md) templates + finding-reporting standard; record untested areas and the coverage receipt.

## Definition of done
Every in-scope change classified; each research family = mechanism/evidence/block; every verified finding fired with controls and independently reproduced; chains have evidence on every edge; coverage receipt has no unexplained gaps; disclosure routing decided; untested areas recorded.
```

---

## Notes for the operator
- If `{{target type}}` is an AI component, add the AI-component surface checks from [audit-playbook](../method/audit-playbook.md) (invocation authz, prompt-injection boundary, model-output-as-instructions, provider egress, tenant isolation, cost amplification).
- If reproduction needs persistent object cache / multisite / external queues, pick an environment that models it and **say so** if it can't ([wordpress-attack-surfaces](../method/wordpress-attack-surfaces.md) fidelity note).
- For owned plugins, the `wp-audit` skill + `wp-audit-pipeline` Workflow already implement the prove-by-firing loop — use them for the baseline pass, then apply the deeper invariant/chain work here.
