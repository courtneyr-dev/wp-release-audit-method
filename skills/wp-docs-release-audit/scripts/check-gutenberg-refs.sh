#!/usr/bin/env bash
# Resolve every Gutenberg PR or issue number cited in the given files and flag
# anything that is not a merged PR. Read-only.
# Usage: check-gutenberg-refs.sh FILE...
# Output: number|PR or issue|state|merged at|title, then FLAG lines.
set -euo pipefail
[ "$#" -ge 1 ] || { sed -n '2,5p' "$0"; exit 2; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 2; }
nums=$(cat "$@" | grep -oE 'gutenberg#[0-9]+|gutenberg/(pull|issues)/[0-9]+' |
  grep -oE '[0-9]+$' | sort -un)
[ -n "$nums" ] || { echo "no Gutenberg references found"; exit 0; }
table=$(printf '%s\n' $nums | xargs -P 8 -I{} sh -c '
  gh api "repos/WordPress/gutenberg/issues/$1" --jq "[\"$1\", \
    (if .pull_request then \"PR\" else \"issue\" end), .state, \
    (.pull_request.merged_at // \"-\"), (.title|.[0:80])] | join(\"|\")" 2>/dev/null \
  || echo "$1|ERROR|-|-|not found"' _ {} | sort -t'|' -k1,1n)
printf '%s\n' "$table"
echo "--- $(printf '%s\n' "$table" | wc -l | tr -d ' ') references ---"
printf '%s\n' "$table" | awk -F'|' '
  $2=="ERROR"            {print "FLAG not found: #" $1}
  $2=="issue"            {print "FLAG issue, not a PR (" $3 "): #" $1 " " $5}
  $2=="PR" && $4=="-"    {print "FLAG PR not merged (" $3 "): #" $1 " " $5}'
