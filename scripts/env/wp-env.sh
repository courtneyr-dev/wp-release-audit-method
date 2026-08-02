#!/bin/bash
# wp-env driver — @wordpress/env, the environment this repo's suites grew up on.
#
# Nine scripts in scripts/ already drive wp-env by hand (crud-suite.sh, verify.sh,
# multisite-11.sh, users-pages-install.sh, preflight-sensitivity.sh, lib-fast.sh …).
# This driver EXTRACTS what those already do — the same `wp db reset --yes`, the same
# memory-raised `core download`, the same docker-exec fast path — rather than inventing
# a second way to talk to the same containers.
#
# THE FAST PATH IS THE WHOLE POINT. `npx @wordpress/env run` pays ~1.4s of node startup
# per call; `docker exec` against the same container pays ~0.12s — measured 12x on
# 2026-07-29. A 150-call suite is ~3.5 minutes of pure overhead versus ~18 seconds, which
# on release-party timescales is the difference between reporting during the party and
# reporting after it. So env_wp resolves the container ONCE at init and execs into it
# forever after. The npx route survives only as a fallback for when the container cannot
# be named, and the capabilities that depend on the fast path are withheld in that case.
#
# Verified 2026-08-01 against @wordpress/env 10.x on Docker Desktop / arm64 macOS, with a
# throwaway project under $HOME (NOT $TMPDIR — that path breaks the container mounts).
#
# DELTAS FROM THE DDEV REFERENCE (read scripts/env/ddev.sh first):
#
#   no https                — wp-env serves http://localhost:PORT and nothing else.
#   no hostfs-synced        — the document root is a plain Docker bind mount, so the host
#                             view is synchronous in both directions. env_sync stays a
#                             no-op; there is no Mutagen equivalent to flush.
#   snapshot is SYNTHESISED — wp-env has no snapshot verb, so this driver builds one from
#                             `wp db export` / `wp db import`. Dumps live on the host,
#                             OUTSIDE the document root: a dump written inside it would
#                             show up in env_tree and read as a WordPress finding.
#
# Four things it probes rather than assumes, all four found by that verification run:
#
#   1. THE EXEC USER IS NOT ALWAYS 33. lib-fast.sh hardcodes uid 33 (www-data), which is
#      right for the images it was written against. Current wp-env builds run the CLI
#      container as the HOST uid so the bind-mounted document root stays writable, and
#      record that in the compose file. Read it off the container; keep 33 as the fallback.
#   2. THE DOCUMENT ROOT PATH IS NOT FIXED. It is ~/.wp-env/<project>-<hash>/WordPress on
#      a default project but wordpress-<n> once a project pins a core version, and both
#      live under a hash this driver has no business recomputing. Read the mount table.
#   3. CORE-UPDATER IS CONDITIONAL. WordPress's own updater needs get_filesystem_method()
#      == direct AND egress to api.wordpress.org. Both hold on a stock wp-env, but a
#      locked-down docker network or an FS_METHOD in `config` breaks either one, and the
#      243-stale-file finding is exactly the thing that then reports a false PASS.
#   4. SUBDOMAIN MULTISITE IS NOT ACTUALLY REFUSED. The folklore — and this driver's own
#      first draft — said WP-CLI will not convert an install served at host:PORT. It
#      does. `wp core multisite-install --subdomains --url=http://localhost:8987` prints
#      "Warning: Wildcard DNS may not be configured correctly." and then succeeds; sites
#      get domain "beta.localhost:8987", `--url` addressing works, content stays isolated,
#      and http://beta.localhost:8987/ answers 200 with the subsite's content. All
#      verified 2026-08-01.
#
#      What actually decides it is whether *.localhost resolves ON THE HOST, which is an
#      OS question, not a WordPress one: macOS and systemd-resolved answer it, a plain
#      glibc CI runner does not. So the capability is probed with a real request to a
#      throwaway *.localhost name rather than declared or denied on principle.
#
#      Note the limit this does NOT fix: nothing inside the containers can reach the site
#      over HTTP at all (loopback to localhost:PORT hits the container, not the web
#      service), so cron and REST self-requests are dead for the main site and subsites
#      alike. That is a wp-env property, not a subdomain one, and no capability token in
#      lib-env.sh covers it.

_WPENV_DIR=""
_WPENV_SERVICE=""
_WPENV_WEB_SERVICE=""
_WPENV_CONTAINER=""
_WPENV_WEB_CONTAINER=""
_WPENV_USER=""
_WPENV_DOCROOT=""
_WPENV_SNAPDIR=""

env_driver_init() {
  local target="${1:-.}"
  command -v npx >/dev/null 2>&1 || { echo "wp-env: npx not installed — needs Node.js" >&2; return 1; }
  command -v docker >/dev/null 2>&1 || { echo "wp-env: docker not installed" >&2; return 1; }

  _WPENV_DIR="$(cd "$target" 2>/dev/null && pwd)" || { echo "wp-env: no such directory: $target" >&2; return 1; }
  if [ ! -f "$_WPENV_DIR/.wp-env.json" ]; then
    echo "wp-env: $_WPENV_DIR has no .wp-env.json." >&2
    echo "        echo '{\"core\":null}' > '$_WPENV_DIR/.wp-env.json' && (cd '$_WPENV_DIR' && npx @wordpress/env start)" >&2
    return 1
  fi

  # The dev site and the tests site are separate containers with separate databases and
  # separate document roots. The suites in this repo use both — crud-suite.sh runs against
  # `cli` so state stays inspectable afterwards, verify.sh and multisite-11.sh run against
  # `tests-cli`. Default to `cli`, matching lib-fast.sh.
  _WPENV_SERVICE="${WP_AUDIT_WPENV_SERVICE:-cli}"
  case "$_WPENV_SERVICE" in
    cli)       _WPENV_WEB_SERVICE="wordpress" ;;
    tests-cli) _WPENV_WEB_SERVICE="tests-wordpress" ;;
    *) echo "wp-env: WP_AUDIT_WPENV_SERVICE must be 'cli' or 'tests-cli', got '$_WPENV_SERVICE'" >&2; return 1 ;;
  esac

  _wpenv_resolve || return 1
}

# ---------------------------------------------------------------- container resolution

# Two tiers, because container names are derived and derived names drift.
#
# Tier 1 is lib-fast.sh's regex verbatim: wp-env-<project>-<hash>-<service>-1. Tier 2
# exists because Docker Compose sanitises project names (a directory called "wp-7.0.2"
# loses its dots) and that silently breaks tier 1 — but the compose labels still carry
# the untouched working directory, which wp-env always names wp-env-<project>-<hash>.
#
# Tier 2 also has to reject ONE-OFF containers. `wp-env start` spawns short-lived
# wp-env-<project>-<hash>-cli-run-<id> helpers that carry the same service label as the
# real thing; latching onto one means every later docker exec fails with "no such
# container" the moment the helper exits, mid-suite, for no reason a results table would
# ever explain. Tier 1's trailing "-1" excludes them by luck; tier 2 does it on purpose.
_wpenv_find_container() {
  local service="$1" project name
  project="$(basename "$_WPENV_DIR")"

  name="$(docker ps --format '{{.Names}}' 2>/dev/null \
    | grep -E "^wp-env-${project}-[a-f0-9]+-${service}-1$" | head -1)"
  if [ -z "$name" ]; then
    name="$(docker ps --format '{{.Names}}|{{.Label "com.docker.compose.project.working_dir"}}|{{.Label "com.docker.compose.service"}}|{{.Label "com.docker.compose.oneoff"}}' 2>/dev/null \
      | awk -F'|' -v s="$service" -v p="/wp-env-${project}-" \
          '$3 == s && $4 != "True" && index($2, p) { print $1; exit }')"
  fi
  echo "$name"
}

_wpenv_resolve() {
  _WPENV_CONTAINER="$(_wpenv_find_container "$_WPENV_SERVICE")"
  _WPENV_WEB_CONTAINER="$(_wpenv_find_container "$_WPENV_WEB_SERVICE")"

  if [ -n "$_WPENV_CONTAINER" ]; then
    # Compose records the user it runs the service as. Empty on the older images, where
    # www-data (33) is correct; "<uid>:<gid>" on current ones, where 33 would be writing
    # into a bind mount it does not own.
    _WPENV_USER="$(docker inspect --format '{{.Config.User}}' "$_WPENV_CONTAINER" 2>/dev/null)"
    [ -n "$_WPENV_USER" ] && [ "$_WPENV_USER" != "root" ] || _WPENV_USER=33

    # Don't construct this path — the directory under ~/.wp-env is hash-named and the
    # docroot inside it is WordPress or wordpress-<n> depending on the project's config.
    _WPENV_DOCROOT="$(docker inspect \
      --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Source}}{{end}}{{end}}' \
      "$_WPENV_CONTAINER" 2>/dev/null)"
    # A named volume reports a path that only exists inside the Docker VM. If the host
    # cannot see it, there is no hostfs here and env_tree must say so rather than guess.
    [ -n "$_WPENV_DOCROOT" ] && [ -d "$_WPENV_DOCROOT" ] || _WPENV_DOCROOT=""

    _WPENV_SNAPDIR="${WP_ENV_HOME:-$HOME/.wp-env}/.wpaudit-snapshots/$(docker inspect \
      --format '{{index .Config.Labels "com.docker.compose.project"}}' "$_WPENV_CONTAINER" 2>/dev/null)-$_WPENV_SERVICE"
    return 0
  fi

  # No container name matched. wp-env may still be running and reachable through npx, so
  # check before failing — but say plainly that every call from here costs ~1.4s.
  if _wpenv_npx wp --version >/dev/null 2>&1; then
    echo "wp-env: could not name the '$_WPENV_SERVICE' container for $(basename "$_WPENV_DIR")." >&2
    echo "        Falling back to 'npx @wordpress/env run' — ~12x slower per call, and" >&2
    echo "        hostfs / snapshot are withheld because both need the container." >&2
    _WPENV_USER=""; _WPENV_DOCROOT=""; _WPENV_SNAPDIR=""
    return 0
  fi

  echo "wp-env: no running environment for $_WPENV_DIR" >&2
  echo "        start it first:  (cd '$_WPENV_DIR' && npx @wordpress/env start)" >&2
  return 1
}

# Fast path. Same shape as lib-fast.sh's w(): stdout only, CRs stripped.
#
# Capture-then-clean rather than pipe, because a pipeline returns the LAST stage's status —
# `docker exec … | tr` is always 0 even when WP-CLI failed. lib-fast.sh's w() has that
# shape, which is fine for its callers, but the driver interface promises a real exit
# status: every `env_wp … || fallback` in every suite depends on it, and a driver that
# cannot report failure manufactures false PASSes.
_wpenv_raw() {
  local out rc
  out="$(docker exec -u "$_WPENV_USER" "$_WPENV_CONTAINER" "$@" 2>/dev/null)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | tr -d '\r'
  return $rc
}

# The slow path has to strip wp-env's own chrome — the "ℹ Starting…" / "✔ Ran…" lines and
# the blank lines around them — so it normalises more than the fast path does. This filter
# is lifted unchanged from crud-suite.sh / verify.sh, which is where it was proven.
#
# Same capture-then-filter reasoning, with an extra trap: `grep -v` exits 1 when it emits
# nothing, so piping straight through would report failure for every command that
# legitimately prints no output.
_wpenv_npx() {
  local out rc
  out="$( ( cd "$_WPENV_DIR" && npx --yes @wordpress/env@latest run "$_WPENV_SERVICE" -- "$@" ) 2>/dev/null )"
  rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | grep -vE "^(ℹ|✔|npm warn)" | tr -d '\r' | sed '/^$/d'
  return $rc
}

# ---------------------------------------------------------------- capabilities

# Whether a subsite would be REACHABLE, which is the real constraint — not whether the
# conversion command succeeds.
#
# A plausible-sounding claim was checked here and turned out to be false: that WP-CLI
# refuses `core multisite-convert --subdomains` when the domain carries a port. It does
# not. Measured 2026-08-01 against http://localhost:8889 — WP-CLI printed "Warning:
# Wildcard DNS may not be configured correctly", converted anyway, and exited 0. (The
# port restriction is real, but it belongs to the browser-side Network Setup screen, not
# to WP-CLI.) So the conversion is never the blocker; resolution is.
#
# On the same host, sub1.localhost:8889 then resolved and served HTTP 200, so wp-env CAN
# do subdomain multisite — conditionally. RFC 6761 says everything under `localhost`
# resolves to loopback, and macOS and systemd-resolved honour it, but plenty of Linux
# setups do not. Getting this wrong in the optimistic direction produces a network that
# answers 200 on the main site and nothing else, which from inside a results table is
# indistinguishable from a WordPress routing bug.
#
# Ask the RESOLVER, not the site. An earlier draft of this probe made an HTTP request to
# <name>.localhost:PORT and flickered: during a `wp-env start` rebuild the port is closed,
# so curl failed with "connection refused" rather than "could not resolve" and the
# capability vanished and returned across two env_init calls on the same project. A
# flickering capability is worse than an absent one — half the runs quietly promote a
# BLOCKED cell to PASS. Whether Apache is listening this second is a different question.
#
# No single resolver is present everywhere: getent is glibc-only (absent on macOS),
# dscacheutil is macOS-only, dig and host are frequently not installed. Try in order and
# fall back to ping, which fails fast on a name that does not resolve. ~40ms on macOS.
_wpenv_wildcard_localhost() {
  local probe="wpaudit-wildcard-probe.localhost"
  if command -v getent >/dev/null 2>&1; then
    getent hosts "$probe" >/dev/null 2>&1 && return 0
  fi
  if command -v dscacheutil >/dev/null 2>&1; then
    dscacheutil -q host -a name "$probe" 2>/dev/null | grep -q 'ip_address' && return 0
  fi
  ping -c 1 "$probe" >/dev/null 2>&1
}

env_driver_caps() {
  local caps="db-reset php-switch core-zip shell multisite-subdir apache"

  # Bind mount, not a sync agent: writes are visible in both directions immediately.
  # Verified by writing from the container and reading on the host in the same command.
  [ -n "$_WPENV_DOCROOT" ] && caps="$caps hostfs"

  # Host-dependent, so probed in both directions rather than assumed in either.
  # See _wpenv_wildcard_localhost for what was actually measured.
  _wpenv_wildcard_localhost && caps="$caps multisite-subdomain"

  # WordPress's own updater, not WP-CLI's. Needs a directly-writable document root and
  # egress to api.wordpress.org; either can be absent on a hardened host, and without
  # both the 243-stale-file finding is unreachable rather than passing.
  #
  # The write probe TOUCHES A FILE instead of asking `test -w`, because on Docker Desktop
  # for macOS the bind-mount root reports itself as root:root 0755 while writes into it
  # succeed anyway — `test -w /var/www/html` returns 1 on an environment whose updater
  # works perfectly. Verified 2026-08-01: test -w FAILED, touch SUCCEEDED, and
  # get_filesystem_method() returned "direct" on the same container.
  if [ -n "$_WPENV_CONTAINER" ] \
     && docker exec -u "$_WPENV_USER" "$_WPENV_CONTAINER" sh -c \
          'touch /var/www/html/.wpaudit-probe && rm -f /var/www/html/.wpaudit-probe' >/dev/null 2>&1 \
     && docker exec -u "$_WPENV_USER" "$_WPENV_CONTAINER" \
          curl -sS -o /dev/null --max-time 8 https://api.wordpress.org/core/version-check/1.7/ >/dev/null 2>&1
  then
    caps="$caps core-updater"
  fi

  # Snapshots are synthesised, so probe the two things the synthesis needs: a reachable
  # database and a writable host directory to keep dumps in. Both go through docker exec,
  # so a fallback-mode driver never advertises this.
  if [ -n "$_WPENV_CONTAINER" ] && [ -n "$_WPENV_SNAPDIR" ] \
     && mkdir -p "$_WPENV_SNAPDIR" 2>/dev/null \
     && docker exec -u "$_WPENV_USER" "$_WPENV_CONTAINER" wp db query 'SELECT 1' >/dev/null 2>&1
  then
    caps="$caps snapshot"
  fi

  # Xdebug is a start-time flag (`wp-env start --xdebug`), so it is toggleable in the
  # sense the interface means — but only when the images were built with the extension.
  # A stock start leaves xdebug.so absent entirely, so look for the file, not the module.
  if [ -n "$_WPENV_WEB_CONTAINER" ] && docker exec "$_WPENV_WEB_CONTAINER" \
       sh -c 'ls "$(php -r "echo ini_get(\"extension_dir\");")" | grep -qi xdebug' >/dev/null 2>&1
  then
    caps="$caps xdebug"
  fi

  case "$(_wpenv_db_image)" in
    mysql*) caps="$caps mysql" ;;
    *)      caps="$caps mariadb" ;;
  esac

  echo "$caps"
}

# The database container is the service the CLI container talks to, so it tracks the same
# dev/tests split. Read the image rather than asking the server, because caps are probed
# before a suite has necessarily left a working wp-config.php in place.
_wpenv_db_image() {
  local db="mysql"
  [ "$_WPENV_SERVICE" = "tests-cli" ] && db="tests-mysql"
  docker inspect --format '{{.Config.Image}}' "$(_wpenv_find_container "$db")" 2>/dev/null
}

# ---------------------------------------------------------------- lifecycle

# CAUTION, and this one bites: `wp-env start` is NOT idempotent against a document root
# whose wp-config.php declares multisite while the database does not. Its own install step
# dies with "Site 'localhost:PORT/' not found. Verify DOMAIN_CURRENT_SITE…", wp-env reports
# a docker compose failure, and — because `stop` is a compose *down* — the containers are
# already gone, so a failed start leaves NOTHING RUNNING rather than the previous state.
# Reproduced 2026-08-01 by converting to multisite, resetting the database, and restarting.
#
# The fix is the `wp config delete WP_ALLOW_MULTISITE MULTISITE …` loop that multisite-11.sh
# opens with — which is what that loop has always been for. It is suite-level cleanup, not
# the driver's to do, so this returns the failure loudly instead of papering over it.
env_start() {
  ( cd "$_WPENV_DIR" && npx --yes @wordpress/env@latest start ) || {
    echo "wp-env: start failed — the environment is now DOWN, not merely unchanged." >&2
    echo "        If the site was multisite, clear the multisite constants from" >&2
    echo "        wp-config.php in the document root and start again." >&2
    return 1; }
  # Container ids change across a start; re-resolve so the fast path keeps working.
  _wpenv_resolve
}

# `stop` removes the containers rather than pausing them; the databases live in named
# volumes, so state survives, but nothing is exec-able until env_start returns.
env_stop()    { ( cd "$_WPENV_DIR" && npx --yes @wordpress/env@latest stop ); }
env_destroy() { ( cd "$_WPENV_DIR" && npx --yes @wordpress/env@latest destroy --force ); }

# ---------------------------------------------------------------- commands

env_wp() {
  if [ -n "$_WPENV_CONTAINER" ]; then _wpenv_raw wp "$@"; else _wpenv_npx wp "$@"; fi
}

env_exec() {
  if [ -n "$_WPENV_CONTAINER" ]; then
    docker exec -u "$_WPENV_USER" "$_WPENV_CONTAINER" "$@"
  else
    ( cd "$_WPENV_DIR" && npx --yes @wordpress/env@latest run "$_WPENV_SERVICE" -- "$@" )
  fi
}

env_docroot() { echo "$_WPENV_DOCROOT"; }

# Ask Docker for the published port instead of reading .wp-env.json: with autoPort (or
# --auto-port) the configured port is a request, not a fact, and a suite that curls the
# wrong port reports a dead front end.
env_url() {
  local p
  [ -n "$_WPENV_WEB_CONTAINER" ] || return 0
  p="$(docker port "$_WPENV_WEB_CONTAINER" 80 2>/dev/null | head -1 | sed 's/.*://')"
  [ -n "$p" ] && echo "http://localhost:$p"
}

# ---------------------------------------------------------------- database

env_db_reset() { env_wp db reset --yes >/dev/null; }

# No `tr -d '\r'` on the dump: it is data, and stripping bytes out of it would corrupt
# any row that legitimately contains a CR.
env_db_snapshot() {
  local name="$1"
  [ -n "$_WPENV_CONTAINER" ] || { echo "wp-env: snapshot needs the container fast path" >&2; return 3; }
  mkdir -p "$_WPENV_SNAPDIR" || return 1
  docker exec -u "$_WPENV_USER" "$_WPENV_CONTAINER" wp db export - --add-drop-table \
    > "$_WPENV_SNAPDIR/$name.sql" 2>/dev/null
  if [ ! -s "$_WPENV_SNAPDIR/$name.sql" ]; then
    rm -f "$_WPENV_SNAPDIR/$name.sql"
    echo "wp-env: snapshot '$name' produced an empty dump" >&2
    return 1
  fi
}

# Reset before importing. `db import` only replays what the dump contains, so tables
# created AFTER the snapshot — the per-site tables a multisite conversion adds, say —
# would survive a plain import and the "restored" database would not match the snapshot.
env_db_restore() {
  local name="$1" f
  [ -n "$_WPENV_CONTAINER" ] || { echo "wp-env: restore needs the container fast path" >&2; return 3; }
  f="$_WPENV_SNAPDIR/$name.sql"
  [ -s "$f" ] || { echo "wp-env: no snapshot named '$name' in $_WPENV_SNAPDIR" >&2; return 1; }
  env_db_reset || return 1
  docker exec -i -u "$_WPENV_USER" "$_WPENV_CONTAINER" wp db import - < "$f" >/dev/null 2>&1
}

# ---------------------------------------------------------------- PHP

# Report the WEB container's PHP, not the CLI container's. They are built from separate
# images and a project that pins only one of them ends up serving requests on a different
# version than `wp eval` reports — which reads as a version-specific WordPress bug.
env_php_get() {
  if [ -n "$_WPENV_WEB_CONTAINER" ]; then
    docker exec "$_WPENV_WEB_CONTAINER" php -r 'echo PHP_VERSION;' 2>/dev/null
  else
    env_wp eval 'echo PHP_VERSION;' 2>/dev/null
  fi
}

# phpVersion in .wp-env.json plus a rebuild. Edited through node rather than sed because
# .wp-env.json is the user's file and a regex would reformat the parts it didn't mean to
# touch; node is already a hard dependency of wp-env itself.
#
# Verifies the outcome — a start that fails to rebuild leaves the OLD version serving, and
# a suite would then attribute PHP-8.1 behaviour to a PHP-8.3 cell.
env_php_set() {
  local want="$1" got
  local -a flags=(start --update)

  # Xdebug is a property of the LAST start, not of the config file, so a plain restart here
  # would silently drop it — while WP_AUDIT_ENV_CAPS, computed once at env_init, went on
  # advertising it. That is the driver manufacturing its own over-claim, so carry the
  # current state across the rebuild.
  if [ -n "$_WPENV_WEB_CONTAINER" ] \
     && docker exec "$_WPENV_WEB_CONTAINER" sh -c 'php -m | grep -qi xdebug' >/dev/null 2>&1
  then
    flags+=(--xdebug)
  fi

  node -e '
    const fs = require("fs"), p = process.argv[1];
    const c = JSON.parse(fs.readFileSync(p, "utf8"));
    c.phpVersion = process.argv[2];
    fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n");
  ' "$_WPENV_DIR/.wp-env.json" "$want" || return 1
  ( cd "$_WPENV_DIR" && npx --yes @wordpress/env@latest "${flags[@]}" ) >/dev/null 2>&1
  _wpenv_resolve || return 1
  got="$(env_php_get)"
  case "$got" in
    "$want"*) echo "$got" ;;
    *) echo "wp-env: asked for PHP '$want', web container runs '$got' — rebuild did not take" >&2; return 1 ;;
  esac
}

# ---------------------------------------------------------------- core

# Accepts a version string ("7.1-beta4", "nightly") or a zip URL.
#
# The memory_limit=1024M is lib-fast.sh's wdl() and it is not optional: the container's
# default 128M OOMs mid-extract, WP-CLI still exits 0, and the OLD version stays in place.
# That is a silent wrong-version run, which is why the result is VERIFIED here rather than
# trusted — same reasoning as ddev.sh's env_core_install.
env_core_install() {
  local target="$1" before after
  before="$(env_wp core version)"
  case "$target" in
    http://*|https://*)
      env_exec sh -c "curl -sSL -o /tmp/core.zip '$target' && \
        rm -rf /tmp/core-x && mkdir -p /tmp/core-x && unzip -q /tmp/core.zip -d /tmp/core-x && \
        cp -a /tmp/core-x/wordpress/. /var/www/html/" >/dev/null 2>&1 ;;
    *)
      # --allow-root is a no-op at these uids; it is kept because every existing script in
      # scripts/ passes it and the invocations should stay diffable against each other.
      env_exec php -d memory_limit=1024M /usr/local/bin/wp core download \
        --version="$target" --force --allow-root >/dev/null 2>&1 ;;
  esac
  after="$(env_wp core version)"
  if [ -z "$after" ]; then
    echo "wp-env: core install left no readable version (was '$before')" >&2; return 1
  fi
  case "$target" in
    "$after"*|http*) ;;
    *) echo "wp-env: asked for '$target', got '$after' — install did not take" >&2; return 1 ;;
  esac
  echo "$after"
}

# ---------------------------------------------------------------- multisite

# Subdomain conversion works here (header note 4) but only where the host resolves
# *.localhost. Gate on the probed capability rather than on the attempt: WP-CLI will
# happily convert on a host that cannot then reach a single subsite, which leaves a
# network that answers 200 on the main site and nothing else — indistinguishable, from
# inside a results table, from a WordPress routing bug.
env_multisite_convert() {
  if [ "${1:-}" = "--subdomains" ]; then
    env_has multisite-subdomain || {
      echo "wp-env: this host does not resolve *.localhost, so subdomain subsites would" >&2
      echo "        be unreachable even though WP-CLI would convert. Use the ddev driver." >&2
      return 3; }
    env_wp core multisite-convert --subdomains
  else
    env_wp core multisite-convert
  fi
}
