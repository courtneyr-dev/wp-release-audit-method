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
# HTTP DECIDES; the CLI boot is a second opinion (2026-09-01).
# WP-CLI requires wp-settings.php from inside WP_CLI\Runner->load_wordpress(), and PHP executes
# an included file in the INCLUDING scope — so a plugin's file-scope `$Var = new Thing()` becomes
# a local of that method instead of a global, and code reading it back with `global $Var` gets
# null. That fatals under WP-CLI on a site HTTP serves perfectly. It is what made
# `eps-301-redirects` look like a real 7.1 fatal in core's own plugin-compatibility workflow
# until someone installed the plugin by hand and found the site healthy.
#
# So the HTTP probe is authoritative and a CLI-only fatal downgrades to a NOTE. Exit 3 means the
# target broke an actual request. If no home URL exists, no HTTP probe runs and a CLI fatal is
# reported as a fatal, with that stated in the output.
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

# Two callers, deliberately different. State reads must not absorb WP-CLI's stderr —
# a deprecation notice landing inside $LIVE_VERSION turns a comparison into nonsense, which
# is the "false fails from WP-CLI noise" class Ginder fixed upstream in 6d8feb90. Probe runs
# DO want stderr, because that is where probe-render.php writes FATAL:/THROW:.
run_wp()  { $WP "$@" 2>&1; }
wp_value() { $WP "$@" 2>/dev/null | tr -d '\r' | awk 'NF { line=$0 } END { printf "%s", line }'; }

# Tightened 2026-09-01 from upstream. The old pattern was /(Fatal error|Parse error|Uncaught )/i,
# which matches any page that merely mentions those words — a post about debugging, a plugin's
# own error-log viewer. This requires the real shape.
PHP_FATAL_GREP='(<b>)?(Fatal error|Parse error)(</b>)?:|Uncaught (Error|TypeError|Exception|ErrorException|ArgumentCountError|ValueError|InvalidArgumentException|RuntimeException|DivisionByZeroError|AssertionError|PDOException)\b'

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
BOOT_FILE=""
cleanup_all() { cleanup_preview; cleanup_boot_file 2>/dev/null || true; }
trap cleanup_all EXIT

echo "== fixture state before the probe"
LIVE_VERSION="$(wp_value core version --skip-plugins --skip-themes)"
DB_BEFORE="$(wp_value option get db_version --skip-plugins --skip-themes)"
ABSPATH="$(wp_value eval 'echo untrailingslashit( ABSPATH );' --skip-plugins --skip-themes)"
ACTIVE="$(run_wp plugin list --status=active --field=name --skip-plugins --skip-themes | tr -d '\r' | paste -sd, -)"
SITE_URL="$(wp_value option get home --skip-plugins --skip-themes)"
echo "live_version=${LIVE_VERSION}"
echo "db_version=${DB_BEFORE}"
echo "abspath=${ABSPATH}"
echo "active_plugins=${ACTIVE:-<none>}"
echo "site_url=${SITE_URL:-<none>}"
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
src = re.sub(
    r"require(?:_once)?\s*\(?\s*(?:ABSPATH\s*\.\s*['\"]wp-settings\.php['\"]"
    r"|dirname\s*\(\s*__FILE__\s*\)\s*\.\s*['\"]/wp-settings\.php['\"]"
    r"|__DIR__\s*\.\s*['\"]/wp-settings\.php['\"])\s*\)?\s*;",
    "/* wp-settings deferred by core-preflight-probe */", src)
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
// WP's shutdown flushes leftover buffers and dumps the page after a caught throwable,
// burying THROW: under HTML in the excerpt the caller greps.
remove_action( 'shutdown', 'wp_ob_end_flush_all', 1 );
if ( ! defined( 'WP_USE_THEMES' ) ) {
	define( 'WP_USE_THEMES', true );
}
global $wp;
ob_start();
try {
	$wp->main( '' );
	require ABSPATH . WPINC . '/template-loader.php';
} catch ( Throwable $t ) {
	while ( ob_get_level() > 0 ) { ob_end_clean(); }
	fwrite( STDERR, 'THROW: ' . $t->getMessage() . ' in ' . $t->getFile() . ':' . $t->getLine() . "\n" );
	exit( 2 );
}
$html = ob_get_clean();
while ( ob_get_level() > 0 ) { ob_end_clean(); }
$fatal = preg_match(
	'/(?:<b>)?(?:Fatal error|Parse error)(?:<\/b>)?:|Uncaught (?:Error|TypeError|Exception|ErrorException|ArgumentCountError|ValueError|InvalidArgumentException|RuntimeException|DivisionByZeroError|AssertionError|PDOException)\b/',
	$html
) ? 1 : 0;
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

# ── HTTP probe ────────────────────────────────────────────────────────────────
# The reason this exists, and why a CLI-only fatal is no longer a verdict:
# WP-CLI requires wp-settings.php from inside WP_CLI\Runner->load_wordpress(), and PHP runs an
# included file in the INCLUDING scope. A plugin's file-scope `$Var = new Thing()` is therefore
# a local of that method, not a global, and code reading it back with `global $Var` gets null.
# That fatals under WP-CLI on a site HTTP serves perfectly. It is exactly what made
# eps-301-redirects look like a real 7.1 fatal in core's own workflow until someone installed
# it by hand. So: HTTP decides. CLI is a second opinion.
HTTP_STATUS=""
HTTP_FATAL=""
HTTP_BOOT_VERSION=""

cleanup_boot_file() {
  [ -n "$BOOT_FILE" ] || return 0
  case "$BOOT_FILE" in
    core-preview-boot-*.php) ;;
    *) echo "core-preflight-probe: refusing to remove unexpected boot file: $BOOT_FILE" >&2; return 1 ;;
  esac
  local p="${FIXTURE}/${BOOT_FILE}"
  [ -L "$p" ] && return 1
  # marker check, so we never delete a file we did not write
  [ -f "$p" ] && grep -q 'X-Core-Preview-Boot' "$p" && rm -f -- "$p"
  return 0
}

if [ -z "$SITE_URL" ]; then
  echo
  echo "== HTTP probe: SKIPPED (no home URL)"
else
  echo
  echo "== HTTP probe: serve / from ${TARGET_VERSION} through the real web stack"
  TOKEN="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  BOOT_FILE="core-preview-boot-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n').php"
  cat > "${FIXTURE}/${BOOT_FILE}" <<PHP
<?php
\$expected = '${TOKEN}';
\$given    = isset( \$_SERVER['HTTP_X_CORE_PREVIEW'] ) ? \$_SERVER['HTTP_X_CORE_PREVIEW'] : '';
if ( ! is_string( \$given ) || \$given === '' || ! hash_equals( \$expected, \$given ) ) {
	header( 'HTTP/1.1 404 Not Found' );
	echo 'not found';
	exit;
}
\$_SERVER['REQUEST_URI'] = '/';
\$_SERVER['SCRIPT_NAME'] = '/index.php';
\$_SERVER['PHP_SELF']    = '/index.php';
\$_GET = array();
include '${PREVIEW_WP}/wp-includes/version.php';
header( 'X-Robots-Tag: noindex, nofollow' );
header( 'Cache-Control: private, no-store, no-cache, must-revalidate' );
header( 'X-Core-Preview-Boot: 1' );
header( 'X-Core-Preview-Version: ' . \$wp_version );
define( 'WP_USE_THEMES', true );
require '${PREVIEW_WP}/wp-blog-header.php';
PHP
  chmod 644 "${FIXTURE}/${BOOT_FILE}"

  BODY_FILE="$(mktemp)"
  HDR_FILE="$(mktemp)"

  # The boot file is written from HERE; the web server reads it from THERE. On a container
  # with a mounted volume (ddev/colima, lando) propagation is not instant, so an immediate
  # request can 404 on a file that exists. That is the probe failing to run, NOT the target
  # failing — reporting it as a fatal would be a harness fault wearing a verdict's clothes,
  # which is the same mistake the damaged-sideload gate above exists to prevent.
  HTTP_ATTEMPTS=0
  while [ $HTTP_ATTEMPTS -lt 12 ]; do
    HTTP_STATUS="$(curl -ksS --max-time 60 -o "$BODY_FILE" -D "$HDR_FILE" -w '%{http_code}' \
      -H "X-Core-Preview: ${TOKEN}" -H 'Cache-Control: no-cache' \
      "${SITE_URL}/${BOOT_FILE}?path=/" 2>/dev/null || echo 000)"
    # 404 here means the server cannot see the file yet: the token gate answers 404 too, but
    # only for a request without the token, and this one carries it.
    [ "$HTTP_STATUS" != "404" ] && break
    HTTP_ATTEMPTS=$((HTTP_ATTEMPTS + 1))
    sleep 1
  done
  [ $HTTP_ATTEMPTS -gt 0 ] && echo "http_waited_for_mount=${HTTP_ATTEMPTS}s"

  HTTP_BOOT_VERSION="$(awk -F': ' 'tolower($1)=="x-core-preview-version" {gsub("\r","",$2); print $2}' "$HDR_FILE")"
  echo "http_status=${HTTP_STATUS}"
  echo "http_booted_version=${HTTP_BOOT_VERSION:-<none>}"
  echo "http_bytes=$(wc -c <"$BODY_FILE" | tr -d ' ')"

  if [ "$HTTP_STATUS" = "404" ] || [ "$HTTP_STATUS" = "000" ]; then
    rm -f -- "$BODY_FILE" "$HDR_FILE"; cleanup_boot_file
    echo "core-preflight-probe: the boot file was never served (HTTP ${HTTP_STATUS} after" >&2
    echo "  ${HTTP_ATTEMPTS}s). The probe did not run; this is an error, not a result." >&2
    exit 1
  fi

  if grep -qE "$PHP_FATAL_GREP" "$BODY_FILE"; then
    HTTP_FATAL="body contains a PHP fatal"
  elif [ "$HTTP_STATUS" != "200" ] && [ "$HTTP_STATUS" != "301" ] && [ "$HTTP_STATUS" != "302" ]; then
    HTTP_FATAL="HTTP ${HTTP_STATUS}"
  elif [ -n "$HTTP_BOOT_VERSION" ] && [ "$HTTP_BOOT_VERSION" != "$TARGET_VERSION" ]; then
    HTTP_FATAL="booted ${HTTP_BOOT_VERSION}, expected ${TARGET_VERSION}"
  fi
  rm -f -- "$BODY_FILE" "$HDR_FILE"
  cleanup_boot_file
  [ -n "$HTTP_FATAL" ] && echo "http_probe=FATAL reason=${HTTP_FATAL}" || echo "http_probe=clean"
fi

echo
echo "== invariant: the probe changed nothing"
DB_AFTER="$(wp_value option get db_version --skip-plugins --skip-themes)"
echo "db_version_before=${DB_BEFORE} db_version_after=${DB_AFTER}"
if [ "$DB_BEFORE" != "$DB_AFTER" ]; then
  echo "core-preflight-probe: PROBE MUTATED db_version — invalid run" >&2
  exit 4
fi
LIVE_AFTER="$(wp_value core version --skip-plugins --skip-themes)"
echo "live_version_before=${LIVE_VERSION} live_version_after=${LIVE_AFTER}"
if [ "$LIVE_VERSION" != "$LIVE_AFTER" ]; then
  echo "core-preflight-probe: LIVE CORE VERSION CHANGED — invalid run" >&2
  exit 4
fi

echo
# HTTP decides. A CLI fatal with a clean HTTP probe is the scoping artifact far more often
# than it is a release finding, so it downgrades to a note rather than failing the run.
VERDICT_FATAL=0
if [ -n "$HTTP_FATAL" ]; then
  VERDICT_FATAL=1
  echo "probe=FATAL reason=HTTP: ${HTTP_FATAL}"
  [ $PROBE_FATAL -eq 1 ] && echo "probe=ALSO  CLI: ${PROBE_REASON}"
elif [ $PROBE_FATAL -eq 1 ] && [ -n "$SITE_URL" ]; then
  echo "probe=clean target=${TARGET_VERSION} (HTTP served ${HTTP_STATUS})"
  echo "probe=NOTE  the CLI boot fataled: ${PROBE_REASON}"
  echo "probe=NOTE  HTTP is clean, so this is most likely WP-CLI's wp-settings-in-a-method"
  echo "probe=NOTE  scoping artifact, not a release finding. Worth a look, not a failure."
elif [ $PROBE_FATAL -eq 1 ]; then
  VERDICT_FATAL=1
  echo "probe=FATAL reason=CLI: ${PROBE_REASON} (no HTTP probe ran to confirm)"
else
  echo "probe=clean target=${TARGET_VERSION}"
fi
PROBE_FATAL=$VERDICT_FATAL

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
