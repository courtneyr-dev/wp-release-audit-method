#!/bin/bash
# WordPress Studio driver — a plain WordPress tree served by a Node-hosted PHP runtime.
#
# Verified 2026-08-01 against Studio CLI 1.17.0 on arm64 macOS, by creating throwaway
# sites and running every function below: create/start/stop/delete, WP-CLI, host-side
# tree reads, PHP switch 8.4<->8.3, a core downgrade to 7.0.1 followed by WordPress's
# OWN Core_Upgrader putting it back to 7.0.2, db export/import round trip, and BOTH
# multisite conversions with a subsite serving HTTP 200 in each mode.
#
# NOT verified, and stated here so nobody reads this driver as more tested than it is:
# the positive branch of the https probe (no trusted certificate was installed — the
# probe was only observed correctly REFUSING an untrusted .local site); a MySQL-backed
# site (every site on the test machine is SQLite); and --runtime sandbox, which the
# capability list treats as Playground and therefore denies core-updater, php-switch
# and xdebug without ever having run one.
#
# USE THE SUPPORTED CLI. Everything here goes through the documented `studio` binary
# (npm `wp-studio`). Older scripts in this repo invoke
# /Applications/Studio.app/Contents/Resources/bin/studio-cli.sh directly; that is an
# internal launcher shim inside the .app bundle, not an interface anyone promised to
# keep stable. $STUDIO_CLI still overrides the binary here so those scripts can move
# onto this driver without changing how they're invoked.
#
# THE PUBLISHED DOCS DISAGREE WITH THE SHIPPED CLI, which is why this file pins a
# version and warns when the installed one differs — a capability list derived from a
# different CLI is worse than no capability list at all. Confirmed against 1.17.0:
#   docs say `studio site create` / `studio site set`  ->  there is no `studio site`
#       command at all; it is `studio create` and `studio config set`
#   docs say Xdebug is UI-only                         ->  `studio config set --xdebug`
#       works, with the CLI-vs-web caveat noted in env_driver_caps below
#
# Delta from the DDEV reference (scripts/env/ddev.sh), all of it deliberate:
#
#   no nginx / no apache  Studio runs PHP itself. There is no web server to name, so
#                         neither token is ever declared.
#   no db-reset           `wp db reset` cannot work against the default SQLite backend
#                         — WP-CLI shells out to mysql and dies on the placeholder
#                         credentials Studio leaves in wp-config.php. Deleting
#                         wp-content/database/.ht.sqlite does empty the database, but
#                         Studio re-provisions a fully installed site on the next
#                         start, so a caller doing `env_db_reset && wp core install`
#                         gets "WordPress is already installed" instead of a clean
#                         slate. That is not what db-reset promises, so it is not
#                         declared and not implemented. Use snapshot/restore.
#   no hostfs-synced      The document root IS a host directory; there is nothing to
#                         flush, so env_sync stays the lib's no-op.
#   snapshot              is `studio export --mode db` / `studio import` of a .sql
#                         file, not a named server-side snapshot.
#
# Two behaviours worth knowing before you edit this file:
#
#   1. STUDIO'S PROGRESS CHATTER IS ON STDERR. Spinners, "Loading sites…", daemon
#      notices and the tick/cross result lines never touch stdout; WP-CLI's own errors
#      go to stderr too, and exit codes propagate. So `2>/dev/null` is all a reader needs
#      and the ANSI-stripping filter in scripts/seed-screenshot-rig.sh is only there
#      because that script merges the streams with 2>&1.
#   2. WP-CLI WORKS WHILE THE SITE IS STOPPED. It reads the files and the SQLite
#      database directly. env_driver_init therefore does not require a running site —
#      only HTTP-dependent probes (https) and real front-end requests do.

_STUDIO_BIN=""
_STUDIO_DIR=""
_STUDIO_CFG=""

# The version this driver's capability list was actually verified against.
_STUDIO_VERIFIED="1.17.0"

# Studio keeps its per-machine state — PHP builds, cached WordPress versions, daemon
# sockets — here, separate from the sites themselves.
_STUDIO_HOME="$HOME/.studio"

env_driver_init() {
  local target="${1:-.}" installed

  _STUDIO_BIN="${STUDIO_CLI:-studio}"
  command -v "$_STUDIO_BIN" >/dev/null 2>&1 || {
    echo "studio: '$_STUDIO_BIN' not found — npm i -g wp-studio, or set \$STUDIO_CLI" >&2
    echo "        docs: https://developer.wordpress.com/docs/developer-tools/studio/cli/" >&2
    return 1; }

  # Sites are directories, but everyone refers to them by name, so accept either.
  if [ -d "$target" ]; then
    _STUDIO_DIR="$(cd "$target" && pwd)"
  elif [ -d "$HOME/Studio/$target" ]; then
    _STUDIO_DIR="$HOME/Studio/$target"
  else
    echo "studio: no such site directory: $target" >&2
    echo "        known sites:" >&2
    _studio list --format json 2>/dev/null \
      | tr ',' '\n' | sed -n 's/.*"path":"\([^"]*\)".*/          \1/p' >&2
    return 1
  fi

  # Registration, not existence. A WordPress tree that Studio doesn't know about looks
  # fine on disk and then fails every command with "The specified directory is not
  # added to Studio."
  _studio_cfg_refresh
  if [ -z "$(_studio_cfg name)" ]; then
    echo "studio: $_STUDIO_DIR is not a site Studio knows about." >&2
    echo "        studio create --path '$_STUDIO_DIR' --name <name>" >&2
    return 1
  fi

  installed="$(_studio --version 2>/dev/null | tr -d '\r' | head -1)"
  if [ -n "$installed" ] && [ "$installed" != "$_STUDIO_VERIFIED" ]; then
    echo "studio: CLI is $installed; this driver's capabilities were verified against" >&2
    echo "        $_STUDIO_VERIFIED. Re-check env_driver_caps before trusting a verdict." >&2
  fi
}

# NO_COLOR is belt-and-braces: stdout is already clean (see note 1 in the header), but
# a future Studio release colouring a value would silently poison captured output.
_studio() { NO_COLOR=1 "$_STUDIO_BIN" "$@"; }

# Cached because every `studio` call pays Node startup plus a daemon round trip, and
# the capability probe alone reads several keys.
_studio_cfg_refresh() {
  _STUDIO_CFG="$(_studio config get --format json --path "$_STUDIO_DIR" 2>/dev/null)"
}

# Scalar out of the cached config JSON. Only the first colon is a separator — values
# such as admin-password may contain one.
_studio_cfg() {
  printf '%s\n' "$_STUDIO_CFG" | grep -m1 "\"$1\"[[:space:]]*:" \
    | sed 's/^[^:]*: *//; s/,$//; s/^"//; s/"$//'
}

# The PHP build actually serving this site. Directories are named 8.4.23-studio-1, so
# match on the configured major.minor.
_studio_php_dir() {
  local v; v="$(_studio_cfg php)"
  [ -n "$v" ] || return 1
  set -- "$_STUDIO_HOME"/php-bin/"$v".*/
  [ -d "$1" ] || return 1
  printf '%s\n' "${1%/}"
}

env_driver_caps() {
  # hostfs is unconditional and synchronous: ~/Studio/<site> is an ordinary directory
  # holding real core files, not a mount or an image. A `wp core download --force`
  # there survives stop/start — verified.
  local caps="hostfs"
  local runtime url host probe fsmethod api dns

  # EVERYTHING ELSE IS GATED ON THE NATIVE RUNTIME, which is Studio's default and the
  # only one verified here. `--runtime sandbox` is the php-wasm Playground path, and
  # Playground is the environment this whole capability list exists to distinguish
  # from a real server. Rather than guess which tokens survive that switch, a sandbox
  # site gets the files-only list and everything else reports BLOCKED with a reason.
  runtime="$(_studio_cfg runtime)"
  if [ "$runtime" != "native" ]; then
    _studio_db_caps "$caps"
    return
  fi

  # php-switch is a config key plus an automatic restart, not a rebuild. env_php_set
  # rejects anything outside 8.2-8.5 rather than let a caller believe it took.
  caps="$caps shell core-zip multisite-subdir php-switch"

  url="$(env_url)"

  # One WP-CLI round trip for three answers, because each one costs a second.
  #   get_filesystem_method() == direct  -> the core updater won't stop for FTP creds
  #   api.wordpress.org reachable        -> it has an update to fetch
  #   *.<host> resolves                  -> subdomain multisite would actually serve
  host="${url#*://}"; host="${host%%/*}"; host="${host%%:*}"
  probe="$(env_wp eval "require_once ABSPATH.'wp-admin/includes/file.php';
    \$r = wp_remote_get('https://api.wordpress.org/core/version-check/1.7/', array('timeout'=>8));
    echo get_filesystem_method().'|'.(is_wp_error(\$r) ? 'ERR' : wp_remote_retrieve_response_code(\$r))
      .'|'.gethostbyname('wpaudit-dnsprobe.${host:-localhost}');")"
  fsmethod="${probe%%|*}"; probe="${probe#*|}"
  api="${probe%%|*}"; dns="${probe#*|}"

  # The 243-stale-file finding needs WordPress's own updater, not WP-CLI's. Confirmed
  # by execution on 1.17.0: Core_Upgrader->upgrade() ran 7.0.1 -> 7.0.2 in place.
  if [ "$fsmethod" = "direct" ] && [ "$api" = "200" ]; then
    caps="$caps core-updater"
  fi

  # WP-CLI does NOT refuse subdomain conversion on localhost:PORT — it converts, and
  # sub1.localhost:PORT serves, because macOS resolves *.localhost to 127.0.0.1.
  # It is the RESOLVER that decides, so ask it: a custom .local domain gets mDNS,
  # which does not answer for arbitrary subdomains, and this probe correctly says no.
  case "$dns" in
    [0-9]*.[0-9]*.[0-9]*.[0-9]*) caps="$caps multisite-subdomain" ;;
  esac

  # Snapshots are files this driver writes. Probe the destination instead of assuming
  # it, the same way the DDEV driver probes its snapshot directory.
  if mkdir -p "$(_studio_snap_dir)" 2>/dev/null &&
     touch "$(_studio_snap_dir)/.wpaudit-probe" 2>/dev/null; then
    rm -f "$(_studio_snap_dir)/.wpaudit-probe"
    caps="$caps snapshot"
  fi

  # HTTPS needs a .local domain AND a certificate the user trusted by hand in Keychain.
  # Config alone proves nothing: a site can report https=true and still fail every TLS
  # handshake. Only a fetch that validates counts.
  case "$url" in
    https://*)
      case "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$url/" 2>/dev/null)" in
        ''|000) ;;
        *) caps="$caps https" ;;
      esac ;;
  esac

  # Xdebug is real but ASYMMETRIC, and the asymmetry will cost someone an afternoon:
  # `studio config set --xdebug` loads it into the web-request PHP only. `studio wp`
  # runs a separate process that never has it — verified, xdebug 3.5.3 visible over
  # HTTP and absent from wp eval in the same site. Probe the shared object for the
  # configured PHP build; a version Studio hasn't downloaded yet simply under-claims.
  if [ -f "$(_studio_php_dir 2>/dev/null)/ext/xdebug.so" ]; then
    caps="$caps xdebug"
  fi

  _studio_db_caps "$caps"
}

# SQLite by default via the drop-in; MySQL only when wp-config.php carries real
# credentials. When neither is identifiable, declare no engine at all — a wrong engine
# token sends a cell down a query path the database doesn't have.
_studio_db_caps() {
  local caps="$1"
  if [ -f "$_STUDIO_DIR/wp-content/database/.ht.sqlite" ] &&
     grep -qi sqlite "$_STUDIO_DIR/wp-content/db.php" 2>/dev/null; then
    caps="$caps sqlite"
  else
    case "$(sed -n "s/^ *define( *'DB_USER', *'\([^']*\)'.*/\1/p" \
            "$_STUDIO_DIR/wp-config.php" 2>/dev/null | head -1)" in
      ''|username_here) ;;
      *) caps="$caps mysql" ;;
    esac
  fi

  echo "$caps"
}

# Deliberately outside the document root: a .sql file living under ~/Studio/<site>
# shows up in env_tree and reads as core-tree drift in exactly the comparisons this
# repo runs.
_studio_snap_dir() { echo "${WP_AUDIT_STUDIO_SNAPSHOTS:-$HOME/.wp-audit/studio-snapshots}"; }
_studio_snap_file() { echo "$(_studio_snap_dir)/$(basename "$_STUDIO_DIR")-$1.sql"; }

# --skip-browser matters in a suite: the default is to open the site in a browser.
env_start()   { _studio start --path "$_STUDIO_DIR" --skip-browser --skip-log-details >/dev/null; }
env_stop()    { _studio stop --path "$_STUDIO_DIR" >/dev/null; }
env_destroy() { _studio delete --path "$_STUDIO_DIR" --files >/dev/null; }

# --path leads, so a WP-CLI subcommand's own positional parsing can never swallow it.
#
# Captured then cleaned, never `… | tr -d '\r'`: a pipeline returns tr's status, which
# is always 0, and that silently disables every `env_wp … || fallback` in every suite.
env_wp() {
  local out rc
  out="$(_studio wp --path="$_STUDIO_DIR" "$@" 2>/dev/null)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | tr -d '\r'
  return "$rc"
}

# There is no container, so "inside the environment" means the document root with the
# site's own PHP build ahead of the host's — `env_exec php -v` reports the version the
# site is actually served with, not whatever Homebrew put on PATH.
env_exec() {
  local php; php="$(_studio_php_dir 2>/dev/null)"
  ( cd "$_STUDIO_DIR" || return 1
    [ -n "$php" ] && PATH="$php:$PATH" && export PATH
    "$@" )
}

env_docroot() { echo "$_STUDIO_DIR"; }

# Studio reports the URL with a trailing slash; drop it to match every other driver.
env_url() {
  _studio status --path "$_STUDIO_DIR" --format json 2>/dev/null \
    | sed -n 's/.*"siteUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | sed 's#/$##'
}

env_db_snapshot() {
  local f; f="$(_studio_snap_file "$1")"
  mkdir -p "$(_studio_snap_dir)" || return 1
  _studio export "$f" --mode db --path "$_STUDIO_DIR" >/dev/null 2>&1 || return 1
  [ -s "$f" ] || { echo "studio: snapshot '$1' produced no data" >&2; return 1; }
}

# Restoring restarts the site — Studio brings the server back up itself, so callers
# don't need an env_start afterwards.
env_db_restore() {
  local f; f="$(_studio_snap_file "$1")"
  [ -s "$f" ] || { echo "studio: no snapshot '$1' at $f" >&2; return 1; }
  _studio import "$f" --path "$_STUDIO_DIR" >/dev/null 2>&1
}

env_php_get() { _studio_cfg php; }

# Studio ships four PHP builds and nothing else. Catch an out-of-range request here
# rather than let a suite read the failure as a PHP-version-specific WordPress result.
env_php_set() {
  local want="$1" got
  case "$want" in
    8.2|8.3|8.4|8.5) ;;
    *) echo "studio: PHP $want unavailable — Studio ships 8.2, 8.3, 8.4, 8.5 only" >&2; return 3 ;;
  esac
  _studio config set --php "$want" --path "$_STUDIO_DIR" >/dev/null 2>&1 || return 1
  _studio_cfg_refresh
  got="$(env_wp eval 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  [ "$got" = "$want" ] || { echo "studio: asked for PHP $want, got '$got'" >&2; return 1; }
}

# Version string ("7.0.1", "7.1-beta4") or a zip URL.
#
# The URL branch unpacks on the host because the host IS the environment — no exec
# into anything. It overwrites in place and does NOT delete files the new build
# dropped, which is the point: that residue is the finding.
#
# Verifies the outcome instead of the exit code, for the reason ddev.sh gives: a core
# download can fail mid-extract and leave the previous version sitting there.
env_core_install() {
  local target="$1" before after tmp
  before="$(env_wp core version)"
  case "$target" in
    http://*|https://*)
      tmp="$(mktemp -d)" || return 1
      curl -sSL -o "$tmp/core.zip" "$target" >/dev/null 2>&1 &&
        unzip -q "$tmp/core.zip" -d "$tmp/x" >/dev/null 2>&1 &&
        cp -a "$tmp/x/wordpress/." "$_STUDIO_DIR/"
      rm -rf "$tmp" ;;
    *)
      env_wp core download --version="$target" --force >/dev/null 2>&1 ;;
  esac
  after="$(env_wp core version)"
  if [ -z "$after" ]; then
    echo "studio: core install left no readable version (was '$before')" >&2; return 1
  fi
  case "$target" in
    "$after"*|http*) ;;
    *) echo "studio: asked for '$target', got '$after' — install did not take" >&2; return 1 ;;
  esac
  _studio_cfg_refresh
  echo "$after"
}

env_multisite_convert() {
  local host
  if [ "${1:-}" = "--subdomains" ]; then
    env_has multisite-subdomain || {
      host="$(env_url)"; host="${host#*://}"; host="${host%%/*}"; host="${host%%:*}"
      echo "studio: *.$host does not resolve, so subdomain subsites would not serve" >&2
      return 3; }
    env_wp core multisite-convert --subdomains
  else
    env_wp core multisite-convert
  fi
}
