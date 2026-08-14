#!/bin/bash
# Detect the newest WordPress Beta/RC — and whether a prerelease cycle is actually ACTIVE.
#
# Feed-scraping approach adapted from Chris Reynolds's wpnext-test
# (https://github.com/jazzsequence/wpnext-test, MIT), where a weekly cron uses it to
# upgrade a standing Pantheon site unattended. One structural difference: his script
# answers "what is the newest Beta/RC ever announced" and lets the caller compare against
# a live site's version. This repo has no site to compare against, so the cycle check
# lives here — the newest prerelease mention is only a result if it is NEWER than the
# current stable release, otherwise the feeds are just remembering the last cycle.
#
# Why RSS and not the API: api.wordpress.org's version-check endpoint offers stable
# builds only — it never surfaces a Beta or RC. The two feeds that reliably carry
# prerelease announcements are the News releases category and Make/Core's releases tag,
# and neither alone catches everything, so both are fetched and merged.
#
#   bash scripts/check-latest-release.sh          # prints e.g. "7.2-RC1"
#   bash scripts/check-latest-release.sh --url    # prints the package URL instead
#
# Exit codes, mirroring rc_build_identity.sh:
#   0  active prerelease found and its package is live
#   3  announced, but the package is not downloadable yet (try again later)
#   2  no active cycle — newest prerelease mention is not ahead of current stable
#   1  error (feeds unreachable, nothing parseable)

set -uo pipefail

MODE=version
for a in "$@"; do
  case "$a" in
    --url) MODE=url ;;
    *) echo "check-latest-release: unknown argument '$a' (only --url)" >&2; exit 1 ;;
  esac
done

fetch() { curl -sSfL --max-time 30 "$1" 2>/dev/null; }

# Test seams — controls before readings applies to this instrument too:
#   WP_AUDIT_FEED_FILE          read this file instead of fetching either feed
#   WP_AUDIT_STABLE             pin the current-stable answer, skip the API call
#   WP_AUDIT_SKIP_PACKAGE_CHECK=1  skip the package-liveness probe
# check-repo.py's calibration cells drive all three against a captured feed
# snapshot in fixtures/feeds/, so a parser regression fails CI, not release day.
if [ -n "${WP_AUDIT_FEED_FILE:-}" ]; then
  news="$(cat "$WP_AUDIT_FEED_FILE" 2>/dev/null)" || news=""
  make=""
  if [ -z "$news" ]; then
    echo "check-latest-release: could not read WP_AUDIT_FEED_FILE=$WP_AUDIT_FEED_FILE" >&2
    exit 1
  fi
else
  news="$(fetch "https://wordpress.org/news/category/releases/feed/")" || news=""
  make="$(fetch "https://make.wordpress.org/core/tag/releases/feed/")" || make=""
  if [ -z "$news" ] && [ -z "$make" ]; then
    echo "check-latest-release: could not fetch either release feed" >&2
    exit 1
  fi
fi

# Every "WordPress X.Y[.Z] Beta N" / "RC N" / "Release Candidate N" mention, both feeds.
mentions="$(printf '%s\n%s\n' "$news" "$make" \
  | sed 's/&nbsp;/ /g' \
  | grep -oE 'WordPress [0-9]+\.[0-9]+(\.[0-9]+)? *(Beta|Release Candidate|RC) *[0-9]*' \
  | sed 's/^WordPress //')" || mentions=""
if [ -z "$mentions" ]; then
  echo "check-latest-release: no Beta/RC mentions in either feed" >&2
  exit 2
fi

# Normalize to "version priority suffix" (priority: RC=1, Beta=2) so one sort finds the
# newest build: newest version first, then RC before Beta, then RC4 before RC3.
best="$(printf '%s\n' "$mentions" | awk '
  {
    ver = $1
    rest = $0
    sub(/^[^ ]+ */, "", rest)
    pri = (rest ~ /RC|Release Candidate/) ? 1 : 2
    num = 1
    if (match(rest, /[0-9]+ *$/)) num = substr(rest, RSTART, RLENGTH) + 0
    print ver, pri, num
  }' | sort -k1,1Vr -k2,2n -k3,3nr | head -1)"

ver="${best%% *}"
rest="${best#* }"
pri="${rest%% *}"
num="${rest#* }"
if [ "$pri" = "1" ]; then label="RC$num"; else label="beta$num"; fi
prerelease="$ver-$label"

# The cycle gate. Outside a release cycle the feeds still carry the LAST cycle's
# announcements, and returning those forever is how an automation ends up re-testing a
# release that already shipped. Active means: strictly ahead of current stable.
stable="${WP_AUDIT_STABLE:-}"
if [ -z "$stable" ]; then
  stable="$(fetch "https://api.wordpress.org/core/version-check/1.7/" \
    | grep -oE '"current":"[0-9][^"]*"' | head -1 | sed 's/.*:"//; s/"//')" || stable=""
fi
if [ -n "$stable" ]; then
  highest="$(printf '%s\n%s\n' "$stable" "$ver" | sort -V | tail -1)"
  if [ "$ver" = "$stable" ] || [ "$highest" = "$stable" ]; then
    echo "check-latest-release: newest prerelease mention is $prerelease but stable is already $stable — no active cycle" >&2
    exit 2
  fi
fi

# Betas and RCs are packaged at the wordpress.org root (stable lives at
# downloads.wordpress.org/release/ — the two-lane split rc_build_identity.sh checks).
# Announced-but-not-built happens on release day; that is WAITING, not absence.
url="https://wordpress.org/wordpress-$prerelease.zip"
if [ "${WP_AUDIT_SKIP_PACKAGE_CHECK:-0}" != "1" ]; then
  if ! curl -sIfL --max-time 30 -o /dev/null "$url"; then
    echo "check-latest-release: feeds announce $prerelease but $url is not live yet" >&2
    exit 3
  fi
fi

case "$MODE" in
  url) echo "$url" ;;
  *)   echo "$prerelease" ;;
esac
