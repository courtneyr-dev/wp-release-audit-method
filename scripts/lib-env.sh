#!/bin/bash
# Environment driver interface. Source this, pick a driver, run WordPress anywhere.
#
#   source scripts/lib-env.sh
#   env_init ddev ~/wp-test        # or: wp-env | playground | cli | studio | lando
#   env_wp core version
#   env_caps
#
# WHY: the same test cell has to run on wp-env, DDEV, Playground, a Local site, or a
# staging box, and those environments are NOT equivalent. Playground has no shell and no
# HTTPS. wp-env has no HTTPS either. A remote host has no host-readable document root. A
# suite that ignores those differences reports PASS for cells that could never have
# failed — which this repo's whole argument says is not evidence.
#
# Capabilities are PROBED, never assumed, and the reason is that assuming loses. This
# library once documented that Playground "cannot reach WordPress's own updater"; running
# it showed WP_Filesystem_Direct, a live api.wordpress.org, and Core_Upgrader rewriting
# the docroot. Plausible, widely repeated, and false.
#
# So a driver does two jobs: run commands, and DECLARE WHAT IT CANNOT DO. A cell whose
# requirements aren't met reports BLOCKED with the missing capability named, never PASS.
#
# DDEV is the reference implementation: it supports every capability in the list below,
# so every other driver is describable as a delta from it. Adding a driver means writing
# scripts/env/<name>.sh — see scripts/env/README.md.

WP_AUDIT_ENV_DRIVER=""
WP_AUDIT_ENV_TARGET=""
WP_AUDIT_ENV_CAPS=""

# Where this file lives, resolved ONCE at source time and never recomputed.
#
# Two reasons it has to be done here rather than inside env_init:
#
#   1. ZSH DOES NOT SET BASH_SOURCE. The documented way to use this library is to source
#      it from your shell — `. scripts/lib-env.sh && env_init ddev ~/wp-test` — and on
#      macOS that shell is zsh. There, ${BASH_SOURCE[0]} is empty, dirname turns that
#      into ".", and the driver lookup goes hunting in $PWD/env for files that live next
#      to this script. The failure reads as "no driver 'ddev'", which sends you looking
#      for a missing file rather than a wrong directory. $0 is the sourced path in zsh,
#      so the fallback covers it without any shell-specific syntax that would break the
#      other interpreter at parse time.
#   2. Resolving at source time means a later `cd` cannot move the drivers.
_WP_AUDIT_ENV_SELF="${BASH_SOURCE[0]:-$0}"
WP_AUDIT_ENV_DIR="$(cd "$(dirname "$_WP_AUDIT_ENV_SELF")" 2>/dev/null && pwd)"
unset _WP_AUDIT_ENV_SELF

# ---------------------------------------------------------------- capability tokens
#
#   hostfs              document root is readable from the host, synchronously
#   hostfs-synced       ...readable, but ASYNCHRONOUSLY. env_sync before hashing.
#   core-updater        WordPress's OWN updater is reachable, not just WP-CLI's.
#                       The 243-stale-file finding needs this one.
#   db-reset            can empty the database
#   snapshot            can snapshot AND restore the database
#   php-switch          PHP version is a parameter, not a rebuild
#   core-zip            can install an arbitrary core zip / version string
#   multisite-subdir    can convert to subdirectory multisite
#   multisite-subdomain can convert to subdomain multisite AND serve the subsites.
#                       Widely-repeated folklore says WP-CLI refuses this on a
#                       localhost:PORT install. It does not — measured three separate
#                       ways on 2026-08-01 (wp-env, Studio, and by hand): it warns about
#                       wildcard DNS, converts, exits 0, and sub1.localhost:PORT then
#                       serves HTTP 200. The real gate is whether the RESOLVER answers
#                       for arbitrary subdomains, so drivers probe it rather than
#                       assuming either way.
#   https               serves over TLS
#   xdebug              Xdebug can be toggled
#   shell               arbitrary shell commands run inside the environment
#   nginx / apache      web server actually in use
#   mysql / mariadb / sqlite   database engine actually in use
#
WP_AUDIT_ALL_CAPS="hostfs hostfs-synced core-updater db-reset snapshot php-switch \
core-zip multisite-subdir multisite-subdomain https xdebug shell nginx apache \
mysql mariadb sqlite"

# ---------------------------------------------------------------- init

env_init() {
  local driver="${1:-${WP_AUDIT_ENV:-}}" target="${2:-.}" dir
  if [ -z "$driver" ]; then
    echo "env_init: no driver. Pass one, or set WP_AUDIT_ENV." >&2
    echo "          available: $(env_list_drivers | tr '\n' ' ')" >&2
    return 1
  fi
  dir="$WP_AUDIT_ENV_DIR"
  if [ ! -f "$dir/env/$driver.sh" ]; then
    echo "env_init: no driver '$driver' in $dir/env/" >&2
    echo "          available: $(env_list_drivers | tr '\n' ' ')" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  . "$dir/env/$driver.sh" || return 1
  WP_AUDIT_ENV_DRIVER="$driver"
  WP_AUDIT_ENV_TARGET="$target"
  env_driver_init "$target" || return 1
  # Probed, not declared. A capability that is configured but broken — see the DDEV
  # snapshot-under-$TMPDIR case — must not be advertised.
  WP_AUDIT_ENV_CAPS=" $(env_driver_caps | tr '\n' ' ' | tr -s ' ') "
  return 0
}

env_list_drivers() {
  find "$WP_AUDIT_ENV_DIR/env" -maxdepth 1 -name '*.sh' -exec basename {} .sh \; 2>/dev/null | sort
}

# ---------------------------------------------------------------- capabilities

env_caps() { echo "$WP_AUDIT_ENV_CAPS" | tr -s ' ' | sed 's/^ //;s/ $//'; }

# env_has <cap> — quiet test.
env_has() { case "$WP_AUDIT_ENV_CAPS" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# env_missing <cap…> — echoes the caps this driver does NOT have.
env_missing() {
  local c out=""
  for c in "$@"; do env_has "$c" || out="$out $c"; done
  echo "$out" | sed 's/^ //'
}

# env_require <cell-id> <cap…> — the gate. Returns 0 to run the cell, 2 to skip it.
# On 2 it has already printed the BLOCKED verdict, so callers just return.
#
#   env_require T1-44 core-updater hostfs || return
#
env_require() {
  local cell="$1"; shift
  local miss; miss="$(env_missing "$@")"
  [ -z "$miss" ] && return 0
  echo "BLOCKED  $cell  driver=$WP_AUDIT_ENV_DRIVER  missing:$(echo " $miss" | tr -s ' ')"
  return 2
}

# env_caps_report — the block preflight-sensitivity.sh prints.
env_caps_report() {
  local c missing=""
  echo "════ ENVIRONMENT CAPABILITIES  (driver: ${WP_AUDIT_ENV_DRIVER:-none})"
  echo "  target: ${WP_AUDIT_ENV_TARGET:-none}"
  echo "  has:    $(env_caps)"
  for c in $WP_AUDIT_ALL_CAPS; do env_has "$c" || missing="$missing $c"; done
  echo "  MISSING:$missing"
  echo
  echo "  A cell needing any MISSING capability reports BLOCKED, not PASS."
  env_has core-updater || echo "  NOTE: no core-updater — stale-file findings are UNREACHABLE here."
  env_has hostfs-synced && echo "  NOTE: host filesystem is async — env_sync before any hash or diff."
}

# ---------------------------------------------------------------- defaults
#
# Every operation defaults to "unsupported". A driver overrides only what it can do,
# and anything it doesn't override fails loudly instead of silently succeeding.

_env_unsupported() {
  echo "env: '$1' is not supported by driver '${WP_AUDIT_ENV_DRIVER:-none}'" >&2
  return 3
}

# CONTRACT NOTE for driver authors: env_wp MUST propagate WP-CLI's exit status.
# The tempting one-liner `cmd | tr -d '\r'` returns tr's status, which is always 0, and
# that quietly disables every `env_wp … || fallback` in every suite. Capture the output,
# then clean it — see env/ddev.sh. A driver that cannot report failure manufactures
# false PASSes, which is the failure this whole repository exists to prevent.

env_driver_init()       { :; }
env_driver_caps()       { echo ""; }
env_start()             { _env_unsupported start; }
env_stop()              { _env_unsupported stop; }
env_destroy()           { _env_unsupported destroy; }
env_wp()                { _env_unsupported wp; }
env_exec()              { _env_unsupported exec; }
env_docroot()           { echo ""; }
env_url()               { echo ""; }
env_sync()              { :; }   # no-op is correct for every non-synced driver
env_db_reset()          { _env_unsupported db_reset; }
env_db_snapshot()       { _env_unsupported db_snapshot; }
env_db_restore()        { _env_unsupported db_restore; }
env_php_get()           { env_wp eval 'echo PHP_VERSION;' 2>/dev/null; }
env_php_set()           { _env_unsupported php_set; }
env_core_install()      { _env_unsupported core_install; }
env_multisite_convert() { _env_unsupported multisite_convert; }

# ---------------------------------------------------------------- shared helpers

# env_tree <output-file> — hash-comparable file listing of the document root.
# Syncs first, because on an async driver a listing taken without one is quietly wrong,
# and a wrong listing here reads as a WordPress finding rather than a harness fault.
env_tree() {
  local out="$1" root
  root="$(env_docroot)"
  if [ -z "$root" ] || [ ! -d "$root" ]; then
    echo "env_tree: no host-readable docroot on driver '$WP_AUDIT_ENV_DRIVER'" >&2
    return 3
  fi
  env_sync
  ( cd "$root" && find . -type f -not -path './.ddev/*' -not -path './.git/*' | LC_ALL=C sort ) > "$out"
}

# env_assert_ready — call before a suite. Fails fast with a usable message.
env_assert_ready() {
  local v
  v="$(env_wp core version 2>/dev/null | tr -d '\r')"
  if [ -z "$v" ]; then
    echo "env: driver '$WP_AUDIT_ENV_DRIVER' cannot reach WordPress at '$WP_AUDIT_ENV_TARGET'" >&2
    return 1
  fi
  echo "$v"
}
