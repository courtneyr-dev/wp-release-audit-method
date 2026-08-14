# WordPress release testing

The ubiquitous language of this repository. These terms are used exactly, everywhere — README,
playbooks, scripts, skills, prompts. If a document here uses one of these words, it means what
this file says, and nothing else.

## Language

### The work

**Cell**:
The smallest unit of testing that produces its own verdict — one check, individually executed.
A suite line that was never individually run is not a cell result.
_Avoid_: test case, check, step

**Suite**:
An ordered collection of cells run as one script against one environment.
_Avoid_: test run, script (when the topic is the testing, not the file)

**Lane**:
A named path through the testing — an upgrade route, an install method, a hosting shape — that
cells run inside. "Recurring lane" for one that runs every cycle.
_Avoid_: standing lane (standing is reserved — see standing environment), track, flow

**Chain**:
A cross-release interaction test: two or more features exercised together across an upgrade,
where each release changed one of them.
_Avoid_: scenario, integration test

**Act**:
One of the three phases of a release cycle's testing: Act I before the drop (build fixtures on
the current release), Act II the party (breadth, fast), Act III after (depth, honest).
_Avoid_: phase, stage

### The instruments

**Driver**:
An adapter that runs WordPress somewhere (DDEV, Playground, wp-env, Studio, Lando, a plain
CLI) behind the one `lib-env.sh` interface.
_Avoid_: environment (that's the thing the driver provides), backend

**Capability**:
A fact a driver declares about what its environment can physically do (hostfs, snapshot,
core-updater…). Probed, never assumed.
_Avoid_: feature, support

**Gate**:
A scripted go/no-go check that runs before results count — build identity, security-fix
presence, an active release cycle. Gates have exit codes, not opinions.
_Avoid_: check, validation

**Control**:
A run whose answer is already known, executed to prove the instrument can detect what it
claims — the patched build reading PATCHED, the finished cycle reading no-cycle. Controls run
before cells.
_Avoid_: sanity check, smoke test

**Detector**:
The gate that answers "is there a new Beta/RC, and is a prerelease cycle actually active?"
_Avoid_: watcher, checker

### The materials

**Fixture**:
A disposable environment built to a known state for evidence — cattle, rebuilt fresh, its
starting state nameable.
_Avoid_: test site (ambiguous with standing environment), sandbox

**Standing environment**:
The one site never rebuilt: upgraded in place every Beta/RC, state deliberately accumulating.
Applied to testing infrastructure, "standing" means this and only this — never a lane that
happens to run every cycle (say "recurring lane"). The ordinary sense in "standing rule" or
"standing method", meaning established policy, is unaffected.
_Avoid_: pet site, permanent install, standing lane

**Target**:
The build under test, always pinned — a package zip URL, never "whatever is newest." Suites
receive it; they do not choose it.
_Avoid_: latest, the beta

**Corpus**:
A canonical body of imported test content (theme-test-data, a11y-theme-unit-test).
_Avoid_: demo content, sample data

**Ledger**:
An append-only dated record that gives state provenance — what changed, when, from what to
what.
_Avoid_: log, history

### The verdicts

**BLOCKED**:
The verdict of a cell that needed a capability its driver lacks. Named after the missing
capability; never converted to PASS.
_Avoid_: skipped, N/A

**INVALID**:
The verdict of a result produced by a harness fault — the measurement was of the rig, not of
WordPress.
_Avoid_: false positive (that's a claim about WordPress; INVALID is a claim about the rig)

**Harness fault**:
A defect in the testing apparatus itself — a stale host view, an unflushed rewrite rule, a
self-upgraded fixture — that manufactures findings.
_Avoid_: test bug, flake

**Evidence ceiling**:
The strongest claim a given setup can honestly support. A pass on an environment that could
not have detected the failure is above its ceiling.
_Avoid_: confidence level

**Finding**:
A confirmed, reduced, reproducible behavior of the target — mechanism, evidence, and fix
attached. A lead from the standing environment is not yet a finding.
_Avoid_: bug (until reduced), issue, result

### The documents

**Playbook**:
A runbook for a recurring situation — ordered actions with a clock on them (release day, a
security release, a performance pass).

**Method**:
The reasoning a playbook rests on — why the procedure is shaped the way it is. Read when
designing, not when executing.

**Prompt**:
A verbatim artifact handed to an AI agent, preserved byte-for-byte once used, because handoffs
cite the exact prompt that ran.

**Skill**:
A packaged procedure an AI assistant loads and follows (the `skills/` directory).
_Avoid_: agent, workflow
