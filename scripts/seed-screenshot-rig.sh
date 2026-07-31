#!/usr/bin/env bash
# Seed a Studio cell into a publishable screenshot / label-verification rig.
#
# Why this exists: a bare WordPress install produces unpublishable screenshots and
# unreliable captures. Every step below traces to a specific failure recorded in
# "WP 7.1 screenshot pass — learnings":
#   - placeholder content ("Hello world!", admin named "admin") looks like a test site
#   - deleting Sample Page WITHOUT replacements broke the header Page List block and
#     put an error notice in frame -> create replacements first, delete after, re-verify
#   - editor state (welcome guides, sidebar, panel open/closed) persists server-side in
#     wp_persisted_preferences, so one stray toggle silently changes every later capture
#   - Notes / @mentions and multi-user scenarios need real collaborator accounts
#
# Usage:  ./seed-screenshot-rig.sh [studio-site-dir]     (default: wp-71-screenshots)
# Safe to re-run: every step is idempotent.

set -uo pipefail

SITE_DIR="${1:-$HOME/Studio/wp-71-screenshots}"
[ -d "$SITE_DIR" ] || { echo "No such Studio site: $SITE_DIR"; exit 1; }
cd "$SITE_DIR" || exit 1

export NO_COLOR=1
# Studio CLI prints spinner + daemon chatter on stdout; strip it or it lands in your data.
strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g;s/\x1b\]8;;[^\x07]*\x07//g' \
        | grep -viE "loading sites|connecting to|found [0-9]+ site|connected to|^[[:space:]]*$"; }
w() { studio wp "$@" 2>&1 | strip; }

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }

say "Rig: $SITE_DIR"
w core version | tail -1

# ---------------------------------------------------------------- identity
say "1. Site identity"
w option update blogname "Ridgeline Cabins" >/dev/null
w option update blogdescription "Four seasons in the high country" >/dev/null
# Fictional persona on purpose — published screenshots shouldn't carry your real
# name or address. Change it if you want the shots attributed to you.
w user update 1 --display_name="Rowan Ellis" --first_name="Rowan" \
    --last_name="Ellis" --user_email="rowan@ridgelinecabins.test" >/dev/null
echo "   blogname   : $(w option get blogname | tail -1)"
echo "   admin name : $(w user get 1 --field=display_name | tail -1)"

# ---------------------------------------------------------------- collaborators
# Needed for Notes, @mentions, and any multi-user editor scenario. Real-looking
# names matter: "user2" in a mention dropdown is a giveaway in a published shot.
say "2. Collaborator accounts"
seed_user() { # login email role display first last
  if w user get "$1" --field=ID >/dev/null 2>&1 && [ -n "$(w user get "$1" --field=ID | tail -1)" ]; then
    echo "   exists   : $1"
  else
    w user create "$1" "$2" --role="$3" --display_name="$4" --first_name="$5" \
        --last_name="$6" --porcelain >/dev/null && echo "   created  : $1 ($3)"
  fi
}
seed_user maya   maya@ridgelinecabins.test   editor "Maya Okonkwo"  Maya  Okonkwo
seed_user devin  devin@ridgelinecabins.test  author "Devin Alvarez" Devin Alvarez
seed_user harper harper@ridgelinecabins.test editor "Harper Singh"  Harper Singh

# ---------------------------------------------------------------- media
# Generated in-site with GD (this cell is deliberately GD-only, no Imagick), so the
# rig needs no network and no binary assets checked into the vault.
say "3. Media library"
# NOTE: `wp eval` takes NO positional arguments — it errors with "Too many positional
# arguments". Values must be interpolated into the code string. (Cost one silent
# failure the first time: the errors went to /dev/null and media stayed empty while
# every other step reported success.)
gen_image() { # filename width height r g b label
  local f=$1 wd=$2 ht=$3 r=$4 g=$5 b=$6 label=$7
  w eval "
    \$path = trailingslashit( wp_upload_dir()['path'] ) . '$f';
    if ( file_exists(\$path) ) { echo 'exists'; return; }
    \$im = imagecreatetruecolor($wd,$ht);
    for ( \$y = 0; \$y < $ht; \$y++ ) {          // vertical gradient, dark enough for AA-safe white text
      \$t = \$y / $ht;
      \$c = imagecolorallocate( \$im, (int)($r*(1-\$t*0.45)), (int)($g*(1-\$t*0.45)), (int)($b*(1-\$t*0.45)) );
      imagefilledrectangle( \$im, 0, \$y, $wd, \$y, \$c );
    }
    imagestring( \$im, 5, 40, $ht-60, '$label', imagecolorallocate(\$im,255,255,255) );
    imagejpeg( \$im, \$path, 90 ); imagedestroy( \$im );
    echo file_exists(\$path) ? 'created' : 'FAILED';
  " | tail -1
}
import_media() { # filename title
  local up id result
  up=$(w eval 'echo wp_upload_dir()["path"];' | tail -1)
  if [ ! -f "$up/$1" ]; then echo "   MISSING  : $1 (generation failed)"; return 1; fi
  id=$(w eval "\$q = get_posts(['post_type'=>'attachment','title'=>'$2','fields'=>'ids','numberposts'=>1]); echo \$q ? \$q[0] : '';" | tail -1)
  if [ -n "$id" ]; then echo "   exists   : $1 (#$id)"; return 0; fi
  result=$(w media import "$up/$1" --title="$2" --porcelain | tail -1)
  case "$result" in
    ''|*[!0-9]*) echo "   FAILED   : $1 -> $result"; return 1 ;;
    *)           echo "   imported : $1 (#$result)" ;;
  esac
}
for spec in "cabin-exterior.jpg|74|103|65|Ridgeline Cabins|Cabin exterior at dusk" \
            "cabin-interior.jpg|122|84|52|The Larch Cabin|Interior, the Larch cabin" \
            "trail-map.jpg|47|82|112|Trail Map|Ridge trail map"; do
  IFS='|' read -r fn r g b label title <<< "$spec"
  echo "   generate : $fn -> $(gen_image "$fn" 1600 1000 "$r" "$g" "$b" "$label")"
  import_media "$fn" "$title"
done

# ---------------------------------------------------------------- real pages
# Created BEFORE removing Sample Page, so navigation never renders empty.
say "4. Pages"
seed_page() { # slug title content
  local id; id=$(w post list --post_type=page --name="$1" --field=ID | tail -1)
  if [ -n "$id" ]; then echo "   exists   : $1"; return; fi
  w post create --post_type=page --post_status=publish --post_name="$1" \
      --post_title="$2" --post_content="$3" --porcelain >/dev/null \
      && echo "   created  : $1"
}
seed_page home "Home" '<!-- wp:paragraph --><p>Six cabins on forty acres, open year round. Wood heat, no televisions, and a trailhead thirty steps from the porch.</p><!-- /wp:paragraph -->'
seed_page cabins "The Cabins" '<!-- wp:paragraph --><p>Each cabin sleeps two to six. Larch and Aspen have full kitchens; Fern and Sorrel share the bathhouse.</p><!-- /wp:paragraph -->'
seed_page rates "Rates &amp; Seasons" '<!-- wp:paragraph --><p>Shoulder season runs mid-April to mid-June. Winter rates include a cord of split wood.</p><!-- /wp:paragraph -->'
seed_page visiting "Visiting" '<!-- wp:paragraph --><p>Forty minutes of gravel past the last cell signal. Bring what you need; the nearest store closes at six.</p><!-- /wp:paragraph -->'

say "5. Posts with featured images"
# Look the attachment up by title, not slug: `post list --name=` does not filter
# attachments reliably. Resolve it fresh here so a re-run repairs a post that was
# created on an earlier pass before any media existed.
FEAT=$(w eval '$q = get_posts(["post_type"=>"attachment","title"=>"Interior, the Larch cabin","fields"=>"ids","numberposts"=>1]); echo $q ? $q[0] : "";' | tail -1)
seed_post() { # slug title content
  local id; id=$(w post list --post_type=post --name="$1" --field=ID | tail -1)
  if [ -z "$id" ]; then
    id=$(w post create --post_status=publish --post_name="$1" --post_title="$2" \
          --post_content="$3" --porcelain | tail -1)
    echo "   created  : $1"
  else
    echo "   exists   : $1"
  fi
  # Always reconcile the thumbnail — creation and attachment are separate concerns.
  if [ -n "$FEAT" ] && [ -n "$id" ]; then
    local cur; cur=$(w post meta get "$id" _thumbnail_id 2>/dev/null | tail -1)
    if [ "$cur" != "$FEAT" ]; then
      w post meta update "$id" _thumbnail_id "$FEAT" >/dev/null && echo "   thumb    : $1 -> #$FEAT"
    fi
  fi
}
seed_post first-snow "First snow on the ridge" '<!-- wp:paragraph --><p>It came early this year, four inches before the last guests left.</p><!-- /wp:paragraph -->'
seed_post wood-stove "How to run the wood stove" '<!-- wp:paragraph --><p>Damper open for ten minutes, then halfway. It will hold overnight if you load it at eleven.</p><!-- /wp:paragraph -->'

# Front page. Do this before touching Sample Page so nav never has a gap.
HOME_ID=$(w post list --post_type=page --name=home --field=ID | tail -1)
if [ -n "$HOME_ID" ]; then
  w option update show_on_front page >/dev/null
  w option update page_on_front "$HOME_ID" >/dev/null
  echo "   front page set to Home ($HOME_ID)"
fi

# ---------------------------------------------------------------- placeholders
say "6. Placeholder cleanup (replacements exist first)"
for slug in sample-page hello-world; do
  id=$(w post list --post_type=page,post --name="$slug" --field=ID | tail -1)
  if [ -n "$id" ]; then w post delete "$id" --force >/dev/null && echo "   removed  : $slug"
  else echo "   absent   : $slug"; fi
done

# ---------------------------------------------------------------- editor state
# The silent capture-corrupter. Per-user, in the DB; a mid-run toggle changes every
# subsequent shot. Seed it for EVERY user, not just admin.
say "7. Editor preferences (welcome guides off, fullscreen off)"
w eval '
  $prefs = [
    "core"             => [ "isComplementaryAreaVisible" => true, "showListViewByDefault" => false ],
    "core/edit-post"   => [ "welcomeGuide" => false, "fullscreenMode" => false, "welcomeGuideTemplate" => false ],
    "core/edit-site"   => [ "welcomeGuide" => false, "fullscreenMode" => false, "welcomeGuideStyles" => false, "welcomeGuidePage" => false, "welcomeGuideTemplate" => false ],
    "core/edit-widgets"=> [ "welcomeGuide" => false ],
    "core/editor"      => [ "welcomeGuide" => false, "fullscreenMode" => false ],
    "_modified"        => gmdate("c"),
  ];
  foreach ( get_users( [ "fields" => "ID" ] ) as $uid ) {
    update_user_meta( $uid, "wp_persisted_preferences", $prefs );
  }
  echo "seeded for " . count( get_users( [ "fields" => "ID" ] ) ) . " users";
' | tail -1 | sed 's/^/   /'

# Suppress the admin-pointer tour bubbles that overlay the UI in fresh installs.
w eval 'foreach ( get_users(["fields"=>"ID"]) as $uid ) { update_user_meta($uid,"dismissed_wp_pointers","theme_editor_notice,plugin_editor_notice"); } echo "pointers dismissed";' | tail -1 | sed 's/^/   /'

# ---------------------------------------------------------------- verify
say "8. Verify"
printf "   front end   : "; curl -s -o /dev/null -w "HTTP %{http_code}\n" "$(w option get siteurl | tail -1)"
printf "   checksums   : "; w core verify-checksums | tail -1
printf "   pages       : "; w post list --post_type=page --post_status=publish --format=count | tail -1
printf "   posts       : "; w post list --post_type=post --post_status=publish --format=count | tail -1
printf "   attachments : "; w post list --post_type=attachment --format=count | tail -1
printf "   users       : "; w user list --format=count | tail -1
printf "   sub-sizes   : "; w eval '
  $a = get_posts(["post_type"=>"attachment","numberposts"=>1,"fields"=>"ids"]);
  if(!$a){ echo "no attachments"; return; }
  $m = wp_get_attachment_metadata($a[0]);
  echo isset($m["sizes"]) ? count($m["sizes"])." generated" : "NONE — image pipeline problem";
' | tail -1

say "Done. Re-inspect the front end before capturing — placeholder cleanup has knock-on effects."
echo "URL: $(w option get siteurl | tail -1)"
