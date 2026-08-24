#!/usr/bin/env bash
# Core preflight probe — boot a TARGET WordPress build against a fixture's live database
# and live wp-content, and report fatals, without touching the fixture's core files.
#
# Adapted from Austin Ginder's `update-core` remote script in CaptainCore (MIT,
# https://github.com/CaptainCore/captaincore/blob/master/lib/remote-scripts/update-core).
# The method write-up, with the invariants and the limits, is method/preflight-core-probe.md.
#
# Three deliberate differences from the original, all in the direction of "this repo tests,
# it does not operate fleets":
#
#   1. NO APPLY PATH. The original probes and then updates live core. This only ever probes.
#      There is no flag that makes it write to the fixture's core, so the backup/restore
#      machinery the original needs does not exist here and cannot misfire.
#   2. Environment-agnostic. The original uses its hosts' on-server loopback
#      (curl -H "Host: <site>" https://localhost/), which is a Kinsta and Rocket.net
#      behavior. This drives WordPress through $WP_AUDIT_WP, so it runs on ddev, lando,
#      wp-env, or a plain local install — the same seam every other script here uses.
#   3. Disposable fixtures only. The original is built to be safe against production. This
#      is not a substitute for it; if you want the production-grade version, run the
#      original.
#
# Usage:
#   scripts/core-preflight-probe.sh --target=7.1
#   WP_AUDIT_WP="ddev wp" scripts/core-preflight-probe.sh --target=7.1 --path=/path/to/fixture
#
#   --target=<version>   core build to sideload and boot. Required.
#   --path=<dir>         fixture root as seen from HERE (default: current directory).
#                        Must be writable from here; the sideloaded tree is written into it.
#   --control=positive   the probe MUST report a fatal (exit 4 if it comes back clean)
#   --control=negative   the probe MUST come back clean (exit 4 if it reports a fatal)
#   --keep               leave the sideloaded tree in place for inspection
#
# Exit codes:
#   0  probe clean — the target booted against this fixture's plugins with no fatal
#   3  probe found a fatal. This is a RESULT, not an error
#   4  control miscalibrated — the run is invalid, do not report its verdict
#   1  error (bad arguments, download failed, fixture not a WordPress root)
#
# What a clean probe does NOT prove, restated here because the exit code is easy to
# over-read: it boots the front end only, `db_version` unchanged means core migration did
# not run rather than "nothing wrote to the database", and a plugin that only fatals in
# wp-admin, on POST, or on cron passes this. See the method page's limits section.

set -uo pipefail

WP="${WP_AUDIT_WP:-wp}"
TARGET=""
FIXTURE="$(pwd)"
CONTROL=""
KEEP=""
PREVIEW_NAME=".preflight-core-preview"

for arg in "$@"; do
  case "$arg" in
    --target=*)  TARGET="${arg#*=}" ;;
    --path=*)    FIXTURE="${arg#*=}" ;;
    --control=*) CONTROL="${arg#*=}" ;;
    --keep)      KEEP=1 ;;
    *) echo "core-preflight-probe: unknown argument '$arg'" >&2; exit 1 ;;
  esac
done

[ -n "$TARGET" ] || { echo "core-preflight-probe: --target=<version> is required" >&2; exit 1; }
case "${CONTROL:-none}" in none|positive|negative) ;; *)
  echo "core-preflight-probe: --control must be positive or negative" >&2; exit 1 ;;
esac

FIXTURE="${FIXTURE%/}"
PREVIEW_HOST="${FIXTURE}/${PREVIEW_NAME}"

for f in wp-config.php wp-includes wp-admin wp-content; do
  [ -e "${FIXTURE}/${f}" ] || {
    echo "core-preflight-probe: ${FIXTURE} is not a WordPress root (no ${f})" >&2; exit 1; }
done

run_wp() { $WP "$@" 2>&1; }

# Only ever removes the preview tree this script creates, by exact name, never a symlink.
cleanup_preview() {
  [ -n "$KEEP" ] && return 0
  local p="$PREVIEW_HOST"
  case "$p" in
    */"$PREVIEW_NAME") ;;
    *) echo "core-preflight-probe: refusing to remove unexpected path: $p" >&2; return 1 ;;
  esac
  [ -L "$p" ] && { echo "core-preflight-probe: preview path is a symlink, not removing" >&2; return 1; }
  [ -d "$p" ] && rm -rf -- "$p"
  return 0
}
trap cleanup_preview EXIT

echo "== fixture state before the probe"
LIVE_VERSION="$(run_wp core version --skip-plugins --skip-themes | tr -d '\r')"
DB_BEFORE="$(run_wp option get db_version --skip-plugins --skip-themes | tr -d '\r')"
ABSPATH="$(run_wp eval 'echo untrailingslashit( ABSPATH );' --skip-plugins --skip-themes | tr -d '\r')"
ACTIVE="$(run_wp plugin list --status=active --field=name --skip-plugins --skip-themes | tr -d '\r' | paste -sd, -)"
echo "live_version=${LIVE_VERSION}"
echo "db_version=${DB_BEFORE}"
echo "abspath=${ABSPATH}"
echo "active_plugins=${ACTIVE:-<none>}"
echo "target=${TARGET}"

# Paths as WordPress sees them, which is not the same as paths as we see them when the
# fixture runs in a container. Everything written into PHP below uses these.
PREVIEW_WP="${ABSPATH}/${PREVIEW_NAME}"
CONTENT_WP="${ABSPATH}/wp-content"

echo
echo "== sideload ${TARGET}"
cleanup_preview || exit 1
# Deliberately NOT `wp core download`. On at least one common setup (wp-cli 2.12 inside a
# ddev/colima container) its extractor silently truncates long filenames — 25 files under
# wp-includes/php-ai-client/ arrive with their names cut and their .php extension gone. The
# release zip is fine; `unzip` on the same machine extracts it correctly; only wp-cli's
# extractor does it. A probe that boots a quietly damaged target tree produces verdicts about
# a build that does not exist, so this fetches and extracts the package itself and then makes
# the tree prove itself against the checksum API before anything boots.
ZIP="${PREVIEW_HOST}.zip"
UNPACK="${PREVIEW_HOST}.unpack"
rm -rf -- "$UNPACK" "$ZIP"
if ! curl -sSfL --max-time 300 -o "$ZIP" "https://downloads.wordpress.org/release/wordpress-${TARGET}.zip"; then
  echo "core-preflight-probe: failed to download wordpress-${TARGET}.zip" >&2
  exit 1
fi
if ! unzip -q "$ZIP" -d "$UNPACK"; then
  echo "core-preflight-probe: failed to extract wordpress-${TARGET}.zip" >&2
  rm -rf -- "$UNPACK" "$ZIP"; exit 1
fi
rm -f -- "$ZIP"
mv "${UNPACK}/wordpress" "$PREVIEW_HOST" || {
  echo "core-preflight-probe: unexpected zip layout" >&2; rm -rf -- "$UNPACK"; exit 1; }
rm -rf -- "$UNPACK"
# --skip-content equivalent: the preview borrows the fixture's wp-content, so its own is noise
rm -rf -- "${PREVIEW_HOST}/wp-content"
[ -f "${PREVIEW_HOST}/wp-includes/version.php" ] || {
  echo "core-preflight-probe: sideloaded tree is incomplete" >&2; exit 1; }

# Gate: a damaged sideload is an ERROR, never a probe verdict. Without this the truncation
# bug above turns into "the target fatals on this site," which is a lie about the release.
echo "-- verifying the sideloaded tree against the checksum API"
VERIFY_OUT="$(run_wp core verify-checksums --version="$TARGET" --path="$PREVIEW_NAME")"
VERIFY_RC=$?
printf '%s\n' "$VERIFY_OUT" | grep -vE "^Warning: File should not exist: (wp-config|\.)" | tail -3
if [ $VERIFY_RC -ne 0 ]; then
  echo "core-preflight-probe: the sideloaded ${TARGET} tree does not verify against its" >&2
  echo "  checksums — refusing to probe a damaged build. This is an error, not a result." >&2
  exit 1
fi

TARGET_VERSION="$(sed -n "s/^\$wp_version = '\(.*\)';/\1/p" "${PREVIEW_HOST}/wp-includes/version.php")"
TARGET_DB="$(sed -n "s/^\$wp_db_version = \(.*\);/\1/p" "${PREVIEW_HOST}/wp-includes/version.php")"
echo "preview_version=${TARGET_VERSION}"
echo "preview_db_version=${TARGET_DB}"

# The preview borrows everything but the core files: same wp-config (so same database),
# same wp-content (so the same plugins and theme), new wp-settings.
python3 - "$FIXTURE" "$PREVIEW_HOST" "$CONTENT_WP" <<'PY'
import re, sys
fixture, preview, content_dir = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(f"{fixture}/wp-config.php", encoding="utf-8", errors="surrogateescape").read()
# Defer wp-settings so our wrapper can define constants first, and make sure a page cache
# cannot serve the OLD core's HTML and be read as the new core booting cleanly.
src = re.sub(r"require(?:_once)?\s+ABSPATH\s*\.\s*['\"]wp-settings\.php['\"]\s*;",
             "/* wp-settings deferred by core-preflight-probe */", src, count=1)
src = re.sub(r"^[ \t]*define\(\s*['\"]WP_CACHE['\"].+$",
             "/* WP_CACHE stripped by core-preflight-probe */", src, flags=re.M)
open(f"{preview}/wp-config.php.live.php", "w", encoding="utf-8", errors="surrogateescape").write(src)
open(f"{preview}/wp-config.php", "w", encoding="utf-8").write(
    "<?php\n"
    f"define( 'WP_CONTENT_DIR', {content_dir!r} );\n"
    "define( 'WP_CACHE', false );\n"
    "define( 'DONOTCACHEPAGE', true );\n"
    "define( 'CORE_PREVIEW', true );\n"
    "require __DIR__ . '/wp-config.php.live.php';\n"
    "require ABSPATH . 'wp-settings.php';\n")
PY
[ -f "${PREVIEW_HOST}/wp-config.php" ] || {
  echo "core-preflight-probe: failed to write the preview wp-config" >&2; exit 1; }

cat > "${PREVIEW_HOST}/probe-render.php" <<'PHP'
<?php
$path = $args[0] ?? '/';
register_shutdown_function( function () {
	$e = error_get_last();
	if ( $e && in_array( $e['type'], array( E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR, E_USER_ERROR, E_RECOVERABLE_ERROR ), true ) ) {
		fwrite( STDERR, "FATAL: {$e['message']} in {$e['file']}:{$e['line']}\n" );
	}
} );
$host = wp_parse_url( home_url(), PHP_URL_HOST );
$_SERVER['REQUEST_METHOD']  = 'GET';
$_SERVER['HTTP_HOST']       = $host;
$_SERVER['SERVER_NAME']     = $host;
$_SERVER['REQUEST_URI']     = $path;
$_SERVER['QUERY_STRING']    = '';
$_SERVER['SERVER_PROTOCOL'] = 'HTTP/1.1';
$_GET  = array();
$_POST = array();
remove_action( 'template_redirect', 'redirect_canonical' );
add_filter( 'redirect_canonical', '__return_false', 99 );
if ( ! defined( 'WP_USE_THEMES' ) ) {
	define( 'WP_USE_THEMES', true );
}
global $wp;
ob_start();
try {
	$wp->main( '' );
	require ABSPATH . WPINC . '/template-loader.php';
} catch ( Throwable $t ) {
	ob_end_clean();
	fwrite( STDERR, 'THROW: ' . $t->getMessage() . ' in ' . $t->getFile() . ':' . $t->getLine() . "\n" );
	exit( 2 );
}
$html  = ob_get_clean();
$fatal = preg_match( '/(Fatal error|Parse error|Uncaught )/i', $html ) ? 1 : 0;
printf(
	"path=%s bytes=%d is_404=%s fatal_in_html=%d wp_version=%s\n",
	$path, strlen( $html ), is_404() ? '1' : '0', $fatal, $GLOBALS['wp_version']
);
if ( $fatal ) {
	exit( 2 );
}
PHP

PROBE_FATAL=0
PROBE_REASON=""

echo
echo "== boot ${TARGET_VERSION} with this fixture's plugins and theme (CLI)"
BOOT_OUT="$(run_wp --path="$PREVIEW_NAME" eval 'echo "booted=" . $GLOBALS["wp_version"] . " theme=" . get_template() . " plugins=" . count( (array) get_option( "active_plugins" ) ) . "\n";')"
BOOT_RC=$?
echo "$BOOT_OUT" | tail -5
if [ $BOOT_RC -ne 0 ] || ! printf '%s' "$BOOT_OUT" | grep -q '^booted='; then
  PROBE_FATAL=1
  PROBE_REASON="target core failed to boot with this fixture's plugins/themes"
fi

# The booted version must be the target. A preview that quietly loaded the OLD core would
# otherwise pass everything below and mean nothing.
BOOTED_VERSION="$(printf '%s' "$BOOT_OUT" | sed -n 's/^booted=\([^ ]*\).*/\1/p')"
if [ $PROBE_FATAL -eq 0 ] && [ "$BOOTED_VERSION" != "$TARGET_VERSION" ]; then
  PROBE_FATAL=1
  PROBE_REASON="booted ${BOOTED_VERSION}, expected ${TARGET_VERSION}"
fi

if [ $PROBE_FATAL -eq 0 ]; then
  echo
  echo "== render / on ${TARGET_VERSION}"
  RENDER_OUT="$(run_wp --path="$PREVIEW_NAME" eval-file "${PREVIEW_WP}/probe-render.php" /)"
  RENDER_RC=$?
  echo "$RENDER_OUT" | tail -5
  if [ $RENDER_RC -ne 0 ] || printf '%s' "$RENDER_OUT" | grep -qiE 'FATAL:|THROW:|fatal_in_html=1'; then
    PROBE_FATAL=1
    PROBE_REASON="target core fatals rendering /"
  fi
fi

echo
echo "== invariant: the probe changed nothing"
DB_AFTER="$(run_wp option get db_version --skip-plugins --skip-themes | tr -d '\r')"
echo "db_version_before=${DB_BEFORE} db_version_after=${DB_AFTER}"
if [ "$DB_BEFORE" != "$DB_AFTER" ]; then
  echo "core-preflight-probe: PROBE MUTATED db_version — invalid run" >&2
  exit 4
fi
LIVE_AFTER="$(run_wp core version --skip-plugins --skip-themes | tr -d '\r')"
echo "live_version_before=${LIVE_VERSION} live_version_after=${LIVE_AFTER}"
if [ "$LIVE_VERSION" != "$LIVE_AFTER" ]; then
  echo "core-preflight-probe: LIVE CORE VERSION CHANGED — invalid run" >&2
  exit 4
fi

echo
if [ $PROBE_FATAL -eq 1 ]; then
  echo "probe=FATAL reason=${PROBE_REASON}"
else
  echo "probe=clean target=${TARGET_VERSION}"
fi

case "$CONTROL" in
  positive)
    if [ $PROBE_FATAL -eq 1 ]; then
      echo "CONTROL-PASS positive: the probe caught the seeded fatal"; exit 0
    fi
    echo "CONTROL-FAIL positive: probe came back clean on a fixture seeded to fatal" >&2
    exit 4 ;;
  negative)
    if [ $PROBE_FATAL -eq 0 ]; then
      echo "CONTROL-PASS negative: the probe cleared a fixture with no seeded fatal"; exit 0
    fi
    echo "CONTROL-FAIL negative: probe reported a fatal on a fixture expected to be clean" >&2
    echo "  reason was: ${PROBE_REASON}" >&2
    exit 4 ;;
esac

[ $PROBE_FATAL -eq 1 ] && exit 3
exit 0
