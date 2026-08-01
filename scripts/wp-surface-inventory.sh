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
[ -d "$DIR" ] || { echo "Usage: $0 <plugin-or-theme-dir> [--csv]" >&2; exit 1; }
DIR="${DIR%/}"

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
DEPRECATED='wp_get_sites|get_page_by_title|wp_make_content_images_responsive|screen_icon|get_currentuserinfo|wp_get_http|create_function|wp_localize_script|get_theme_data|attribute_escape|clean_url|js_escape|wp_specialchars|get_settings|the_search_query|get_links|debug_fopen|force_ssl_login|wp_clone|wp_get_attachment_thumb_file'
scan "deprecated" "($DEPRECATED)\s*\(" "($DEPRECATED)"

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

Full method: https://github.com/courtneyr-dev/wp-release-audit-method/tree/main/plugin-authors
EOF
exit 0
