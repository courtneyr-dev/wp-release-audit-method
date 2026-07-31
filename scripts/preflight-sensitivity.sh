#!/bin/bash
# Preflight: report what this environment CAN and CANNOT detect.
# Run before any release pass and log the output beside the results — a passing
# test on an insensitive environment is not evidence.
#
# Usage: preflight-sensitivity.sh <wp-env-project-dir>

PROJ="${1:-$HOME/projects/wp71-test-suite}"
cd "$PROJ" || exit 1
w() { npx --yes @wordpress/env@latest run cli -- "$@" 2>/dev/null | grep -vE "^(ℹ|✔|npm warn)" | tr -d '\r'; }

echo "=== Environment sensitivity report — $(basename "$PROJ")"
echo

w wp eval '
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
             : "GD-only: CAN detect GD fallback bugs; CANNOT test Imagick delegates");

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
w bash -c 'php -r "\$v = curl_version(); echo \"curl \" . \$v[\"version\"] . \"  ssl \" . \$v[\"ssl_version\"] . \"\n\";"'
echo "  (old-cURL regressions like the 6.4 'error 28' need libcurl ~7.29 — modern builds CANNOT detect them)"
