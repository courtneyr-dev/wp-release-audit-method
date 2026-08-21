#!/usr/bin/env bash
# Security-fix presence gate.
#
# Question this answers: does the build you are about to test (an RC, beta, or
# nightly) already contain every *code* fix that shipped in the most recent
# stable security release? An RC packaged before a security release can miss
# fixes that are, by then, public and patched — a window where testers run
# known-vulnerable code, and the exact case this gate exists to catch.
#
# Method: diff the stable security release against its immediate predecessor to
# derive the fix set from source (no hand-maintained CVE signatures — the diff
# IS the signature). Then, per changed file, decide whether the target build
# carries the patched lines, still carries the pre-fix lines, or diverges from
# both and needs a human read.
#
# This is a REGRESSION check against a KNOWN public fix, so diffing against the
# patched version is correct here — the opposite of novel-bug hunting, where you
# withhold the answer key.
#
# Known limits (the tool triages; it does not adjudicate):
#   - It works on lines, not semantics. A change confined to a docblock/example
#     (e.g. class-wp-script-modules.php in 7.0.3) is flagged VULNERABLE because the
#     old example text is still present — read those before believing them.
#   - DIVERGED means the target refactored around the fix site: neither clearly
#     patched nor clearly pre-fix. Always read DIVERGED by hand.
#   - PATCHED/VULNERABLE are strong signals, not proof. For anything shipping,
#     confirm the high-severity ones behaviorally (e.g. call wp_http_validate_url
#     against a link-local address for the SSRF fix).
#
# Usage:
#   security_fix_presence.sh <target_dir|target_zip> <prev_version> <fixed_version>
#   security_fix_presence.sh ~/rc/wordpress 7.0.2 7.0.3
#
#   security_fix_presence.sh <target_dir|target_zip> --all
#     Run every (prev -> fixed) pair in data/security-releases.csv against the
#     target, so a fleet on an arbitrary version checks against the whole known
#     backport matrix rather than one hardcoded pair. Rows with a blank fixed_in
#     or an equal prev/fixed are skipped (nothing to diff). Exit 4 if ANY pair
#     flags VULNERABLE.
#
# Exit codes: 0 all fixes present · 4 one or more fixes VULNERABLE in target · 2 setup error
set -uo pipefail

TARGET="${1:?target dir or zip}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "${2:-}" = "--all" ]; then
  CSV="${WP_SECREL_CSV:-$HERE/../data/security-releases.csv}"
  [ -s "$CSV" ] || { echo "ERROR: no security-releases.csv at $CSV"; exit 2; }
  overall=0
  # release,date,cve,cvss,summary,fixed_in,diff_prev,backport_floor,branches_patched,source_url
  # The fix set is diff_prev -> fixed_in (the immediate predecessor whose diff
  # IS the fix). backport_floor is descriptive (how far back it was patched),
  # NOT the thing to diff — 4.7 vs 7.0.3 is a whole-major diff, meaningless here.
  while IFS=, read -r release _date cve _cvss _summary fixed_in prev _floor _branches _url; do
    [ "$release" = "release" ] && continue
    [ -z "$fixed_in" ] && continue
    [ -z "$prev" ] && continue
    [ "$prev" = "$fixed_in" ] && continue
    echo "=== ${cve:-$release}: $prev -> $fixed_in"
    if ! "$0" "$TARGET" "$prev" "$fixed_in"; then overall=4; fi
    echo
  done < "$CSV"
  exit "$overall"
fi

PREV="${2:?prev version e.g. 7.0.2}"; FIXED="${3:?fixed version e.g. 7.0.3}"
UA="wp-release-audit (read-only verification)"
CACHE="${WP_SECFIX_CACHE:-$HOME/.wp-secfix-cache}"; mkdir -p "$CACHE"

say() { printf '%s\n' "$*"; }

resolve() { # version -> extracted wordpress/ dir in cache
  local v="$1" zip="$CACHE/wp-$1.zip" dir="$CACHE/x-$1"
  if [ ! -d "$dir/wordpress" ]; then
    if [ ! -s "$zip" ]; then
      for url in "https://wordpress.org/wordpress-$v.zip" "https://downloads.wordpress.org/release/wordpress-$v.zip"; do
        [ "$(curl -s -o "$zip" -w '%{http_code}' --max-time 300 -A "$UA" "$url")" = "200" ] && break
      done
    fi
    [ -s "$zip" ] || { say "ERROR: could not fetch WordPress $v"; return 2; }
    mkdir -p "$dir"; (cd "$dir" && unzip -qo "$zip") || return 2
  fi
  printf '%s\n' "$dir/wordpress"
}

# Target -> a wordpress/ dir
TDIR="$TARGET"
if [ -f "$TARGET" ]; then
  ex="$CACHE/x-target"; rm -rf "$ex"; mkdir -p "$ex"; (cd "$ex" && unzip -qo "$TARGET") || exit 2
  TDIR="$ex/wordpress"
fi
[ -d "$TDIR" ] || { say "ERROR: target $TDIR not a directory"; exit 2; }

PDIR="$(resolve "$PREV")"   || exit 2
FDIR="$(resolve "$FIXED")"  || exit 2

say "Security-fix presence gate"
say "  fix set:  WordPress $PREV -> $FIXED  (diff-derived)"
say "  target:   $TDIR"
say ""

# Changed files, source only (skip minified/build artifacts and the version stamp).
# Portable array fill (macOS ships bash 3.2 — no mapfile).
FILES=()
while IFS= read -r line; do [ -n "$line" ] && FILES+=("$line"); done < <(diff -rq "$PDIR" "$FDIR" 2>/dev/null \
  | awk '/ differ$/ {print $2}' \
  | sed "s#^$PDIR/##" \
  | grep -Ev '(\.min\.js$|wp-includes/version\.php$)' )

total=0; patched=0; vulnerable=0; diverged=0; informational=0
VULN_LIST=()

substantive() { # keep lines with real code, drop pure punctuation/blank
  grep -E '[A-Za-z0-9_]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk 'length>3'
}

for rel in "${FILES[@]}"; do
  [ -f "$TDIR/$rel" ] || { printf '  %-11s %s (absent from target tree)\n' "MISSING-FILE" "$rel"; continue; }
  d="$(diff -u "$PDIR/$rel" "$FDIR/$rel" 2>/dev/null)"
  # Added = fix lines; Removed = pre-fix lines.
  ADD=(); while IFS= read -r line; do ADD+=("$line"); done < <(printf '%s\n' "$d" | grep -E '^\+' | grep -Ev '^\+\+\+' | sed 's/^\+//' | substantive)
  DEL=(); while IFS= read -r line; do DEL+=("$line"); done < <(printf '%s\n' "$d" | grep -E '^-'  | grep -Ev '^---'    | sed 's/^-//'  | substantive)
  [ "${#ADD[@]}" -eq 0 ] && [ "${#DEL[@]}" -eq 0 ] && continue
  total=$((total+1))

  add_hits=0; if [ "${#ADD[@]}" -gt 0 ]; then for l in "${ADD[@]}"; do grep -qF -- "$l" "$TDIR/$rel" && add_hits=$((add_hits+1)); done; fi
  del_hits=0; if [ "${#DEL[@]}" -gt 0 ]; then for l in "${DEL[@]}"; do grep -qF -- "$l" "$TDIR/$rel" && del_hits=$((del_hits+1)); done; fi
  add_ratio=0; [ "${#ADD[@]}" -gt 0 ] && add_ratio=$(( add_hits * 100 / ${#ADD[@]} ))
  del_ratio=0; [ "${#DEL[@]}" -gt 0 ] && del_ratio=$(( del_hits * 100 / ${#DEL[@]} ))

  # Classify. Fix present = most added lines found. Vulnerable = pre-fix lines
  # still present and the fix lines mostly absent.
  if [ "$add_ratio" -ge 80 ]; then
    printf '  %-11s %s\n' "PATCHED" "$rel"; patched=$((patched+1))
  elif [ "${#DEL[@]}" -gt 0 ] && [ "$del_ratio" -ge 80 ] && [ "$add_ratio" -lt 80 ]; then
    # Every pre-fix line is still present and the fix lines are not fully in — the
    # old code path is intact. Strong vulnerable signal even if refactoring around
    # it moved some shared context lines (which inflate add_ratio).
    printf '  %-11s %s\n' "VULNERABLE" "$rel"; vulnerable=$((vulnerable+1)); VULN_LIST+=("$rel")
  elif [ "${#ADD[@]}" -ge 1 ] && [ "${#ADD[@]}" -le 2 ] && printf '%s\n' "${ADD[@]}" | grep -qiE 'security (issue|release)|version %s|release notes'; then
    printf '  %-11s %s\n' "INFO" "$rel"; informational=$((informational+1))  # changelog/about copy
  else
    printf '  %-11s %s  (add %d%% / prefix %d%% — read)\n' "DIVERGED" "$rel" "$add_ratio" "$del_ratio"; diverged=$((diverged+1))
  fi
done

say ""
say "  $total fix-bearing files · $patched patched · $vulnerable VULNERABLE · $diverged diverged · $informational informational"
if [ "$vulnerable" -gt 0 ]; then
  say ""
  say "  Target is MISSING fixes that shipped in $FIXED:"
  for v in "${VULN_LIST[@]}"; do say "    - $v"; done
  say "  If $FIXED is public, these are known, patched-elsewhere vulnerabilities live in the target."
  say "  Confirm they are closed in the next build before shipping — do not assume merge-forward."
  exit 4
fi
say "  All derived fixes present in target."
exit 0
