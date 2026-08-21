#!/usr/bin/env bash
# C-03 — multisite status flags x network upgrade x first load. See README.md.
set -u

SC="${STUDIO_CLI:-/Applications/Studio.app/Contents/Resources/bin/studio-cli.sh}"
# Detector scripts ship in this repo; a private run root can still override.
AUDIT_ROOT="${AUDIT_ROOT:-${WP_AUDIT_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}}"
SITE="$HOME/Studio/codex-wp71-beta4-multisite"
ARCHIVED_URL="http://codex-archived.localhost:8885/"
restored=0

cleanup() {
  if [[ "$restored" -eq 1 ]]; then
    "$SC" wp eval 'update_blog_status( 3, "archived", 1 );' --path="$SITE" >/dev/null
  fi
}
trap cleanup EXIT

echo "== C-03 denominator control =="
(
  cd "$SITE" || exit 2
  "$AUDIT_ROOT/scripts/assert_multisite_denominator.sh"
)
control_exit=$?
if [[ "$control_exit" -ne 0 ]]; then
  echo "BATCH_VERDICT=INVALID reason=denominator-control-failed"
  exit 4
fi

before=$("$SC" wp option get db_version --url="$ARCHIVED_URL" --path="$SITE")
echo "CELL=archived-first-load before_db_version=$before"

"$SC" wp eval 'update_blog_status( 3, "archived", 0 );' --path="$SITE" >/dev/null
restored=1
curl --silent --show-error --max-time 15 --output /dev/null \
  --write-out 'http_status=%{http_code}\n' "$ARCHIVED_URL"
after=$("$SC" wp option get db_version --url="$ARCHIVED_URL" --path="$SITE")
echo "after_db_version=$after"

"$SC" wp eval 'update_blog_status( 3, "archived", 1 );' --path="$SITE" >/dev/null
restored=0
flag=$("$SC" wp eval 'echo (int) get_site( 3 )->archived;' --path="$SITE")
echo "cleanup_archived_flag=$flag"

if [[ "$flag" != "1" ]]; then
  echo "BATCH_VERDICT=INVALID reason=cleanup-failed"
  exit 4
fi

echo "VERDICT=INCONCLUSIVE reason=no-schema-dependent-feature-named"
echo "cleanup_verified=yes"
