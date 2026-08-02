#!/usr/bin/env bash
# C-02 — upgrade path x file-removal ledger x clean-tree integrity. See README.md.
set -u

SC="${STUDIO_CLI:-/Applications/Studio.app/Contents/Resources/bin/studio-cli.sh}"
AUDIT_ROOT="${AUDIT_ROOT:-$WP_AUDIT_ROOT}"
VERSIONS="$HOME/.studio/server-files/wordpress-versions"
STUDIO="$HOME/Studio"
CLEAN="$STUDIO/codex-wp71-beta4-qa"

core_files() {
  (
    cd "$1" || exit 2
    find wp-admin wp-includes -type f -print
    find . -maxdepth 1 -type f -name '*.php' -print
  ) | LC_ALL=C sort
}

compare_tree() {
  local label="$1"
  local candidate="$2"
  local candidate_version
  local clean_version
  candidate_version=$(sed -n "s/^\$wp_version = '\([^']*\)';/\1/p" "$candidate/wp-includes/version.php")
  clean_version=$(sed -n "s/^\$wp_version = '\([^']*\)';/\1/p" "$CLEAN/wp-includes/version.php")
  echo "CELL=$label"
  echo "candidate_version=$candidate_version clean_version=$clean_version"
  if [[ "$candidate_version" != "7.1-beta4" || "$clean_version" != "7.1-beta4" ]]; then
    echo "VERDICT=BLOCKED reason=build-identity-mismatch"
    return
  fi
  local extras
  local missing
  extras=$(comm -23 <(core_files "$candidate") <(core_files "$CLEAN") | wc -l | tr -d ' ')
  missing=$(comm -13 <(core_files "$candidate") <(core_files "$CLEAN") | wc -l | tr -d ' ')
  echo "extra_core_files=$extras missing_core_files=$missing"
  comm -23 <(core_files "$candidate") <(core_files "$CLEAN") | sed -n '1,10p'
  if [[ "$extras" -eq 0 && "$missing" -eq 0 ]]; then
    echo "VERDICT=REFUTED no-file-set-divergence"
  else
    echo "VERDICT=CONFIRMED file-set-divergence"
  fi
}

echo "== C-02 preflight =="
"$SC" wp core version --path="$CLEAN"

echo "== detector positive control: 7.0.2 -> beta4 =="
python3 "$AUDIT_ROOT/scripts/stale_file_check.py" \
  "$VERSIONS/7.0.2" "$VERSIONS/7.1-beta4"
positive_exit=$?
echo "detector_exit=$positive_exit expected=1"

echo "== detector negative control: beta4 -> beta4 =="
python3 "$AUDIT_ROOT/scripts/stale_file_check.py" \
  "$VERSIONS/7.1-beta4" "$VERSIONS/7.1-beta4"
negative_exit=$?
echo "detector_exit=$negative_exit expected=0"

if [[ "$positive_exit" -ne 1 || "$negative_exit" -ne 0 ]]; then
  echo "BATCH_VERDICT=INVALID reason=control-miscalibration"
  exit 4
fi

compare_tree "prior-stable-core" "$STUDIO/codex-wp702-core-upgrader"
compare_tree "prior-stable-wp-cli" "$STUDIO/codex-wp702-upgrade"
compare_tree "prior-beta-core" "$STUDIO/codex-wp71-beta3-core-upgrader"

echo "CELL=prior-beta-wp-cli"
echo "VERDICT=BLOCKED reason=no-verified-prior-beta-wp-cli-fixture"
echo "cleanup_verified=yes read-only-batch"

