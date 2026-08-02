#!/bin/bash
# Lando driver (wordpress recipe) — and the portability test for lib-env.sh.
#
# ===========================================================================
#  UNVERIFIED. NOT ONE LINE OF THIS FILE HAS BEEN EXECUTED.
# ===========================================================================
#
# Lando is not installed on the machine this was written on, and installing it was not
# authorized. Every behavioural claim below is read off docs.lando.dev (2026-08-01), not
# off a terminal. By this repo's own argument that makes all of it a hypothesis: an
# untested claim is not a finding, and a driver that silently read as "tested" would be
# worse than no driver, because a wrong capability list turns BLOCKED cells into PASSes.
#
# Treat every capability this driver reports as provisional until someone runs the
# checklist at the bottom of this header on a real Lando install.
#
# What IS verified, and how:
#   * The Lando CLI surface used here — `lando wp|ssh|start|stop|destroy|rebuild|info|
#     mysql|db-export|db-import`, and every flag passed to them — was read from the
#     current docs page for each command, not from memory.
#   * `*.lndo.site` wildcard DNS resolves at ARBITRARY DEPTH. Checked from a shell on
#     2026-08-01: `dig +short a.b.wpaudit.lndo.site A` -> 127.0.0.1. This is the one
#     capability Lando has that no localhost:PORT driver can have (see multisite-subdomain).
#   * `bash -n` and `shellcheck -S error` (v0.11.0) pass on this file.
#   * The pieces that touch no container WERE run, against fixture Landofiles: the
#     _lando_cfg_* readers, the wildcard-proxy grep, env_exec's argv->string quoting, and
#     env_php_set's in-place rewrite (including its refusal on an unpinned Landofile).
#     That pass found two real bugs, both now fixed and both noted at their site.
#     Everything that needs a running Lando remains untested.
#
# ---------------------------------------------------------------------------
# Because nothing here could be exercised, env_driver_caps PROBES rather than declares,
# much harder than ddev.sh does. A probe degrades gracefully on a machine nobody has
# seen; a hard-coded guess degrades into a false PASS. Three consequences worth knowing:
#
#   1. NO LANDO DEFAULT IS EVER TRUSTED for php or database. Lando's own config docs
#      carry an "Always set explicit versions!" warning because the documented defaults
#      (php: '7.4', database: mysql:5.7) trail the recipe's advertised support (php up to
#      8.5, postgres) by years. So the php version and db engine are read from `lando
#      info`, which reports what is actually RUNNING, and env_driver_init separately
#      shouts if .lando.yml pins neither — the config-hygiene problem and the runtime
#      truth are different questions and get answered separately.
#   2. WHERE DDEV'S DRIVER FALLS BACK, THIS ONE DECLINES. ddev.sh ends its webserver
#      case with `*) nginx`; here an unreadable `via` yields neither `apache` nor `nginx`.
#      A cell that needs to know the web server should block, not be told a guess.
#   3. `hostfs` IS PROVEN, NOT INFERRED. Lando bind-mounts the project to /app, so the
#      docroot "is" host-readable — except that a Landofile `excludes:` key layers named
#      volumes over parts of /app, and those paths are not on the host at all. A driver
#      that reasoned "bind mount, therefore hostfs" would hand env_tree a docroot with
#      holes in it, and the missing files would read as a WordPress finding. So the probe
#      writes a marker in the container and looks for it on the host.
#      Note the probe cannot tell "async" from "not shared" — both fail it, and both drop
#      the cap. That is the safe direction, and it is why hostfs-synced is never claimed:
#      Lando 3 has no Mutagen equivalent to flush, so lib-env.sh's no-op env_sync is left
#      in place unoverridden rather than stubbed.
#
# ---------------------------------------------------------------------------
# WHERE THE ddev.sh -> lando.sh MAPPING STOPPED BEING MECHANICAL
#
#   * env_exec is ARGV-SHAPED, lando's exec surface is STRING-SHAPED. `ddev exec -- "$@"`
#     passes a vector; `lando ssh -c "<cmd>"` takes one string. The driver re-quotes with
#     printf %q. Costless here, but it is the interface leaning on DDEV's calling convention.
#   * NO SNAPSHOT VERB, and the file-based substitute fights env_tree. `lando db-export`
#     writes a dump and `lando db-import` reads one, but Docker file sharing requires the
#     dump to live INSIDE the project directory — which, at the default `webroot: .`, is
#     also the docroot that env_tree hashes. A dump sitting there during a before/after
#     core-upgrade diff is a phantom file in the results. So snapshots are staged into the
#     project only for the duration of one call and immediately moved to a store outside
#     it. (Store defaults under $HOME, not $TMPDIR — the DDEV driver's snapshot bug is a
#     standing warning about macOS temp paths.)
#   * NO `ddev xdebug on` EQUIVALENT. Toggling Xdebug on Lando is a Landofile edit plus
#     `lando rebuild`, not a verb. So the xdebug cap here reports what is LOADED right
#     now, not what is theoretically switchable.
#   * NO `ddev config --php-version=` EQUIVALENT either; env_php_set rewrites .lando.yml
#     and rebuilds, and refuses when there is no `php:` key to rewrite.
#   * `ddev start -y` -> `lando start`. lando start documents no --yes flag; destroy and
#     rebuild do.
#   * `ddev delete -O -y` -> `lando destroy -y`. Lando has no "omit snapshot" notion
#     because it never took one.
#
# ---------------------------------------------------------------------------
# VERIFICATION CHECKLIST — run these on a real Lando install to promote this file from
# hypothesis to driver. Each line names the thing it would settle.
#
#   env_init lando <proj>; env_caps                 does the whole probe path run at all
#   lando info -s appserver --path webroot          --path returns a bare scalar
#   lando info -s database --path creds.database    dotted --path traversal works
#   lando ssh -c 'printenv LANDO_SERVICE_NAME'      appserver name is discoverable, output clean
#   lando wp core version                           tooling stdout is not polluted by lando banners
#   lando mysql -e 'SELECT 1'                       -e passes through to the mysql client
#   lando db-export .x/d.sql && ls .x/              output filename (docs say .gz is appended)
#   lando db-import .x/d.sql.gz                     relative subdir path resolves under /app
#   cat d.sql | lando db-import                     stdin path (docs call it "finicky"); unused here
#   env_php_set 8.3 && env_php_get                  sed rewrite + rebuild round-trips
#   env_core_install 6.7.2 && env_tree /tmp/t       docroot is whole, no phantom files
#   with proxy: ["*.app.lndo.site"], multisite_convert --subdomains, then load a subsite
#                                                   traefik really routes the wildcard
#
_LANDO_DIR=""
_LANDO_YML=""
_LANDO_APP=""
_LANDO_SERVICE=""
_LANDO_DB_SERVICE=""
_LANDO_WEBROOT=""
_LANDO_SNAPDIR=""

env_driver_init() {
  local target="${1:-.}" probe
  command -v lando >/dev/null 2>&1 || { echo "lando: not installed — https://docs.lando.dev/getting-started/installation.html" >&2; return 1; }
  _LANDO_DIR="$(cd "$target" 2>/dev/null && pwd)" || { echo "lando: no such directory: $target" >&2; return 1; }

  if   [ -f "$_LANDO_DIR/.lando.yml"  ]; then _LANDO_YML="$_LANDO_DIR/.lando.yml"
  elif [ -f "$_LANDO_DIR/.lando.yaml" ]; then _LANDO_YML="$_LANDO_DIR/.lando.yaml"
  else
    echo "lando: $_LANDO_DIR has no Landofile." >&2
    echo "       cd '$_LANDO_DIR' && lando init --source cwd --recipe wordpress --webroot ." >&2
    echo "       then pin php and database explicitly — see the warning below." >&2
    return 1
  fi

  # One call settles two things at once: that the app is actually up (nothing else here
  # works otherwise) and what its appserver is really called. `lando ssh` with no -s uses
  # the default service, which is `appserver` unless the Landofile reorders things — so
  # ask the container for its own name instead of hard-coding the recipe's.
  probe="$( ( cd "$_LANDO_DIR" && lando ssh -c 'printf "%s|%s\n" "$LANDO_SERVICE_NAME" "$LANDO_APP_NAME"' ) 2>/dev/null \
            | tr -d '\r' | grep '|' | tail -1 )"
  _LANDO_SERVICE="${probe%%|*}"
  _LANDO_APP="${probe##*|}"
  if [ -z "$_LANDO_SERVICE" ] || [ -z "$_LANDO_APP" ]; then
    echo "lando: project at $_LANDO_DIR is not running — run: (cd '$_LANDO_DIR' && lando start)" >&2
    return 1
  fi

  # Documented default, and also db-import/db-export's own `--host` default.
  _LANDO_DB_SERVICE="${WP_AUDIT_LANDO_DB_SERVICE:-database}"
  _LANDO_SNAPDIR="${WP_AUDIT_LANDO_SNAPSHOTS:-$HOME/.wp-audit/lando-snapshots}/$_LANDO_APP"

  # Cached because env_docroot is on env_tree's hot path and `lando info` shells out.
  _LANDO_WEBROOT="$(_lando_info "$_LANDO_SERVICE" webroot)"
  [ -n "$_LANDO_WEBROOT" ] || _LANDO_WEBROOT="$(_lando_cfg_webroot)"

  # LOUD, not fatal. The run is still valid — it is the RECORD of it that is broken,
  # because "we tested on Lando's default" names a moving target. Lando's own docs say
  # to always pin these; a result whose PHP version came from an unpinned default cannot
  # be reproduced later or compared to another cell.
  if [ -z "$(_lando_cfg_php)" ]; then
    echo "lando: WARNING — $_LANDO_YML pins no 'php:'. Lando's documented default ('7.4')" >&2
    echo "       is years behind the versions the recipe advertises. This run's PHP is" >&2
    echo "       whatever Lando picked ($(_lando_info "$_LANDO_SERVICE" version)); pin it before trusting a result." >&2
  fi
  if [ -z "$(_lando_cfg_db)" ]; then
    echo "lando: WARNING — $_LANDO_YML pins no 'database:'. Lando's documented default" >&2
    echo "       ('mysql:5.7') is not what the recipe page advertises. This run's engine is" >&2
    echo "       '$(_lando_info "$_LANDO_DB_SERVICE" type):$(_lando_info "$_LANDO_DB_SERVICE" version)'; pin it before trusting a result." >&2
  fi
}

_lando()    { ( cd "$_LANDO_DIR" && lando "$@" ); }

# lando's exec surface takes a command STRING, so everything routed through it has to be
# re-quoted. See the mapping note in the header.
_lando_sh() { _lando ssh -s "$_LANDO_SERVICE" -c "$1"; }

# `lando info --path` does the JSON traversal so this driver does not have to; quoting of
# the returned scalar varies by value type, hence the strip.
_lando_info() {
  _lando info -s "$1" --path "$2" 2>/dev/null | tr -d '\r"' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | head -1
}

# The Landofile nests a SECOND `config:` block whose `php:` and `database:` keys hold
# FILE PATHS (php.ini, my.cnf), not versions — so a ddev-style `grep '^ *php:'` can
# happily return "config/php.ini" as the PHP version. Match on the value's SHAPE instead
# of on position, which holds however the file is ordered.
#
# _lando_cfg_val strips to the FIRST colon, not the last. ddev.sh's `s/.*: *//` is safe
# there because DDEV's scalars have no internal colons; Lando's routinely do (`mysql:8.0`,
# `apache:2.4`), and the greedy form silently reports "8.0" as the database engine —
# caught by running these three against fixture Landofiles, which is the only part of this
# file that could be exercised at all.
_lando_cfg_val() { sed "s/^[^:]*:[[:space:]]*//; s/[\"']//g; s/[[:space:]]*\$//"; }

_lando_cfg_php() {
  grep -E "^[[:space:]]+php:[[:space:]]*['\"]?[0-9]" "$_LANDO_YML" 2>/dev/null \
    | head -1 | _lando_cfg_val
}
_lando_cfg_db() {
  grep -E "^[[:space:]]+database:[[:space:]]*['\"]?(mysql|mariadb|postgres)" "$_LANDO_YML" 2>/dev/null \
    | head -1 | _lando_cfg_val
}
_lando_cfg_webroot() {
  grep -E "^[[:space:]]+webroot:" "$_LANDO_YML" 2>/dev/null | head -1 | _lando_cfg_val
}

# db-export/db-import are recipe TOOLING, not core verbs — a Landofile that overrides the
# tooling block can remove them. Bare `lando` in the project lists what is actually routed.
_lando_tooling_has() { _lando 2>/dev/null | grep -qE "^[[:space:]]*$1([[:space:]]|\$)"; }

# WP-CLI reads the name out of wp-config.php, which is the value WordPress actually uses;
# lando info reports what Lando provisioned. They agree on a healthy site and the first is
# the one that matters, so prefer it and treat disagreement as WP-CLI winning.
_lando_dbname() {
  local n; n="$(env_wp config get DB_NAME 2>/dev/null | tr -d '\r' | head -1)"
  [ -n "$n" ] || n="$(_lando_info "$_LANDO_DB_SERVICE" creds.database)"
  echo "$n"
}

env_driver_caps() {
  local caps="multisite-subdir core-zip" probe dbname

  _lando_sh 'exit 0' >/dev/null 2>&1 && caps="$caps shell"

  # See header note 3 — prove the bind mount, don't infer it from Lando's architecture.
  probe=".wp-audit-hostfs-$$"
  if _lando_sh "touch \"\$LANDO_WEBROOT/$probe\"" >/dev/null 2>&1; then
    [ -e "$(env_docroot)/$probe" ] && caps="$caps hostfs"
    _lando_sh "rm -f \"\$LANDO_WEBROOT/$probe\"" >/dev/null 2>&1
  fi

  case "$(env_url)" in https://*) caps="$caps https" ;; esac

  # No `*)` fallback, deliberately — header note 2.
  case "$(_lando_info "$_LANDO_SERVICE" via)" in
    apache*) caps="$caps apache" ;;
    nginx*)  caps="$caps nginx"  ;;
  esac

  # db-reset is DROP/CREATE through `lando mysql`, so it rides on the engine speaking the
  # MySQL wire protocol AND on knowing the database name. Postgres gets `lando psql`
  # instead, where DROP DATABASE cannot run from a session connected to that database —
  # left unimplemented rather than stubbed with something that would half-work.
  dbname="$(_lando_dbname)"
  case "$(_lando_info "$_LANDO_DB_SERVICE" type)" in
    mysql*)    caps="$caps mysql";   [ -n "$dbname" ] && caps="$caps db-reset" ;;
    mariadb*)  caps="$caps mariadb"; [ -n "$dbname" ] && caps="$caps db-reset" ;;
    postgres*) : ;;
  esac

  if _lando_tooling_has db-export && _lando_tooling_has db-import \
     && mkdir -p "$_LANDO_SNAPDIR" 2>/dev/null && [ -w "$_LANDO_SNAPDIR" ]; then
    caps="$caps snapshot"
  fi

  # Only when the Landofile already pins php. Writing a `php:` key Lando never recorded
  # means inventing the version we are claiming to switch away FROM, and afterwards that
  # invented value is indistinguishable from a real pin.
  [ -n "$(_lando_cfg_php)" ] && caps="$caps php-switch"

  # Loaded, not toggleable — header mapping note. `php -m` is asked of the appserver
  # rather than of `lando php`, so a tooling override cannot answer for the runtime.
  _lando_sh 'php -m' 2>/dev/null | tr -d '\r' | grep -qi '^xdebug$' && caps="$caps xdebug"

  # The 243-stale-file finding lives or dies on this one, so it is probed, not assumed:
  # WordPress's own updater has to reach api.wordpress.org from inside the container.
  # A container that cannot get out reports the update as "already current" — a silent
  # false PASS on exactly the cell this capability exists to gate.
  _lando_sh 'curl -sSf -m 8 -o /dev/null https://api.wordpress.org/core/version-check/1.7/' \
    >/dev/null 2>&1 && caps="$caps core-updater"

  # Mirrors ddev.sh's wildcard-hostname check, and needs the same two things — but only
  # one of them is the hard part here. DNS is free: *.lndo.site resolves at arbitrary
  # depth (verified 2026-08-01, `dig +short a.b.wpaudit.lndo.site A` -> 127.0.0.1), which
  # is why Lando can host subdomain multisite at all and why WP-CLI will not refuse the
  # conversion the way it does on localhost:PORT. What is NOT free is traefik routing:
  # without a left-most-wildcard `proxy:` entry the proxy knows one exact hostname, so
  # site2.myapp.lndo.site resolves and then 404s. Left-most only — Lando's automatic
  # certs cover `*.app.lndo.site` but not a mid-string wildcard.
  grep -qE "^[[:space:]]*-[[:space:]]*[\"']\*\." "$_LANDO_YML" 2>/dev/null \
    && caps="$caps multisite-subdomain"

  echo "$caps"
}

env_start()   { _lando start; }
env_stop()    { _lando stop; }
env_destroy() { _lando destroy -y; }

# Capture-then-clean, never pipe: `_lando wp … | tr` returns TR's exit status, which is
# always 0, so every `env_wp … || fallback` in every suite silently stops firing. A driver
# that cannot report failure manufactures false PASSes. See the contract note in lib-env.sh.
env_wp() {
  local out rc
  out="$(_lando wp "$@" 2>/dev/null)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | tr -d '\r'
  return $rc
}

env_exec() {
  local out="" a
  for a in "$@"; do out="$out $(printf '%q' "$a")"; done
  _lando_sh "${out# }"
}

env_docroot() {
  if [ -z "$_LANDO_WEBROOT" ] || [ "$_LANDO_WEBROOT" = "." ]; then
    echo "$_LANDO_DIR"
  else
    echo "$_LANDO_DIR/$_LANDO_WEBROOT"
  fi
}

# DDEV hands back one DDEV_PRIMARY_URL; Lando reports an array. Prefer https so callers
# exercising cookies, redirects or mixed content see what a browser would see.
env_url() {
  local urls secure
  urls="$(_lando info -s "$_LANDO_SERVICE" --path urls 2>/dev/null | tr -d '\r')"
  secure="$(printf '%s' "$urls" | grep -oE 'https://[^ ,"]+' | head -1)"
  if [ -n "$secure" ]; then
    echo "$secure"
  else
    printf '%s' "$urls" | grep -oE 'https?://[^ ,"]+' | head -1
  fi
}

# env_sync is deliberately NOT overridden. Lando 3 bind-mounts the project with no
# Mutagen-style sync layer to flush, so lib-env.sh's no-op is the correct implementation
# and writing a fake one here would only imply a sync step exists.

env_db_reset() {
  local db; db="$(_lando_dbname)"
  if [ -z "$db" ]; then
    echo "lando: cannot determine the database name — refusing to reset" >&2; return 1
  fi
  _lando mysql -e "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\`;" >/dev/null 2>&1
}

# Lando has no snapshot verb, so db-export/db-import stand in for one. Both ends stage
# through a directory inside the project because Docker file sharing gives db-import no
# other way to see the file — and both ends tear that directory down again in the same
# call, because at the default `webroot: .` it would otherwise be sitting inside the
# docroot that env_tree hashes. See the header.
#
# The staged file is found rather than named: db-export appends its own compression
# suffix, and guessing it wrong would produce a snapshot that restores as an empty database.
_LANDO_STAGE_REL=".wp-audit-dump"

env_db_snapshot() {
  local name="$1" stage="$_LANDO_DIR/$_LANDO_STAGE_REL" f rc=0
  if [ -z "$name" ]; then echo "lando: db_snapshot needs a name" >&2; return 1; fi
  rm -rf "$stage"
  if ! mkdir -p "$stage"; then return 1; fi

  _lando db-export "$_LANDO_STAGE_REL/$name.sql" >/dev/null 2>&1
  f="$(find "$stage" -maxdepth 1 -type f 2>/dev/null | head -1)"
  if [ -z "$f" ]; then
    rm -rf "$stage"
    echo "lando: db-export produced no file in $stage" >&2
    return 1
  fi

  rm -rf "${_LANDO_SNAPDIR:?}/$name"
  if mkdir -p "$_LANDO_SNAPDIR/$name"; then
    mv "$f" "$_LANDO_SNAPDIR/$name/" || rc=1
  else
    rc=1
  fi
  rm -rf "$stage"
  return "$rc"
}

env_db_restore() {
  local name="$1" stage="$_LANDO_DIR/$_LANDO_STAGE_REL" src base rc
  src="$(find "$_LANDO_SNAPDIR/$name" -maxdepth 1 -type f 2>/dev/null | head -1)"
  if [ -z "$src" ]; then
    echo "lando: no snapshot '$name' under $_LANDO_SNAPDIR" >&2
    return 1
  fi
  base="$(basename "$src")"
  rm -rf "$stage"
  if ! mkdir -p "$stage" || ! cp "$src" "$stage/$base"; then
    rm -rf "$stage"
    return 1
  fi
  # db-import wipes the target first by default, which is what a restore wants; --no-wipe
  # would merge the dump into whatever the failing test left behind.
  _lando db-import "$_LANDO_STAGE_REL/$base" >/dev/null 2>&1
  rc=$?
  rm -rf "$stage"
  return "$rc"
}

# The RUNNING version, not the configured one — the whole point of the "never trust a
# Lando default" rule at the top of this file.
env_php_get() { _lando_info "$_LANDO_SERVICE" version; }

env_php_set() {
  local want="$1" got
  if [ -z "$(_lando_cfg_php)" ]; then
    echo "lando: $_LANDO_YML has no explicit 'php:' to change, and this driver will not add one." >&2
    echo "       Adding it means inventing the version being switched away from, and Lando's" >&2
    echo "       documented default is stale. Pin 'php:' under 'config:' first." >&2
    return 3
  fi
  # Quoted on the way in: unquoted YAML reads 8.0 as the float 8, and 8.10 as 8.1.
  sed -i.wpaudit-bak -E "s|^([[:space:]]*)php:[[:space:]]*['\"]?[0-9].*|\1php: '$want'|" "$_LANDO_YML" || return 1
  rm -f "$_LANDO_YML.wpaudit-bak"
  _lando rebuild -y >/dev/null 2>&1 || return 1
  # Verified rather than trusted: a rebuild that cannot pull the requested image can fail
  # back to the previous container, and the old version then reads as a successful switch.
  got="$(env_php_get)"
  case "$got" in
    "$want"*) echo "$got" ;;
    *) echo "lando: asked for php '$want', running '$got' — rebuild did not take" >&2; return 1 ;;
  esac
}

# Accepts a version string ("6.9", "nightly") or a zip URL.
#
# Structurally identical to the DDEV version, including the verify-the-outcome step, and
# for the same reason: WP-CLI's core download can OOM mid-extract and leave the OLD
# version in place with a zero exit code. The one difference is the destination —
# $LANDO_WEBROOT is read from the container rather than hard-coded, so a non-default
# `webroot:` does not quietly overwrite the wrong directory.
env_core_install() {
  local target="$1" before after
  before="$(env_wp core version)"
  case "$target" in
    http://*|https://*)
      _lando_sh "curl -sSL -o /tmp/core.zip '$target' && \
        rm -rf /tmp/core-x && mkdir -p /tmp/core-x && unzip -q /tmp/core.zip -d /tmp/core-x && \
        cp -a /tmp/core-x/wordpress/. \"\$LANDO_WEBROOT\"/" >/dev/null 2>&1 ;;
    *)
      env_wp core download --version="$target" --force >/dev/null 2>&1 ;;
  esac
  env_sync
  after="$(env_wp core version)"
  if [ -z "$after" ]; then
    echo "lando: core install left no readable version (was '$before')" >&2; return 1
  fi
  case "$target" in
    "$after"*|http*) ;;
    *) echo "lando: asked for '$target', got '$after' — install did not take" >&2; return 1 ;;
  esac
  echo "$after"
}

env_multisite_convert() {
  if [ "${1:-}" = "--subdomains" ]; then
    env_has multisite-subdomain || {
      echo "lando: subdomain multisite needs a left-most wildcard proxy route in $_LANDO_YML, e.g." >&2
      echo "         proxy:" >&2
      echo "           $_LANDO_SERVICE:" >&2
      echo "             - $_LANDO_APP.lndo.site" >&2
      echo "             - \"*.$_LANDO_APP.lndo.site\"" >&2
      echo "       DNS already resolves those; without the route traefik 404s them." >&2
      return 3; }
    env_wp core multisite-convert --subdomains
  else
    env_wp core multisite-convert
  fi
}
