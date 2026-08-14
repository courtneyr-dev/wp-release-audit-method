#!/bin/bash
# Multisite (MU) suite: multi-subsite network, CRUD per subsite, network users,
# network plugin/theme activation, and a network upgrade with several sites.
# Target build: --target=<zip-url> anywhere in the args, or WP_AUDIT_TARGET
# (explicit flag wins). Default unchanged — a suite never picks its own target.
_FLAG=""; _ARGS=()
for _a in "$@"; do case "$_a" in --target=*) _FLAG="${_a#--target=}" ;; *) _ARGS+=("$_a") ;; esac; done
# Restore the stripped args as positionals: array INDEXING differs between
# bash (0-based) and zsh (1-based), positionals do not.
set -- "${_ARGS[@]}"
PROJ="$1"; URL="$2"; MODE="${3:-subdir}"
TARGET="${_FLAG:-${WP_AUDIT_TARGET:-https://wordpress.org/wordpress-7.1-beta4.zip}}"
TARGET_VER="$(basename "$TARGET" .zip | sed 's/^wordpress-//')"
cd "$PROJ" || exit 1
t() { npx --yes @wordpress/env@latest run tests-cli -- "$@" 2>/dev/null | grep -vE "^(ℹ|✔|npm warn)" | tr -d '\r' | sed '/^$/d'; }
sec() { echo; echo "======== $1"; }

sec "MU SETUP — install 7.0.2 network [$MODE], then add subsites"
t wp db reset --yes >/dev/null
t php -d memory_limit=1024M /usr/local/bin/wp core download --version=7.0.2 --force --allow-root >/dev/null 2>&1
SD=""; [ "$MODE" = "subdomain" ] && SD="--subdomains"
t wp core multisite-install $SD --url="$URL" --title="MU Network" --admin_user=admin \
     --admin_password=password --admin_email=admin@example.com --skip-email 2>&1 | tail -1
echo "is_multisite=$(t wp eval 'echo is_multisite()?"yes":"no";')"
echo "subdomain_install=$(t wp eval 'echo (defined("SUBDOMAIN_INSTALL") && SUBDOMAIN_INSTALL)?"yes":"no";')"

for s in alpha beta gamma; do
  if [ "$MODE" = "subdomain" ]; then
    t wp site create --slug=$s --title="Site $s" >/dev/null 2>&1
  else
    t wp site create --slug=$s --title="Site $s" >/dev/null 2>&1
  fi
done
echo "sites_in_network=$(t wp site list --format=count)"
t wp site list --fields=blog_id,url,registered 2>/dev/null | head -6

sec "MU CRUD — content per subsite (isolation check)"
# NOTE: `wp site list --slug=` does NOT filter — it returns nothing and older
# versions of this script silently fell back to the MAIN site, which produced a
# false "isolation failure". Always build the subsite URL from $URL + slug.
for s in alpha beta; do
  SURL="$URL/$s/"
  PID=$(t wp post create --url="$SURL" --post_title="Post on $s" --post_content="marker-$s" --post_status=publish --porcelain 2>/dev/null)
  PGID=$(t wp post create --url="$SURL" --post_type=page --post_title="Page on $s" --post_status=publish --porcelain 2>/dev/null)
  echo "site=$s url=$SURL post=$PID page=$PGID posts=$(t wp post list --url="$SURL" --format=count 2>/dev/null)"
done
# isolation: alpha's marker must not appear on beta
AU="$URL/alpha/"
BU="$URL/beta/"
echo "alpha_posts=$(t wp post list --url="$AU" --format=count 2>/dev/null) beta_posts=$(t wp post list --url="$BU" --format=count 2>/dev/null)"
echo "isolation_beta_has_alpha_marker=$(t wp post list --url="$BU" --format=csv --fields=post_title 2>/dev/null | grep -c 'alpha')  (expect 0)"

sec "MU USERS — network user, per-site roles, super admin"
NU=$(t wp user create netuser netuser@example.com --role=author --user_pass=password --porcelain 2>/dev/null)
echo "network_user_id=$NU"
t wp user set-role $NU editor --url="$AU" >/dev/null 2>&1
echo "role_on_alpha=$(t wp user get $NU --field=roles --url="$AU" 2>/dev/null)"
echo "role_on_beta=$(t wp user get $NU --field=roles --url="$BU" 2>/dev/null)  (expect empty/none = not a member)"
t wp super-admin add netuser >/dev/null 2>&1
echo "super_admins=$(t wp super-admin list 2>/dev/null | tr '\n' ',')"
t wp super-admin remove netuser >/dev/null 2>&1
echo "after_remove_super=$(t wp super-admin list 2>/dev/null | tr '\n' ',')"
t wp user delete $NU --network --yes >/dev/null 2>&1
echo "user_deleted=$(t wp user get $NU --field=ID 2>/dev/null || echo gone)"

sec "MU PLUGINS/THEMES — network activation"
t wp plugin install classic-editor --version=1.6.2 >/dev/null 2>&1
t wp plugin activate classic-editor --network >/dev/null 2>&1
echo "network_active=$(t wp plugin list --name=classic-editor --field=status 2>/dev/null)"
echo "active_on_alpha=$(t wp plugin list --name=classic-editor --field=status --url="$AU" 2>/dev/null)"
t wp theme enable twentytwentyfour --network >/dev/null 2>&1
echo "theme_enabled_network=$(t wp theme list --field=name --status=active 2>/dev/null | head -1)"

sec "MU NETWORK UPGRADE — 7.0.2 -> $TARGET_VER across all sites"
echo "before_version=$(t wp core version)  sites=$(t wp site list --format=count)"
t wp core update "$TARGET" --force 2>&1 | tail -1
t wp core update-db --network 2>&1 | tail -2
echo "after_version=$(t wp core version)  db=$(t wp option get db_version)"
echo "network_frontend=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/")"
for s in alpha beta gamma; do
  SU="$URL/$s/"
  echo "  subsite $s url=$SU http=$(curl -s -o /dev/null -w '%{http_code}' -L "$SU") posts=$(t wp post list --url="$SU" --format=count 2>/dev/null)"
done
echo "network_admin_http=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/wp-admin/network/")"
echo "fatal_scan=$(curl -sL "$URL/" | grep -ciE 'fatal error|parse error')"
echo "db_check=$(t wp db check 2>/dev/null | tail -1)"

sec "MU PASSWORD-PROTECTED CONTENT on a subsite"
PP=$(t wp post create --url="$AU" --post_type=page --post_title="MU protected" --post_content="mu-secret-marker" --post_status=publish --porcelain 2>/dev/null)
t wp post update $PP --url="$AU" --post_password="hunter2" >/dev/null 2>&1
echo "password_set=$(t wp post get $PP --url="$AU" --field=post_password 2>/dev/null)"
echo "anon_sees_secret=$(curl -sL "$AU?page_id=$PP" | grep -c 'mu-secret-marker')  (expect 0)"
echo "password_form_shown=$(curl -sL "$AU?page_id=$PP" | grep -ciE 'post-password-form|type=.password.')"
