#!/bin/bash
# Plugin and theme install suite: every way a plugin or theme gets onto a site.
#
#   bash scripts/extension-install-suite.sh --env=cli ~/Studio/rel-72 http://localhost:8881
#   bash scripts/extension-install-suite.sh --env=cli ~/Studio/rel-72 http://localhost:8881 --no-network
#
# Options:
#   --no-network   mark WordPress.org, URL and REST-install cells BLOCKED instead of downloading
#   --out=<dir>    also write the cell table to <dir>/extension-install-suite.tsv
#
# Methods covered:
#   upload screen over HTTP   Plugins > Add New > Upload, Themes > Add New > Upload, the real
#                             form with a logged-in session, once per MIME type a browser sends
#                             for a .zip (application/zip from macOS, application/x-zip-compressed
#                             from Windows, application/octet-stream), then "Replace current
#                             with uploaded"
#   upgrader directly         Plugin_Upgrader / Theme_Upgrader->install(), the code behind the
#                             screens, for every zip shape below, unzipped by ZipArchive AND by
#                             PclZip (the fallback on hosts without the zip extension)
#   WordPress.org directory   plugins_api / themes_api, then install, as Install Now does
#   from a URL                once per HTTP transport (cURL, streams)
#   REST                      POST /wp/v2/plugins {slug}
#   WP-CLI                    wp plugin|theme install <slug | zip | url>
#   manual                    a folder copied in (FTP), a child theme, an mu-plugin file
#   dependencies              Requires Plugins blocks activation until the dependency is active
#
# Zip shapes, built here rather than downloaded, so each one is exactly what its tool makes:
#   infozip            zip -r: directory entries, Unix modes
#   macos-finder       adds __MACOSX/ AppleDouble (._) entries and .DS_Store
#   macos-ditto        the real thing from `ditto -c -k --sequesterRsrc --keepParent`, when on macOS
#   windows-explorer   no directory entries, DOS attributes
#   windows-backslash  PowerShell 5.1 Compress-Archive: BACKSLASH path separators
#   no-top-folder      files at the archive root, a common hand-made zip
# The last two are recorded as INFO (no OS tool should produce them, people upload them anyway);
# compare them with the previous stable rather than judging them alone.

DRIVER="${WP_AUDIT_ENV:-}"
ARGS=()
NETWORK=1
OUT=""
for a in "$@"; do
  case "$a" in
    --env=*)      DRIVER="${a#--env=}" ;;
    --no-network) NETWORK=0 ;;
    --out=*)      OUT="${a#--out=}" ;;
    *)            ARGS+=("$a") ;;
  esac
done
PROJ="${ARGS[0]:-.}"
URL="${ARGS[1]:-}"
DRIVER="${DRIVER:-wp-env}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=/dev/null
. "$HERE/lib-env.sh" || exit 1
env_init "$DRIVER" "$PROJ" || exit 1
[ -n "$URL" ] || URL="$(env_url)"
W() { env_wp "$@"; }

TMP="$(mktemp -d)"
JAR="$TMP/cookies"
USER_LOGIN="ext-suite-$$"
cleanup_user() { W user delete "$USER_LOGIN" --yes ${MULTI:+--network} >/dev/null 2>&1; }
trap 'cleanup_user; rm -rf "$TMP"' EXIT
: > "$TMP/cells.tsv"
cell() { printf 'CELL\t%s\t%s\t%s\n' "$1" "$2" "$3" >> "$TMP/cells.tsv"; }
MULTI="$(W eval 'echo is_multisite() ? 1 : "";' 2>/dev/null | tail -1)"

# ---------------------------------------------------------------- build the archives
python3 - "$TMP" <<'PY'
import os, sys, zipfile, time
out = sys.argv[1]
T = (2026, 11, 10, 12, 0, 0)
PLUGIN = {"ms-ext/ms-ext.php": "<?php\n/**\n * Plugin Name: MS Ext\n * Version: {v}\n * Description: extension-install-suite fixture.\n */\n",
          "ms-ext/readme.txt": "=== MS Ext ===\nStable tag: {v}\n"}
THEME = {"ms-ext-theme/style.css": "/*\nTheme Name: MS Ext Theme\nTemplate: twentytwentyfive\nVersion: {v}\n*/\n",
         "ms-ext-theme/functions.php": "<?php\n// extension-install-suite fixture\n"}
DEPENDENT = {"ms-ext-dependent/ms-ext-dependent.php": "<?php\n/**\n * Plugin Name: MS Ext Dependent\n * Requires Plugins: ms-ext-required\n * Version: 1.0\n */\n"}
REQUIRED = {"ms-ext-required/ms-ext-required.php": "<?php\n/**\n * Plugin Name: MS Ext Required\n * Version: 1.0\n */\n"}

def info(name, system, attr, is_dir=False):
    zi = zipfile.ZipInfo(name, T)
    zi.create_system = system
    zi.external_attr = attr
    zi.compress_type = zipfile.ZIP_DEFLATED
    return zi

def build(path, files, variant, v="1.0"):
    files = {k: c.replace("{v}", v) for k, c in files.items()}
    with zipfile.ZipFile(path, "w") as z:
        if variant in ("infozip", "macos-finder"):
            for d in sorted({k.split("/")[0] + "/" for k in files}):
                z.writestr(info(d, 3, (0o40755 << 16) | 0x10), b"")
        for name, body in files.items():
            if variant == "windows-backslash":
                z.writestr(info(name.replace("/", "\\"), 0, 0x20), body)
            elif variant == "windows-explorer":
                z.writestr(info(name, 0, 0x20), body)
            elif variant == "no-top-folder":
                z.writestr(info(name.split("/", 1)[1], 3, 0o100644 << 16), body)
            else:
                z.writestr(info(name, 3, 0o100644 << 16), body)
        if variant == "macos-finder":
            top = next(iter(files)).split("/")[0]
            z.writestr(info(f"{top}/.DS_Store", 3, 0o100644 << 16), b"\x00\x00\x00\x01Bud1")
            z.writestr(info("__MACOSX/", 3, (0o40755 << 16) | 0x10), b"")
            for name in files:
                d, f = name.rsplit("/", 1)
                z.writestr(info(f"__MACOSX/{d}/._{f}", 3, 0o100644 << 16), b"\x00\x05\x16\x07\x00\x02\x00\x00Mac OS X        ")

for variant in ("infozip", "macos-finder", "windows-explorer", "windows-backslash", "no-top-folder"):
    build(f"{out}/plugin-{variant}.zip", PLUGIN, variant)
    build(f"{out}/theme-{variant}.zip", THEME, variant)
build(f"{out}/plugin-v2.zip", PLUGIN, "infozip", "2.0")
build(f"{out}/theme-v2.zip", THEME, "infozip", "2.0")
build(f"{out}/plugin-dependent.zip", DEPENDENT, "infozip")
build(f"{out}/plugin-required.zip", REQUIRED, "infozip")
for kind, files in (("plugin", PLUGIN), ("theme", THEME)):
    for name, body in files.items():
        p = f"{out}/src-{kind}/{name}"
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(body.replace("{v}", "1.0"))
PY
if command -v ditto >/dev/null 2>&1; then
  for kind in plugin theme; do
    src="$TMP/src-$kind/$( [ $kind = plugin ] && echo ms-ext || echo ms-ext-theme )"
    # An extended attribute, as a downloaded or edited file carries, so Finder-style AppleDouble entries appear.
    xattr -w com.apple.metadata:kMDItemWhereFroms "ext-suite" "$src"/* 2>/dev/null
    ditto -c -k --sequesterRsrc --keepParent "$src" "$TMP/$kind-macos-ditto.zip"
  done
fi

zips=""
for f in "$TMP"/plugin-*.zip "$TMP"/theme-*.zip; do
  b="$(basename "$f" .zip)"; kind="${b%%-*}"; variant="${b#*-}"
  zips="$zips'$kind:$variant' => '$(base64 < "$f" | tr -d '\n')',"
done

echo "======== extension install suite  driver=$WP_AUDIT_ENV_DRIVER url=$URL multisite=${MULTI:-no}"
echo "version=$(W core version 2>/dev/null | tail -1)"

# ---------------------------------------------------------------- in-site upgrader cells
PAYLOAD="\$EX_ZIPS = array($zips); \$EX_NETWORK = $( [ $NETWORK = 1 ] && echo true || echo false ); \$EX_TAG = 'ext-suite';
$(sed '1s/^<?php//' "$HERE/extension-install-suite.php")"
W eval "$PAYLOAD" > "$TMP/run.out" 2> "$TMP/run.err"
grep '^CELL' "$TMP/run.out" >> "$TMP/cells.tsv"
grep -q '^CELL' "$TMP/run.out" || { echo "payload failed:"; tail -20 "$TMP/run.err"; exit 2; }

# Dependencies, satisfied half: each step is its own process, as each admin request is.
if grep -q '^DEPTEST' "$TMP/run.out"; then
  if W plugin activate ms-ext-dependent >"$TMP/dep0.log" 2>&1; then
    cell plugin-dependency-blocks-activation FAIL "activated while ms-ext-required was inactive"
    W plugin deactivate ms-ext-dependent >/dev/null 2>&1
  else
    cell plugin-dependency-blocks-activation PASS "$(grep -o -i 'requires[^.]*' "$TMP/dep0.log" | head -1)"
  fi
  if W plugin activate ms-ext-required >/dev/null 2>&1 && W plugin activate ms-ext-dependent >"$TMP/dep.log" 2>&1 && W plugin is-active ms-ext-dependent; then
    cell plugin-dependency-satisfied PASS "activated once the required plugin was active"
  else
    cell plugin-dependency-satisfied FAIL "$(grep -E 'Error|Warning' "$TMP/dep.log" | head -1)"
  fi
  W plugin deactivate ms-ext-dependent ms-ext-required >/dev/null 2>&1
  W plugin delete ms-ext-dependent ms-ext-required >/dev/null 2>&1
fi

# ---------------------------------------------------------------- WP-CLI install paths
wpcli() {  # wpcli <cell> <check-type> <check-slug> <install args...>
  local c="$1" type="$2" slug="$3"; shift 3
  if W "$type" install "$@" >"$TMP/cli.log" 2>&1 && W "$type" is-installed "$slug" >/dev/null 2>&1; then
    cell "$c" PASS "wp $type install $(basename "$1")"
  else
    cell "$c" FAIL "$(grep -E 'Error|Warning' "$TMP/cli.log" | head -1)"
  fi
  W "$type" delete "$slug" >/dev/null 2>&1
}
if env_has hostfs; then
  wpcli wpcli-plugin-zip plugin ms-ext "$TMP/plugin-infozip.zip"
  wpcli wpcli-theme-zip theme ms-ext-theme "$TMP/theme-infozip.zip"
else
  cell wpcli-plugin-zip "BLOCKED(hostfs)" "the zip is on the host; this driver can't see it"
  cell wpcli-theme-zip "BLOCKED(hostfs)" "the zip is on the host; this driver can't see it"
fi
if [ "$NETWORK" = 1 ]; then
  wpcli wpcli-plugin-slug plugin hello-dolly hello-dolly
  wpcli wpcli-plugin-url plugin hello-dolly https://downloads.wordpress.org/plugin/hello-dolly.zip
else
  cell wpcli-plugin-slug "BLOCKED(no-network)" ""; cell wpcli-plugin-url "BLOCKED(no-network)" ""
fi

# ---------------------------------------------------------------- the upload screens, over HTTP
ADMIN="$URL/wp-admin${MULTI:+/network}"
if ! curl -sk -o /dev/null --max-time 20 "$URL/wp-login.php"; then
  cell upload-screen "BLOCKED(no-http)" "nothing answers at $URL"
else
  PASS_="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
  W user create "$USER_LOGIN" "$USER_LOGIN@example.test" --role=administrator --user_pass="$PASS_" >/dev/null 2>&1
  [ -n "$MULTI" ] && W super-admin add "$USER_LOGIN" >/dev/null 2>&1
  curl -sk -c "$JAR" -b "wordpress_test_cookie=WP%20Cookie%20check" -o /dev/null "$URL/wp-login.php"
  curl -sk -c "$JAR" -b "$JAR" -b "wordpress_test_cookie=WP%20Cookie%20check" -o /dev/null \
    --data-urlencode "log=$USER_LOGIN" --data-urlencode "pwd=$PASS_" -d "testcookie=1" -d "redirect_to=$ADMIN/" "$URL/wp-login.php"
  unset PASS_
  nonce_for() {  # nonce_for <page> <action> — the _wpnonce inside that upload form
    curl -sk -b "$JAR" "$1" | python3 -c '
import re, sys
html = sys.stdin.read(); m = re.search(r"action=\"[^\"]*update\.php\?action=" + sys.argv[1] + r"\"(.*?)</form>", html, re.S)
n = m and re.search(r"name=\"_wpnonce\" value=\"([0-9a-f]+)\"", m.group(1))
print(n.group(1) if n else "")' "$2"
  }
  upload() {  # upload <cell> <kind> <zip> <mime>
    local c="$1" kind="$2" zip="$3" mime="$4" page action field ok n
    if [ "$kind" = plugin ]; then page="$ADMIN/plugin-install.php?tab=upload"; action=upload-plugin; field=pluginzip; ok="Plugin installed successfully"
    else page="$ADMIN/theme-install.php?upload"; action=upload-theme; field=themezip; ok="Theme installed successfully"; fi
    n="$(nonce_for "$page" "$action")"
    [ -n "$n" ] || { cell "$c" FAIL "no upload form nonce on $(basename "$page") (login failed?)"; return; }
    curl -sk -b "$JAR" -o "$TMP/up.html" -F "_wpnonce=$n" -F "_wp_http_referer=/wp-admin/" -F "$field=@$zip;type=$mime;filename=ms-ext.zip" \
      -F "install-$kind-submit=Install Now" "$URL/wp-admin/update.php?action=$action"
    if grep -q "$ok" "$TMP/up.html"; then cell "$c" PASS "$mime"; else cell "$c" FAIL "$mime: $(python3 -c 'import re,sys,html;t=re.sub(r"<[^>]+>"," ",open(sys.argv[1]).read());m=re.search(r"(Installation failed[^.]*\.|The package could not[^.]*\.|[^.]*rror[^.]*\.)",t);print(html.unescape(m.group(1)).strip()[:140] if m else "no success message")' "$TMP/up.html")"; fi
  }
  for mime in application/zip application/x-zip-compressed application/octet-stream; do
    upload "upload-screen-plugin-${mime#application/}" plugin "$TMP/plugin-infozip.zip" "$mime"; W plugin delete ms-ext >/dev/null 2>&1
    upload "upload-screen-theme-${mime#application/}" theme "$TMP/theme-infozip.zip" "$mime"; W theme delete ms-ext-theme >/dev/null 2>&1
  done
  # Each OS's own archive with the MIME type its browsers send.
  upload upload-screen-plugin-macos-finder plugin "$TMP/plugin-macos-finder.zip" application/zip; W plugin delete ms-ext >/dev/null 2>&1
  [ -s "$TMP/plugin-macos-ditto.zip" ] && { upload upload-screen-plugin-macos-ditto plugin "$TMP/plugin-macos-ditto.zip" application/zip; W plugin delete ms-ext >/dev/null 2>&1; }
  upload upload-screen-plugin-windows-explorer plugin "$TMP/plugin-windows-explorer.zip" application/x-zip-compressed; W plugin delete ms-ext >/dev/null 2>&1
  upload upload-screen-theme-windows-explorer theme "$TMP/theme-windows-explorer.zip" application/x-zip-compressed; W theme delete ms-ext-theme >/dev/null 2>&1

  # Replace current with uploaded, through the screen: upload 1.0, upload 2.0, follow the replace link.
  upload upload-screen-plugin-replace-setup plugin "$TMP/plugin-infozip.zip" application/zip
  n="$(nonce_for "$ADMIN/plugin-install.php?tab=upload" upload-plugin)"
  curl -sk -b "$JAR" -o "$TMP/up2.html" -F "_wpnonce=$n" -F "_wp_http_referer=/wp-admin/" -F "pluginzip=@$TMP/plugin-v2.zip;type=application/zip;filename=ms-ext.zip" -F "install-plugin-submit=Install Now" "$URL/wp-admin/update.php?action=upload-plugin"
  link="$(python3 -c 'import re,sys,html;m=re.search(r"href=\"([^\"]*overwrite=update-plugin[^\"]*)\"",open(sys.argv[1]).read());print(html.unescape(m.group(1)) if m else "")' "$TMP/up2.html")"
  if [ -z "$link" ]; then
    cell upload-screen-plugin-replace FAIL "no Replace current with uploaded link after uploading 2.0"
  else
    case "$link" in http*) ;; *) link="$URL/wp-admin/$link" ;; esac
    curl -sk -b "$JAR" -o "$TMP/up3.html" "$link"
    ver="$(W plugin get ms-ext --field=version 2>/dev/null | tail -1)"
    [ "$ver" = "2.0" ] && cell upload-screen-plugin-replace PASS "replaced 1.0 with 2.0" || cell upload-screen-plugin-replace FAIL "version after replace: ${ver:-none}"
  fi
  W plugin delete ms-ext >/dev/null 2>&1
fi

# ---------------------------------------------------------------- report
echo
awk -F'\t' '{printf "%-50s %-26s %s\n", $2, $3, $4}' "$TMP/cells.tsv"
echo
for v in PASS FAIL BLOCKED INFO; do
  printf '%s=%s ' "$v" "$(awk -F'\t' -v v="$v" 'index($3, v) == 1' "$TMP/cells.tsv" | wc -l | tr -d ' ')"
done
echo
if [ -n "$OUT" ]; then mkdir -p "$OUT" && cut -f2- "$TMP/cells.tsv" > "$OUT/extension-install-suite.tsv"; fi
! grep -q $'\tFAIL\t' "$TMP/cells.tsv"
