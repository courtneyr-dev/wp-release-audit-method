# Methods registers — the schema contract

Two registers the prompts and skills read by path. Same arrangement as
[`learning/`](../learning/README.md): the header row is the contract, populated rows live in
the private run root, and [`method/registers.md`](../method/registers.md) defines the id
schemes. The public digest of accepted detector rows is the
[detector status table](../method/method-improvements-summary.md#detector-status).

| Register | One row per | Cited as |
|---|---|---|
| [`detection-rules.csv`](detection-rules.csv) | Accepted detector, with its calibration evidence | `D-*` |
| [`test-and-fixture-registry.csv`](test-and-fixture-registry.csv) | Fixture the loop can build or has built | `FX-*` |

A detector only gets a `D-` row after a shadow run with both controls
(`learning/shadow-run-results.csv`); a fixture row records what the fixture *is* so that a
cell can name its starting state instead of describing it.
