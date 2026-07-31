#!/usr/bin/env bash
set -u

SC="${STUDIO_CLI:-/Applications/Studio.app/Contents/Resources/bin/studio-cli.sh}"
SITE="$HOME/Studio/codex-wp71-beta4-multisite"
URL="http://codex-active.localhost:8885/"
PROBE="$(cd "$(dirname "$0")" && pwd)/probe.php"
DEPENDENCY="codex-dependency"
DEPENDENT="codex-dependent"

original_network=$("$SC" wp plugin is-active "$DEPENDENCY" --network --path="$SITE"; echo $?)
original_site=$("$SC" wp plugin is-active "$DEPENDENCY" --url="$URL" --path="$SITE"; echo $?)
original_dependent_network=$("$SC" wp plugin is-active "$DEPENDENT" --network --path="$SITE"; echo $?)
original_dependent_site=$("$SC" wp plugin is-active "$DEPENDENT" --url="$URL" --path="$SITE"; echo $?)

restore() {
  "$SC" wp plugin deactivate "$DEPENDENT" --network --path="$SITE" >/dev/null 2>&1 || true
  "$SC" wp plugin deactivate "$DEPENDENT" --url="$URL" --path="$SITE" >/dev/null 2>&1 || true
  "$SC" wp plugin deactivate "$DEPENDENCY" --network --path="$SITE" >/dev/null 2>&1 || true
  "$SC" wp plugin deactivate "$DEPENDENCY" --url="$URL" --path="$SITE" >/dev/null 2>&1 || true

  if [[ "$original_network" == "0" ]]; then
    "$SC" wp plugin activate "$DEPENDENCY" --network --path="$SITE" >/dev/null
  elif [[ "$original_site" == "0" ]]; then
    "$SC" wp plugin activate "$DEPENDENCY" --url="$URL" --path="$SITE" >/dev/null
  fi
  if [[ "$original_dependent_network" == "0" ]]; then
    "$SC" wp plugin activate "$DEPENDENT" --network --path="$SITE" >/dev/null
  elif [[ "$original_dependent_site" == "0" ]]; then
    "$SC" wp plugin activate "$DEPENDENT" --url="$URL" --path="$SITE" >/dev/null
  fi
}
trap restore EXIT

set_state() {
  local state="$1"
  "$SC" wp plugin deactivate "$DEPENDENT" --network --path="$SITE" >/dev/null 2>&1 || true
  "$SC" wp plugin deactivate "$DEPENDENT" --url="$URL" --path="$SITE" >/dev/null 2>&1 || true
  "$SC" wp plugin deactivate "$DEPENDENCY" --network --path="$SITE" >/dev/null 2>&1 || true
  "$SC" wp plugin deactivate "$DEPENDENCY" --url="$URL" --path="$SITE" >/dev/null 2>&1 || true
  if [[ "$state" == "network" ]]; then
    "$SC" wp plugin activate "$DEPENDENCY" --network --path="$SITE" >/dev/null
  elif [[ "$state" == "site" ]]; then
    "$SC" wp plugin activate "$DEPENDENCY" --url="$URL" --path="$SITE" >/dev/null
  fi
}

echo "== C-04 preflight =="
"$SC" wp core version --path="$SITE"
"$SC" wp eval 'echo is_multisite() ? "multisite\n" : "single\n";' --path="$SITE"
"$SC" wp user get 1 --field=user_login --path="$SITE"
"$SC" wp user get 2 --field=user_login --path="$SITE"

for state in network site inactive; do
  set_state "$state"
  echo "DEPENDENCY_STATE=$state"
  for scope in network site; do
    for viewer in 1 2; do
      echo "CELL=dependency-$state/scope-$scope/viewer-$viewer"
      CHAIN_VIEWER_ID="$viewer" CHAIN_SCOPE="$scope" \
        "$SC" wp eval-file "$PROBE" --url="$URL" --path="$SITE"
    done
  done
done

restore
trap - EXIT

network_after=$("$SC" wp plugin is-active "$DEPENDENCY" --network --path="$SITE"; echo $?)
site_after=$("$SC" wp plugin is-active "$DEPENDENCY" --url="$URL" --path="$SITE"; echo $?)
dependent_network_after=$("$SC" wp plugin is-active "$DEPENDENT" --network --path="$SITE"; echo $?)
dependent_site_after=$("$SC" wp plugin is-active "$DEPENDENT" --url="$URL" --path="$SITE"; echo $?)
echo "cleanup_state dependency_network=$network_after dependency_site=$site_after dependent_network=$dependent_network_after dependent_site=$dependent_site_after"

if [[ "$network_after" != "$original_network" || "$site_after" != "$original_site" || "$dependent_network_after" != "$original_dependent_network" || "$dependent_site_after" != "$original_dependent_site" ]]; then
  echo "BATCH_VERDICT=INVALID reason=cleanup-state-mismatch"
  exit 4
fi
echo "cleanup_verified=yes"

