#!/usr/bin/env bash
set -u

SC="${STUDIO_CLI:-/Applications/Studio.app/Contents/Resources/bin/studio-cli.sh}"
OLD="$HOME/Studio/codex-wp71-beta3-core-upgrader"
NEW="$HOME/Studio/codex-wp71-beta4-qa"
PROBE="$(cd "$(dirname "$0")" && pwd)/probe.php"
SAVE_PROBE="$(cd "$(dirname "$0")" && pwd)/save-probe.php"

echo "== X-PERS-03r direct-parser gate =="
old_version=$("$SC" wp core version --path="$OLD")
new_version=$("$SC" wp core version --path="$NEW")
echo "old_version=$old_version new_version=$new_version"
if [[ "$old_version" != "7.0.2" || "$new_version" != "7.1-beta4" ]]; then
  echo "BATCH_VERDICT=BLOCKED reason=build-identity-mismatch"
  exit 3
fi

echo "BUILD=7.0.2"
"$SC" wp eval-file "$PROBE" --path="$OLD"
echo "BUILD=7.1-beta4"
"$SC" wp eval-file "$PROBE" --path="$NEW"
echo "SAVE_PATH_BUILD=7.0.2"
"$SC" wp eval-file "$SAVE_PROBE" --path="$OLD"
echo "SAVE_PATH_BUILD=7.1-beta4"
"$SC" wp eval-file "$SAVE_PROBE" --path="$NEW"
echo "cleanup_verified=yes parser-gate-read-only;save-probe-cleaned"

