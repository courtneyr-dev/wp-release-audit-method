#!/bin/bash
# WP 7.1-beta4 release-party CRUD smoke suite.
# Runs against the wp-env DEV site (not tests), so state is inspectable afterward.
PROJ="$1"; URL="$2"
cd "$PROJ" || exit 1

w() { npx --yes @wordpress/env@latest run cli -- "$@" 2>/dev/null \
      | grep -vE "^(ℹ|✔|npm warn)" | tr -d '\r' | sed '/^$/d'; }
ok() { [ "$1" = "$2" ] && echo "PASS" || echo "FAIL (got '$1' want '$2')"; }
sec() { echo; echo "======== $1"; }

sec "0. Baseline"
echo "version=$(w wp core version)  php=$(w wp eval 'echo PHP_VERSION;')"

sec "1. Posts — create / update / delete"
PID=$(w wp post create --post_title="CRUD post" --post_content="body v1" --post_status=publish --porcelain)
echo "created id=$PID status=$(w wp post get $PID --field=post_status)"
w wp post update $PID --post_title="CRUD post edited" --post_content="body v2" >/dev/null
echo "updated title=$(w wp post get $PID --field=post_title)"
echo "frontend_has_post=$(curl -s "$URL/?p=$PID" | grep -c 'CRUD post edited')"
w wp post delete $PID >/dev/null
echo "after_trash status=$(w wp post get $PID --field=post_status 2>/dev/null)"
w wp post delete $PID --force >/dev/null
echo "after_force_delete exists=$(w wp post get $PID --field=ID 2>/dev/null || echo gone)"

sec "2. Comments — add / delete"
CPID=$(w wp post create --post_title="Comment host" --post_status=publish --porcelain)
CID=$(w wp comment create --comment_post_ID=$CPID --comment_content="hello comment" --comment_author=tester --comment_author_email=t@example.com --porcelain)
echo "comment id=$CID approved=$(w wp comment get $CID --field=comment_approved)"
w wp comment update $CID --comment_content="edited comment" >/dev/null
echo "edited=$(w wp comment get $CID --field=comment_content)"
echo "count_on_post=$(w wp comment count $CPID | head -2 | tr '\n' ' ')"
w wp comment delete $CID --force >/dev/null
echo "after_delete=$(w wp comment get $CID --field=comment_ID 2>/dev/null || echo gone)"

sec "3. Pages — create / update / delete"
PGID=$(w wp post create --post_type=page --post_title="CRUD page" --post_status=publish --porcelain)
w wp post update $PGID --post_title="CRUD page edited" >/dev/null
echo "page id=$PGID title=$(w wp post get $PGID --field=post_title) type=$(w wp post get $PGID --field=post_type)"
echo "frontend=$(curl -s -o /dev/null -w '%{http_code}' "$URL/?page_id=$PGID")"
w wp post delete $PGID --force >/dev/null
echo "deleted=$(w wp post get $PGID --field=ID 2>/dev/null || echo gone)"

sec "4. Custom post type — create / update / delete"
w bash -c 'mkdir -p /var/www/html/wp-content/mu-plugins && cat > /var/www/html/wp-content/mu-plugins/cpt-mu.php <<"PHPEOF"
<?php
add_action("init", function () {
    register_post_type("crud_book", array(
        "public" => true, "label" => "Books", "show_in_rest" => true,
        "supports" => array("title","editor","custom-fields","thumbnail"),
    ));
    register_taxonomy("crud_genre", "crud_book", array("public"=>true,"hierarchical"=>true,"show_in_rest"=>true));
});
PHPEOF' >/dev/null 2>&1
echo "cpt registered=$(w wp post-type list --field=name | grep -c crud_book)"
BID=$(w wp post create --post_type=crud_book --post_title="CRUD book" --post_status=publish --porcelain)
w wp post update $BID --post_title="CRUD book edited" >/dev/null
echo "book id=$BID title=$(w wp post get $BID --field=post_title)"
echo "rest_visible=$(curl -s -o /dev/null -w '%{http_code}' "$URL/wp-json/wp/v2/crud_book")"
w wp post delete $BID --force >/dev/null
echo "deleted=$(w wp post get $BID --field=ID 2>/dev/null || echo gone)"

sec "5. Categories and tags"
CAT=$(w wp term create category "CRUD Cat" --porcelain)
TAG=$(w wp term create post_tag "CRUD Tag" --porcelain)
echo "cat=$CAT tag=$TAG"
TPID=$(w wp post create --post_title="Termed post" --post_status=publish --porcelain)
w wp post term add $TPID category "CRUD Cat" >/dev/null
w wp post term add $TPID post_tag "CRUD Tag" >/dev/null
echo "assigned cats=$(w wp post term list $TPID category --field=name | tr '\n' ',') tags=$(w wp post term list $TPID post_tag --field=name | tr '\n' ',')"
echo "archive_http=$(curl -s -o /dev/null -w '%{http_code}' "$URL/?cat=$CAT")"
w wp post term remove $TPID category "CRUD Cat" >/dev/null
echo "after_remove cats=$(w wp post term list $TPID category --field=name | tr '\n' ',' || echo none)"
w wp term delete category $CAT >/dev/null; w wp term delete post_tag $TAG >/dev/null
echo "terms_deleted cat=$(w wp term get category $CAT --field=term_id 2>/dev/null || echo gone)"

sec "6. Media — upload / edit / delete (image, video, PDF)"
w bash -c 'cd /tmp && php -r "\$im=imagecreatetruecolor(1200,800); imagefill(\$im,0,0,imagecolorallocate(\$im,40,90,160)); imagejpeg(\$im,\"/tmp/test-image.jpg\",90);"' >/dev/null 2>&1
w bash -c 'printf "%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n" > /tmp/test-doc.pdf'
IMG=$(w wp media import /tmp/test-image.jpg --title="CRUD image" --porcelain)
echo "image id=$IMG"
echo "  sizes=$(w wp eval "\$m=wp_get_attachment_metadata($IMG); echo implode(',', array_keys(\$m['sizes'] ?? array()));")"
echo "  dims=$(w wp eval "\$s=wp_get_attachment_image_src($IMG,'full'); echo \$s[1].'x'.\$s[2];")"
echo "  edit_rotate=$(w wp eval "
    \$f=get_attached_file($IMG); \$e=wp_get_image_editor(\$f);
    if (is_wp_error(\$e)) { echo 'editor_error:'.\$e->get_error_message(); }
    else { \$r=\$e->rotate(90); \$c=\$e->crop(0,0,400,300);
           \$sv=\$e->save(\$f); echo is_wp_error(\$sv)?'save_error':'rotated+cropped_ok'; }")"
PDF=$(w wp media import /tmp/test-doc.pdf --title="CRUD pdf" --porcelain)
echo "pdf id=$PDF mime=$(w wp post get $PDF --field=post_mime_type)"
echo "media_list_count=$(w wp post list --post_type=attachment --format=count)"
w wp post delete $IMG --force >/dev/null; w wp post delete $PDF --force >/dev/null
echo "media_after_delete=$(w wp post list --post_type=attachment --format=count)"

sec "7. Theme switching"
echo "themes=$(w wp theme list --field=name | tr '\n' ' ')"
CUR=$(w wp theme list --status=active --field=name)
echo "active_before=$CUR"
for T in twentytwentyfour twentytwentythree; do
  w wp theme install $T >/dev/null 2>&1
done
for T in $(w wp theme list --field=name); do
  w wp theme activate $T >/dev/null 2>&1
  A=$(w wp theme list --status=active --field=name)
  H=$(curl -s -o /dev/null -w '%{http_code}' "$URL/")
  echo "  activated=$A frontend=$H"
done
w wp theme activate "$CUR" >/dev/null 2>&1
echo "restored=$(w wp theme list --status=active --field=name)"

sec "8. Plugin install from a macOS Finder-style zip (__MACOSX / resource forks)"
echo "  (zip built with ditto --sequesterRsrc --keepParent, which is what Finder 'Compress' produces)"
echo "  see separate step — run macos-zip-plugin.sh"

sec "9. Plugin + theme updates"
w wp plugin install hello-dolly --version=1.7.1 >/dev/null 2>&1
echo "installed hello dolly v=$(w wp plugin get hello-dolly --field=version 2>/dev/null)"
echo "update_available=$(w wp plugin list --name=hello-dolly --field=update)"
w wp plugin update hello-dolly >/dev/null 2>&1
echo "after_update v=$(w wp plugin get hello-dolly --field=version 2>/dev/null)"
w wp theme install twentytwentyone --version=2.0 >/dev/null 2>&1
echo "theme t21 v=$(w wp theme get twentytwentyone --field=version 2>/dev/null)"
w wp theme update twentytwentyone >/dev/null 2>&1
echo "after_update v=$(w wp theme get twentytwentyone --field=version 2>/dev/null)"

sec "DONE"
echo "final_frontend=$(curl -s -o /dev/null -w '%{http_code}' "$URL/")"
echo "final_fatal_scan=$(curl -s "$URL/" | grep -ciE 'fatal error|parse error')"
