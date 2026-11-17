#!/usr/bin/env bash
# Check every HelpHub or developer.wordpress.org URL cited in the given files:
# status, where it ends up after redirects, and the page title.
# Usage: check-doc-urls.sh FILE...
# FLAG lines: non-200, redirected to a different page, or a "(Deprecated)" title.
# developer.wordpress.org reference pages 404 until the post-release build.
set -euo pipefail
[ "$#" -ge 1 ] || { sed -n '2,6p' "$0"; exit 2; }
urls=$(cat "$@" | grep -oE "https://(wordpress\.org/(documentation|support)|developer\.wordpress\.org)[^) >\"']*" |
  sed -E 's/[.,;]+$//; s/#.*$//' | sort -u)
[ -n "$urls" ] || { echo "no documentation URLs found"; exit 0; }
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
while read -r u; do
  meta=$(curl -s -L -m 20 -w '%{http_code} %{url_effective}' -o "$tmp" "$u" || echo "000 curl-failed")
  code=${meta%% *} final=${meta#* }
  title=$(grep -o '<title>[^<]*' "$tmp" 2>/dev/null | head -1 | sed 's/<title>//; s/ &#124;.*//; s/ |.*//')
  echo "$code $u -> $final | $title"
  [ "$code" = 200 ] || echo "FLAG status $code: $u"
  [ "${final%/}" = "${u%/}" ] || echo "FLAG redirects: $u -> $final"
  case $title in *Deprecated*) echo "FLAG deprecated page: $u";; esac
done <<<"$urls"
