#!/bin/bash
# WordPress Playground driver — the only driver with native prerelease WordPress.
#
# `--wp=beta|trunk|nightly|7.1-RC1` boots the real prerelease in about ten seconds. Every
# other driver here reaches a prerelease by fetching a zip and pointing WP-CLI at it, so
# during a Beta/RC cycle this is the one to reach for.
#
# It is also the driver least like the DDEV reference: no containers, no daemon, no shell,
# PHP compiled to WebAssembly, SQLite instead of MySQL, and no long-lived process for
# WP-CLI to attach to. Read ddev.sh first — this file is the delta from it.
#
# Verified 2026-08-01 against @wp-playground/cli 3.1.47 / Node 25.9 / arm64 macOS:
# installs of 6.8.6, 7.1-beta4, nightly and a wordpress.org zip URL; WP-CLI round trips;
# a host-side file-tree diff across a real 6.8.6 -> 7.0.2 core update; SQLite snapshot and
# restore; PHP 7.4 / 8.1 / 8.5 switching; subdirectory multisite served over HTTP; teardown.
#
# core-updater IS DECLARED, which contradicts the usual assumption about Playground, so
# here is the evidence. Inside the WASM sandbox `wp_remote_get()` reached
# api.wordpress.org (HTTP 200), `WP_Filesystem()` initialised as WP_Filesystem_Direct,
# `get_core_updates()` returned a genuine offer, and `Core_Upgrader::upgrade()` pulled
# wordpress-7.0.2-no-content.zip — the real partial-update package — and rewrote the
# mounted document root from 6.8.6 to 7.0.2. Run once through the CLI SAPI and once over
# HTTP through `wp-playground-cli server`; both completed. The upgraded tree then differed
# from a pristine 7.0.2 install by exactly one wp-content file, which is what a no-content
# package is supposed to leave behind. So stale-file findings ARE reachable here. Do not
# downgrade this to "WP-CLI only" without re-running that probe.
#
# Four things this driver does differently from ddev.sh, each because of a failure seen
# during that run:
#
#   1. IT NEVER USES A BLUEPRINT. Passing `--blueprint=<file>` SILENTLY OVERRIDES `--wp=`:
#      `--wp=6.8 --blueprint=x.json` installed 7.0.2 and exited 0. On a release-testing
#      rig that is the worst possible failure — every cell passes, against the wrong
#      WordPress. The `wp-cli` blueprint step also writes run-cli.php INTO the document
#      root and leaves it there, which lands in every file-tree diff as a phantom finding.
#      env_wp therefore runs wp-cli.phar directly through the `php` subcommand, which
#      gives real stdout, real stderr and a real exit code, and touches nothing.
#   2. IT PINS THE DOCUMENT ROOT WITH A MOUNT. With no mount the document root is a
#      per-run native temp dir (`start` instead hides it in ~/.wordpress-playground/sites/
#      <sha256-of-cwd> and leaves the project directory empty). Either way env_tree would
#      hash something that is not the site, or that disappears — exactly the harness fault
#      this repo calls INVALID rather than a finding.
#   3. IT PINS --site-url ON EVERY INVOCATION. Without it each run picks an ephemeral port
#      and WordPress records whatever it saw: two consecutive calls reported siteurl
#      http://127.0.0.1:63972 and http://127.0.0.1:63189, and a multisite converted under
#      one port is unreachable under the next.
#   4. IT DOES NOT UPGRADE IN PLACE WITH THE INSTALLER. Re-running the installer over a
#      populated document root prints "Cannot unzip WordPress files ... already exists",
#      changes nothing, and still exits 0. env_core_install installs to a scratch
#      directory and overlays instead — the same overwrite-don't-delete semantics as
#      ddev.sh's `wp core download --force`.
#
# NOT declared, and why:
#   https                — no TLS anywhere in the CLI; the server is plain HTTP.
#   shell                — WASM sandbox. `php` runs PHP, not commands. env_exec is left
#                          unimplemented so lib-env.sh's loud default fires.
#   multisite-subdomain  — confirmed here too that WP-CLI does NOT refuse this on a
#                          host:PORT install: `core multisite-convert --subdomains` warns
#                          "Wildcard DNS may not be configured correctly", converts, and
#                          writes SUBDOMAIN_INSTALL=true against 127.0.0.1:9400. So the
#                          conversion is not the gate. Two other things are, and both
#                          fail structurally for the URL this driver pins. Playground's
#                          own enableMultisite step throws on any custom port — verified
#                          by running it: "The current host is 127.0.0.1:9400, but
#                          WordPress multisites do not support custom ports" — while the
#                          same step against a portless hostname succeeds and still
#                          writes SUBDOMAIN_INSTALL=false. And the resolver gate cannot
#                          be passed at all, because this driver's host is the IP literal
#                          127.0.0.1 and no resolver answers for a subdomain of an IP.
#                          There is nothing left to probe; if a future version accepts
#                          ports and a real hostname, add a wildcard-DNS lookup here.
#   nginx / apache       — neither. Requests are routed into php-wasm by a Node server.
#   mysql / mariadb      — SQLite only. --skip-sqlite-setup expects an external MySQL this
#                          driver does not manage.
#   hostfs-synced        — the mount is the host directory itself; writes are visible
#                          immediately, so env_sync stays the lib-env.sh no-op.
#
# Layout, created by env_driver_init under the target directory:
#   <target>/wordpress/   document root, mounted at /wordpress  (this is env_docroot)
#   <target>/.playground/ driver state — deliberately OUTSIDE the document root so
#                         wp-cli.phar and DB snapshots never appear in env_tree
#
# Env overrides: WP_AUDIT_PLAYGROUND_BIN, WP_AUDIT_PLAYGROUND_PORT (default 9400),
# WP_AUDIT_PLAYGROUND_WP (version for the initial install, default "latest"),
# WP_AUDIT_WP_CLI_PHAR (path to an existing wp-cli.phar, skips the download).

_PG_BIN=()
_PG_DIR=""
_PG_DOCROOT=""
_PG_STATE=""
_PG_URL=""

# Playground's own download cache. A version string that does not exist yet is cached here
# as an 18-byte "Release not found." file named <version>.zip — see _pg_unpoison_cache.
_PG_CACHE="$HOME/.wordpress-playground"

env_driver_init() {
  local target="${1:-.}"

  # The CLI ships no `engines` field and no version gate of its own, so a too-old Node
  # fails deep inside the WASM loader with nothing actionable. Check it here instead.
  command -v node >/dev/null 2>&1 || { echo "playground: node not installed — needs Node >= 20.18" >&2; return 1; }
  local nv major minor
  nv="$(node --version 2>/dev/null)"; nv="${nv#v}"
  major="${nv%%.*}"; minor="${nv#*.}"; minor="${minor%%.*}"
  if [ "${major:-0}" -lt 20 ] || { [ "$major" = "20" ] && [ "${minor:-0}" -lt 18 ]; }; then
    echo "playground: Node $nv is too old — @wp-playground/cli needs >= 20.18" >&2
    return 1
  fi

  if [ -n "${WP_AUDIT_PLAYGROUND_BIN:-}" ]; then
    read -r -a _PG_BIN <<<"$WP_AUDIT_PLAYGROUND_BIN"
  elif command -v wp-playground-cli >/dev/null 2>&1; then
    _PG_BIN=(wp-playground-cli)
  elif [ -x "$target/node_modules/.bin/wp-playground-cli" ]; then
    _PG_BIN=("$target/node_modules/.bin/wp-playground-cli")
  elif command -v npx >/dev/null 2>&1; then
    # Works, but re-resolves the registry on every call and puts an extra process between
    # env_stop and the server it is trying to kill. Prefer an installed binary.
    _PG_BIN=(npx --yes @wp-playground/cli@latest)
  else
    echo "playground: no wp-playground-cli and no npx — npm i -g @wp-playground/cli" >&2
    return 1
  fi

  mkdir -p "$target" 2>/dev/null
  _PG_DIR="$(cd "$target" 2>/dev/null && pwd)" || { echo "playground: no such directory: $target" >&2; return 1; }
  _PG_DOCROOT="$_PG_DIR/wordpress"
  _PG_STATE="$_PG_DIR/.playground"
  mkdir -p "$_PG_DOCROOT" "$_PG_STATE/bin" "$_PG_STATE/snapshots" || return 1

  # Written once and re-read afterwards so the URL survives across shells. WordPress bakes
  # it into siteurl/home and into the multisite tables; changing it later breaks the site.
  if [ -s "$_PG_STATE/site-url" ]; then
    _PG_URL="$(cat "$_PG_STATE/site-url")"
  else
    _PG_URL="http://127.0.0.1:${WP_AUDIT_PLAYGROUND_PORT:-9400}"
    printf '%s\n' "$_PG_URL" > "$_PG_STATE/site-url"
  fi

  _pg_wpcli || return 1

  # Unlike DDEV there is nothing to be "running", and unlike DDEV this driver can create
  # the site itself, so an empty document root is not an init failure — env_start fills it.
  # lib-env.sh's env_assert_ready is what catches a genuinely unusable target.
  if [ ! -f "$_PG_DOCROOT/wp-includes/version.php" ]; then
    echo "playground: no WordPress in $_PG_DOCROOT yet — run env_start (WP_AUDIT_PLAYGROUND_WP=beta env_start to pin a prerelease)" >&2
  fi
  return 0
}

# WP-CLI is not a flag and not a subcommand — Playground only offers it as a blueprint
# step, which is the one thing this driver refuses to use (see note 1). So keep a phar in
# the state directory and mount it alongside the document root.
_pg_wpcli() {
  local phar="$_PG_STATE/bin/wp-cli.phar"
  [ -s "$phar" ] && return 0
  if [ -n "${WP_AUDIT_WP_CLI_PHAR:-}" ] && [ -s "$WP_AUDIT_WP_CLI_PHAR" ]; then
    cp "$WP_AUDIT_WP_CLI_PHAR" "$phar" && return 0
  fi
  command -v curl >/dev/null 2>&1 || { echo "playground: need curl to fetch wp-cli.phar, or set WP_AUDIT_WP_CLI_PHAR" >&2; return 1; }
  curl -sSfL -o "$phar" https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar 2>/dev/null \
    || { rm -f "$phar"; echo "playground: could not fetch wp-cli.phar — set WP_AUDIT_WP_CLI_PHAR to a local copy" >&2; return 1; }
  [ -s "$phar" ]
}

# Every Playground invocation. --php is re-sent each time because there is no config file
# to hold it: the PHP version is a per-process argument, which is also why php-switch is
# free here and a container rebuild on DDEV.
_pg() {
  local sub="$1"; shift
  "${_PG_BIN[@]}" "$sub" \
    --mount-before-install="$_PG_DOCROOT:/wordpress" \
    --mount-before-install="$_PG_STATE/bin:/wpaudit" \
    --site-url="$_PG_URL" \
    --php="$(env_php_get)" \
    --verbosity=quiet \
    "$@"
}

_pg_port() {
  local hostport="${_PG_URL#*://}"; hostport="${hostport%%/*}"
  case "$hostport" in *:*) echo "${hostport##*:}" ;; *) echo 80 ;; esac
}

env_driver_caps() {
  local caps="core-updater php-switch core-zip xdebug multisite-subdir"

  # The mount IS the host directory — no bind-mount indirection, no Mutagen, nothing to
  # flush. A 3950-file install was complete to `find` the instant the process exited.
  [ -d "$_PG_DOCROOT" ] && [ -w "$_PG_DOCROOT" ] && caps="$caps hostfs"

  # wp-content/database is where the SQLite integration keeps .ht.sqlite, and that single
  # file IS the storage engine — which is what makes reset, snapshot and restore plain
  # file operations here.
  #
  # Two cases, because lib-env.sh caches capabilities at env_init and the site may not
  # exist yet. An empty document root means this driver is about to build the site, and it
  # never passes --skip-sqlite-setup, so SQLite is a settled fact. A populated document
  # root is evidence in itself: no database directory means someone pointed this at an
  # external MySQL, which this driver does not manage and must not claim to reset.
  if [ ! -f "$_PG_DOCROOT/wp-includes/version.php" ] || [ -d "$_PG_DOCROOT/wp-content/database" ]; then
    caps="$caps sqlite db-reset snapshot"
  fi

  echo "$caps"
}

# `build-snapshot --outfile=` exists but has no symmetric restore, so it is not what backs
# the snapshot capability. These three are: the entire database is one file in the mounted
# document root. Verified with a real round trip — seed A, snapshot, mutate to B, restore,
# read A back.
env_db_snapshot() {
  local name="${1:?snapshot name required}"
  [ -d "$_PG_DOCROOT/wp-content/database" ] || return 1
  rm -rf "$_PG_STATE/snapshots/$name"
  cp -a "$_PG_DOCROOT/wp-content/database" "$_PG_STATE/snapshots/$name"
}

env_db_restore() {
  local name="${1:?snapshot name required}"
  [ -d "$_PG_STATE/snapshots/$name" ] || { echo "playground: no snapshot '$name'" >&2; return 1; }
  rm -rf "$_PG_DOCROOT/wp-content/database"
  cp -a "$_PG_STATE/snapshots/$name" "$_PG_DOCROOT/wp-content/database"
}

# `wp db reset` fails under the SQLite integration ("Failed to get current SQL modes"), so
# do what DDEV's drop-and-recreate does: leave an empty database and an uninstalled site.
env_db_reset() {
  [ -d "$_PG_DOCROOT/wp-content/database" ] || return 1
  rm -f "$_PG_DOCROOT/wp-content/database/.ht.sqlite"
}

env_start() {
  local port; port="$(_pg_port)"
  if [ ! -f "$_PG_DOCROOT/wp-includes/version.php" ]; then
    _pg_install "${WP_AUDIT_PLAYGROUND_WP:-latest}" || return 1
  fi
  _pg_server_up && return 0
  # exec so the pidfile holds the process that becomes the server, not a wrapper shell.
  ( exec "${_PG_BIN[@]}" server \
      --mount-before-install="$_PG_DOCROOT:/wordpress" \
      --mount-before-install="$_PG_STATE/bin:/wpaudit" \
      --site-url="$_PG_URL" --port="$port" --php="$(env_php_get)" \
      --wordpress-install-mode=do-not-attempt-installing \
      --verbosity=normal >"$_PG_STATE/server.log" 2>&1 ) &
  echo $! > "$_PG_STATE/server.pid"
  local i
  for i in $(seq 1 60); do _pg_server_up && return 0; sleep 1; done
  echo "playground: server did not come up on port $port — see $_PG_STATE/server.log" >&2
  return 1
}

# Both halves matter: a stale log from a crashed run still says "Ready!", and a live pid
# says nothing about whether the WASM boot finished.
_pg_server_up() {
  local pid
  [ -f "$_PG_STATE/server.pid" ] || return 1
  pid="$(cat "$_PG_STATE/server.pid")"
  kill -0 "$pid" 2>/dev/null || return 1
  grep -q "Ready!" "$_PG_STATE/server.log" 2>/dev/null
}

env_stop() {
  local pid child
  [ -f "$_PG_STATE/server.pid" ] || return 0
  pid="$(cat "$_PG_STATE/server.pid")"
  # npx sits between us and node when no binary was on PATH, so sweep children too.
  for child in $(pgrep -P "$pid" 2>/dev/null); do kill "$child" 2>/dev/null; done
  kill "$pid" 2>/dev/null
  rm -f "$_PG_STATE/server.pid" "$_PG_STATE/server.log"
  return 0
}

env_destroy() {
  env_stop
  rm -rf "$_PG_DOCROOT" "$_PG_STATE"
}

# do-not-attempt-installing on every call: this driver never wants an implicit install
# behind a `wp` command, and Playground will happily perform one otherwise.
#
# Not piped, unlike ddev.sh, so the WP-CLI exit code survives — a driver whose `wp` always
# reports success is a driver that reports PASS for cells that never ran.
env_wp() {
  local out rc
  out="$(_pg php --wordpress-install-mode=do-not-attempt-installing \
          -- /wpaudit/wp-cli.phar --path=/wordpress "$@" 2>/dev/null)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | tr -d '\r'
  return $rc
}

env_docroot() { echo "$_PG_DOCROOT"; }
env_url()     { echo "$_PG_URL"; }

env_php_get() {
  if [ -s "$_PG_STATE/php-version" ]; then cat "$_PG_STATE/php-version"; else echo "8.3"; fi
}

# No rebuild, no restart — the next invocation just gets a different PHP binary. Verified
# 7.4.33, 8.1.34 and 8.5.8 against the same document root.
env_php_set() {
  case "$1" in
    8.5|8.4|8.3|8.2|8.1|8.0|7.4|5.2) printf '%s\n' "$1" > "$_PG_STATE/php-version" ;;
    *) echo "playground: PHP $1 is not one of 8.5 8.4 8.3 8.2 8.1 8.0 7.4 5.2" >&2; return 1 ;;
  esac
  # A live server keeps the PHP it booted with, so leaving it up would put env_wp on the
  # new version and every HTTP request on the old one.
  if _pg_server_up; then env_stop && env_start >/dev/null; fi
}

# An unreleased version string returns "Release not found." and Playground caches those 18
# bytes as <version>.zip. The cache entry outlives the mistake, so `--wp=7.1-RC1` typed a
# few days early keeps failing after RC1 actually ships. Clear only obvious garbage.
_pg_unpoison_cache() {
  local z="$_PG_CACHE/$1.zip"
  [ -f "$z" ] || return 0
  if [ "$(wc -c < "$z" 2>/dev/null | tr -d ' ')" -lt 1024 ]; then rm -f "$z"; fi
  return 0
}

# Fresh install into an empty document root. Only correct when empty — see note 4.
_pg_install() {
  local version="$1"
  _pg_unpoison_cache "$version"
  "${_PG_BIN[@]}" run-blueprint \
    --mount-before-install="$_PG_DOCROOT:/wordpress" \
    --site-url="$_PG_URL" --php="$(env_php_get)" --wp="$version" \
    --wordpress-install-mode=download-and-install \
    --verbosity=quiet >/dev/null 2>&1
  [ -f "$_PG_DOCROOT/wp-includes/version.php" ] \
    || { echo "playground: install of '$version' produced no WordPress in $_PG_DOCROOT" >&2; return 1; }
}

# Accepts anything --wp accepts: "6.8", "7.1-RC1", "beta", "trunk", "nightly", or a zip URL.
# The prerelease channels are the reason this driver exists.
#
# Installs to a scratch directory and overlays, because the installer refuses to overwrite
# a populated document root while still exiting 0 (note 4). Overlay means files dropped by
# the new version stay behind — the same semantics as ddev.sh's `wp core download --force`,
# and the condition a stale-file cell is looking for, so do not "fix" it into a wipe.
#
# VERIFIES the result rather than trusting the exit code, for the same reason ddev.sh does.
env_core_install() {
  local target="$1" before after scratch
  before="$(env_wp core version)"
  scratch="$_PG_STATE/scratch"
  rm -rf "$scratch"; mkdir -p "$scratch" || return 1
  _pg_unpoison_cache "$target"

  "${_PG_BIN[@]}" run-blueprint \
    --mount-before-install="$scratch:/wordpress" \
    --site-url="$_PG_URL" --php="$(env_php_get)" --wp="$target" \
    --wordpress-install-mode=download-and-install \
    --verbosity=quiet >/dev/null 2>&1

  if [ ! -f "$scratch/wp-includes/version.php" ]; then
    rm -rf "$scratch"
    echo "playground: '$target' did not resolve to a WordPress build (was '$before')" >&2
    return 1
  fi

  # wp-config.php carries the multisite constants and wp-content carries the database, so
  # both survive the overlay.
  local entry
  for entry in "$scratch"/* "$scratch"/.[!.]*; do
    [ -e "$entry" ] || continue
    case "$(basename "$entry")" in wp-content|wp-config.php) continue ;; esac
    cp -a "$entry" "$_PG_DOCROOT/" || return 1
  done
  rm -rf "$scratch"

  env_wp core update-db >/dev/null 2>&1 || true   # best effort: no DB yet on a bare tree

  after="$(env_wp core version)"
  if [ -z "$after" ]; then
    echo "playground: core install left no readable version (was '$before')" >&2; return 1
  fi
  case "$target" in
    latest|beta|trunk|nightly|http://*|https://*) ;;   # channel names carry nothing to compare
    *) case "$after" in "$target"*) ;; *) echo "playground: asked for '$target', got '$after' — install did not take" >&2; return 1 ;; esac ;;
  esac
  echo "$after"
}

# Subdirectory only. Verified end to end: convert, `wp site create --slug=sub1`, then
# `wp-playground-cli server` served <title>My WordPress Website</title> at / and
# <title>Sub1</title> at /sub1/.
env_multisite_convert() {
  if [ "${1:-}" = "--subdomains" ]; then
    echo "playground: subdomain multisite is not supported here — nothing resolves a subdomain of ${_PG_URL#*://}, and Playground's own enableMultisite step rejects custom ports outright" >&2
    return 3
  fi
  env_wp core multisite-convert
}
