#!/bin/bash
# Multisite suite at realistic scale: 1 top-level site + 10 subsites.
#
# Deliberately builds the network on the PREVIOUS release and upgrades it, because
# several historical multisite bugs only reproduce on a network that was UPGRADED
# rather than freshly created.
#
# Usage: multisite-11.sh <project-dir> <network-url> [subdir|subdomain] [from-version]

PROJ="$1"; URL="$2"; MODE="${3:-subdir}"; FROM="${4:-7.0.2}"
TARGET="${TARGET_ZIP:-https://wordpress.org/wordpress-7.1-beta4.zip}"
SUBS="alpha beta gamma delta epsilon zeta eta theta iota kappa"   # 10 subsites
cd "$PROJ" || exit 1

# Runs against the container directly rather than through `npx @wordpress/env run`.
# npx costs ~1.4s of node startup per call; docker exec costs ~0.12s. This script
# makes ~150 WP-CLI calls in a full pass, so that is ~3.5 minutes of pure overhead
# versus ~18 seconds. Container must already be up (`wp-env start` once).
CONTAINER=$(docker ps --format '{{.Names}}' \
  | grep -E "^wp-env-$(basename "$PROJ")-[a-f0-9]+-tests-cli-1$" | head -1)
if [ -z "$CONTAINER" ]; then
  echo "No running tests-cli container for $(basename "$PROJ")." >&2
  echo "Start it first:  (cd $PROJ && npx @wordpress/env start)" >&2
  exit 1
fi
echo "using container: $CONTAINER"
t() { docker exec -u 33 "$CONTAINER" "$@" 2>/dev/null | tr -d '\r' | sed '/^$/d'; }
sec() { echo; echo "════ $1"; }

sec "SETUP — clean docroot, install $FROM, build an 11-site network [$MODE]"
# ORDER MATTERS. `wp config delete` needs a working WordPress to run, so it must
# happen BEFORE wp-admin/wp-includes are removed — otherwise the constants are
# never cleared, the later multisite-install lands on a half-configured site, and
# every wp-cli call afterwards returns "The site you have requested is not
# installed" while HTTP still answers 200. That combination reads like a core bug.
for C in WP_ALLOW_MULTISITE MULTISITE SUBDOMAIN_INSTALL DOMAIN_CURRENT_SITE PATH_CURRENT_SITE SITE_ID_CURRENT_SITE; do
  t wp config delete "$C" >/dev/null 2>&1
done
t wp db reset --yes >/dev/null 2>&1
# core download --force overwrites but never deletes: stale bundled themes across
# versions produce fatals that look like upgrade bugs. Wipe first.
t bash -c 'rm -rf /var/www/html/wp-admin /var/www/html/wp-includes /var/www/html/wp-content/themes/*' >/dev/null 2>&1
t php -d memory_limit=1024M /usr/local/bin/wp core download --version="$FROM" --force --allow-root >/dev/null 2>&1
t bash -c 'rm -rf /var/www/html/wp-content/themes/twentytwentytwo' >/dev/null 2>&1

SD=""; [ "$MODE" = "subdomain" ] && SD="--subdomains"
t wp core multisite-install $SD --url="$URL" --title="MU11" --admin_user=admin \
     --admin_password=password --admin_email=admin@example.com --skip-email 2>&1 | tail -1
echo "  version=$(t wp core version)  is_multisite=$(t wp eval 'echo is_multisite()?"yes":"no";')"
echo "  subdomain_install=$(t wp eval 'echo (defined("SUBDOMAIN_INSTALL")&&SUBDOMAIN_INSTALL)?"yes":"no";')"

i=0
for s in $SUBS; do
  i=$((i+1))
  t wp site create --slug="$s" --title="Site $s" >/dev/null 2>&1
done
echo "  sites in network: $(t wp site list --format=count)  (expect 11)"

sec "SEED — content + a user on every subsite"
suburl() { if [ "$MODE" = "subdomain" ]; then echo "http://$1.localhost:9876/"; else echo "$URL/$1/"; fi; }
for s in $SUBS; do
  U=$(suburl "$s")
  t wp post create --url="$U" --post_title="Post on $s" --post_content="MARKER-$s" --post_status=publish >/dev/null 2>&1
  t wp post create --url="$U" --post_type=page --post_title="Page on $s" --post_status=publish >/dev/null 2>&1
done
NU=$(t wp user create netuser netuser@example.com --role=author --user_pass=password --porcelain 2>/dev/null | tail -1)
t wp user set-role "$NU" editor --url="$(suburl alpha)" >/dev/null 2>&1
echo "  seeded 2 posts per subsite; network user id=$NU (editor on alpha only)"

sec "ISOLATION — content must not bleed between subsites"
AU=$(suburl alpha); BU=$(suburl beta)
echo "  alpha posts=$(t wp post list --url="$AU" --format=count)  beta posts=$(t wp post list --url="$BU" --format=count)"
echo "  beta contains alpha marker (DB) = $(t wp post list --url="$BU" --format=csv --fields=post_content 2>/dev/null | grep -c 'MARKER-alpha')   (expect 0)"
echo "  separate tables: $(t wp db tables --url="$AU" --all-tables 2>/dev/null | grep -cE '_[0-9]+_posts') per-site posts tables"
echo "  role on alpha=$(t wp user get "$NU" --field=roles --url="$AU" 2>/dev/null)  role on beta=$(t wp user get "$NU" --field=roles --url="$BU" 2>/dev/null)  (beta expect empty)"

sec "SWITCH_TO_BLOG — global/cache leakage across all 11 sites"
t wp eval '
$ids = get_sites(array("fields" => "ids", "number" => 100));
$fail = 0;
$home = home_url();
foreach ($ids as $id) {
    switch_to_blog($id);
    $u = home_url();
    $p = $GLOBALS["wpdb"]->prefix;
    if (1 !== (int) $id && false === strpos($p, "_" . $id . "_")) { echo "  !! prefix wrong on blog $id: $p\n"; $fail++; }
    restore_current_blog();
    if (home_url() !== $home) { echo "  !! home_url not restored after blog $id\n"; $fail++; }
}
echo "  switch/restore across " . count($ids) . " sites: " . ($fail ? "$fail FAILURES" : "clean") . "\n";
echo "  final prefix=" . $GLOBALS["wpdb"]->prefix . " (expect base)\n";
'

sec "CAPABILITY ASYMMETRY — the multisite security boundary"
# On multisite ONLY super admins hold unfiltered_html, so kses IS the privilege
# boundary. Any XSS finding dismissed with "that role already has unfiltered_html"
# must be re-judged here: on a network it's a subsite-admin -> super-admin escalation.
AU0=$(suburl alpha)
t wp user create subadmin sa@example.test --role=administrator --url="$AU0" --user_pass=password >/dev/null 2>&1
t wp user create subeditor se@example.test --role=editor --url="$AU0" --user_pass=password >/dev/null 2>&1
t wp eval --url="$AU0" '
foreach (array("admin"=>"super admin","subadmin"=>"subsite administrator","subeditor"=>"subsite editor") as $l=>$label) {
    $u = get_user_by("login", $l);
    if (!$u) { printf("  %-24s (missing)\n", $label); continue; }
    printf("  %-24s unfiltered_html=%s\n", $label, user_can($u, "unfiltered_html") ? "YES" : "no");
}
echo "  expected: super admin YES, subsite admin/editor no\n";
'

sec "OBJECT INJECTION GUARD (CVE-2022-21663 regression check)"
# upgrade_280() loops every option on multisite; it must use maybe_unserialize(),
# and is_serialized() must reject C:-prefixed custom-deserialization payloads.
# Trigger needs no old network — a super admin can force db_version below 10360.
t wp eval '
printf("  is_serialized(C: payload) = %s   (expect false)\n",
    var_export(is_serialized("C:11:\"ArrayObject\":21:{x:i:0;a:0:{};m:a:0:{}}"), true));
$src = file_get_contents(ABSPATH . "wp-admin/includes/upgrade.php");
preg_match("/function upgrade_280.*?\n\}/s", $src, $m);
echo "  upgrade_280 uses maybe_unserialize: " . (isset($m[0]) && strpos($m[0], "maybe_unserialize") !== false ? "YES (fixed)" : "NO — VULNERABLE") . "\n";
'

sec "MULTISITE REGRESSION GUARDS (bugs that shipped 2021-2026)"
t wp eval '
// #60290 — get_template_directory() must follow switch_to_blog(). Broken 6.4.2-6.4.4:
// the fix for #59847 removed the memoization that also carried the multisite handling.
$main = get_template_directory(); $bad = 0;
foreach (get_sites(array("fields"=>"ids","number"=>5)) as $id) {
    switch_to_blog($id);
    if (basename(get_template_directory()) !== get_option("template")) { $bad++; }
    restore_current_blog();
}
printf("  #60290 template dir follows switch_to_blog: %s (wp_set_template_globals: %s)\n",
    $bad ? "$bad MISMATCH" : "correct", function_exists("wp_set_template_globals") ? "present" : "MISSING");
printf("  #60290 restored to main afterwards: %s\n", get_template_directory() === $main ? "yes" : "NO");

// #61146 — marking a network user as spam must NOT spam every site they belong to.
// Fixed 7.0 behind a filter defaulting to false. NOTE: the commit message advertises
// network_user_spam_propagate_to_blogs; the CODE registers propagate_network_user_spam_to_blogs.
$u = file_get_contents(ABSPATH . "wp-admin/network/users.php");
preg_match("/apply_filters\(\s*.propagate_network_user_spam_to_blogs.,\s*(\w+)/", $u, $m);
printf("  #61146 spam-propagation filter default: %s (expect false)\n", $m[1] ?? "NOT FOUND");

// #55926 — blank fileupload_maxk was int * string => TypeError on PHP 8. Fixed 6.1.
update_site_option("fileupload_maxk", "");
$lim = apply_filters("upload_size_limit", wp_max_upload_size());
printf("  #55926 blank fileupload_maxk handled: %s (no TypeError)\n", var_export($lim, true));
update_site_option("fileupload_maxk", 1500);

// #55462 — WP_Site_Query cache key must ignore cache-control args. Fixed 6.0.
$q = file_get_contents(ABSPATH . "wp-includes/class-wp-site-query.php");
printf("  #55462 site-query cache key ignores update_site_cache: %s\n",
    preg_match("/unset\(\s*\\\$_args\[.fields.\][^;]*update_site_cache/", $q) ? "yes" : "NO");

// #63104 — ms-files.php must guard BLOGUPLOADDIR before rtrim(). Fixed 6.9.
$f = file_get_contents(ABSPATH . "wp-includes/ms-files.php");
printf("  #63104 BLOGUPLOADDIR guarded before use: %s\n", strpos($f, "defined( \x27BLOGUPLOADDIR\x27 )") !== false ? "yes" : "NO");
// #63285 — and it must NOT call is_super_admin() under SHORTINIT. Shipped broken in 6.8.
printf("  #63285 ms-files.php free of is_super_admin(): %s\n", strpos($f, "is_super_admin") === false ? "yes" : "NO — REGRESSION");
'

sec "UPGRADE-MACHINERY GUARDS + known-open items"
t wp eval '
$up = file_get_contents(ABSPATH . "wp-admin/includes/upgrade.php");

// #64005 — dbDelta compared Non_unique with === against a string. Under DB layers
// that return native ints (mysqli INT_AND_FLOAT_NATIVE, or a db.php drop-in like
// HyperDB/LudicrousDB/SQLite) every UNIQUE KEY looked missing, so dbDelta emitted a
// duplicate ADD UNIQUE KEY per site, per upgrade. Broke 6.7.0-6.8.6; fixed 6.9.
printf("  #64005 dbDelta Non_unique cast to string: %s\n",
    strpos($up, "(string) \$tableindex->Non_unique") !== false ? "yes (fixed)" : "NO — REGRESSION");

// Sibling defect from the same changeset, inside upgrade_network() itself. Still
// unfixed in trunk. Impact is bounded: the guard is $wp_current_db_version < 33055,
// so only networks upgrading from pre-4.3 run it, and the redundant DROP/ADD INDEX
// on wp_signups succeeds rather than erroring. Track, do not panic.
printf("  upgrade_network Sub_part strict compare: %s\n",
    strpos($up, "\x27140\x27 !== \$index->Sub_part") !== false ? "PRESENT (known open, low impact)" : "changed — recheck");

// 6.9 widened a guard pinned at 25448 since 2013 up to 60497, re-arming 9 blocking
// ALTER TABLEs on wp_blogs/wp_signups/wp_sitemeta for every network. Those are the
// tables that are huge on large networks — a timeout regression would surface here.
// NOTE: several guards match "< N && is_multisite()"; take the LAST (highest) one,
// which is the currently-armed threshold, not the 2013-era 14139/25448 leftovers.
preg_match_all("/wp_current_db_version < (\d+) && is_multisite\(\)/", $up, $mm);
printf("  pre_schema_upgrade global-table ALTER guard: %s (all: %s)\n",
    $mm[1] ? max(array_map("intval", $mm[1])) : "not found",
    $mm[1] ? implode(",", $mm[1]) : "-");
'
t wp eval '
// wp_get_plugin_action_button() decides "are this plugin\x27s dependencies satisfied?"
// from get_option("active_plugins") alone. It never reads active_sitewide_plugins,
// so a NETWORK-ACTIVATED dependency reads as inactive on Add Plugins. Present 6.5-7.1.
$pi = file_get_contents(ABSPATH . "wp-admin/includes/plugin-install.php");
printf("  plugin dependency check reads active_sitewide_plugins: %s\n",
    strpos($pi, "active_sitewide_plugins") !== false ? "yes" : "NO — network-activated deps read as inactive");
'
t wp eval '
// populate_network_meta() writes upload_filetypes ONLY at network creation. When core
// adds a format to the default list (avif in 6.5, heic later), existing networks keep
// their stored list and silently reject the new type. No migration exists.
$ft = get_site_option("upload_filetypes");
$missing = array();
foreach (array("avif","webp","heic") as $e) { if (false === strpos(" $ft ", " $e ")) { $missing[] = $e; } }
printf("  network upload_filetypes covers modern formats: %s\n",
    $missing ? "NO — missing: " . implode(",", $missing) . " (upgraded-network trap)" : "yes");
'

sec "SITE FLAGS — archived / spam / deleted / mature"
t wp site archive 3 >/dev/null 2>&1; t wp site spam 4 >/dev/null 2>&1
echo "  archived id3 -> http $(curl -s -o /dev/null -w '%{http_code}' -L "$(suburl beta)")"
echo "  spammed  id4 -> http $(curl -s -o /dev/null -w '%{http_code}' -L "$(suburl gamma)")"
t wp site unarchive 3 >/dev/null 2>&1; t wp site unspam 4 >/dev/null 2>&1
echo "  restored -> beta $(curl -s -o /dev/null -w '%{http_code}' -L "$(suburl beta)")  gamma $(curl -s -o /dev/null -w '%{http_code}' -L "$(suburl gamma)")"

sec "NETWORK PLUGIN/THEME activation across the network"
t wp plugin install classic-editor --version=1.7.0 >/dev/null 2>&1
t wp plugin activate classic-editor --network >/dev/null 2>&1
echo "  network status=$(t wp plugin list --name=classic-editor --field=status)"
echo "  seen active on 3 random subsites: $(for s in delta theta kappa; do t wp plugin list --name=classic-editor --field=status --url="$(suburl $s)" 2>/dev/null; done | tr '\n' ' ')"

sec "UPLOAD QUOTA (multisite-only code path)"
# NOTE: networks ship with upload_space_check_disabled = 1, so enforcement is OFF
# by default and a naive run never exercises the reject branch. Force it on, test
# both branches, then restore. check_upload_size() is a no-op on single-site, so
# this is the ONLY place its logic can be tested at all.
AU1=$(suburl alpha)
t wp eval '
echo "  defaults: check_disabled=" . var_export(get_site_option("upload_space_check_disabled"), true)
   . " blog_upload_space=" . get_site_option("blog_upload_space", "(unset)")
   . " fileupload_maxk=" . get_site_option("fileupload_maxk", "(unset)") . "\n";
update_site_option("upload_space_check_disabled", 0);
update_site_option("blog_upload_space", 1);
update_site_option("fileupload_maxk", 50);
'
t bash -c 'php -r "\$i=imagecreatetruecolor(3000,2400); for(\$x=0;\$x<3000;\$x+=3){ imagefilledrectangle(\$i,\$x,0,\$x+1,2400, imagecolorallocate(\$i, rand(0,255), rand(0,255), rand(0,255))); } imagejpeg(\$i,\"/var/www/html/q-big.jpg\",100);
\$s=imagecreatetruecolor(200,150); imagejpeg(\$s,\"/var/www/html/q-small.jpg\",70);"' >/dev/null 2>&1
t wp eval --url="$AU1" '
wp_set_current_user(1);
require_once ABSPATH . "wp-admin/includes/ms.php";
echo "  space_available=" . get_upload_space_available() . " bytes  over_quota=" . var_export(upload_is_user_over_quota(false), true) . "\n";
$c = new WP_REST_Attachments_Controller("attachment");
$m = new ReflectionMethod($c, "check_upload_size"); $m->setAccessible(true);
foreach (array("q-big.jpg" => "oversized", "q-small.jpg" => "under cap") as $f => $label) {
    $r = $m->invoke($c, array("name" => $f, "tmp_name" => "/var/www/html/" . $f));
    printf("  %-10s => %s\n", $label, is_wp_error($r) ? "REJECTED (" . $r->get_error_code() . ")" : "allowed");
}
'
t wp eval 'update_site_option("upload_space_check_disabled", 1); update_site_option("blog_upload_space", 100); update_site_option("fileupload_maxk", 1500);' >/dev/null 2>&1
t bash -c 'rm -f /var/www/html/q-big.jpg /var/www/html/q-small.jpg' >/dev/null 2>&1
echo "  (quota settings restored)"

sec "NETWORK UPGRADE — $FROM -> target across all 11 sites"
echo "  before: version=$(t wp core version) db=$(t wp option get db_version) sites=$(t wp site list --format=count)"
t wp core update "$TARGET" --force 2>&1 | tail -1
t wp core update-db --network 2>&1 | tail -2
echo "  after:  version=$(t wp core version) db=$(t wp option get db_version)"

sec "POST-UPGRADE — every site must be healthy and keep its content"
FAIL=0
printf "  %-10s %-6s %-6s %-8s\n" SITE HTTP POSTS DB_VERSION
for s in main $SUBS; do
  if [ "$s" = "main" ]; then U="$URL/"; else U=$(suburl "$s"); fi
  H=$(curl -s -o /dev/null -w '%{http_code}' -L "$U")
  P=$(t wp post list --url="$U" --format=count 2>/dev/null)
  D=$(t wp option get db_version --url="$U" 2>/dev/null)
  printf "  %-10s %-6s %-6s %-8s\n" "$s" "$H" "$P" "$D"
  [ "$H" != "200" ] && FAIL=$((FAIL+1))
done
echo "  network admin: $(curl -s -o /dev/null -w '%{http_code}' -L "$URL/wp-admin/network/")"
echo "  sites still in network: $(t wp site list --format=count)"
echo "  frontend fatals: $(curl -sL "$URL/" | grep -ciE 'fatal error|parse error')"
echo "  db check: $(t wp db check 2>/dev/null | tail -1)"
echo "  RESULT: $([ $FAIL -eq 0 ] && echo 'PASS — all 11 sites healthy' || echo "FAIL — $FAIL sites not 200")"

sec "SITE DELETION — remove a subsite, confirm tables go with it"
BEFORE=$(t wp db tables --all-tables 2>/dev/null | grep -cE '_[0-9]+_posts')
t wp site delete 11 --yes >/dev/null 2>&1
AFTER=$(t wp db tables --all-tables 2>/dev/null | grep -cE '_[0-9]+_posts')
echo "  per-site posts tables: $BEFORE -> $AFTER (expect one fewer)"
echo "  sites remaining: $(t wp site list --format=count)"
