#!/usr/bin/env python3
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REGISTER_HEADER = [
    "chain_id",
    "name",
    "anchor_change_ids",
    "hypothesis",
    "source_citations",
    "matrix_cells",
    "fixture_id",
    "positive_control",
    "negative_control",
    "threat_model",
    "status",
    "verdict",
    "evidence_path",
]
RESULTS_HEADER = [
    "chain_id",
    "cell",
    "expected",
    "observed",
    "verdict",
    "command",
    "output_path",
    "fixture_state_hash",
    "cleanup_verified",
]
ALLOWED_VERDICTS = {
    "CONFIRMED",
    "REFUTED",
    "INCONCLUSIVE",
    "BLOCKED",
    "INVALID",
}


def load(path):
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        return reader.fieldnames, list(reader)


register_header, register = load(ROOT / "chain-register.csv")
results_header, results = load(ROOT / "results.csv")
assert register_header == REGISTER_HEADER, register_header
assert results_header == RESULTS_HEADER, results_header

chain_ids = [row["chain_id"] for row in register]
assert len(chain_ids) == len(set(chain_ids)), "duplicate chain IDs"
known = set(chain_ids)

for row in results:
    assert row["chain_id"] in known, row["chain_id"]
    assert row["verdict"] in ALLOWED_VERDICTS, row["verdict"]
    assert row["command"].strip(), row
    assert row["fixture_state_hash"].strip(), row
    assert row["cleanup_verified"] in {"yes", "no", "not-run"}, row

print(f"PASS: {len(register)} chains, {len(results)} result cells")

