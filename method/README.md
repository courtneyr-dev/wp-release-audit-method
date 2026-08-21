# The method — who this directory is for

The [main README](../README.md) promises you are *"not expected to read WordPress core code,
write PHP, or know what a changeset is."* That promise holds for the README, the playbooks,
and the skills. **It does not hold here.** These documents assume you can read core source,
follow a capability check through `map_meta_cap()`, and argue with a threat model — several
([security-invariants](security-invariants.md), [audit-playbook](audit-playbook.md),
[validation-and-proof](validation-and-proof.md)) exist precisely to be that demanding.

**If you're a release tester:** you can ignore this whole directory and lose nothing on
release day. The rules you need are already baked into the scripts, the matrices, and the
skills. Come here only when a rule feels arbitrary and you want the receipt for it.

**If you're extending or challenging the method:** start with
[release-audit-learning-loop.md](release-audit-learning-loop.md) — the five laws and the
calibrated detectors — then [registers.md](registers.md) for what the row ids mean.

## The map

The full one-screen index of every layer — README, skills, playbooks, method, examples,
prompts, with a line on when each is worth reading — is in
[`wp-release-followup`](../skills/wp-release-followup/SKILL.md#where-this-fits--the-whole-method-in-one-screen).
The short version:

| Layer | Read when |
|---|---|
| [README](../README.md) | You're testing a release |
| [Playbooks](../playbooks/) | You're going deep on one axis, today |
| [Skills](../skills/) | You want an assistant to run the cycle |
| **This directory** | A rule feels arbitrary and you want to know what breaks without it |
| [Examples](../examples/chains/) | You want to see one investigation done end to end, with evidence |
