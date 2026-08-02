#!/usr/bin/env bash
# C-03 cleanup — re-archives site 3 after the first-load observation.
set -u
SC="${STUDIO_CLI:-/Applications/Studio.app/Contents/Resources/bin/studio-cli.sh}"
SITE="$HOME/Studio/codex-wp71-beta4-multisite"
"$SC" wp eval 'update_blog_status( 3, "archived", 1 );' --path="$SITE"
"$SC" wp eval 'echo (int) get_site( 3 )->archived . "\n";' --path="$SITE"
