#!/bin/bash
# Shared fast WP-CLI helper. Source this instead of shelling out to npx.
#
#   source lib-fast.sh && wpfast_init wp71-test-suite cli   # or: ... tests-cli
#   w wp core version
#
# WHY: every `npx @wordpress/env run ...` call costs ~1.4s of npx/node startup
# before WordPress does anything. `docker exec` against the same container costs
# ~0.12s. Measured 2026-07-29: 1.43s vs 0.12s — **12x**. A suite making 150 calls
# goes from ~3.5 minutes to ~18 seconds. On release-party timescales that is the
# difference between reporting during the party and reporting after it.
#
# The container must already be running (`wp-env start` once, up front).

WPFAST_CONTAINER=""

wpfast_init() {
  local project="$1" service="${2:-cli}"
  # wp-env names containers wp-env-<project>-<hash>-<service>-1
  WPFAST_CONTAINER=$(docker ps --format '{{.Names}}' \
    | grep -E "^wp-env-${project}-[a-f0-9]+-${service}-1$" | head -1)
  if [ -z "$WPFAST_CONTAINER" ]; then
    echo "wpfast: no running container for project '$project' service '$service'" >&2
    echo "        run: (cd ~/projects/$project && npx @wordpress/env start)" >&2
    return 1
  fi
  echo "wpfast: using $WPFAST_CONTAINER"
}

# Run WP-CLI (or any command) in the container. uid 33 = www-data.
w() { docker exec -u 33 "$WPFAST_CONTAINER" "$@" 2>/dev/null | tr -d '\r'; }

# Same, but keep stderr — use when you need to see an actual error.
wv() { docker exec -u 33 "$WPFAST_CONTAINER" "$@" 2>&1 | tr -d '\r'; }

# Core download needs a raised memory limit: the default 128M OOMs mid-extract
# and the failure is easy to swallow, silently leaving the OLD version in place.
wdl() { w php -d memory_limit=1024M /usr/local/bin/wp core download --version="$1" --force --allow-root; }
