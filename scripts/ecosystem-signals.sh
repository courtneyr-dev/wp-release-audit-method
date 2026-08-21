#!/usr/bin/env bash
# Ecosystem-signals triage: scan a signals source you control and flag the items
# that plausibly touch the method — mentions of the upcoming release, of a plugin
# in your fleet, of a release in the security-backport matrix, or of an incident
# shape near a version. See method/ecosystem-signals.md.
#
# It is a triage aid, not an oracle. Every hit goes through adjudication (check
# it against the primary source) before it becomes a cell, a lane, or a register
# row. It never sends your notes anywhere — WP_AUDIT_SIGNALS stays local.
#
# Usage:
#   export WP_AUDIT_SIGNALS=~/my-ecosystem-notes      # file or directory of text
#   export WP_AUDIT_FLEET="wp-rocket,elementor-pro"    # optional plugin slugs
#   bash scripts/ecosystem-signals.sh --version 7.2
#
#   --signals <path>   override WP_AUDIT_SIGNALS
#   --fleet a,b,c      override WP_AUDIT_FLEET
#   --version X.Y      the upcoming release string to watch for (recommended)
#   --self-test        run the built-in controls against fixtures/signals/ and exit
#
# With no signals source and no --self-test, it prints the source types to watch
# and exits 0 — it does not invent signals.
#
# Exit codes: 0 ran (hits are advisory) · 2 setup error · 4 control miscalibration
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SIGNALS="${WP_AUDIT_SIGNALS:-}"
FLEET="${WP_AUDIT_FLEET:-}"
VERSION=""
SELFTEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --signals) SIGNALS="${2:?}"; shift 2 ;;
    --fleet)   FLEET="${2:?}"; shift 2 ;;
    --version) VERSION="${2:?}"; shift 2 ;;
    --self-test) SELFTEST=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# security-release identifiers (versions + CVEs) from the backport matrix, so a
# note mentioning a patched release or CVE surfaces as a signal.
sec_terms() {
  local csv="$ROOT/data/security-releases.csv"
  [ -s "$csv" ] || return 0
  # columns: release,date,cve,cvss,summary,fixed_in,diff_prev,backport_floor,...
  awk -F, 'NR>1 { if ($3!="") printf "%s ", $3; if ($1!="") printf "%s ", $1 }' "$csv"
}

# The classifier. Reads text on stdin, prints one line per matched signal:
#   TAG<TAB>source<TAB>excerpt
classify() {
  local src="$1"
  local version="$2" fleet="$3"
  # Case-insensitivity via tolower(), not IGNORECASE: the latter is a gawk
  # extension that BSD/macOS awk silently ignores, so a slug would miss a
  # display name on exactly the machines this repo is written on.
  awk -v src="$src" -v version="$version" -v fleet="$fleet" -v sec="$4" '
    BEGIN {
      n = split(tolower(fleet), F, /[, ]+/);
      s = split(tolower(sec), S, /[, ]+/);
      vlow = tolower(version);
    }
    {
      if ($0 ~ /^[ \t]*$/) next;
      low = tolower($0);
      tag = "";
      # incident shape: a breakage word near a version-looking token
      if (low ~ /(fatal|white screen|wsod|regression|breaks|broke|deprecat|removed in|rce|xss|sqli|cve-)/ &&
          low ~ /[0-9]+\.[0-9]/) tag = "INCIDENT";
      # upcoming release mention
      if (vlow != "" && index(low, vlow) > 0) tag = tag=="" ? "RELEASE" : tag "+RELEASE";
      # fleet plugin mention — slug OR display name: a hyphen in the slug also
      # matches a space (wp-rocket ~ "wp rocket").
      for (i = 1; i <= n; i++) {
        if (F[i] == "") continue;
        pat = F[i]; gsub(/-/, "[- ]", pat);
        if (low ~ pat) { tag = tag=="" ? "FLEET" : tag "+FLEET"; break }
      }
      # security-matrix term (version or CVE)
      for (i = 1; i <= s; i++) {
        if (S[i] != "" && index(low, S[i]) > 0) { tag = tag=="" ? "SECURITY" : tag "+SECURITY"; break }
      }
      if (tag != "") {
        excerpt = $0; gsub(/^[ \t]+/, "", excerpt);
        if (length(excerpt) > 160) excerpt = substr(excerpt, 1, 157) "...";
        printf "%s\t%s\t%s\n", tag, src, excerpt;
      }
    }'
}

scan_path() {
  local p="$1" version="$2" fleet="$3" sec="$4"
  if [ -d "$p" ]; then
    find "$p" -type f \( -name '*.md' -o -name '*.txt' \) -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do
          classify "$(basename "$f")" "$version" "$fleet" "$sec" < "$f"
        done
  elif [ -f "$p" ]; then
    classify "$(basename "$p")" "$version" "$fleet" "$sec" < "$p"
  else
    echo "ERROR: signals source not found: $p" >&2
    return 2
  fi
}

if [ "$SELFTEST" = "1" ]; then
  fx="$ROOT/fixtures/signals"
  [ -d "$fx" ] || { echo "ERROR: no fixture at $fx"; exit 2; }
  out="$(scan_path "$fx/positive.md" "7.2" "wp-rocket" "$(sec_terms)")" || exit 2
  # Positive control: the fixture's planted release, fleet, security, and incident
  # lines must each surface; the negative (noise) line must not.
  bad=0
  for want in RELEASE FLEET SECURITY INCIDENT; do
    echo "$out" | grep -q "^$want" || { echo "CONTROL-FAIL: $want signal not flagged"; bad=1; }
  done
  if echo "$out" | grep -qi 'this line is ordinary release-notes prose about nothing'; then
    echo "CONTROL-FAIL: negative control (noise line) was flagged"; bad=1
  fi
  [ "$bad" = "0" ] && { echo "CONTROL-PASS: 4 signal classes flagged, noise ignored"; exit 0; }
  exit 4
fi

if [ -z "$SIGNALS" ]; then
  cat <<'EOS'
No signals source set. Point WP_AUDIT_SIGNALS at your ecosystem notes (a file or
a folder of .md/.txt) and re-run, or watch these source types by hand — see
method/ecosystem-signals.md:

  - Make/Core dev notes      https://make.wordpress.org/core/tag/dev-notes/
  - WordPress releases       https://wordpress.org/news/
  - Trac milestone for the upcoming release
  - The public tracker of every plugin in your fleet
  - Incident write-ups and WCUS/WCEU talks

Nothing was scanned. This tool does not invent signals.
EOS
  exit 0
fi

SEC="$(sec_terms)"
echo "== ecosystem-signals — source: $SIGNALS${VERSION:+  watching: $VERSION}${FLEET:+  fleet: $FLEET}"
RESULT="$(scan_path "$SIGNALS" "$VERSION" "$FLEET" "$SEC")" || exit 2
if [ -z "$RESULT" ]; then
  echo "no signals matched. Widen --fleet, confirm --version, or read the sources by hand."
  exit 0
fi
printf '%s\n' "$RESULT" | sort | awk -F'\t' '
  { printf "[%-16s] %-24s %s\n", $1, $2, $3 }'
echo
echo "Each line is a CANDIDATE, not a finding. Adjudicate against the primary source"
echo "before it becomes a cell, a lane, or a register row (method/ecosystem-signals.md)."
exit 0
