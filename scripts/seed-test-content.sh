#!/bin/bash
# Bring a scripted environment to parity with the beta-rc Playground blueprint.
#
# The one-click blueprint arrives loaded: the six-plugin debugging toolkit, plus the two
# canonical content corpora — theme-test-data (the markup-edge-case corpus WordPress
# theme reviewers use; Chris Reynolds's wpnext-test ships the same file in its rig) and
# a11y-theme-unit-test (the accessibility team's corpus: skip links, form labels, heading
# hierarchies, media alternatives). A site built by scripts/env/ drivers arrives bare,
# so cells exercised on it run against less content than the Playground lane — this
# closes that gap, for any driver.
#
#   bash scripts/seed-test-content.sh --env=ddev ~/wp-test
#   bash scripts/seed-test-content.sh --env=studio ~/wp-test --plugins-only
#   bash scripts/seed-test-content.sh --env=playground ~/wp-test --content-only
#
# Safe to re-run: plugins are checked before installing, and each corpus import is
# recorded in an option so it happens once (the importer does not reliably dedupe).
#
# Content import needs the hostfs capability (the WXR is written into the document root
# from the host). A driver without it reports BLOCKED for that half — never a fake pass.

set -uo pipefail

DRIVER="${WP_AUDIT_ENV:-}"
DO_PLUGINS=1
DO_CONTENT=1
ARGS=()
for a in "$@"; do
  case "$a" in
    --env=*)         DRIVER="${a#--env=}" ;;
    --plugins-only)  DO_CONTENT=0 ;;
    --content-only)  DO_PLUGINS=0 ;;
    *)               ARGS+=("$a") ;;
  esac
done
PROJ="${ARGS[0]:-.}"
DRIVER="${DRIVER:-wp-env}"

# shellcheck source=/dev/null
. "$(cd "$(dirname "$0")" && pwd)/lib-env.sh" || exit 1
env_init "$DRIVER" "$PROJ" || exit 1

sec() { echo; echo "======== $1"; }
RC=0

sec "0. Baseline"
echo "driver=$WP_AUDIT_ENV_DRIVER version=$(env_wp core version)"

# ---------------------------------------------------------------- plugins
# The same six the blueprint preinstalls (see the README's debugging-toolkit table for
# what each is for), plus wordpress-importer, which `wp import` below requires.
if [ "$DO_PLUGINS" = "1" ]; then
  sec "1. Debugging toolkit (blueprint parity)"
  for slug in query-monitor health-check debug-bar user-switching test-reports \
              create-block-theme wordpress-importer; do
    if env_wp plugin is-installed "$slug" 2>/dev/null; then
      if env_wp plugin is-active "$slug" 2>/dev/null; then
        echo "   exists   : $slug (active)"
      else
        env_wp plugin activate "$slug" >/dev/null 2>&1 \
          && echo "   activated: $slug" \
          || { echo "   FAILED   : $slug would not activate"; RC=1; }
      fi
    else
      env_wp plugin install "$slug" --activate >/dev/null 2>&1 \
        && echo "   installed: $slug" \
        || { echo "   FAILED   : $slug did not install"; RC=1; }
    fi
  done
fi

# ---------------------------------------------------------------- content corpora
# Written into the document root from the host so every driver imports from a path that
# exists INSIDE its environment — computed from ABSPATH, not from the host path, because
# on containerized drivers the two differ.
seed_corpus() { # marker-option url filename label
  local marker="$1" url="$2" fn="$3" label="$4" abspath before after
  if [ -n "$(env_wp option get "$marker" 2>/dev/null)" ]; then
    echo "   exists   : $label (option $marker set)"
    return 0
  fi
  mkdir -p "$(env_docroot)/wp-content/uploads/wp-audit-seed" || return 1
  curl -sSfL --max-time 120 -o "$(env_docroot)/wp-content/uploads/wp-audit-seed/$fn" "$url" \
    || { echo "   FAILED   : could not fetch $label"; return 1; }
  env_sync
  abspath="$(env_wp eval 'echo ABSPATH;' | tail -1)"
  before="$(env_wp post list --post_type=any --format=count 2>/dev/null | tail -1)"
  env_wp import "${abspath}wp-content/uploads/wp-audit-seed/$fn" --authors=create >/dev/null 2>&1 \
    || { echo "   FAILED   : $label import errored"; return 1; }
  after="$(env_wp post list --post_type=any --format=count 2>/dev/null | tail -1)"
  # Trust the count, not the exit code — an importer that ran and imported nothing is
  # a failure wearing a zero.
  if [ "${after:-0}" -gt "${before:-0}" ] 2>/dev/null; then
    env_wp option update "$marker" "$(env_wp core version)" >/dev/null 2>&1
    echo "   imported : $label ($before -> $after posts)"
  else
    echo "   FAILED   : $label imported no content ($before -> $after)"
    return 1
  fi
}

if [ "$DO_CONTENT" = "1" ]; then
  sec "2. Content corpora (blueprint parity)"
  if ! env_has hostfs; then
    echo "BLOCKED  content import needs capability: hostfs (driver=$WP_AUDIT_ENV_DRIVER)"
    echo "         the Playground lane already has both corpora via the beta-rc blueprint"
    RC=2
  elif [ "$DO_PLUGINS" = "0" ] && ! env_wp plugin is-active wordpress-importer 2>/dev/null; then
    echo "BLOCKED  wp import needs the wordpress-importer plugin — run without --content-only first"
    RC=2
  else
    seed_corpus _wp_audit_seed_theme_test_data \
      "https://raw.githubusercontent.com/WordPress/theme-test-data/master/themeunittestdata.wordpress.xml" \
      theme-test-data.xml "theme-test-data" || RC=1
    seed_corpus _wp_audit_seed_a11y_test_data \
      "https://raw.githubusercontent.com/wpaccessibility/a11y-theme-unit-test/master/a11y-theme-unit-test-data.xml" \
      a11y-theme-unit-test.xml "a11y-theme-unit-test" || RC=1
  fi
fi

# ---------------------------------------------------------------- verify
sec "3. Verify"
echo "   active plugins : $(env_wp plugin list --status=active --format=count 2>/dev/null | tail -1)"
echo "   posts (any)    : $(env_wp post list --post_type=any --format=count 2>/dev/null | tail -1)"
echo "   front end      : $(curl -sk -o /dev/null -w 'HTTP %{http_code}' "$(env_url)")"

exit "$RC"
