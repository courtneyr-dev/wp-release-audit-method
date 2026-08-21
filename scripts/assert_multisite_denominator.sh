#!/usr/bin/env bash
# Multisite denominator asserter (D-04): print total / eligible / held-back and
# per-site db_version BEFORE reading any "upgraded on N/N sites" output.
#
# A network upgrade once reported "2 of 2 sites upgraded" on a five-site network
# — three sites were archived or spam, got skipped, and sat on the old database
# version, quietly broken (FM-03; FM-15). You cannot read an N/N line correctly
# without first printing what N should have been.
#
# Usage — from the site directory (how examples/chains/C-03 calls it), or with a
# path:
#   scripts/assert_multisite_denominator.sh [site-path]
#   WP_AUDIT_WP="/Applications/Studio.app/Contents/Resources/bin/studio-cli.sh wp" \
#     scripts/assert_multisite_denominator.sh ~/Studio/my-multisite
#
# Options:
#   --expect-uniform   exit 5 if any ELIGIBLE site's db_version differs from the
#                      network's — the post-upgrade assertion. Held-back sites at
#                      an old db_version are reported but never fail the check;
#                      they are the finding this tool exists to surface, and on
#                      a network whose target shipped no schema change, "held
#                      back" and "current" can legitimately match.
#
# Exit codes:
#   0  inventory printed; denominator known
#   2  setup error (not a WordPress install, wp unavailable)
#   3  not multisite
#   5  --expect-uniform and an eligible site is not at the network db_version
#
# Calibration status: counting, flag handling, uniformity, and the not-multisite
# path are proven against a stubbed five-site inventory (the FM-03 shape), AND
# against a live DDEV five-site network on WordPress 7.1 (2026-08-21): 5 total,
# 3 eligible, 2 held back, per-site db_version read correctly. The live run is
# the one that mattered — it caught a stdin-swallowing bug the stub structurally
# could not (see the </dev/null comment below).
set -uo pipefail

EXPECT_UNIFORM=0
SITE="."
for a in "$@"; do
  case "$a" in
    --expect-uniform) EXPECT_UNIFORM=1 ;;
    *) SITE="$a" ;;
  esac
done

# WP_AUDIT_WP lets a wrapper CLI (Studio, ddev exec, lando) stand in for wp.
read -r -a WP <<< "${WP_AUDIT_WP:-wp}"

run_wp() { "${WP[@]}" --path="$SITE" "$@"; }

if ! run_wp core is-installed >/dev/null 2>&1; then
  echo "ERROR: no WordPress install at $SITE (or wp not runnable)"; exit 2
fi
if ! run_wp core is-installed --network >/dev/null 2>&1; then
  echo "NOT-MULTISITE: $SITE is a single site; there is no denominator to assert"; exit 3
fi

# The codebase's own $wp_db_version is the target every eligible site should
# reach — read it from the tree, not from an option a broken upgrade may not
# have written.
NETWORK_DB=$(run_wp eval 'require ABSPATH . "wp-includes/version.php"; echo $wp_db_version;' 2>/dev/null || true)
LIST=$(run_wp site list --fields=blog_id,url,archived,spam,deleted --format=csv 2>/dev/null) || {
  echo "ERROR: wp site list failed"; exit 2; }

total=0; eligible=0; held=0; nonuniform=0
echo "== multisite denominator — $SITE"
[ -n "$NETWORK_DB" ] && echo "codebase db_version target: $NETWORK_DB"
printf '%-8s %-6s %-6s %-6s %-10s %s\n' "blog_id" "arch" "spam" "del" "db_version" "url"

while IFS=, read -r blog_id url archived spam deleted; do
  [ "$blog_id" = "blog_id" ] && continue
  [ -z "$blog_id" ] && continue
  total=$((total+1))
  # </dev/null matters: wp reads stdin, and without it the first per-site call
  # swallows the rest of the site list — the live five-site control counted 1
  # of 5 until this line. The stubbed control never caught it because the stub
  # didn't read stdin. Runtime proof beats a passing stub.
  dbv=$(run_wp option get db_version --url="$url" </dev/null 2>/dev/null || echo "unreadable")
  if [ "$archived" = "1" ] || [ "$spam" = "1" ] || [ "$deleted" = "1" ]; then
    held=$((held+1)); flag="held-back"
  else
    eligible=$((eligible+1)); flag=""
    if [ -n "$NETWORK_DB" ] && [ "$dbv" != "$NETWORK_DB" ]; then
      nonuniform=$((nonuniform+1)); flag="ELIGIBLE-BEHIND"
    fi
  fi
  printf '%-8s %-6s %-6s %-6s %-10s %s %s\n' "$blog_id" "$archived" "$spam" "$deleted" "$dbv" "$url" "$flag"
done <<< "$LIST"

echo
echo "total=$total eligible=$eligible held_back=$held"
echo "Read any 'upgraded on N/N sites' line against eligible=$eligible, never against total=$total."
if [ "$held" -gt 0 ]; then
  echo "NOTE: $held held-back site(s) will be skipped by the network upgrade BY DESIGN."
  echo "      Their db_version stays behind; that is a reporting hazard, not a defect."
fi

if [ "$EXPECT_UNIFORM" = "1" ] && [ "$nonuniform" -gt 0 ]; then
  echo "*** FAIL — $nonuniform eligible site(s) not at the network db_version"
  exit 5
fi
exit 0
