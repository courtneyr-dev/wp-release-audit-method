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
#     or an equal prev/fixed are reported as SKIPPED (inapplicable: nothing to
#     diff). Exit 4 if ANY pair flags VULNERABLE; exit 3 if ANY pair errored.
#
# Exit codes:
#   0  every comparison ran and none read VULNERABLE (DIVERGED / MISSING-FILE
#      still need a human read; exit 0 does not mean every fix is present)
#   4  every comparison ran and one or more files read VULNERABLE
#   3  run error: a diff/grep/awk subprocess failed, or zero comparisons ran.
#      The result is incomplete; do not read it as a pass or a fail.
#   2  setup error (bad target, could not fetch or extract a release)
set -uo pipefail

TARGET="${1:?target dir or zip}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "${2:-}" = "--all" ]; then
  CSV="${WP_SECREL_CSV:-$HERE/../data/security-releases.csv}"
  [ -s "$CSV" ] || { echo "ERROR: no security-releases.csv at $CSV"; exit 2; }
  ran=0; errored=0; vulnerable_pairs=0
  # release,date,cve,cvss,summary,fixed_in,diff_prev,backport_floor,branches_patched,source_url
  # The fix set is diff_prev -> fixed_in (the immediate predecessor whose diff
  # IS the fix). backport_floor is descriptive (how far back it was patched),
  # NOT the thing to diff — 4.7 vs 7.0.3 is a whole-major diff, meaningless here.
  while IFS=, read -r release _date cve _cvss _summary fixed_in prev _floor _branches _url; do
    [ "$release" = "release" ] && continue
    if [ -z "$fixed_in" ] || [ -z "$prev" ] || [ "$prev" = "$fixed_in" ]; then
      echo "=== ${cve:-$release}: SKIPPED (inapplicable: diff_prev '${prev}' -> fixed_in '${fixed_in}' is not a diffable pair)"
      echo
      continue
    fi
    echo "=== ${cve:-$release}: $prev -> $fixed_in"
    ran=$((ran+1))
    bash "$0" "$TARGET" "$prev" "$fixed_in"; rc=$?
    case "$rc" in
      0) ;;
      4) vulnerable_pairs=$((vulnerable_pairs+1)) ;;
      *) errored=$((errored+1)); echo "ERROR: pair $prev -> $fixed_in exited $rc (run error, result incomplete)" >&2 ;;
    esac
    echo
  done < "$CSV"
  echo "--all: $ran pair(s) run · $vulnerable_pairs VULNERABLE · $errored errored"
  [ "$ran" -gt 0 ] || { echo "ERROR: --all ran zero comparisons (no diffable rows in $CSV)" >&2; exit 3; }
  [ "$errored" -gt 0 ] && exit 3
  [ "$vulnerable_pairs" -gt 0 ] && exit 4
  exit 0
fi

PREV="${2:?prev version e.g. 7.0.2}"; FIXED="${3:?fixed version e.g. 7.0.3}"
UA="wp-release-audit (read-only verification)"
CACHE="${WP_SECFIX_CACHE:-$HOME/.wp-secfix-cache}"; mkdir -p "$CACHE"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 3; }   # run error: never a pass

resolve() { # version -> extracted wordpress/ dir in cache
  local v="$1" zip="$CACHE/wp-$1.zip" dir="$CACHE/x-$1"
  if [ ! -d "$dir/wordpress" ]; then
    if [ ! -s "$zip" ]; then
      for url in "https://wordpress.org/wordpress-$v.zip" "https://downloads.wordpress.org/release/wordpress-$v.zip"; do
        [ "$(curl -s -o "$zip" -w '%{http_code}' --max-time 300 -A "$UA" "$url")" = "200" ] && break
      done
    fi
    [ -s "$zip" ] || { say "ERROR: could not fetch WordPress $v" >&2; return 2; }
    mkdir -p "$dir"; unzip -qo "$zip" -d "$dir" || { say "ERROR: could not extract $zip" >&2; return 2; }
  fi
  printf '%s\n' "$dir/wordpress"
}

# Target -> a wordpress/ dir
TDIR="$TARGET"
if [ -f "$TARGET" ]; then
  ex="$CACHE/x-target"; rm -rf "$ex"; mkdir -p "$ex"; unzip -qo "$TARGET" -d "$ex" || { say "ERROR: could not extract $TARGET" >&2; exit 2; }
  TDIR="$ex/wordpress"
fi
[ -d "$TDIR" ] || { say "ERROR: target $TDIR not a directory"; exit 2; }

PDIR="$(resolve "$PREV")"   || exit 2
FDIR="$(resolve "$FIXED")"  || exit 2

say "Security-fix presence gate"
say "  fix set:  WordPress $PREV -> $FIXED  (diff-derived)"
say "  target:   $TDIR"
say ""

WORK="$(mktemp -d "${TMPDIR:-/tmp}/secfix.XXXXXX")" || { say "ERROR: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
export ADDF="$WORK/add" DELF="$WORK/del"

# Changed files, source only (skip minified/build artifacts and the version stamp).
# diff -rq exits 0 (same), 1 (differences) or >1 (trouble); only >1 is an error.
# Paths are cut with string operations, not awk fields, so trees whose path
# contains spaces parse correctly.
diff -rq "$PDIR" "$FDIR" > "$WORK/tree.diff" 2> "$WORK/tree.err"; rc=$?
[ "$rc" -le 1 ] || die "diff -rq $PDIR $FDIR exited $rc: $(head -3 "$WORK/tree.err")"
# Portable array fill (macOS ships bash 3.2 — no mapfile).
FILES=()
while IFS= read -r line; do
  case "$line" in "Files $PDIR/"*" differ") ;; *) continue ;; esac
  rel="${line#"Files $PDIR/"}"; rel="${rel%" and $FDIR/"*}"
  case "$rel" in *.min.js|wp-includes/version.php) continue ;; esac
  FILES+=("$rel")
done < "$WORK/tree.diff"
[ "${#FILES[@]}" -gt 0 ] || die "no changed source files between $PREV and $FIXED; zero comparisons possible"

total=0; patched=0; vulnerable=0; diverged=0; informational=0; missing=0
VULN_LIST=()

# Split a unified diff into fix lines (added) and pre-fix lines (removed), keeping
# only substantive lines: has a word character, trimmed, longer than 3 bytes.
split_diff() {
  LC_ALL=C awk '
    /^\+/ && !/^\+\+\+/ { s = substr($0, 2); out = ENVIRON["ADDF"] }
    /^-/  && !/^---/       { s = substr($0, 2); out = ENVIRON["DELF"] }
    out != "" {
      if (s ~ /[A-Za-z0-9_]/) {
        sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
        if (length(s) > 3) print s > out
      }
      out = ""
    }' "$1"
}

# Count how many lines of a pattern file occur as fixed substrings in a target
# file. awk index() instead of one grep -F per line: BSD grep runs out of memory
# on very long fixed patterns (minified CSS lines over 100 KB) and exits 2.
count_present() {
  LC_ALL=C awk '
    FNR == NR { pat[++n] = $0; next }
    { line[++m] = $0; whole[$0] = 1 }
    END {
      hits = 0
      for (i = 1; i <= n; i++) {
        p = pat[i]
        if (p in whole) { hits++; continue }
        for (j = 1; j <= m; j++) if (index(line[j], p)) { hits++; break }
      }
      print hits
    }' "$1" "$2"
}

for rel in "${FILES[@]}"; do
  [ -f "$TDIR/$rel" ] || { printf '  %-11s %s (absent from target tree)\n' "MISSING-FILE" "$rel"; missing=$((missing+1)); continue; }
  diff -u "$PDIR/$rel" "$FDIR/$rel" > "$WORK/file.diff" 2> "$WORK/file.err"; rc=$?
  [ "$rc" -le 1 ] || die "diff -u on $rel exited $rc: $(head -3 "$WORK/file.err")"
  # Added = fix lines; Removed = pre-fix lines.
  : > "$ADDF"; : > "$DELF"
  split_diff "$WORK/file.diff" || die "splitting the diff for $rel failed"
  n_add=$(wc -l < "$ADDF") || die "wc failed for $rel"; n_add=$((n_add+0))
  n_del=$(wc -l < "$DELF") || die "wc failed for $rel"; n_del=$((n_del+0))
  [ "$n_add" -eq 0 ] && [ "$n_del" -eq 0 ] && continue
  total=$((total+1))

  add_hits=0; if [ "$n_add" -gt 0 ]; then add_hits=$(count_present "$ADDF" "$TDIR/$rel") || die "matching fix lines in $rel failed"; fi
  del_hits=0; if [ "$n_del" -gt 0 ]; then del_hits=$(count_present "$DELF" "$TDIR/$rel") || die "matching pre-fix lines in $rel failed"; fi
  case "$add_hits$del_hits" in ''|*[!0-9]*) die "non-numeric match count for $rel" ;; esac
  add_ratio=0; [ "$n_add" -gt 0 ] && add_ratio=$(( add_hits * 100 / n_add ))
  del_ratio=0; [ "$n_del" -gt 0 ] && del_ratio=$(( del_hits * 100 / n_del ))

  # Classify. Fix present = most added lines found. Vulnerable = pre-fix lines
  # still present and the fix lines mostly absent.
  if [ "$add_ratio" -ge 80 ]; then
    printf '  %-11s %s\n' "PATCHED" "$rel"; patched=$((patched+1))
  elif [ "$n_del" -gt 0 ] && [ "$del_ratio" -ge 80 ] && [ "$add_ratio" -lt 80 ]; then
    # Every pre-fix line is still present and the fix lines are not fully in — the
    # old code path is intact. Strong vulnerable signal even if refactoring around
    # it moved some shared context lines (which inflate add_ratio).
    printf '  %-11s %s\n' "VULNERABLE" "$rel"; vulnerable=$((vulnerable+1)); VULN_LIST+=("$rel")
  elif [ "$n_add" -ge 1 ] && [ "$n_add" -le 2 ] && { grep -qiE 'security (issue|release)|version %s|release notes' "$ADDF"; rc=$?; [ "$rc" -le 1 ] || die "grep on fix lines of $rel exited $rc"; [ "$rc" -eq 0 ]; }; then
    printf '  %-11s %s\n' "INFO" "$rel"; informational=$((informational+1))  # changelog/about copy
  else
    printf '  %-11s %s  (add %d%% / prefix %d%% — read)\n' "DIVERGED" "$rel" "$add_ratio" "$del_ratio"; diverged=$((diverged+1))
  fi
done

say ""
say "  $total fix-bearing files · $patched patched · $vulnerable VULNERABLE · $diverged diverged · $informational informational · $missing missing-file"
[ "$total" -gt 0 ] || die "zero comparisons ran ($missing changed files absent from target $TDIR); nothing was checked"
if [ "$vulnerable" -gt 0 ]; then
  say ""
  say "  Target is MISSING fixes that shipped in $FIXED:"
  for v in "${VULN_LIST[@]}"; do say "    - $v"; done
  say "  If $FIXED is public, these are known, patched-elsewhere vulnerabilities live in the target."
  say "  Confirm they are closed in the next build before shipping — do not assume merge-forward."
  exit 4
fi
if [ "$diverged" -gt 0 ] || [ "$missing" -gt 0 ]; then
  say "  No VULNERABLE files, but $diverged DIVERGED and $missing MISSING-FILE need a human read."
else
  say "  All derived fixes present in target."
fi
exit 0
