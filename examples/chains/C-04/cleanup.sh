#!/usr/bin/env bash
# C-04 cleanup — restores the original network and site plugin activation scopes.
set -u
SC="${STUDIO_CLI:-/Applications/Studio.app/Contents/Resources/bin/studio-cli.sh}"
SITE="$HOME/Studio/codex-wp71-beta4-multisite"
URL="http://codex-active.localhost:8885/"
"$SC" wp plugin deactivate codex-dependent --network --path="$SITE" || true
"$SC" wp plugin deactivate codex-dependent --url="$URL" --path="$SITE" || true
"$SC" wp plugin deactivate codex-dependency --url="$URL" --path="$SITE" || true
"$SC" wp plugin activate codex-dependency --network --path="$SITE"

