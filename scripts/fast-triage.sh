#!/bin/bash
# RELEASE-PARTY FAST TRIAGE — answers in ~60 seconds, no containers, no database.
#
# Hand it the new build's zip. It reports what changed, what's missing from
# $_old_files, whether the upgrade path has a polyfill landmine, and where the
# security-relevant surface moved — before anything boots.
#
# Usage: fast-triage.sh <new-zip> [<prev-zip-or-extracted-dir>]
#   fast-triage.sh ~/Downloads/wordpress-7.1-beta5.zip
#   fast-triage.sh ~/Downloads/wordpress-7.1-RC1.zip ~/Downloads/wordpress-7.1-beta4.zip

set -uo pipefail
NEW_ZIP="$1"
PREV="${2:-}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

hdr() { echo; echo "════ $1"; }

hdr "BUILD IDENTITY"
unzip -qo "$NEW_ZIP" -d "$WORK/new"
NEWDIR="$WORK/new/wordpress"
grep -E "^\\\$wp_version|^\\\$wp_db_version" "$NEWDIR/wp-includes/version.php" | sed 's/^/  /'
echo "  sha256: $(shasum -a 256 "$NEW_ZIP" | cut -d' ' -f1)"

# Resolve the comparison baseline
if [ -n "$PREV" ]; then
  if [ -d "$PREV" ]; then
    PREVDIR="$PREV"; [ -d "$PREV/wordpress" ] && PREVDIR="$PREV/wordpress"
  else
    unzip -qo "$PREV" -d "$WORK/prev"; PREVDIR="$WORK/prev/wordpress"
  fi
else
  echo "  (no baseline given — skipping diff sections; pass the previous zip for the full report)"
  PREVDIR=""
fi

hdr "STATIC GATE 1 — upgrade-path polyfill landmine"
# update-core.php runs from the NEW package inside the OLD runtime. A PHP 8
# function polyfilled by the new compat.php is a fatal for old installs (#59145).
HITS=$(grep -nE '(str_contains|str_starts_with|str_ends_with|array_is_list)[[:space:]]*\(' \
        "$NEWDIR/wp-admin/includes/update-core.php" 2>/dev/null | grep -vE '^\s*[0-9]+:\s*\*')
if [ -z "$HITS" ]; then echo "  PASS — no polyfilled PHP8 functions called"
else echo "  *** FAIL — these fatal when upgrading old WP on old PHP:"; echo "$HITS" | sed 's/^/    /'; fi

if [ -n "$PREVDIR" ]; then
  hdr "STATIC GATE 2 — \$_old_files completeness"
  ( cd "$PREVDIR" && find wp-admin wp-includes -type f 2>/dev/null | sort ) > "$WORK/old.txt"
  ( cd "$NEWDIR"  && find wp-admin wp-includes -type f 2>/dev/null | sort ) > "$WORK/new.txt"
  comm -23 "$WORK/old.txt" "$WORK/new.txt" > "$WORK/deleted.txt"
  python3 - "$NEWDIR" "$WORK/deleted.txt" <<'PY'
import re, sys, collections
src = open(sys.argv[1] + '/wp-admin/includes/update-core.php').read()
m = re.search(r'\$_old_files\s*=\s*array\((.*?)\n\);', src, re.S)
listed = set(re.findall(r"'([^']+)'", m.group(1))) if m else set()
deleted = [l.strip() for l in open(sys.argv[2]) if l.strip()]
missing = [d for d in deleted if d not in listed
           and not any(d.startswith(e.rstrip('/') + '/') for e in listed)]
print(f"  deleted since baseline: {len(deleted)}   listed in $_old_files: {len(listed)}")
if missing:
    print(f"  *** FAIL — {len(missing)} deleted files NOT in $_old_files (orphaned on upgrade):")
    for k, v in collections.Counter('/'.join(p.split('/')[:3]) for p in missing).most_common(10):
        print(f"      {v:5}  {k}/")
else:
    print("  PASS — every deleted file is accounted for")
PY

  hdr "STATIC GATE 3 — changed PHP surface (what to actually test)"
  diff -rq "$PREVDIR" "$NEWDIR" 2>/dev/null | grep '\.php ' \
    | sed "s|Files $PREVDIR/||; s| and .*differ||" > "$WORK/changed.txt"
  echo "  changed PHP files: $(wc -l < "$WORK/changed.txt" | tr -d ' ')"
  echo "  --- security-relevant (audit these first):"
  grep -iE "rest-api|capabilit|kses|auth|user|comment|upload|file\.php|filesystem|updater|http|media|abilit|sanitiz|cron" \
    "$WORK/changed.txt" | sed 's/^/      /' | head -25
  echo "  --- new files:"
  diff -rq "$PREVDIR" "$NEWDIR" 2>/dev/null | grep "^Only in $NEWDIR" | sed 's/^/      /' | head -10
fi

hdr "NEXT (parallel, while you read this)"
cat <<'EOS'
  Cell 3 (PHP 7.4):  direct-jump-matrix.sh  +  stepped-chain.sh
  Cell 2 (PHP 8.2):  crud-suite.sh  +  users-pages-install.sh
  Preflight:         preflight-sensitivity.sh   (log what this rig CANNOT detect)
  Subagents:         (a) what's PUNTED/reverted since last drop   (b) calls for testing
  Never run two wp-env commands against the same project at once.
EOS
