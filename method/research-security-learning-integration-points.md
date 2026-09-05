# Security-learning integration points

## Question

Where should a WordPress plugin vulnerability watch connect to this repository's existing method, and which parts can it reuse, need extension, or conflict with the proposed candidate, observation, training-case, and method-signal concepts?

## Executive answer

The repository already has a learning spine that fits the project: external news enters as a **signal**, human adjudication checks it against primary evidence, a surviving gap becomes a proposed failure-mode row plus a proposed method-change row, and a detector reaches acceptance only after controlled shadow runs. The security-learning project should connect to that spine, not create a second promotion process. [`ecosystem-signals.md:21-48`](ecosystem-signals.md) [`ecosystem-signals.md:97-107`](ecosystem-signals.md) [`retro.md:80-83`](retro.md)

What is missing is the durable layer before promotion: the current repository has no register for watched disclosures, plugin identity, CVE/non-CVE state, review disposition, or the link from a reviewed case to the invariant, surface, failure mode, and method proposal it informed. The shipped learning registers begin with method failures and proposed changes; their public copies are schema-only, while populated rows live in the private run root. [`registers.md:8-27`](registers.md) [`../learning/README.md:1-24`](../learning/README.md)

The clean integration boundary is therefore:

> public disclosure intake → observation/candidate review record → approved training case → zero or more method signals → existing FM/MC/SR/D promotion path

That boundary preserves the repository's rule that reading is discovery, not a verdict, and that evidence rather than model judgment promotes status. [`ecosystem-signals.md:26-48`](ecosystem-signals.md) [`validation-and-proof.md:23-45`](validation-and-proof.md)

## Vocabulary fit

The root glossary says repository terms must have one exact meaning across documentation, scripts, skills, and prompts, so these four concepts need explicit definitions before they become shared artifacts. [`../CONTEXT.md:1-5`](../CONTEXT.md)

| Proposed concept | Best connection | Fit or conflict |
|---|---|---|
| **Observation** | The existing **Signal** stage: an item found in public ecosystem reading, before primary-source adjudication. | **Reuse with a naming decision.** "Source observation" already means unproved analysis, and the proof guide says it is not a vulnerability. If the project keeps *observation* as a record type, it must remain below finding status. [`release-audit-learning-loop.md:33-43`](release-audit-learning-loop.md) [`validation-and-proof.md:40-45`](validation-and-proof.md) |
| **Candidate** | The existing **Candidate** stage: a signal that might change the method. | **Conflict requiring qualification.** The repository also uses *chain candidate* for a partly proved exploit chain and *register candidate* for a possible FM/MC row. A bare `candidate` status would mix disclosure triage, vulnerability proof, and method governance. [`ecosystem-signals.md:26-36`](ecosystem-signals.md) [`validation-and-proof.md:25-35`](validation-and-proof.md) [`retro.md:46-51`](retro.md) |
| **Training case** | The missing external corpus named by the security method: a pre-registered, human-curated body used for control calibration and invariant-coverage measurement. | **Extension.** A reviewed public disclosure can enter this corpus without becoming a repository finding. The current method says external corpus coverage is required and also says the corpus has not been built. [`validation-and-proof.md:47-51`](validation-and-proof.md) [`security-invariants.md:84-90`](security-invariants.md) [`open-research.md:42-51`](open-research.md) |
| **Method signal** | The output of comparing an approved training case against current invariants, surfaces, controls, and lanes. | **Reuse with a traceability extension.** It should enter the existing FM/MC path only when the case shows method blindness or a justified fix; checked-and-cleared cases remain useful without generating a method change. [`ecosystem-signals.md:45-48`](ecosystem-signals.md) [`ecosystem-signals.md:97-107`](ecosystem-signals.md) |

## Integration map

### 1. Intake and source adjudication

**Reuse:** `method/ecosystem-signals.md` is already the conceptual intake. It names security releases, incident write-ups, and plugin trackers as watched source types and requires human adjudication before any hit becomes a check. [`ecosystem-signals.md:50-72`](ecosystem-signals.md) The current helper already detects CVE-shaped text and terms from `data/security-releases.csv`, labels all matches candidates, and tells the operator to check the primary source. [`../scripts/ecosystem-signals.sh:44-98`](../scripts/ecosystem-signals.sh) [`../scripts/ecosystem-signals.sh:149-160`](../scripts/ecosystem-signals.sh)

**Extend:** the present helper scans operator-supplied Markdown/text and, with no source, prints a manual watch list; it is not a durable disclosure collector. [`../scripts/ecosystem-signals.sh:100-113`](../scripts/ecosystem-signals.sh) [`../scripts/ecosystem-signals.sh:132-147`](../scripts/ecosystem-signals.sh) The project needs an intake seam that preserves each observed source item and its review state before it enters the existing signal pipeline.

**Conflict:** the official-source register currently allows only two non-WordPress.org sources for discovery, while the security project intends to watch public plugin advisories across distribution channels. That is a direct source-policy mismatch, not a collector detail. [`../sources/official-sources.md:15-22`](../sources/official-sources.md) The same register does supply the right adjudication rule: choose evidence by the claim, preserve conflicts, and treat canonical issues plus runtime reproduction as stronger than informal signals. [`../sources/official-sources.md:40-52`](../sources/official-sources.md)

### 2. Case and evidence storage

**Reuse:** evidence should stay in the private run root while public repository files expose stable schemas and reviewed summaries. That boundary already protects mid-investigation verdicts and fixture details. [`registers.md:22-39`](registers.md) Every non-clear claim already requires a record with URL, status, locator, excerpt, hash, and replay command. [`../playbooks/security-release-audit-playbook.md:146-148`](../playbooks/security-release-audit-playbook.md)

**Extend:** neither `data/security-releases.csv` nor the learning registers can serve as the case inventory. The former is a Core backport matrix keyed by release and fixed-version diff; the latter starts at method failure/change/control status. [`../data/security-releases.csv:1-4`](../data/security-releases.csv) [`registers.md:10-18`](registers.md) A separate case layer is needed to preserve plugin identity, version evidence, CVE state, source provenance, human disposition, and later learning links. This research does not select its file format.

**Conflict:** published learning-register copies must remain headers only. Populating them with every CVE would violate the current public/private contract and would also misstate disclosures as method failures. [`../learning/README.md:1-24`](../learning/README.md)

### 3. Classification against the security method

**Reuse:** approved training cases can be classified against the existing plugin attack-surface model. That model already enumerates plugin request paths, storage/state, dynamic behavior, lifecycle, dependency, multisite, external-service, and cross-component surfaces. [`wordpress-attack-surfaces.md:19-42`](wordpress-attack-surfaces.md) They can also map to the invariant catalog, whose entries pair a broken assumption with a test and negative control. [`security-invariants.md:18-23`](security-invariants.md)

**Extend:** classification must allow "no current invariant matches." The repository already treats that outcome as under-coverage through the mandatory `unknown-shape` research family, which is the correct seam for novel CVE mechanisms. [`orchestration.md:55-60`](orchestration.md) The corpus then becomes an external coverage oracle rather than a collection measured against the catalog it is meant to challenge. [`security-invariants.md:84-87`](security-invariants.md)

**Conflict:** an advisory's vulnerability class cannot by itself prove that the repository's current control would detect the mechanism. The method distinguishes source trace, dynamic primitive, verified vulnerability, and regression protection, and requires more evidence at each step. [`validation-and-proof.md:23-35`](validation-and-proof.md)

### 4. Training-case admission and proof status

**Reuse:** the approved corpus should remain human-curated and pre-registered; controls authored by the same model in the same run cannot calibrate that run. [`validation-and-proof.md:47-48`](validation-and-proof.md) The project's human approval gate fits this rule.

**Extend:** a training-case admission status is separate from a vulnerability verdict. For third-party targets that cannot be safely built, the method requires `source-attested` labeling and says the checklist is weaker than the owned-repository firing loop. [`validation-and-proof.md:50-57`](validation-and-proof.md) An approved training case may therefore be strong enough to teach the method while still lacking a locally fired finding.

**Conflict:** current authorization forbids testing unowned extensions and limits active security testing to disposable local environments. [`release-audit-learning-loop.md:27-31`](release-audit-learning-loop.md) The CVE project can study already-public disclosures, patches, and safe local controls, but it cannot turn monitoring into live probing of third-party sites or unowned plugins without redrawing that boundary. The playbook also forbids external filing without operator approval and keeps exploit-grade material private. [`../playbooks/security-release-audit-playbook.md:27-32`](../playbooks/security-release-audit-playbook.md)

### 5. Promotion into method changes

**Reuse:** a training case that reveals blindness belongs first in a proposed FM row; the proposed fix belongs in a linked MC row; a new detector then needs shadow-run evidence with positive and negative controls before acceptance. [`registers.md:10-16`](registers.md) [`../learning/failure-mode-register.csv:1`](../learning/failure-mode-register.csv) [`../learning/method-change-proposals.csv:1`](../learning/method-change-proposals.csv) [`../learning/shadow-run-results.csv:1`](../learning/shadow-run-results.csv) The existing follow-up skill already routes new failure modes and method changes through those registers. [`../skills/wp-release-followup/SKILL.md:206-212`](../skills/wp-release-followup/SKILL.md)

**Extend:** the new case layer must retain the link from case to method signal and from signal to FM/MC rows. Current FM/MC schemas link method failures, proposals, detectors, and shadow runs, but they do not link back to an external training case. [`../learning/failure-mode-register.csv:1`](../learning/failure-mode-register.csv) [`../learning/method-change-proposals.csv:1`](../learning/method-change-proposals.csv)

**Conflict:** the project should not create one rule per CVE. Existing ecosystem logic promotes only a demonstrated blind spot and its fix, while checked-and-cleared signals remain recorded without changing the method. [`ecosystem-signals.md:45-48`](ecosystem-signals.md) Existing accepted changes also show that a method rule needs named controls and recorded shadow evidence, not frequency or severity alone. [`method-improvements-summary.md:83-104`](method-improvements-summary.md)

### 6. Human review and public contribution

**Reuse:** the repository has low-friction field reports, method-improvement issues, and pull requests as progressively stronger public contribution doors. [`../CONTRIBUTING.md:3-29`](../CONTRIBUTING.md) The method-improvement issue asks what is missing, what happened during a run, the proposed change, its area, and detector controls. [`../.github/ISSUE_TEMPLATE/method-improvement.yml:12-58`](../.github/ISSUE_TEMPLATE/method-improvement.yml)

**Extend:** a weekly review queue needs a distinct review surface or a carefully delimited use of existing issues. A raw advisory is neither a field report from running the tool nor yet a method-improvement proposal. The field-report template explicitly routes security vulnerabilities away from the repository. [`../.github/ISSUE_TEMPLATE/field-report.yml:6-16`](../.github/ISSUE_TEMPLATE/field-report.yml) The test-report template does the same and requires a build, environment, reproduction, controls, and evidence ceiling that an intake candidate may not have. [`../.github/ISSUE_TEMPLATE/test-report.yml:6-22`](../.github/ISSUE_TEMPLATE/test-report.yml) [`../.github/ISSUE_TEMPLATE/test-report.yml:68-118`](../.github/ISSUE_TEMPLATE/test-report.yml)

**Conflict:** no public review artifact may expose a new, undisclosed vulnerability or exploit-grade detail. Public method contributions derived from coordinated disclosure must omit mechanism, endpoint, and reproduction until a fix ships. [`../CONTRIBUTING.md:73-78`](../CONTRIBUTING.md)

### 7. Scheduled automation and repository checks

**Reuse:** the two existing watch workflows provide useful operating patterns. `release-watch` runs daily, uses an issue as its deduplication record, and dispatches an automated suite while leaving a human checklist. [`../.github/workflows/release-watch.yml:11-16`](../.github/workflows/release-watch.yml) [`../.github/workflows/release-watch.yml:49-83`](../.github/workflows/release-watch.yml) `upstream-watch` runs controls before network-backed readings, grants only read-content/write-issue permissions, and keeps one refreshable review issue instead of creating weekly noise. [`../.github/workflows/upstream-watch.yml:20-48`](../.github/workflows/upstream-watch.yml) [`../.github/workflows/upstream-watch.yml:65-94`](../.github/workflows/upstream-watch.yml) It also keeps untrusted upstream text out of shell interpolation. [`../.github/workflows/upstream-watch.yml:8-16`](../.github/workflows/upstream-watch.yml)

**Extend:** neither workflow monitors plugin advisories. One detects Core prerelease packages; the other detects commit drift in projects whose techniques this repository borrows. [`../.github/workflows/release-watch.yml:1-7`](../.github/workflows/release-watch.yml) [`../.github/workflows/upstream-watch.yml:1-10`](../.github/workflows/upstream-watch.yml) The agreed daily discovery and weekly human digest need their own seam while retaining those controls, deduplication, low-noise issue handling, and narrow permissions.

**Extend:** repository self-test currently validates Markdown links, sensitive path/token patterns, YAML, scripts, and the exact Core security-release CSV shape. [`../scripts/check-repo.py:42-124`](../scripts/check-repo.py) [`../scripts/check-repo.py:206-234`](../scripts/check-repo.py) Any durable case or mapping artifact will need a validation contract of its own if it is to support coverage claims rather than remain prose.

## Missing seams exposed by the repository

These are planning gaps, not implementation proposals:

1. **Vocabulary seam:** no exact, non-overlapping definitions connect observation, disclosure candidate, approved training case, and method signal to the repository's existing Signal/Candidate/Finding vocabulary. The glossary requires this precision. [`../CONTEXT.md:1-5`](../CONTEXT.md)
2. **Source-policy seam:** the current allowlist does not cover the intended plugin-advisory ecosystem, so authority, corroboration, and conflict rules must be settled before collection claims completeness. [`../sources/official-sources.md:15-22`](../sources/official-sources.md) [`../sources/official-sources.md:40-52`](../sources/official-sources.md)
3. **Identity seam:** the Core backport matrix cannot express plugin slugs across distribution channels or uncertain version ranges. Its schema is Core-release-specific. [`../data/security-releases.csv:1-4`](../data/security-releases.csv)
4. **Lifecycle seam:** no durable record joins first observation, CVE assignment or rejection, human approval, checked-and-cleared disposition, and corpus admission. Existing registers begin after a method gap is found. [`../learning/README.md:16-24`](../learning/README.md)
5. **Traceability seam:** no current register links an external case to mapped surfaces/invariants and onward to FM/MC/SR/D records. The present ID system links only the method-learning artifacts. [`registers.md:8-20`](registers.md)
6. **Corpus-governance seam:** the method requires a human-curated external corpus but leaves its contents and curator open. [`open-research.md:42-51`](open-research.md)
7. **Third-party evidence seam:** the method distinguishes fired owned-repository proof from source-attested third-party analysis, but the planned corpus needs an admission rule that does not confuse those evidence ceilings. [`validation-and-proof.md:50-57`](validation-and-proof.md)
8. **Review-surface seam:** existing public issue templates either start from a run or explicitly reject vulnerability reporting, so they do not directly model an already-public advisory awaiting method review. [`../.github/ISSUE_TEMPLATE/field-report.yml:6-16`](../.github/ISSUE_TEMPLATE/field-report.yml) [`../.github/ISSUE_TEMPLATE/method-improvement.yml:12-31`](../.github/ISSUE_TEMPLATE/method-improvement.yml)
9. **Coverage seam:** the repository states that discovery breadth is the ceiling and that false-positive rate, false-negative rate, coverage, and verification time remain unmeasured until a known-bug corpus exists. [`open-research.md:42-48`](open-research.md)
10. **Automation seam:** existing automation supplies good patterns but no plugin-vulnerability collector, case deduplication key, review-state store, or daily-to-weekly queue contract. [`../.github/workflows/release-watch.yml:49-83`](../.github/workflows/release-watch.yml) [`../.github/workflows/upstream-watch.yml:65-94`](../.github/workflows/upstream-watch.yml)

## Planning conclusions

1. Treat `method/ecosystem-signals.md` as the sole entry into method learning; add a durable disclosure/case layer before it rather than another learning loop. [`ecosystem-signals.md:21-48`](ecosystem-signals.md)
2. Treat the approved training-case corpus as the missing external oracle already required by `security-invariants.md` and `validation-and-proof.md`, while keeping corpus admission separate from finding verification. [`security-invariants.md:84-90`](security-invariants.md) [`validation-and-proof.md:23-35`](validation-and-proof.md)
3. Promote only explicit method signals into the existing FM/MC/SR/D registers, retaining checked-and-cleared cases as corpus evidence without manufacturing method changes. [`ecosystem-signals.md:45-48`](ecosystem-signals.md) [`registers.md:10-16`](registers.md)
4. Preserve the private run-root/public-schema split and the no-public-disclosure boundary. [`../learning/README.md:1-14`](../learning/README.md) [`../CONTRIBUTING.md:73-83`](../CONTRIBUTING.md)
5. Resolve source authority, plugin identity, lifecycle, review surface, traceability, and coverage measurement as distinct planning decisions before selecting tools or file formats. The repository itself marks the corpus and its measurable performance as unresolved. [`open-research.md:42-54`](open-research.md)

## Blocked facts

No repository fact blocked this investigation. The repository does not decide which external advisory sources are authoritative for plugin CVEs, how plugin identities reconcile across distribution channels, or what evidence admits a disclosure to the corpus; those are open design decisions for later Wayfinder tickets, not facts recoverable from the current tree. The current source policy is narrower than the proposed watch, and the corpus is explicitly still unbuilt. [`../sources/official-sources.md:15-22`](../sources/official-sources.md) [`open-research.md:42-51`](open-research.md)
