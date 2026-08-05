#!/usr/bin/env bash
# Build-identity gate: prove the build you are about to test actually exists,
# before any runtime cell runs. "Tested RC1" when you tested beta4 is a claim
# nobody can reproduce — this is the check that prevents it.
#
# Usage: rc_build_identity.sh <version> [label]
#   rc_build_identity.sh 7.1 RC1      # pre-release
#   rc_build_identity.sh 7.1          # final
#
# Exit codes:
#   0  RELEASED — package exists; sha256 printed for pinning
#   3  WAITING  — package not published; do NOT substitute beta/trunk/nightly
#   2  ERROR    — network/usage; retry, don't record a verdict
#
# Package URL lanes differ by release type, and getting this wrong reads as
# WAITING when the build is actually live:
#   stable:      https://downloads.wordpress.org/release/wordpress-X.Y.Z.zip
#   beta/RC:     https://wordpress.org/wordpress-X.Y-RCn.zip   (root, not /release/)
# We check both lanes and report whichever answers.
set -uo pipefail

V="${1:?usage: rc_build_identity.sh <version> [label]}"
L="${2:-}"
UA="wp-release-audit (read-only verification)"
PKG="wordpress-${V}${L:+-$L}.zip"

CANDIDATES=(
  "https://wordpress.org/${PKG}"
  "https://downloads.wordpress.org/release/${PKG}"
)

echo "Build-identity gate: ${V}${L:+ $L}"
FOUND=""
for url in "${CANDIDATES[@]}"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 -A "$UA" -I "$url" || echo "000")
  printf '  %-70s %s\n' "$url" "$code"
  case "$code" in
    200) FOUND="$url"; break ;;
    000) echo "  network error — retry; this is not WAITING"; exit 2 ;;
  esac
done

if [ -z "$FOUND" ]; then
  echo "WAITING — ${PKG} is not published on either lane."
  echo "Do not substitute a beta, trunk, nightly, or a prior RC."
  echo "Mark every runtime cell WAITING and say so in the report."
  exit 3
fi

# Pin identity: sha256 plus the version constants inside the package itself.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! curl -sL --max-time 300 -A "$UA" -o "$TMP/wp.zip" "$FOUND"; then
  echo "download failed — retry; this is not WAITING"; exit 2
fi

SHA=$(shasum -a 256 "$TMP/wp.zip" | awk '{print $1}')
echo "RELEASED  $FOUND"
echo "  sha256: $SHA"
unzip -p "$TMP/wp.zip" wordpress/wp-includes/version.php 2>/dev/null \
  | grep -E '^\$(wp_version|wp_db_version) ' | sed 's/^/  /'
echo "Pin the sha256 in your run log. If a local zip is being tested instead,"
echo "its sha256 must MATCH the line above before any cell counts."
exit 0
