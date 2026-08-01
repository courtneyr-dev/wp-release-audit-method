#!/usr/bin/env bash
# Derive which WordPress surfaces a plugin or theme actually touches.
#
# You don't need to know what someone's plugin DOES to test it against a release.
# You need to know what it TOUCHES — and that's mechanical. This greps a codebase
# for every core API it consumes, so you can intersect that list with what the
# release changed. The intersection is the test plan.
#
# Usage: wp-surface-inventory.sh <plugin-or-theme-dir> [--csv]
#
# Output: a human-readable report, or --csv for surface,item,count,files
# Reads only. Never modifies the target.

set -uo pipefail

DIR="${1:-}"
FORMAT="${2:-text}"
BASELINE="${3:-}"
[ -d "$DIR" ] || { cat >&2 <<'USAGE'
Usage: wp-surface-inventory.sh <plugin-or-theme-dir> [--csv]
       wp-surface-inventory.sh <dir> --baseline <previous.csv>

  --csv                  machine-readable: surface,item,count
  --baseline <file>      diff against a previous --csv run and report only
                         what changed. New surfaces are surfaces you have
                         never tested through an upgrade.

Typical cycle:
  wp-surface-inventory.sh . --csv > surfaces-7.1.csv     # this release
  wp-surface-inventory.sh . --baseline surfaces-7.1.csv  # next release
USAGE
exit 1; }
DIR="${DIR%/}"

# ── Baseline diff mode ───────────────────────────────────────────────────────
if [ "$FORMAT" = "--baseline" ]; then
  [ -f "$BASELINE" ] || { echo "Baseline file not found: $BASELINE" >&2; exit 1; }
  CUR=$(mktemp); trap 'rm -f "$CUR"' EXIT
  "$0" "$DIR" --csv > "$CUR" 2>/dev/null
  printf '\033[1mSurface diff: %s\033[0m\n' "$(basename "$DIR")"
  echo "baseline: $BASELINE"
  echo

  # Compare on surface+item, ignoring counts.
  key() { awk -F, 'NR>1 && NF>=2 {print $1 "," $2}' "$1" | sort -u; }
  ADDED=$(comm -13 <(key "$BASELINE") <(key "$CUR"))
  GONE=$(comm -23 <(key "$BASELINE") <(key "$CUR"))

  if [ -n "$ADDED" ]; then
    printf '\033[1;32m NEW since baseline — never tested through an upgrade\033[0m\n'
    echo "$ADDED" | sed 's/^/  + /'
  else
    echo " No new surfaces."
  fi
  echo
  if [ -n "$GONE" ]; then
    printf '\033[1;33m GONE since baseline — confirm this was deliberate\033[0m\n'
    echo "$GONE" | sed 's/^/  - /'
  else
    echo " No surfaces dropped."
  fi
  echo
  CHANGED=$(awk -F, '
    FNR==NR { if (FNR>1 && NF>=3) old[$1 "\x1f" $2] = $NF; next }
    FNR>1 && NF>=3 {
      k = $1 "\x1f" $2
      if (k in old && old[k] != $NF) {
        split(k, p, "\x1f")
        printf "  ~ %s / %s: %s → %s\n", p[1], p[2], old[k], $NF
      }
    }' "$BASELINE" "$CUR")
  if [ -n "$CHANGED" ]; then
    printf '\033[1m Usage changed (same surface, different call count)\033[0m\n'
    echo "$CHANGED" | head -25
  else
    echo " No usage-count changes."
  fi
  echo
  echo " Anything under NEW is a surface your existing tests have never covered."
  echo " Cross-reference it against this release's dev notes first."
  exit 0
fi

# Only source files. Skip vendor, node_modules, build output, and minified assets.
php_files() { find "$DIR" -type f -name '*.php' \
    ! -path '*/vendor/*' ! -path '*/node_modules/*' ! -path '*/build/*' ! -path '*/dist/*' 2>/dev/null; }
js_files()  { find "$DIR" -type f \( -name '*.js' -o -name '*.jsx' -o -name '*.ts' -o -name '*.tsx' \) \
    ! -path '*/vendor/*' ! -path '*/node_modules/*' ! -path '*/build/*' ! -path '*/dist/*' \
    ! -name '*.min.js' 2>/dev/null; }

PHP=$(php_files); JS=$(js_files)
[ -z "$PHP$JS" ] && { echo "No source files found under $DIR" >&2; exit 1; }

CSV=""; [ "$FORMAT" = "--csv" ] && CSV=1
[ -n "$CSV" ] && echo "surface,item,count"

# Detect this project's own prefix, so its own hooks and options don't drown out
# the core ones. Core compatibility depends on what you consume FROM core, not on
# what you named your own things.
detect_prefix() {
  local p
  # The most common leading token across the project's own option and hook names.
  # This beats the declared Text Domain, which is often the long human-readable
  # slug while the code uses a short initialism.
  p=$(echo "$PHP" | tr '\n' '\0' \
      | xargs -0 grep -hoE "((get|update|add|delete)_option|add_(action|filter)|do_action|apply_filters)\(\s*['\"][a-z0-9]{2,}_" 2>/dev/null \
      | grep -oE "['\"][a-z0-9]{2,}_" | tr -d "'\"" \
      | grep -vE '^(wp|admin|init|save|the|pre|post|user|get|set|is|do|add)_$' \
      | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  # Fall back to the declared text domain.
  [ -z "$p" ] && p=$(echo "$PHP" | tr '\n' '\0' | xargs -0 grep -hoE '^ \* Text Domain: *[a-z0-9_-]+' 2>/dev/null \
      | head -1 | sed 's/.*: *//' | tr '-' '_')
  echo "${p%_}"
}
PREFIX=$(detect_prefix)
# Match the detected prefix and its hyphenated form, anchored at the start.
own_re() { [ -z "$PREFIX" ] && { echo '^$'; return; }
  echo "^(${PREFIX}|$(echo "$PREFIX" | tr '_' '-'))[_-]?"; }
OWN=$(own_re)

# scan <label> <regex> <capture-regex> [files] [filter]
#   filter: core = drop this project's own names (default for consumed surfaces)
#           own  = keep ONLY this project's own names
#           all  = no filtering
scan() {
  local label="$1" pat="$2" cap="$3" files="${4:-$PHP}" filter="${5:-all}"
  [ -z "$files" ] && return
  local out
  out=$(echo "$files" | tr '\n' '\0' | xargs -0 grep -hoE "$pat" 2>/dev/null \
        | grep -oE "$cap" | sed "s/['\"]//g" | sort | uniq -c | sort -rn)
  case "$filter" in
    core) out=$(echo "$out" | awk '{print}' | grep -vE "  *${OWN#^}" || true) ;;
    own)  out=$(echo "$out" | grep -E "  *${OWN#^}" || true) ;;
  esac
  out=$(echo "$out" | grep -vE '^\s*$' || true)
  [ -z "$out" ] && return
  if [ -n "$CSV" ]; then
    echo "$out" | awk -v l="$label" '{c=$1; $1=""; sub(/^ /,""); print l "," $0 "," c}'
  else
    printf '\n\033[1m%s\033[0m\n' "$label"
    echo "$out" | head -40 | sed 's/^/  /'
    local n; n=$(echo "$out" | wc -l | tr -d ' ')
    [ "$n" -gt 40 ] && echo "  … and $((n-40)) more"
  fi
}

hdr() { [ -z "$CSV" ] && printf '\n\033[1;36m══ %s\033[0m\n' "$1"; }

[ -z "$CSV" ] && {
  printf '\033[1mSurface inventory: %s\033[0m\n' "$(basename "$DIR")"
  echo "PHP files: $(echo "$PHP" | grep -c . ) · JS files: $(echo "$JS" | grep -c .)"
  echo "Intersect this with the release's dev notes. Anything in both lists is a test."
}

hdr "CORE HOOKS CONSUMED — break if core renames, removes, or changes their arguments"
scan "hook:action" "add_action\(\s*['\"][^'\"]+" "['\"][^'\"]+$" "$PHP" core
scan "hook:filter" "add_filter\(\s*['\"][^'\"]+" "['\"][^'\"]+$" "$PHP" core

hdr "HOOKS PROVIDED — your own extension points; other plugins depend on these"
scan "hook:do_action"     "do_action\(\s*['\"][^'\"]+"     "['\"][^'\"]+$" "$PHP" own
scan "hook:apply_filters" "apply_filters\(\s*['\"][^'\"]+" "['\"][^'\"]+$" "$PHP" own

hdr "REGISTRATIONS — post types, taxonomies, blocks, shortcodes, REST"
scan "post_type"  "register_post_type\(\s*['\"][^'\"]+"       "['\"][^'\"]+$"
scan "taxonomy"   "register_taxonomy\(\s*['\"][^'\"]+"        "['\"][^'\"]+$"
scan "shortcode"  "add_shortcode\(\s*['\"][^'\"]+"            "['\"][^'\"]+$"
scan "rest_route" "register_rest_route\(\s*['\"][^'\"]+"      "['\"][^'\"]+$"
scan "meta"       "register_(post_)?meta\(\s*['\"][^'\"]+"    "['\"][^'\"]+$"
scan "setting"    "register_setting\(\s*['\"][^'\"]+"         "['\"][^'\"]+$"
scan "block:php"  "register_block_type[_from_metadata]*\(\s*[^)]*"  "[a-z0-9-]+/[a-z0-9-]+"
scan "block:json" "\"name\"\s*:\s*\"[a-z0-9-]+/[a-z0-9-]+\"" "[a-z0-9-]+/[a-z0-9-]+" \
  "$(find "$DIR" -name block.json ! -path '*/node_modules/*' 2>/dev/null)"

hdr "CAPABILITIES AND ROLES — the security boundary; test as a low role, not admin"
scan "capability" "current_user_can\(\s*['\"][^'\"]+"  "['\"][^'\"]+$"
scan "capability" "user_can\(\s*[^,]+,\s*['\"][^'\"]+" "['\"][^'\"]+$"
scan "role"       "(add_role|get_role|add_cap|remove_cap)\(\s*['\"][^'\"]+" "['\"][^'\"]+$"

hdr "PERSISTENCE — where your state lives, and what an upgrade must preserve"
scan "option:core" "(get|update|add|delete)_option\(\s*['\"][^'\"]+"     "['\"][^'\"]+$" "$PHP" core
scan "option:own"  "(get|update|add|delete)_option\(\s*['\"][^'\"]+"     "['\"][^'\"]+$" "$PHP" own
scan "transient" "(get|set|delete)_transient\(\s*['\"][^'\"]+"           "['\"][^'\"]+$"
scan "usermeta"  "(get|update|add|delete)_user_meta\(\s*[^,]+,\s*['\"][^'\"]+" "['\"][^'\"]+$"
scan "postmeta"  "(get|update|add|delete)_post_meta\(\s*[^,]+,\s*['\"][^'\"]+" "['\"][^'\"]+$"

hdr "ASSETS — handles you enqueue or depend on; core can rename or unbundle these"
scan "script" "wp_(enqueue|register)_script\(\s*['\"][^'\"]+" "['\"][^'\"]+$"
scan "style"  "wp_(enqueue|register)_style\(\s*['\"][^'\"]+"  "['\"][^'\"]+$"
scan "wp-package" "@wordpress/[a-z0-9-]+" "@wordpress/[a-z0-9-]+" "$JS"

hdr "SCHEDULED WORK — cron survives upgrades; verify it still fires"
scan "cron" "wp_(schedule_event|schedule_single_event|next_scheduled|clear_scheduled_hook)\(\s*[^,]*,?\s*['\"][^'\"]+" "['\"][^'\"]+$"

hdr "DIRECT DATABASE ACCESS — bypasses core APIs, so core changes won't warn you"
if [ -n "$CSV" ]; then
  echo "db,\$wpdb references,$(echo "$PHP" | tr '\n' '\0' | xargs -0 grep -ohE '\$wpdb->[a-z_]+' 2>/dev/null | wc -l | tr -d ' ')"
else
  scan "wpdb" '\$wpdb->[a-z_]+' '\$wpdb->[a-z_]+'
  DBT=$(echo "$PHP" | tr '\n' '\0' | xargs -0 grep -lE '\$wpdb->(query|get_results|get_row|get_var|prepare)' 2>/dev/null | wc -l | tr -d ' ')
  [ "$DBT" -gt 0 ] && echo "  → $DBT file(s) query the database directly. Core schema changes will not warn you."
fi

hdr "DEPRECATION RISK — already-deprecated APIs still in use"
# The list lives in data/deprecations.csv so it can be extended by pull request
# each cycle instead of being edited inside this script.
DEPFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/data/deprecations.csv"
if [ -f "$DEPFILE" ]; then
  DEPRECATED=$(awk -F, 'NR>1 && $1!="" {printf "%s|", $1}' "$DEPFILE" | sed 's/|$//')
  scan "deprecated" "($DEPRECATED)\s*\(" "($DEPRECATED)"
  if [ -z "$CSV" ]; then
    HITS=$(echo "$PHP" | tr '\n' '\0' | xargs -0 grep -hoE "($DEPRECATED)\s*\(" 2>/dev/null \
           | grep -oE "($DEPRECATED)" | sort -u)
    if [ -n "$HITS" ]; then
      echo
      echo "$HITS" | while read -r h; do
        [ -z "$h" ] && continue
        awk -F, -v s="$h" 'NR>1 && $1==s {printf "  %-36s deprecated in %-8s → %s\n", $1, $3, ($4==""?"no direct replacement":$4)}' "$DEPFILE"
      done
    fi
  fi
else
  [ -z "$CSV" ] && echo "  (data/deprecations.csv not found — run this from the repo checkout to get versions and replacements)"
fi

hdr "VERSION GATES — what you already branch on"
scan "version-check" "(get_bloginfo\(\s*['\"]version|\\\$wp_version|version_compare\(\s*\\\$wp_version)" \
  "(get_bloginfo|wp_version|version_compare)"
scan "function_exists" "function_exists\(\s*['\"][a-z_]+" "['\"][a-z_]+$"

# ─────────────────────────────────────────────────────────────────────────────
# THEME SURFACES — only meaningful if this is a theme, harmless if it isn't.
# ─────────────────────────────────────────────────────────────────────────────
THEMEJSON="$DIR/theme.json"
IS_THEME=""
[ -f "$THEMEJSON" ] && IS_THEME=1
[ -f "$DIR/style.css" ] && grep -qiE '^\s*\*?\s*Theme Name:' "$DIR/style.css" 2>/dev/null && IS_THEME=1

if [ -n "$IS_THEME" ]; then
  hdr "THEME TYPE AND GLOBAL STYLES"
  BLOCK_THEME=""
  [ -f "$DIR/templates/index.html" ] && BLOCK_THEME=1
  if [ -z "$CSV" ]; then
    echo "  theme type       : $([ -n "$BLOCK_THEME" ] && echo 'BLOCK theme (templates/index.html present)' || echo 'CLASSIC theme (no templates/index.html)')"
  fi
  if [ -f "$THEMEJSON" ]; then
    TJV=$(grep -oE '"version"[[:space:]]*:[[:space:]]*[0-9]+' "$THEMEJSON" | head -1 | grep -oE '[0-9]+$')
    APPT=$(grep -cE '"appearanceTools"[[:space:]]*:[[:space:]]*true' "$THEMEJSON")
    if [ -n "$CSV" ]; then
      echo "theme,theme.json schema version,${TJV:-unknown}"
      echo "theme,appearanceTools enabled,$APPT"
    else
      echo "  theme.json       : present, schema version ${TJV:-unknown} (current is 3, WP 6.6+)"
      [ "${TJV:-0}" -lt 3 ] 2>/dev/null && echo "     → schema v${TJV} is behind v3. Migrating unlocks newer settings."
      echo "  appearanceTools  : $([ "$APPT" -gt 0 ] && echo 'enabled' || echo 'NOT enabled — one line unlocks border, link/heading/button color, dimensions, sticky position, spacing, and line-height controls')"
    fi
    scan "theme.json:settings" '"(appearanceTools|useRootPaddingAwareAlignments|color|typography|spacing|border|shadow|dimensions|position|background|layout|blocks|custom)"[[:space:]]*:' \
      '"[a-zA-Z]+"' "$THEMEJSON"
  else
    [ -z "$CSV" ] && echo "  theme.json       : ABSENT — no global styles. Every design control is hand-rolled."
  fi

  hdr "add_theme_support() — several of these are superseded by theme.json"
  scan "theme-support" "add_theme_support\(\s*['\"][a-z0-9-]+" "['\"][a-z0-9-]+$"

  hdr "TEMPLATES, PARTS, PATTERNS, STYLE VARIATIONS"
  if [ -z "$CSV" ]; then
    for d in templates parts patterns styles; do
      n=$(find "$DIR/$d" -maxdepth 1 -type f \( -name '*.html' -o -name '*.php' -o -name '*.json' \) 2>/dev/null | wc -l | tr -d ' ')
      [ "$n" != "0" ] && echo "  $d/ : $n file(s)"
    done
    CLASSIC=$(find "$DIR" -maxdepth 1 -type f \( -name 'single.php' -o -name 'archive.php' -o -name 'page.php' -o -name 'index.php' -o -name 'front-page.php' -o -name 'search.php' -o -name '404.php' \) 2>/dev/null | wc -l | tr -d ' ')
    [ "$CLASSIC" != "0" ] && echo "  classic template hierarchy files at root: $CLASSIC"
    [ -n "$BLOCK_THEME" ] && [ "$CLASSIC" -gt 1 ] && echo "     → both block templates AND classic templates present. Test which one actually wins."
  fi
  scan "pattern" "register_block_pattern(_category)?\(\s*['\"][^'\"]+" "['\"][^'\"]+$"
fi

# ─────────────────────────────────────────────────────────────────────────────
# ADOPTION CANDIDATES — the opposite of risk. What core now does for you that
# you may still be hand-rolling. Heuristics: each is a prompt to look, not a verdict.
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# EDITOR AND THEME PARADIGM — which of the four deployments you actually serve.
# Classic Editor has ~9 million active installs; assuming block-only is a bet
# against a large share of real sites.
# ─────────────────────────────────────────────────────────────────────────────
hdr "CLASSIC EDITOR SURFACES — only run when the block editor is OFF"
scan "classic:metabox"  "add_meta_box\(\s*['\"][^'\"]+"                    "['\"][^'\"]+$"
scan "classic:tinymce"  "(mce_buttons[_0-9]*|mce_external_plugins|tiny_mce_before_init|teeny_mce_buttons|mce_css)" \
                        "(mce_buttons[_0-9]*|mce_external_plugins|tiny_mce_before_init|teeny_mce_buttons|mce_css)"
scan "classic:editor"   "(wp_editor\(|the_editor|wp_default_editor|media_buttons|quicktags|wp_tiny_mce)" \
                        "(wp_editor|the_editor|wp_default_editor|media_buttons|quicktags|wp_tiny_mce)"
scan "classic:form"     "(edit_form_after_title|edit_form_after_editor|edit_form_top|edit_form_advanced|post_submitbox_misc_actions|dbx_post_sidebar)" \
                        "(edit_form_[a-z_]+|post_submitbox_misc_actions|dbx_post_sidebar)"
scan "classic:gate"     "(use_block_editor_for_post_type|use_block_editor_for_post|gutenberg_can_edit_post)" \
                        "(use_block_editor_for_post[a-z_]*|gutenberg_can_edit_post)"
scan "classic:editorstyle" "add_editor_style\(" "add_editor_style"

hdr "BLOCK EDITOR SURFACES — only run when the block editor is ON"
scan "block:assets"  "(enqueue_block_editor_assets|enqueue_block_assets|block_editor_settings_all|allowed_block_types_all)" \
                     "(enqueue_block_[a-z_]+|block_editor_settings_all|allowed_block_types_all)"
scan "block:js"      "wp\.(blocks|data|blockEditor|editor|element|components|plugins|richText)" \
                     "wp\.[a-zA-Z]+" "$JS"
scan "block:filter"  "addFilter\(\s*['\"][^'\"]+" "['\"][^'\"]+$" "$JS"
scan "block:rest-meta" "show_in_rest" "show_in_rest"

hdr "CLASSIC THEME SURFACES"
scan "classic-theme:sidebar" "(register_sidebar|dynamic_sidebar|register_widget|WP_Widget)" \
                             "(register_sidebar|dynamic_sidebar|register_widget|WP_Widget)"
scan "classic-theme:menu"    "(register_nav_menus?|wp_nav_menu)" "(register_nav_menus?|wp_nav_menu)"
scan "classic-theme:customizer" "(customize_register|WP_Customize_|customize_preview_init)" \
                                "(customize_register|WP_Customize_[A-Za-z]*|customize_preview_init)"
scan "classic-theme:template" "(get_header|get_footer|get_sidebar|get_template_part|comments_template)\(" \
                              "(get_header|get_footer|get_sidebar|get_template_part|comments_template)"

hdr "BLOCK THEME SURFACES"
scan "block-theme:template" "(block_template_hierarchy|get_block_template|wp_template|wp_template_part|render_block_template)" \
                            "(block_template[a-z_]*|get_block_template|wp_template[a-z_]*|render_block_template)"
scan "block-theme:styles"   "(wp_get_global_settings|wp_get_global_styles|wp_theme_json|theme_json_[a-z_]+)" \
                            "(wp_get_global_[a-z]+|wp_theme_json[a-zA-Z_]*|theme_json_[a-z_]+)"

if [ -z "$CSV" ]; then
  CE=$(echo "$PHP" | tr '\n' '\0' | xargs -0 grep -lE "add_meta_box|mce_buttons|wp_editor\(|edit_form_after" 2>/dev/null | wc -l | tr -d ' ')
  BE=$(echo "$PHP$JS" | tr '\n' '\0' | xargs -0 grep -lE "enqueue_block_editor_assets|register_block_type|wp\.blocks" 2>/dev/null | wc -l | tr -d ' ')
  echo
  printf '  \033[1mParadigm exposure:\033[0m classic-editor files: %s · block-editor files: %s\n' "$CE" "$BE"
  if [ "$CE" -gt 0 ] && [ "$BE" -gt 0 ]; then
    echo "     → You serve BOTH. Test all four cells: {classic, block} editor × {classic, block} theme."
  elif [ "$CE" -gt 0 ]; then
    echo "     → Classic-editor features only. Confirm they degrade sanely when the block editor is on."
  elif [ "$BE" -gt 0 ]; then
    echo "     → Block-editor features only. ~9M sites run Classic Editor — confirm you fail gracefully there,"
    echo "       or say so in your readme. Silence reads as 'supported'."
  fi
fi

hdr "INTERNATIONALIZATION — WordPress runs in ~200 locales"
scan "i18n:textdomain" "load_(plugin|theme|muplugin|default)_textdomain" "load_[a-z]+_textdomain"
scan "i18n:funcs" "(esc_html__|esc_attr__|esc_html_e|esc_attr_e|_n_noop|_nx?|_ex?|__)\(" "(esc_[a-z]+__|esc_[a-z]+_e|_n_noop|_nx|_n|_ex|_e|__)"
scan "i18n:js" "wp_set_script_translations" "wp_set_script_translations"
scan "i18n:format" "(date_i18n|number_format_i18n|wp_date)" "(date_i18n|number_format_i18n|wp_date)"

if [ -z "$CSV" ]; then
  EARLY=$(echo "$PHP" | tr '\n' '\0' | xargs -0 grep -lE "get_plugin_data\(" 2>/dev/null | wc -l | tr -d ' ')
  RTLCSS=$(find "$DIR" -name '*-rtl.css' 2>/dev/null | wc -l | tr -d ' ')
  PHYS=$(find "$DIR" -name '*.css' ! -path '*/node_modules/*' ! -name '*.min.css' -print0 2>/dev/null \
         | xargs -0 grep -lE "(margin|padding)-(left|right)|text-align:\s*(left|right)|float:\s*(left|right)" 2>/dev/null | wc -l | tr -d ' ')
  LOGICAL=$(find "$DIR" -name '*.css' ! -path '*/node_modules/*' -print0 2>/dev/null \
         | xargs -0 grep -lE "(margin|padding)-inline|inset-inline|text-align:\s*(start|end)" 2>/dev/null | wc -l | tr -d ' ')
  echo
  printf '  \033[1mLocale and RTL signals\033[0m\n'
  [ "$EARLY" -gt 0 ] && echo "    ⚠ $EARLY file(s) call get_plugin_data() — pass \$translate=false, or WP 6.7+ warns about early translation."
  echo "    CSS with physical properties: $PHYS file(s) · with logical properties: $LOGICAL file(s)"
  [ "$PHYS" -gt 0 ] && echo "    ⚠ Physical properties (margin-left, float:left, text-align:left) do not flip for RTL."
  [ "$RTLCSS" -gt 0 ] && echo "    $RTLCSS -rtl.css file(s) present — confirm they are regenerated, not stale."
  echo "    Method: $(dirname "${BASH_SOURCE[0]}")/../i18n/README.md"
fi

hdr "ACCESSIBILITY SURFACES — every one of these is a keyboard or screen-reader claim"
scan "a11y:aria"     "aria-[a-z]+"                    "aria-[a-z]+"      "$PHP$JS"
scan "a11y:role"     "role=['\"][a-z]+"               "role=['\"][a-z]+" "$PHP$JS"
scan "a11y:tabindex" "tabindex=['\"]-?[0-9]+"         "tabindex=['\"]-?[0-9]+" "$PHP$JS"
scan "a11y:sr-text"  "(screen-reader-text|sr-only|visually-hidden|wp-a11y|speak\()" \
                     "(screen-reader-text|sr-only|visually-hidden|wp-a11y|speak)" "$PHP$JS"
scan "a11y:label"    "(aria-label|aria-labelledby|aria-describedby|<label)" \
                     "(aria-label[a-z]*|aria-describedby|<label)" "$PHP$JS"

if [ -z "$CSV" ]; then
  CLICK=$(echo "$JS" | tr '\n' '\0' | xargs -0 grep -lE "addEventListener\(\s*['\"]click" 2>/dev/null | wc -l | tr -d ' ')
  KEY=$(echo "$JS" | tr '\n' '\0' | xargs -0 grep -lE "addEventListener\(\s*['\"]key(down|up|press)" 2>/dev/null | wc -l | tr -d ' ')
  DIVCLICK=$(echo "$PHP$JS" | tr '\n' '\0' | xargs -0 grep -lE "<(div|span)[^>]*onclick" 2>/dev/null | wc -l | tr -d ' ')
  OUTLINE=$(echo "$PHP$JS" | tr '\n' '\0' | xargs -0 grep -lE "outline:\s*(none|0)" 2>/dev/null | wc -l | tr -d ' ')
  CSSOUT=$(find "$DIR" -name '*.css' ! -path '*/node_modules/*' ! -name '*.min.css' -print0 2>/dev/null \
           | xargs -0 grep -lE "outline:\s*(none|0)" 2>/dev/null | wc -l | tr -d ' ')
  echo
  printf '  \033[1mKeyboard-parity signals\033[0m\n'
  echo "    click handlers: $CLICK file(s) · key handlers: $KEY file(s)"
  if [ "$CLICK" -gt 0 ] && [ "$KEY" -eq 0 ]; then
    echo "    ⚠ Click handlers with no keyboard handlers anywhere. Anything doable with a mouse"
    echo "      must be doable from the keyboard — check these are on native buttons/links."
  fi
  [ "$DIVCLICK" -gt 0 ] && echo "    ⚠ $DIVCLICK file(s) put click handlers on div/span — not focusable or activatable by default."
  if [ $(( OUTLINE + CSSOUT )) -gt 0 ]; then
    echo "    ⚠ $(( OUTLINE + CSSOUT )) file(s) set outline:none — the most common cause of invisible focus."
    echo "      Removing the default outline is fine only if you replace it with a strong visible one."
  fi
  echo "    Method: https://wpaccessibility.org/docs/testing/keyboard/"
fi

hdr "ADOPTION CANDIDATES — core may already do this for you"

flag() { # <condition-count> <label> <recommendation>
  [ "${1:-0}" -eq 0 ] && return
  if [ -n "$CSV" ]; then echo "adoption,$2,$1"
  else printf '  \033[1m%s\033[0m (%s hit(s))\n     → %s\n' "$2" "$1" "$3"; fi
}

count() { echo "$1" | tr '\n' '\0' | xargs -0 grep -lE "$2" 2>/dev/null | wc -l | tr -d ' '; }

JQ=$(count "$PHP$JS" "(jQuery|\\\$\(document\)\.ready|wp_enqueue_script\(\s*['\"]jquery)")
flag "$JQ" "jQuery for front-end behavior" \
  "Interactivity API (WP 6.5+) replaces this for block front ends. Add \"interactivity\": true to block.json supports, use data-wp-* directives and viewScriptModule."

META=$(count "$PHP" "(add_meta_box|register_(post_)?meta)")
flag "$META" "Custom post meta surfaced in the editor" \
  "Block Bindings (WP 6.5+) can display post meta directly in core paragraph/heading/image/button blocks — no custom block needed. Requires register_meta with show_in_rest."

CUSTOMATTR=$(count "$(find "$DIR" -name block.json ! -path '*/node_modules/*' 2>/dev/null)" '"(color|backgroundColor|textColor|fontSize|padding|margin|borderColor|borderRadius)"')
flag "$CUSTOMATTR" "Hand-rolled style attributes in block.json" \
  "Block supports give you the same controls plus the UI for free — color, spacing, typography, border, shadow, dimensions. Check whether an attribute duplicates a support."

LOCALIZE=$(count "$PHP" "wp_localize_script")
flag "$LOCALIZE" "wp_localize_script for passing data" \
  "For non-i18n data prefer wp_add_inline_script, or wp_interactivity_state for Interactivity API blocks. localize_script was designed for translations."

if [ -n "$IS_THEME" ]; then
  SUPERSEDED=$(echo "$PHP" | tr '\n' '\0' | xargs -0 grep -hoE "add_theme_support\(\s*['\"](editor-color-palette|editor-font-sizes|editor-gradient-presets|custom-line-height|custom-spacing|custom-units|editor-styles|responsive-embeds|align-wide|appearance-tools)" 2>/dev/null | wc -l | tr -d ' ')
  flag "$SUPERSEDED" "add_theme_support() calls superseded by theme.json" \
    "editor-color-palette, editor-font-sizes, editor-gradient-presets, custom-line-height, custom-spacing, custom-units, align-wide and friends all belong in theme.json settings now."
  [ ! -f "$THEMEJSON" ] && flag 1 "No theme.json" \
    "Even a classic theme benefits — theme.json controls the editor's available styles and is where design tokens belong."
fi

RENDERCB=$(count "$PHP" "render_callback|register_block_type.*render")
flag "$RENDERCB" "Server-rendered dynamic blocks" \
  "These are the natural home for the Interactivity API — the markup is already server-generated, so add directives rather than a separate front-end script."

[ -z "$CSV" ] && cat <<'EOF'

══════════════════════════════════════════════════════════════════════
WHAT TO DO WITH THIS

1. Read the release's dev notes: https://make.wordpress.org/core/tag/dev-notes/
2. Search this output for every name the dev notes mention. Every hit is a test.
3. Anything under DEPRECATION RISK is already on borrowed time — fix now.
4. Anything under DIRECT DATABASE ACCESS gets no deprecation warning at all.
   Those need manual review against schema changes every cycle.
5. Cross-reference your own changelog: code YOU changed recently, on a surface
   CORE changed this cycle, is your highest-risk cell. Test that first.

Full method: https://github.com/courtneyr-dev/wp-release-audit-method/tree/main/plugin-theme-authors
EOF
exit 0
