#!/usr/bin/env bash
# Test check-draft.py: the clean draft has no findings, and the bad draft trips every rule.
# Usage: test-check-draft.sh   (run from anywhere; exits 1 on any failure)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
lint="$here/../check-draft.py"
status=0

good=$(python3 -I "$lint" "$here/good.draft" || true)
if printf '%s\n' "$good" | grep -qE '^(FAIL|WARN) '; then
  echo "FAIL good.draft produced findings:"; printf '%s\n' "$good"; status=1
else echo "ok   good.draft is clean"; fi

bad=$(python3 -I "$lint" "$here/bad.draft" || true)
missing=0
for slug in $(python3 -I "$lint" --list-rules | sed -E 's/^[A-Z]+ ([a-z0-9-]+):.*/\1/'); do
  if ! printf '%s\n' "$bad" | grep -q "\[$slug\]"; then
    echo "FAIL bad.draft does not trip [$slug]"; missing=$((missing + 1)); status=1
  fi
done
[ "$missing" -eq 0 ] && echo "ok   bad.draft trips every rule ($(python3 -I "$lint" --list-rules | wc -l | tr -d ' '))"
exit "$status"
