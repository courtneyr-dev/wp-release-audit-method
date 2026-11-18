#!/usr/bin/env bash
# Report whether the official Documentation Style Guide repo moved since a pinned commit.
# Usage: style-guide-pin.sh [PINNED_SHA]
#   no argument: print the repo's latest commit on main
#   PINNED_SHA:  also say "unchanged", or list the files that changed since it
# Read-only.
set -euo pipefail
command -v gh >/dev/null || { echo "gh is required" >&2; exit 2; }
repo=WordPress/WordPress-Documentation-Style-Guide
head=$(gh api "repos/$repo/commits/main" --jq '"\(.sha[0:10]) \(.commit.committer.date) \(.commit.message | split("\n")[0])"')
echo "latest on main: $head"
[ "$#" -ge 1 ] || exit 0
pin=$1
if ! gh api "repos/$repo/commits/$pin" --jq '"pinned: \(.sha[0:10]) \(.commit.committer.date)"'; then
  echo "pinned commit $pin not found in $repo" >&2; exit 1
fi
read -r status ahead files < <(gh api "repos/$repo/compare/$pin...main" --jq '"\(.status) \(.ahead_by) \(.files | length)"')
if [ "$status" = identical ]; then echo "unchanged since the pin"; exit 0; fi
echo "main is $ahead commit(s) ahead; $files file(s) changed:"
gh api "repos/$repo/compare/$pin...main" --jq '.files[] | "  \(.status) \(.filename)"'
