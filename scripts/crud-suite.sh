#!/bin/bash
# CRUD smoke suite — posts, comments, pages, CPTs, terms, media, themes, updates.
#
#   bash scripts/crud-suite.sh --env=ddev ~/wp-test
#   bash scripts/crud-suite.sh --env=playground ~/wp-test
#   bash scripts/crud-suite.sh ~/wp-test http://localhost:8888   # legacy, = wp-env
#
# Driver comes from --env=, or $WP_AUDIT_ENV, or defaults to wp-env so the old
# two-argument invocation keeps working.
#
# Runs against the live site (not a tests database) so state stays inspectable after.
#
# Cells that need a capability the driver lacks report BLOCKED with the capability
# named — never PASS. A suite that reports PASS on an environment which could not have
# failed is the exact thing this repo argues is not evidence, and with several drivers
# in play that stops being a hypothetical.

DRIVER="${WP_AUDIT_ENV:-}"
ARGS=()
for a in "$@"; do
  case "$a" in
    --env=*) DRIVER="${a#--env=}" ;;
    *)       ARGS+=("$a") ;;
  esac
done
PROJ="${ARGS[0]:-.}"
URL="${ARGS[1]:-}"
DRIVER="${DRIVER:-wp-env}"

# shellcheck source=/dev/null
. "$(cd "$(dirname "$0")" && pwd)/lib-env.sh" || exit 1
env_init "$DRIVER" "$PROJ" || exit 1
[ -n "$URL" ] || URL="$(env_url)"

ok()  { [ "$1" = "$2" ] && echo "PASS" || echo "FAIL (got '$1' want '$2')"; }
sec() { echo; echo "======== $1"; }

sec "0. Baseline"
echo "driver=$WP_AUDIT_ENV_DRIVER url=$URL"
echo "version=$(env_wp core version)  php=$(env_wp eval 'echo PHP_VERSION;')"
echo "caps=$(env_caps)"
# Flush rewrite rules before testing any archive URL.
#
# A site installed with `wp core install` has a permalink structure but never had its
# rewrite rules written the way saving Settings → Permalinks in a browser would. Term
# archives then 404 while single posts serve fine — verified 2026-08-01: /category/<slug>/
# returned 404, and 200 immediately after a flush. That is an artifact of HOW the fixture
# was built, not a WordPress defect, and reporting it as one would be lie #1 in the README
# with the roles reversed. Flush it here so the archive check measures the archive.
env_wp rewrite flush --hard >/dev/null 2>&1
echo "rewrites_flushed=$(env_wp option get permalink_structure 2>/dev/null | head -1)"

sec "1. Posts — create / update / delete"
PID=$(env_wp post create --post_title="CRUD post" --post_content="body v1" --post_status=publish --porcelain)
echo "created id=$PID status=$(env_wp post get "$PID" --field=post_status)"
env_wp post update "$PID" --post_title="CRUD post edited" --post_content="body v2" >/dev/null
echo "updated title=$(env_wp post get "$PID" --field=post_title)"
echo "frontend_has_post=$(curl -skL "$URL/?p=$PID" | grep -c 'CRUD post edited')"
env_wp post delete "$PID" >/dev/null
echo "after_trash status=$(env_wp post get "$PID" --field=post_status 2>/dev/null)"
env_wp post delete "$PID" --force >/dev/null
echo "after_force_delete exists=$(env_wp post get "$PID" --field=ID 2>/dev/null || echo gone)"

sec "2. Comments — add / delete"
CPID=$(env_wp post create --post_title="Comment host" --post_status=publish --porcelain)
CID=$(env_wp comment create --comment_post_ID="$CPID" --comment_content="hello comment" --comment_author=tester --comment_author_email=t@example.com --porcelain)
echo "comment id=$CID approved=$(env_wp comment get "$CID" --field=comment_approved)"
env_wp comment update "$CID" --comment_content="edited comment" >/dev/null
echo "edited=$(env_wp comment get "$CID" --field=comment_content)"
echo "count_on_post=$(env_wp comment count "$CPID" | head -2 | tr '\n' ' ')"
env_wp comment delete "$CID" --force >/dev/null
echo "after_delete=$(env_wp comment get "$CID" --field=comment_ID 2>/dev/null || echo gone)"

sec "3. Pages — create / update / delete"
PGID=$(env_wp post create --post_type=page --post_title="CRUD page" --post_status=publish --porcelain)
env_wp post update "$PGID" --post_title="CRUD page edited" >/dev/null
echo "page id=$PGID title=$(env_wp post get "$PGID" --field=post_title) type=$(env_wp post get "$PGID" --field=post_type)"
echo "frontend=$(curl -skL -o /dev/null -w '%{http_code}' "$URL/?page_id=$PGID")"
env_wp post delete "$PGID" --force >/dev/null
echo "deleted=$(env_wp post get "$PGID" --field=ID 2>/dev/null || echo gone)"

sec "4. Custom post type — create / update / delete"
# Needs `shell`: the CPT is registered by writing an mu-plugin into the document root.
# Playground's WASM sandbox has no shell, so this cell is unreachable there.
if env_require CRUD-04 shell; then
  env_exec bash -c 'mkdir -p /var/www/html/wp-content/mu-plugins && cat > /var/www/html/wp-content/mu-plugins/cpt-mu.php <<"PHPEOF"
<?php
add_action("init", function () {
    register_post_type("crud_book", array(
        "public" => true, "label" => "Books", "show_in_rest" => true,
        "supports" => array("title","editor","custom-fields","thumbnail"),
    ));
    register_taxonomy("crud_genre", "crud_book", array("public"=>true,"hierarchical"=>true,"show_in_rest"=>true));
});
PHPEOF' >/dev/null 2>&1
  echo "cpt registered=$(env_wp post-type list --field=name | grep -c crud_book)"
  BID=$(env_wp post create --post_type=crud_book --post_title="CRUD book" --post_status=publish --porcelain)
  env_wp post update "$BID" --post_title="CRUD book edited" >/dev/null
  echo "book id=$BID title=$(env_wp post get "$BID" --field=post_title)"
  echo "rest_visible=$(curl -skL -o /dev/null -w '%{http_code}' "$URL/wp-json/wp/v2/crud_book")"
  env_wp post delete "$BID" --force >/dev/null
  echo "deleted=$(env_wp post get "$BID" --field=ID 2>/dev/null || echo gone)"
fi

sec "5. Categories and tags"
CAT=$(env_wp term create category "CRUD Cat" --porcelain)
TAG=$(env_wp term create post_tag "CRUD Tag" --porcelain)
echo "cat=$CAT tag=$TAG"
TPID=$(env_wp post create --post_title="Termed post" --post_status=publish --porcelain)
env_wp post term add "$TPID" category "CRUD Cat" >/dev/null
env_wp post term add "$TPID" post_tag "CRUD Tag" >/dev/null
echo "assigned cats=$(env_wp post term list "$TPID" category --field=name | tr '\n' ',') tags=$(env_wp post term list "$TPID" post_tag --field=name | tr '\n' ',')"
echo "archive_http=$(curl -skL -o /dev/null -w '%{http_code}' "$URL/?cat=$CAT")"
env_wp post term remove "$TPID" category "CRUD Cat" >/dev/null
echo "after_remove cats=$(env_wp post term list "$TPID" category --field=name | tr '\n' ',' || echo none)"
env_wp term delete category "$CAT" >/dev/null; env_wp term delete post_tag "$TAG" >/dev/null
echo "terms_deleted cat=$(env_wp term get category "$CAT" --field=term_id 2>/dev/null || echo gone)"

sec "6. Media — upload / edit / delete (image, video, PDF)"
# Also needs `shell` — the fixtures are generated inside the environment.
if env_require CRUD-06 shell; then
  env_exec bash -c 'cd /tmp && php -r "\$im=imagecreatetruecolor(1200,800); imagefill(\$im,0,0,imagecolorallocate(\$im,40,90,160)); imagejpeg(\$im,\"/tmp/test-image.jpg\",90);"' >/dev/null 2>&1
  env_exec bash -c 'printf "%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n" > /tmp/test-doc.pdf'
  IMG=$(env_wp media import /tmp/test-image.jpg --title="CRUD image" --porcelain)
  echo "image id=$IMG"
  echo "  sizes=$(env_wp eval "\$m=wp_get_attachment_metadata($IMG); echo implode(',', array_keys(\$m['sizes'] ?? array()));")"
  echo "  dims=$(env_wp eval "\$s=wp_get_attachment_image_src($IMG,'full'); echo \$s[1].'x'.\$s[2];")"
  echo "  edit_rotate=$(env_wp eval "
    \$f=get_attached_file($IMG); \$e=wp_get_image_editor(\$f);
    if (is_wp_error(\$e)) { echo 'editor_error:'.\$e->get_error_message(); }
    else { \$r=\$e->rotate(90); \$c=\$e->crop(0,0,400,300);
           \$sv=\$e->save(\$f); echo is_wp_error(\$sv)?'save_error':'rotated+cropped_ok'; }")"
  PDF=$(env_wp media import /tmp/test-doc.pdf --title="CRUD pdf" --porcelain)
  echo "pdf id=$PDF mime=$(env_wp post get "$PDF" --field=post_mime_type)"
  echo "media_list_count=$(env_wp post list --post_type=attachment --format=count)"
  env_wp post delete "$IMG" --force >/dev/null; env_wp post delete "$PDF" --force >/dev/null
  echo "media_after_delete=$(env_wp post list --post_type=attachment --format=count)"
fi

sec "7. Theme switching"
echo "themes=$(env_wp theme list --field=name | tr '\n' ' ')"
CUR=$(env_wp theme list --status=active --field=name)
echo "active_before=$CUR"
for T in twentytwentyfour twentytwentythree; do
  env_wp theme install "$T" >/dev/null 2>&1
done
for T in $(env_wp theme list --field=name); do
  env_wp theme activate "$T" >/dev/null 2>&1
  A=$(env_wp theme list --status=active --field=name)
  H=$(curl -skL -o /dev/null -w '%{http_code}' "$URL/")
  echo "  activated=$A frontend=$H"
done
env_wp theme activate "$CUR" >/dev/null 2>&1
echo "restored=$(env_wp theme list --status=active --field=name)"

sec "8. Plugin install from a macOS Finder-style zip (__MACOSX / resource forks)"
echo "  (zip built with ditto --sequesterRsrc --keepParent, which is what Finder 'Compress' produces)"
echo "  see separate step — run macos-zip-plugin.sh"

sec "9. Plugin + theme updates"
env_wp plugin install hello-dolly --version=1.7.1 >/dev/null 2>&1
echo "installed hello dolly v=$(env_wp plugin get hello-dolly --field=version 2>/dev/null)"
echo "update_available=$(env_wp plugin list --name=hello-dolly --field=update)"
env_wp plugin update hello-dolly >/dev/null 2>&1
echo "after_update v=$(env_wp plugin get hello-dolly --field=version 2>/dev/null)"
env_wp theme install twentytwentyone --version=2.0 >/dev/null 2>&1
echo "theme t21 v=$(env_wp theme get twentytwentyone --field=version 2>/dev/null)"
env_wp theme update twentytwentyone >/dev/null 2>&1
echo "after_update v=$(env_wp theme get twentytwentyone --field=version 2>/dev/null)"

sec "DONE"
echo "final_frontend=$(curl -skL -o /dev/null -w '%{http_code}' "$URL/")"
echo "final_fatal_scan=$(curl -skL "$URL/" | grep -ciE 'fatal error|parse error')"
