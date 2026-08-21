#!/bin/bash
# Preflight: report what this environment CAN and CANNOT detect.
# Run before any release pass and log the output beside the results — a passing
# test on an insensitive environment is not evidence.
#
#   bash scripts/preflight-sensitivity.sh --env=ddev ~/wp-test
#   bash scripts/preflight-sensitivity.sh ~/wp-test        # legacy, = wp-env
#
# Two layers, and the first one is newer than the second.
#
# The ENVIRONMENT CAPABILITIES block asks what the environment TOOL can do — can it reach
# WordPress's own updater, can the host read the document root, can it snapshot. The
# sensitivity table below asks what the PHP RUNTIME can notice — zip library, image
# delegates, mbstring, locale.
#
# Both are the same argument. The runtime layer has been here since the beginning; the
# environment layer was added when the suites learned to run on more than one tool, at
# which point "the suite passed" started meaning materially different things depending on
# where you ran it. A capability the driver lacks makes its cells BLOCKED, not PASS.

DRIVER="${WP_AUDIT_ENV:-}"
GATE=""
ARGS=()
for a in "$@"; do
  case "$a" in
    --env=*)  DRIVER="${a#--env=}" ;;
    --gate=*) GATE="${a#--gate=}" ;;
    *)        ARGS+=("$a") ;;
  esac
done
PROJ="${ARGS[0]:-$HOME/projects/wp71-test-suite}"
DRIVER="${DRIVER:-wp-env}"

# shellcheck source=/dev/null
. "$(cd "$(dirname "$0")" && pwd)/lib-env.sh" || exit 1
env_init "$DRIVER" "$PROJ" || exit 1

# --gate=i18n: the report below WARNS that en_US cannot detect i18n bugs; this
# turns the warning into an exit code so the i18n cells can be gated instead of
# skipped. The rule: an en_US-only environment makes every i18n cell
# BLOCKED(locale-en_US) — never SKIP, and never PASS. Exit 0 = a real locale is
# active, run the cells; exit 3 = record them BLOCKED.
if [ "$GATE" = "i18n" ]; then
  LOC="$(env_wp eval 'echo get_locale();' 2>/dev/null)"
  if [ "$LOC" = "en_US" ] || [ -z "$LOC" ]; then
    echo "GATE i18n: locale=${LOC:-unreadable} — BLOCKED(locale-en_US)."
    echo "Record every i18n cell BLOCKED, never SKIP, never PASS. Install a real"
    echo "locale (wp language core install de_DE --activate) to unblock."
    exit 3
  fi
  echo "GATE i18n: locale=$LOC — i18n cells may run."
  exit 0
fi

echo "=== Environment sensitivity report — $(basename "$PROJ")"
echo
env_caps_report
echo
echo "=== Runtime sensitivity"
echo

env_wp eval '
$out = array();

// libzip — CHECKCONS zip regressions (Trac #60398) only reproduce below 1.10.1
$libzip = defined("ZipArchive::LIBZIP_VERSION") ? ZipArchive::LIBZIP_VERSION : "unknown";
$out[] = array("libzip", $libzip,
    (version_compare($libzip, "1.10.1", "<") ? "CAN detect CHECKCONS zip regressions"
                                             : "CANNOT detect CHECKCONS zip regressions (#60398)"));

// image library — delegates matter, not the extension
$imagick = extension_loaded("imagick");
$delegates = "n/a";
if ($imagick) {
    $heic = Imagick::queryFormats("HEI*");
    $avif = Imagick::queryFormats("AVIF");
    $webp = Imagick::queryFormats("WEBP");
    $delegates = "HEIC=" . (count($heic) ? "yes" : "no")
               . " AVIF=" . (count($avif) ? "yes" : "no")
               . " WEBP=" . (count($webp) ? "yes" : "no");
}
$out[] = array("imagick", $imagick ? "loaded ($delegates)" : "absent",
    $imagick ? "CAN test Imagick paths — CHECK DELEGATES, not the extension"
             : "GD (php-gd) only: CAN detect GD fallback bugs; CANNOT test Imagick delegates");

$gd = extension_loaded("gd");
if ($gd) {
    $g = gd_info();
    $out[] = array("gd", "HEIC=" . (isset($g["HEIF Support"]) ? "yes" : "no")
                       . " AVIF=" . (!empty($g["AVIF Support"]) ? "yes" : "no")
                       . " WEBP=" . (!empty($g["WebP Support"]) ? "yes" : "no"), "");
}

// filesystem method — two shipped upgrade regressions live off the direct path
$fs = defined("FS_METHOD") ? FS_METHOD : "(unset = direct)";
$out[] = array("FS_METHOD", $fs,
    ("ftpext" === $fs || "ssh2" === $fs || "ftpsockets" === $fs)
      ? "CAN detect non-direct filesystem upgrade bugs"
      : "CANNOT detect ftpext/ssh2 upgrade fatals (#62718, #56966)");

// mbstring — compat.php polyfills only run when it is ABSENT
$mb = extension_loaded("mbstring");
$out[] = array("mbstring", $mb ? "loaded" : "absent",
    $mb ? "CANNOT exercise compat.php polyfills (#61680)" : "CAN exercise compat.php polyfills");

// locale — the JIT textdomain notice is invisible on en_US by construction
$loc = get_locale();
$out[] = array("locale", $loc,
    ("en_US" === $loc) ? "CANNOT detect i18n / JIT-textdomain bugs" : "CAN detect i18n bugs");

// object + page cache — 7.1 speculative loading only bumps to moderate with both
$oc = wp_using_ext_object_cache();
$pc = defined("WP_CACHE") && WP_CACHE;
$out[] = array("object_cache", $oc ? "yes" : "no", "");
$out[] = array("page_cache(WP_CACHE)", $pc ? "yes" : "no",
    ($oc && $pc) ? "CAN test speculative-loading moderate default"
                 : "CANNOT test speculative-loading moderate default (needs both)");

// drop-ins — early-boot fatals need these present
$drop = array();
foreach (array("advanced-cache.php","object-cache.php","db.php","sunrise.php") as $d) {
    if (file_exists(WP_CONTENT_DIR . "/" . $d)) { $drop[] = $d; }
}
$out[] = array("drop-ins", $drop ? implode(",", $drop) : "none",
    $drop ? "CAN detect early-boot drop-in fatals" : "CANNOT detect early-boot drop-in fatals");

$out[] = array("php", PHP_VERSION, "");
$out[] = array("mysql", $GLOBALS["wpdb"]->db_version(), "");
$out[] = array("charset", $GLOBALS["wpdb"]->charset,
    ("utf8mb4" === $GLOBALS["wpdb"]->charset) ? "" : "CANNOT test utf8mb4-dependent features");
$out[] = array("multisite", is_multisite() ? "yes" : "no", "");

foreach ($out as $r) { printf("%-22s %-34s %s\n", $r[0], $r[1], $r[2]); }
'

echo
echo "=== curl / HTTP stack"
# Through wp eval rather than a shell, so this still reports on the drivers with no
# `shell` capability — Playground runs PHP in WASM and has no shell at all, and the curl
# build is exactly the kind of thing you want to know about there.
env_wp eval '$v = curl_version(); echo "curl " . $v["version"] . "  ssl " . $v["ssl_version"] . "\n";'
echo "  (old-cURL regressions like the 6.4 'error 28' need libcurl ~7.29 — modern builds CANNOT detect them)"
