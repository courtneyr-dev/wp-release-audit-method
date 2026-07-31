#!/bin/bash
# Users, Pages lifecycle, Fresh install, Manual install (incl. missing wp-config.php).
PROJ="$1"; URL="$2"
BETA4="https://wordpress.org/wordpress-7.1-beta4.zip"
cd "$PROJ" || exit 1
t() { npx --yes @wordpress/env@latest run tests-cli -- "$@" 2>/dev/null | grep -vE "^(ℹ|✔|npm warn)" | tr -d '\r' | sed '/^$/d'; }
sec() { echo; echo "======== $1"; }

sec "A. FRESH INSTALL (clean DB, beta4 files, wp core install)"
t wp db reset --yes >/dev/null
t php -d memory_limit=1024M /usr/local/bin/wp core download --version=7.1-beta4 --force --allow-root >/dev/null 2>&1
echo "files_version=$(t wp core version)"
echo "is_installed_before=$(t wp core is-installed >/dev/null 2>&1 && echo yes || echo no)"
t wp core install --url="$URL" --title="Fresh Install" --admin_user=admin --admin_password=password \
     --admin_email=admin@example.com --skip-email 2>&1 | tail -1
echo "is_installed_after=$(t wp core is-installed >/dev/null 2>&1 && echo yes || echo no)"
echo "version=$(t wp core version) db=$(t wp option get db_version)"
echo "frontend=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/")  login=$(curl -s -o /dev/null -w '%{http_code}' "$URL/wp-login.php")"
echo "default_content_posts=$(t wp post list --post_type=post --format=count) pages=$(t wp post list --post_type=page --format=count)"
echo "admin_user=$(t wp user get 1 --field=user_login) role=$(t wp user get 1 --field=roles)"

sec "B. MANUAL INSTALL — remove wp-config.php, walk the browser installer"
t bash -c 'cp /var/www/html/wp-config.php /tmp/wp-config.backup.php 2>/dev/null; rm -f /var/www/html/wp-config.php'
echo "wp_config_present=$(t bash -c '[ -f /var/www/html/wp-config.php ] && echo yes || echo no')"
echo "root_redirects_to_setup=$(curl -s -o /dev/null -w '%{http_code}' "$URL/")"
SETUP=$(curl -sL "$URL/" | grep -oiE "setup-config.php|There doesn't seem to be a wp-config.php|configuration file" | head -2 | tr '\n' ' ')
echo "setup_prompt_detected=[$SETUP]"
echo "setup_config_http=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/wp-admin/setup-config.php")"
SETUPSTEP=$(curl -sL "$URL/wp-admin/setup-config.php?step=1" | grep -oiE "Database Name|Username|Password|Database Host|Table Prefix" | sort -u | tr '\n' ',')
echo "setup_form_fields=[$SETUPSTEP]"
# restore config the way a manual installer would write it, then confirm the site returns
t bash -c 'cp /tmp/wp-config.backup.php /var/www/html/wp-config.php'
echo "restored_config=$(t bash -c '[ -f /var/www/html/wp-config.php ] && echo yes || echo no')"
echo "frontend_after_restore=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/")"

sec "B2. MANUAL INSTALL — fresh DB + wp config create + install.php"
t wp db reset --yes >/dev/null
t bash -c 'rm -f /var/www/html/wp-config.php'
t wp config create --dbname=tests-wordpress --dbuser=root --dbpass=password --dbhost=tests-mysql --force 2>&1 | tail -1
echo "config_created=$(t bash -c '[ -f /var/www/html/wp-config.php ] && echo yes || echo no')"
echo "install_php_http=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/wp-admin/install.php")"
INSTFORM=$(curl -sL "$URL/wp-admin/install.php" | grep -oiE "Site Title|Username|Your Email|weblog_title|user_login" | sort -u | tr '\n' ',')
echo "install_form_fields=[$INSTFORM]"
t wp core install --url="$URL" --title="Manual Install" --admin_user=manualadmin --admin_password=password \
     --admin_email=manual@example.com --skip-email 2>&1 | tail -1
echo "version=$(t wp core version) frontend=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/")"
echo "admin_user=$(t wp user get 1 --field=user_login)"

sec "C. USERS — create / edit / delete"
UID1=$(t wp user create testeditor editor@example.com --role=editor --user_pass=password --porcelain)
echo "created id=$UID1 login=$(t wp user get $UID1 --field=user_login) role=$(t wp user get $UID1 --field=roles) email=$(t wp user get $UID1 --field=user_email)"
t wp user update $UID1 --display_name="Edited Editor" --user_email=edited@example.com --role=author >/dev/null 2>&1
echo "edited display=$(t wp user get $UID1 --field=display_name) email=$(t wp user get $UID1 --field=user_email) role=$(t wp user get $UID1 --field=roles)"
t wp user add-role $UID1 contributor >/dev/null 2>&1
echo "roles_after_add=$(t wp user get $UID1 --field=roles)"
echo "can_edit_posts=$(t wp eval "echo user_can($UID1,'edit_posts')?'yes':'no';")"
echo "login_works=$(t wp eval "\$u=wp_authenticate('testeditor','password'); echo is_wp_error(\$u)?'FAIL:'.\$u->get_error_code():'authenticated';")"
# reassign-on-delete behaviour
RPID=$(t wp post create --post_title="Owned by editor" --post_author=$UID1 --post_status=publish --porcelain)
UID2=$(t wp user create keeper keeper@example.com --role=editor --user_pass=password --porcelain)
t wp user delete $UID1 --reassign=$UID2 --yes >/dev/null 2>&1
echo "deleted user exists=$(t wp user get $UID1 --field=ID 2>/dev/null || echo gone)"
echo "post_reassigned_to=$(t wp post get $RPID --field=post_author) (expected $UID2)"
echo "user_count=$(t wp user list --format=count)"

sec "D. PAGES — create / edit / publish / unpublish (deactivate) / trash / restore / delete"
PID=$(t wp post create --post_type=page --post_title="Lifecycle Page" --post_content="page-marker-v1" --post_status=draft --porcelain)
echo "created id=$PID status=$(t wp post get $PID --field=post_status)"
echo "draft_not_public=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/?page_id=$PID")"
t wp post update $PID --post_title="Lifecycle Page edited" --post_content="page-marker-v2" >/dev/null
echo "edited title=$(t wp post get $PID --field=post_title)"
t wp post update $PID --post_status=publish >/dev/null
echo "published status=$(t wp post get $PID --field=post_status) http=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/?page_id=$PID")"
echo "content_live=$(curl -sL "$URL/?page_id=$PID" | grep -c 'page-marker-v2')"
t wp post update $PID --post_status=draft >/dev/null
echo "deactivated(unpublished) status=$(t wp post get $PID --field=post_status) http=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/?page_id=$PID")"
t wp post update $PID --post_status=private >/dev/null
echo "private status=$(t wp post get $PID --field=post_status) anon_http=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/?page_id=$PID")"
t wp post delete $PID >/dev/null
echo "trashed status=$(t wp post get $PID --field=post_status)"
t wp post update $PID --post_status=publish >/dev/null 2>&1
echo "restored status=$(t wp post get $PID --field=post_status)"
t wp post delete $PID --force >/dev/null
echo "force_deleted=$(t wp post get $PID --field=ID 2>/dev/null || echo gone)"

sec "E. UPDATE POST / UPDATE PAGE — content, meta, revisions"
UPOST=$(t wp post create --post_title="Update target post" --post_content="v1-body" --post_status=publish --porcelain)
UPAGE=$(t wp post create --post_type=page --post_title="Update target page" --post_content="v1-body" --post_status=publish --porcelain)
for i in 2 3; do
  t wp post update $UPOST --post_title="Update target post v$i" --post_content="v$i-body" >/dev/null
  t wp post update $UPAGE --post_title="Update target page v$i" --post_content="v$i-body" >/dev/null
done
echo "post  title=$(t wp post get $UPOST --field=post_title) revisions=$(t wp post list --post_type=revision --post_parent=$UPOST --format=count)"
echo "page  title=$(t wp post get $UPAGE --field=post_title) revisions=$(t wp post list --post_type=revision --post_parent=$UPAGE --format=count)"
echo "post_live_v3=$(curl -sL "$URL/?p=$UPOST" | grep -c 'v3-body')  page_live_v3=$(curl -sL "$URL/?page_id=$UPAGE" | grep -c 'v3-body')"
echo "stale_v1_gone_post=$(curl -sL "$URL/?p=$UPOST" | grep -c 'v1-body')"
t wp post meta update $UPOST test_meta "meta-value-1" >/dev/null
echo "meta_set=$(t wp post meta get $UPOST test_meta)"
t wp post meta update $UPOST test_meta "meta-value-2" >/dev/null
echo "meta_updated=$(t wp post meta get $UPOST test_meta)"
echo "modified_changed=$(t wp eval "\$p=get_post($UPOST); echo (\$p->post_modified > \$p->post_date)?'yes':'same';")"

sec "F. PASSWORD-PROTECTED CONTENT + PASSWORD-PROTECTED SITE"
PP=$(t wp post create --post_type=page --post_title="Protected page" --post_content="secret-body-marker" --post_status=publish --porcelain)
t wp post update $PP --post_password="hunter2" >/dev/null
echo "post_password_set=$(t wp post get $PP --field=post_password)"
echo "post_status=$(t wp post get $PP --field=post_status) (stays publish; protection is via password)"
ANON=$(curl -sL "$URL/?page_id=$PP")
echo "anon_sees_secret=$(echo "$ANON" | grep -c 'secret-body-marker')  (expect 0)"
echo "anon_gets_password_form=$(echo "$ANON" | grep -ciE 'post-password-form|password-protected|Enter your password|type=.password.')"
echo "title_shows_protected=$(echo "$ANON" | grep -ciE 'Protected:')"
# submit the password the way the core form does, then re-request
CJ=/tmp/pwcookies.txt; rm -f $CJ
curl -s -c $CJ -o /dev/null -X POST -d "post_password=hunter2" "$URL/wp-login.php?action=postpass"
AFTER=$(curl -sL -b $CJ "$URL/?page_id=$PP")
echo "after_password_sees_secret=$(echo "$AFTER" | grep -c 'secret-body-marker')  (expect 1)"
echo "wrong_password_blocked=$(curl -s -o /dev/null -X POST -d 'post_password=wrongpw' "$URL/wp-login.php?action=postpass"; curl -sL "$URL/?page_id=$PP" | grep -c 'secret-body-marker')  (expect 0)"
echo "protected_in_feed=$(curl -sL "$URL/?feed=rss2" | grep -c 'secret-body-marker')  (expect 0)"
echo "protected_in_search=$(curl -sL "$URL/?s=secret-body-marker" | grep -c 'secret-body-marker')  (expect 0)"
echo "protected_via_rest=$(curl -s "$URL/wp-json/wp/v2/pages/$PP" | grep -c 'secret-body-marker')  (expect 0)"
# site-level: discourage search engines + private-site behaviour
t wp option update blog_public 0 >/dev/null
echo "site_blog_public=$(t wp option get blog_public) robots=$(curl -s "$URL/robots.txt" | grep -ciE 'Disallow: /')"
t wp option update blog_public 1 >/dev/null
t wp post delete $PP --force >/dev/null

sec "SUMMARY"
echo "frontend=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/")"
echo "fatal_scan=$(curl -sL "$URL/" | grep -ciE 'fatal error|parse error')"
echo "db_check=$(t wp db check | tail -1)"
