#!/bin/bash
# DDEV driver — the reference implementation.
#
# DDEV supports every capability in lib-env.sh, which is why it's the reference: each
# other driver is documented as a delta from this file. If you're writing a new driver,
# read this one first.
#
# Verified 2026-08-01 against DDEV v1.25.3 / arm64 macOS with real WordPress installs:
# config, start, old-core install, host-side tree diff across a 6.7.2 -> 6.9 upgrade,
# snapshot + restore, PHP switch, multisite convert, teardown.
#
# Two things this driver probes rather than assumes, both found by that run:
#
#   1. SNAPSHOTS SILENTLY FAIL under $TMPDIR on macOS. A project in /var/folders/.../T/
#      returns "cp: cannot create regular file '/mnt/ddev_config/db_snapshots/...':
#      Permission denied"; the identical sequence in $HOME works. A fixture script
#      reaching for `mktemp -d` would advertise a snapshot capability it doesn't have.
#   2. MUTAGEN IS ON BY DEFAULT on macOS/Windows, so the host view of the document root
#      is ASYNC. Hashing a file tree without env_sync gives a quietly wrong answer —
#      a harness fault that reads exactly like a WordPress finding.

_DDEV_DIR=""

env_driver_init() {
  local target="${1:-.}"
  command -v ddev >/dev/null 2>&1 || { echo "ddev: not installed — https://ddev.com/get-started/" >&2; return 1; }
  _DDEV_DIR="$(cd "$target" 2>/dev/null && pwd)" || { echo "ddev: no such directory: $target" >&2; return 1; }
  if [ ! -f "$_DDEV_DIR/.ddev/config.yaml" ]; then
    echo "ddev: $_DDEV_DIR is not a DDEV project." >&2
    echo "      cd '$_DDEV_DIR' && ddev config --project-type=wordpress --docroot=." >&2
    echo "      or copy the reference fixture: fixtures/ddev/config.yaml" >&2
    return 1
  fi
  if ! _ddev status >/dev/null 2>&1; then
    echo "ddev: project at $_DDEV_DIR is not running — run: (cd '$_DDEV_DIR' && ddev start)" >&2
    return 1
  fi
}

_ddev() { ( cd "$_DDEV_DIR" && ddev "$@" ); }

env_driver_caps() {
  local caps="core-updater db-reset php-switch core-zip https xdebug shell multisite-subdir"

  # Host filesystem: bind-mount on Linux, async Mutagen sync on macOS/Windows.
  if _ddev mutagen status 2>/dev/null | grep -qiE 'ok|watching|connected'; then
    caps="$caps hostfs-synced"
  else
    caps="$caps hostfs"
  fi

  # Snapshots — probe, don't assume. See note 1 in the header.
  #
  # The probe MUST run in the db container (-s db). DDEV's snapshot copies the dump from
  # there, and the web container is deliberately non-root and always fails this write —
  # probing web reports "no snapshot" on an environment that snapshots perfectly well.
  # Verified 2026-08-01: web DENIED, db OK, real `ddev snapshot` succeeded.
  mkdir -p "$_DDEV_DIR/.ddev/db_snapshots" 2>/dev/null
  if _ddev exec -s db -- sh -c \
      'touch /mnt/ddev_config/db_snapshots/.wpaudit-probe && rm -f /mnt/ddev_config/db_snapshots/.wpaudit-probe' \
      >/dev/null 2>&1; then
    caps="$caps snapshot"
  fi

  # Subdomain multisite needs a wildcard hostname. WP-CLI refuses to convert otherwise.
  grep -qE '^ *additional_hostnames:.*\*|^ *- *"?\*\.' "$_DDEV_DIR/.ddev/config.yaml" 2>/dev/null \
    && caps="$caps multisite-subdomain"

  case "$(_ddev_cfg webserver_type)" in
    apache*) caps="$caps apache" ;;
    *)       caps="$caps nginx"  ;;
  esac

  case "$(_ddev_cfg_db)" in
    mysql*)    caps="$caps mysql"   ;;
    postgres*) : ;;
    *)         caps="$caps mariadb" ;;
  esac

  echo "$caps"
}

# Read a scalar from .ddev/config.yaml without a YAML parser.
_ddev_cfg() {
  grep -E "^ *$1:" "$_DDEV_DIR/.ddev/config.yaml" 2>/dev/null \
    | head -1 | sed 's/.*: *//; s/"//g; s/^ *//; s/ *$//'
}

# database: is a nested block — read the `type:` under it.
_ddev_cfg_db() {
  awk '/^database:/{f=1;next} f&&/^ *type:/{gsub(/.*: *|"/,"");print;exit} /^[a-z]/&&!/^database:/{f=0}' \
    "$_DDEV_DIR/.ddev/config.yaml" 2>/dev/null
}

env_start()   { _ddev start -y; }
env_stop()    { _ddev stop; }
env_destroy() { _ddev delete -O -y; }

# env_wp MUST return WP-CLI's exit status, not the exit status of the pipeline that
# cleans up its output. `cmd | tr -d '\r'` returns tr's status, which is always 0 — so
# every `env_wp ... || fallback` in every suite silently stops firing, and a driver that
# can never report failure is a machine for producing false PASSes. Capture, then clean.
env_wp() {
  local out rc
  out="$(_ddev wp "$@" 2>/dev/null)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | tr -d '\r'
  return $rc
}

# --raw is required, and its absence is subtle. Without it DDEV joins argv into one
# string and re-runs it through bash, so a command carrying its own quoting —
# `env_exec bash -c 'php -r "…"'` — gets parsed twice and the inner quotes are eaten.
# The symptom is not an error: the command silently does nothing and the cell reports
# an empty result, which reads like a WordPress failure. env_exec's contract is argv
# execution; callers that want a shell ask for one explicitly.
env_exec() { _ddev exec --raw -- "$@"; }

env_docroot() {
  local dr; dr="$(_ddev_cfg docroot)"
  if [ -z "$dr" ] || [ "$dr" = "." ]; then echo "$_DDEV_DIR"; else echo "$_DDEV_DIR/$dr"; fi
}

env_url() { _ddev exec -- sh -c 'echo $DDEV_PRIMARY_URL' 2>/dev/null | tr -d '\r'; }

# Flush Mutagen. No-op when the project is a plain bind mount, so it's always safe.
env_sync() { _ddev mutagen sync >/dev/null 2>&1 || true; }

# DDEV has no `reset database` verb; drop and recreate is the documented route.
env_db_reset() {
  local db; db="$(_ddev_cfg dbname)"; db="${db:-db}"
  _ddev mysql -e "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\`;" >/dev/null 2>&1
}

env_db_snapshot() { _ddev snapshot --name="$1" >/dev/null; }
env_db_restore()  { _ddev snapshot restore "$1" >/dev/null; }

# Report the RUNNING PHP, not the configured one. `php_version:` in config.yaml is a
# request; until a restart applies it the container is still serving the old version, and
# a cell labelled "PHP 8.2" that actually ran on 8.3 attributes behaviour to the wrong
# runtime. Probe the web container, same as the wp-env driver does.
env_php_get() {
  local out
  out="$(_ddev exec --raw -- php -r 'echo PHP_VERSION;' 2>/dev/null)" || return 1
  printf '%s' "$out" | tr -d '\r'
}

# Verify the switch took. A restart that fails to rebuild leaves the previous version
# serving and exits 0, which is a silent wrong-runtime run for every cell after it.
env_php_set() {
  local want="$1" got
  _ddev config --php-version="$want" >/dev/null 2>&1 || return 1
  _ddev restart -y >/dev/null 2>&1 || return 1
  got="$(env_php_get)"
  case "$got" in
    "$want"*) echo "$got" ;;
    *) echo "ddev: asked for PHP '$want', container runs '$got' — restart did not take" >&2; return 1 ;;
  esac
}

# Accepts a version string ("6.9", "nightly") or a zip URL.
#
# VERIFIES the result rather than trusting the exit code: WP-CLI's core download can OOM
# mid-extract and leave the OLD version in place, and that failure is easy to swallow.
# lib-fast.sh raises memory_limit for the same reason; here we check the outcome instead
# of guessing the container's WP-CLI path.
env_core_install() {
  local target="$1" before after
  before="$(env_wp core version)"
  case "$target" in
    http://*|https://*)
      _ddev exec -- sh -c "curl -sSL -o /tmp/core.zip '$target' && \
        rm -rf /tmp/core-x && mkdir -p /tmp/core-x && unzip -q /tmp/core.zip -d /tmp/core-x && \
        cp -a /tmp/core-x/wordpress/. /var/www/html/" >/dev/null 2>&1 ;;
    *)
      env_wp core download --version="$target" --force >/dev/null 2>&1 ;;
  esac
  env_sync
  after="$(env_wp core version)"
  if [ -z "$after" ]; then
    echo "ddev: core install left no readable version (was '$before')" >&2; return 1
  fi
  case "$target" in
    "$after"*|http*) ;;
    *) echo "ddev: asked for '$target', got '$after' — install did not take" >&2; return 1 ;;
  esac
  echo "$after"
}

env_multisite_convert() {
  if [ "${1:-}" = "--subdomains" ]; then
    env_has multisite-subdomain || {
      echo "ddev: subdomain multisite needs a wildcard additional_hostnames in .ddev/config.yaml" >&2
      return 3; }
    env_wp core multisite-convert --subdomains
  else
    env_wp core multisite-convert
  fi
}
