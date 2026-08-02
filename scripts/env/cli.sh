#!/bin/bash
# WP-CLI driver — plain `wp` against a WordPress that already exists.
#
#   env_init cli ~/Local\ Sites/wp71/app/public     # a document root
#   env_init cli @staging                           # a WP-CLI alias
#
# The smallest driver here and the largest coverage gain. README Option A (the Beta
# Tester plugin on a site you already have — "how most people do it") and Option C (Local,
# Studio, MAMP, XAMPP) have had no automation at all; this is it. LocalWP's own CLI was
# archived read-only in May 2025 and never wrapped WP-CLI, so pointing this driver at
# ~/Local Sites/<site>/app/public is the only supported way to script a Local site. The
# same shape covers a hosting CLI later: Pantheon's `terminus wp`, WP Engine over SSH.
#
# IT IS ALSO THE ONLY DRIVER THAT CAN BE POINTED AT PRODUCTION. Every other driver builds
# something disposable and can afford to be careless. This one runs against whatever it is
# handed, and nothing about a path or an alias says which. Hence the gate below.
#
# Verified 2026-08-01 — WP-CLI 2.12.0, PHP 8.5.4, macOS arm64 — against a throwaway
# MySQL 9.6 install created and destroyed for the run, and (read-only) a SQLite-backed
# Studio site. Four things this driver probes rather than assumes, all found by that run:
#
#   1. `wp core download` OOMs AT THE DEFAULT memory_limit and leaves the old tree in
#      place — the hazard lib-fast.sh's wdl() raises memory for. Reproduced exactly:
#      fatal in Extractor.php at 128M, docroot left empty, nothing on the exit path that
#      a caller would notice. Raised here via `--exec`, and the result is verified.
#   2. WP-CLI PRINTS PHP DIAGNOSTICS ON STDOUT wherever php.ini has display_errors=On —
#      Homebrew's default, and plenty of shared hosts. `wp core version` returned a blank
#      line, a "Deprecated: ..." line, then "7.0.2". Unfiltered, that poisons every
#      version compare and every database dump this driver takes.
#   3. SQLITE IS NOT A DATABASE WP-CLI CAN DUMP. On the Studio site `wp db query` failed
#      with "Access denied for user 'username_here'" — it falls back to the mysql client
#      and reads the placeholder credentials out of wp-config.php — and `wp db export`
#      returned an empty stream with a ZERO exit status. Probing output instead of exit
#      status is the only reason db-reset and snapshot stay off a SQLite target.
#   4. The `wp` on your PATH need not run the PHP the site serves with. That is the
#      normal case under Local and MAMP. Both are printed at init and a mismatch is
#      called out, because "tested on PHP 8.5" is a false report if the web server is 8.2.
#
# NOT VERIFIED: a remote `@alias` target. Every alias reachable from this machine points
# at somebody's real staging or live site, and this driver's own first rule is that you do
# not touch one of those to see what happens. The remote paths are written so that a
# remote target simply fails the host-visible-docroot test and loses hostfs and shell,
# which is the safe direction to be wrong in — but treat remote as untested until someone
# runs it against a staging box they own. Nothing here has been run over SSH.
#
# Deltas from the DDEV reference: no php-switch (nothing in WP-CLI switches PHP), no
# start/stop/destroy (this driver did not create the site and must not be able to delete
# it), and hostfs/shell only when the install is on this host.

_CLI_ALIAS=""     # "@staging" when the target is an alias, empty otherwise
_CLI_PATH=""      # host path the operator passed, empty for an alias
_CLI_ABSPATH=""   # VERIFIED host-visible docroot — empty when the install is elsewhere
_CLI_FACTS=""     # cached key=value probe output: one round trip, not fifteen

env_driver_init() {
  local target="${1:-.}" ver

  command -v wp >/dev/null 2>&1 || {
    echo "cli: wp (WP-CLI) not installed — https://wp-cli.org/" >&2; return 1; }

  _CLI_ALIAS=""; _CLI_PATH=""; _CLI_ABSPATH=""; _CLI_FACTS=""

  case "$target" in
    @*) _CLI_ALIAS="$target" ;;
    *)
      _CLI_PATH="$(cd "$target" 2>/dev/null && pwd)" || {
        echo "cli: no such directory: $target" >&2; return 1; }
      if [ ! -f "$_CLI_PATH/wp-includes/version.php" ]; then
        echo "cli: no WordPress at $_CLI_PATH — no wp-includes/version.php" >&2
        echo "     give this driver a document root:" >&2
        echo "       ~/Local Sites/<site>/app/public     Local" >&2
        echo "       ~/Studio/<site>                     Studio" >&2
        echo "       /Applications/MAMP/htdocs/<site>    MAMP" >&2
        echo "     or a WP-CLI alias from ~/.wp-cli/config.yml, e.g. @staging" >&2
        return 1
      fi ;;
  esac

  # The gate runs before anything reaches the site. A refusal must cost the target
  # nothing at all — not even a connection.
  _cli_require_disposable "$target" || return 1

  ver="$(env_wp core version)"
  if [ -z "$ver" ]; then
    echo "cli: wp cannot reach WordPress at '$target'" >&2
    [ -n "$_CLI_ALIAS" ] && echo "     check the alias resolves: wp cli alias list" >&2
    echo "     and that it answers directly: wp ${_CLI_ALIAS:---path=$_CLI_PATH} core version" >&2
    return 1
  fi

  _CLI_FACTS="$(_cli_probe)"
  if [ -z "$_CLI_FACTS" ]; then
    echo "cli: WordPress at '$target' answered 'core version' but not 'eval'" >&2
    echo "     the install is probably broken (fatal on load) — fix it before testing a release" >&2
    return 1
  fi

  _cli_resolve_docroot "$ver"
  _cli_disposability_report "$target" "$ver"
}

# ---------------------------------------------------------------- the safety gate
#
# Every other driver creates an environment it can throw away. This one attaches to a
# real WordPress on a real web server — the whole point, and the whole risk. The README's
# safety section is unambiguous: prereleases eat databases, and there is no supported
# downgrade from a Beta or RC. Going back means restoring a backup the operator may not
# have taken.
#
# So the driver will not start until someone says out loud that the target is expendable.
# An environment variable is the cheapest thing that does not happen by accident: it is
# absent from a fresh shell, it is visible in the command that set it, and it names the
# claim being made rather than acknowledging a warning nobody read.
#
# The gate refuses. It does not "warn and continue" — a warning printed above a suite
# that ran anyway is not a safeguard. Detection of production signals (below) is the part
# that only warns, because a signal is a guess and this is a fact the operator supplied.
_cli_require_disposable() {
  local target="$1"
  [ "${WP_AUDIT_CLI_DISPOSABLE:-}" = "1" ] && return 0
  {
    echo
    echo "cli: REFUSING to touch '$target' — nobody has said it is disposable."
    echo
    echo "     This is the only driver here that runs against a WordPress somebody else"
    echo "     installed: a Local site, a staging box, a client's server. A path or an"
    echo "     alias does not tell me which of those it is, and getting it wrong is not"
    echo "     recoverable — prereleases eat databases, and there is no supported way"
    echo "     back down from a Beta or RC. Down means restoring a backup."
    echo
    echo "     If it is genuinely throwaway — a scratch install, or a staging COPY you"
    echo "     could lose without flinching — say so and run again:"
    echo
    echo "         export WP_AUDIT_CLI_DISPOSABLE=1"
    echo
    if [ -n "${WP_AUDIT_CLI_DISPOSABLE:-}" ]; then
      echo "     (WP_AUDIT_CLI_DISPOSABLE is set to '$WP_AUDIT_CLI_DISPOSABLE' — it must be exactly 1)"
      echo
    fi
    echo "     If it is anything you would miss: stop. Copy it, point this at the copy."
    echo
  } >&2
  return 1
}

# What the site itself says about whether it looks like production. Every one of these is
# circumstantial — a legitimate test site can trip any of them, and the Studio site used
# to verify this driver trips one — so this WARNS and never blocks. Its job is to make
# "I pointed it at the wrong thing" visible in the second before it matters, instead of in
# the report afterwards.
_cli_disposability_report() {
  local target="$1" ver="$2" host warn=0 phpcli phpweb
  host="$(_cli_fact home)"; host="${host#*://}"; host="${host%%/*}"
  case "$host" in *:[0-9]*) host="${host%:*}" ;; esac
  phpcli="$(env_wp eval 'echo PHP_VERSION;')"
  phpweb="$(_cli_fact webphp)"
  {
    echo "════ cli: DISPOSABILITY CHECK  (target: $target)"
    echo "  site    $(_cli_fact home)   WordPress $ver"
    echo "  db      $(_cli_fact engine) $(_cli_fact dbver)"
    # Not a disposability signal, so it stays out of the tally below — but it is the
    # harness fault most likely to be written up as a WordPress finding, so it is said
    # first and said loudly. Verified against a Studio site: CLI 8.5.4, web 8.3.32.
    if [ -n "$phpweb" ] && [ "$phpweb" != "$phpcli" ]; then
      echo "  WARN  PHP differs: CLI $phpcli, web server $phpweb — env_php_get reports the CLI's."
      echo "        Anything you attribute to $phpcli did not come from the server under test."
    else
      echo "  php     $phpcli${phpweb:+ (web $phpweb)}"
    fi

    # A hostname nobody could reach from outside is the strongest disposability signal
    # available, so its absence is the strongest production signal.
    case "$host" in
      localhost|127.0.0.1|::1|\[::1\]|*.test|*.local|*.localhost|*.ddev.site|*.lndo.site|*.wip)
        echo "  ok      site URL is a local hostname" ;;
      *)
        echo "  WARN  site URL is NOT local: $host"; warn=$((warn + 1)) ;;
    esac

    # Set deliberately, this is the site telling you what it is. Unset, WordPress returns
    # "production" for everything, so only an explicit value counts either way.
    if [ "$(_cli_fact envset)" = "1" ]; then
      case "$(_cli_fact envtype)" in
        production) echo "  WARN  WP_ENVIRONMENT_TYPE is set to production"; warn=$((warn + 1)) ;;
        *)          echo "  ok      WP_ENVIRONMENT_TYPE = $(_cli_fact envtype)" ;;
      esac
    fi

    [ "$(_cli_fact debug)" = "1" ] || {
      echo "  WARN  WP_DEBUG is off — unusual on a site meant for testing a prerelease"
      warn=$((warn + 1)); }

    # Thresholds sit high on purpose. This repo's own fixture corpora seed real content:
    # the verified Studio site carries 65 published posts and 4 users, and crying wolf on
    # a correctly seeded test site would train the operator to skim past the one that
    # matters.
    [ "$(_cli_fact posts)" -gt 250 ] 2>/dev/null && {
      echo "  WARN  $(_cli_fact posts) published posts — more content than a test site earns"
      warn=$((warn + 1)); }
    [ "$(_cli_fact users)" -gt 10 ] 2>/dev/null && {
      echo "  WARN  $(_cli_fact users) user accounts — real people have accounts here"
      warn=$((warn + 1)); }

    if [ "$warn" -gt 0 ]; then
      echo
      echo "  $warn signal(s) say this may not be disposable. You have affirmed that it is."
      echo "  Nothing has been written yet. If you are wrong, stop now."
    fi
  } >&2

  # Only when a human is watching, and only when the case is bad. In CI there is no TTY
  # and no one to interrupt, so this never costs an automated run anything.
  [ "$warn" -ge 3 ] && [ -t 0 ] && sleep 5
  return 0
}

# ---------------------------------------------------------------- plumbing

_cli_wp() {
  if [ -n "$_CLI_ALIAS" ]; then command wp "$_CLI_ALIAS" "$@"
  else command wp --path="$_CLI_PATH" "$@"; fi
}

# `wp core download` extracts through PharData and dies at a 128M memory_limit, leaving
# the old files in place (header note 1). `--exec` is the portable way to raise it:
# WP_CLI_PHP_ARGS is read only by the shell wrapper — Homebrew ships the bare phar, where
# setting it does nothing, verified — and `php -d` cannot cross an SSH alias, while a
# global flag does. Scoped to that one command deliberately: raising the limit for every
# call would hide a genuine memory regression in the release under test.
_cli_wp_big() { _cli_wp --exec='ini_set("memory_limit","1024M");' "$@"; }

# WP-CLI's own output is clean; PHP's is not (header note 2). Anchored on the full
# "<level>: <message> in <file> on line <n>" shape so that post content merely containing
# the word "Warning:" is never eaten. LC_ALL=C because BSD sed aborts with "illegal byte
# sequence" partway through a mysqldump stream in a UTF-8 locale, which would truncate a
# snapshot into something that still looks like a file. \r first, or the notice pattern
# never matches CRLF output.
_cli_clean() {
  tr -d '\r' | LC_ALL=C sed -E \
    -e '/^(PHP )?(Deprecated|Notice|Warning|Strict Standards|Fatal error|Parse error): .+ in .+ on line [0-9]+$/d' \
    -e '/./,$!d'
}

# One eval, every fact, because a remote alias pays SSH latency per round trip. Written
# without a single-quote character anywhere so it survives the surrounding shell quoting.
_cli_probe() {
  _cli_wp eval '
global $wpdb;
$o = array();
$cls = strtolower( get_class( $wpdb ) );
$dbv = method_exists( $wpdb, "db_server_info" ) ? (string) $wpdb->db_server_info() : "";
if ( strpos( $cls, "sqlite" ) !== false )      { $eng = "sqlite"; }
elseif ( stripos( $dbv, "mariadb" ) !== false ) { $eng = "mariadb"; }
elseif ( $dbv !== "" )                          { $eng = "mysql"; }
else                                            { $eng = "unknown"; }
$cfg = "";
if ( file_exists( ABSPATH . "wp-config.php" ) )              { $cfg = ABSPATH . "wp-config.php"; }
elseif ( file_exists( dirname( ABSPATH ) . "/wp-config.php" ) ) { $cfg = dirname( ABSPATH ) . "/wp-config.php"; }
$o["abspath"]   = ABSPATH;
$o["home"]      = home_url();
$o["engine"]    = $eng;
$o["dbver"]     = $dbv;
$o["multisite"] = is_multisite() ? ( is_subdomain_install() ? "subdomain" : "subdir" ) : "none";
$o["debug"]     = ( defined( "WP_DEBUG" ) && WP_DEBUG ) ? "1" : "0";
$o["envtype"]   = function_exists( "wp_get_environment_type" ) ? wp_get_environment_type() : "unknown";
$o["envset"]    = ( defined( "WP_ENVIRONMENT_TYPE" ) || getenv( "WP_ENVIRONMENT_TYPE" ) ) ? "1" : "0";
$o["posts"]     = (int) wp_count_posts()->publish;
$o["users"]     = (int) $wpdb->get_var( "SELECT COUNT(*) FROM $wpdb->users" );
$o["abspath_w"] = is_writable( ABSPATH ) ? "1" : "0";
$o["config_w"]  = ( $cfg !== "" && is_writable( $cfg ) ) ? "1" : "0";
$o["filemods"]  = ( ( defined( "DISALLOW_FILE_MODS" ) && DISALLOW_FILE_MODS ) || ( defined( "AUTOMATIC_UPDATER_DISABLED" ) && AUTOMATIC_UPDATER_DISABLED ) ) ? "1" : "0";
$o["xdebug"]    = extension_loaded( "xdebug" ) ? "1" : "0";
$r = wp_remote_get( home_url( "/" ), array( "timeout" => 7, "sslverify" => false ) );
$o["loopback"]  = is_wp_error( $r ) ? "0" : (string) wp_remote_retrieve_response_code( $r );
$o["server"]    = is_wp_error( $r ) ? "" : strtolower( (string) wp_remote_retrieve_header( $r, "server" ) );
$o["webphp"]    = is_wp_error( $r ) ? "" : trim( str_replace( "PHP/", "", (string) wp_remote_retrieve_header( $r, "x-powered-by" ) ) );
$a = wp_remote_head( "https://api.wordpress.org/core/version-check/1.7/", array( "timeout" => 7 ) );
$o["wporg"]     = is_wp_error( $a ) ? "0" : "1";
foreach ( $o as $k => $v ) { echo $k, "=", str_replace( array( "\r", "\n" ), " ", $v ), "\n"; }
' 2>/dev/null | _cli_clean
}

_cli_fact() { printf '%s\n' "$_CLI_FACTS" | sed -n "s/^$1=//p" | head -1; }

# hostfs is not "the operator gave me a path" — it is "the directory I can see is the
# install wp is talking to". A WP-CLI alias may be local (path only, no ssh) or remote,
# and a remote path can exist on this machine by coincidence, so ask both sides for the
# version and require them to agree. That one comparison settles hostfs, shell and
# env_docroot for every target shape without parsing an alias definition.
_cli_resolve_docroot() {
  local claimed="$1" abs seen
  abs="$(_cli_fact abspath)"; abs="${abs%/}"
  [ -n "$abs" ] && [ -f "$abs/wp-includes/version.php" ] || return 0
  seen="$(grep -m1 '^\$wp_version' "$abs/wp-includes/version.php" 2>/dev/null | sed "s/[^']*'//; s/'.*//")"
  [ -n "$seen" ] && [ "$seen" = "$claimed" ] && _CLI_ABSPATH="$abs"
  return 0
}

# `wp db reset` is DROP DATABASE + CREATE DATABASE, and shared hosting hands out users
# with neither. Ask the server rather than assuming. Matched with the separators attached
# so the DROP ROLE / CREATE ROLE privileges cannot pass for the real thing.
_cli_db_writable() {
  local g
  g="$(_cli_wp db query 'SHOW GRANTS FOR CURRENT_USER();' 2>/dev/null | _cli_clean)"
  case "$g" in *"ALL PRIVILEGES"*) return 0 ;; esac
  case "$g" in
    *"DROP,"*|*"DROP ON"*) case "$g" in *"CREATE,"*|*"CREATE ON"*) return 0 ;; esac ;;
  esac
  return 1
}

# Writes a dump of the target to $1; extra arguments are passed to `wp db export`.
#
# mysqldump on a GTID-enabled server — the default from MySQL 8 onward — writes a
# SET @@GLOBAL.GTID_PURGED statement that the matching import then refuses:
# "ERROR 3546 (HY000) at line 24: @@GLOBAL.GTID_PURGED cannot be changed". Verified on
# MySQL 9.6: the export reports success, the file looks perfect, and the restore fails on
# the twenty-fourth line of it. --set-gtid-purged=OFF removes the statement, but MariaDB's
# mysqldump has never heard of the option, so try it and fall back rather than branching
# on a version string. (Valued flags pass through; bare ones do not — WP-CLI turns
# `--no-data` into `--no-data=` and mysqldump rejects that, verified.)
_cli_dump() {
  local f="$1"; shift
  _cli_wp db export - --single-transaction --set-gtid-purged=OFF "$@" 2>/dev/null | _cli_clean > "$f"
  _cli_dump_ok "$f" && return 0
  _cli_wp db export - --single-transaction "$@" 2>/dev/null | _cli_clean > "$f"
  _cli_dump_ok "$f"
}

# Judge the file, never the exit status: on SQLite `wp db export` returns an empty stream
# and status 0 (header note 3), and a GTID_PURGED line means a dump that restores into an
# error rather than a database.
_cli_dump_ok() {
  [ -s "$1" ] || return 1
  grep -qi 'CREATE TABLE' "$1" || return 1
  ! grep -qi 'GTID_PURGED' "$1"
}

# Prove the whole snapshot path for a few kilobytes on a site of any size: --where=1=0
# dumps every schema and no rows, which exercises mysqldump, the credentials, the flag
# negotiation above, and whether the snapshot directory is writable at all.
_cli_snapshot_probe() {
  local dir f rc
  dir="$(_cli_snapshot_dir)"; f="$dir/.probe.sql"
  mkdir -p "$dir" 2>/dev/null || return 1
  _cli_dump "$f" --where=1=0; rc=$?
  rm -f "$f"
  return "$rc"
}

# WordPress refuses a subdomain conversion without real hostnames — allow_subdomain_install()
# bails on localhost, on a bare IP, and on a home URL carrying a path. A port is the
# wp-env / Studio giveaway and fails the same test.
_cli_subdomain_ok() {
  local host
  host="$(_cli_fact home)"; host="${host#*://}"
  case "$host" in
    */*) return 1 ;;
    *:*) return 1 ;;
    localhost) return 1 ;;
    [0-9]*.[0-9]*.[0-9]*.[0-9]*) return 1 ;;
  esac
  [ -n "$host" ]
}

_cli_http_ok() {
  case "$(_cli_fact loopback)" in 2??|3??) return 0 ;; *) return 1 ;; esac
}

# Snapshots live beside the operator's other audit state and never in $TMPDIR: macOS
# empties it, and a restore point that evaporates mid-suite is worse than none at all.
# (The DDEV driver avoids $TMPDIR too, for an unrelated reason — snapshots fail outright
# there.) Override with WP_AUDIT_CLI_SNAPSHOT_DIR.
_cli_snapshot_dir() {
  local slug
  slug="$(printf '%s' "${_CLI_ALIAS:-$_CLI_PATH}" | tr -c 'A-Za-z0-9._-' '-')"
  echo "${WP_AUDIT_CLI_SNAPSHOT_DIR:-$HOME/.wp-audit/snapshots}/${slug#-}"
}

# ---------------------------------------------------------------- capabilities

env_driver_caps() {
  local caps="" dbw=1

  # Both come from the same fact: the install is on this host.
  [ -n "$_CLI_ABSPATH" ] && caps="$caps hostfs shell"

  # core-updater is the capability this driver exists to provide — it is one of the few
  # that can reproduce the 243-stale-file finding, because Beta Tester drives exactly
  # this path. WordPress's own updater runs inside PHP, so what it needs is a writable
  # ABSPATH, file modifications allowed, and outbound HTTP to wordpress.org. The loopback
  # check is Site Health's: it proves a web server is really serving this install, which
  # is the difference between a real update and a directory full of PHP files.
  if [ "$(_cli_fact abspath_w)" = "1" ] && [ "$(_cli_fact filemods)" = "0" ] \
     && [ "$(_cli_fact wporg)" = "1" ] && _cli_http_ok; then
    caps="$caps core-updater"
  fi

  # core-zip is WP-CLI's own download path: it needs the tree writable and nothing else.
  [ "$(_cli_fact abspath_w)" = "1" ] && caps="$caps core-zip"

  case "$(_cli_fact engine)" in
    sqlite)  caps="$caps sqlite"; dbw=0 ;;
    mysql)   caps="$caps mysql";   _cli_db_writable || dbw=0 ;;
    mariadb) caps="$caps mariadb"; _cli_db_writable || dbw=0 ;;
    *)       dbw=0 ;;
  esac
  if [ "$dbw" = "1" ]; then
    caps="$caps db-reset"
    _cli_snapshot_probe && caps="$caps snapshot"
  fi

  case "$(_cli_fact home)" in https://*) caps="$caps https" ;; esac

  case "$(_cli_fact multisite)" in
    subdir)    caps="$caps multisite-subdir" ;;
    subdomain) caps="$caps multisite-subdomain" ;;
    none)
      # Converting rewrites wp-config.php, so an unwritable config means no conversion
      # regardless of what the hostname allows.
      if [ "$(_cli_fact config_w)" = "1" ]; then
        caps="$caps multisite-subdir"
        _cli_subdomain_ok && caps="$caps multisite-subdomain"
      fi ;;
  esac

  # Presence, not toggleability. Nothing in WP-CLI can turn Xdebug on or off, and this
  # reads the CLI SAPI, which is not necessarily the web server's — a cell that needs to
  # DISABLE Xdebug is not served by this driver and should not read this as a promise.
  [ "$(_cli_fact xdebug)" = "1" ] && caps="$caps xdebug"

  # Free, since the loopback response is already in hand. Anything that is not plainly
  # one or the other — LiteSpeed, a CDN edge, a stripped header — stays undeclared.
  case "$(_cli_fact server)" in
    *nginx*)  caps="$caps nginx" ;;
    *apache*) caps="$caps apache" ;;
  esac

  echo "$caps"
}

# ---------------------------------------------------------------- operations
#
# Deliberately absent, so lib-env.sh's loud default fires instead:
#
#   env_start / env_stop / env_destroy — this driver did not create the site. A driver
#       that can delete a site it was merely pointed at is a bad trade at any price.
#   env_php_set — nothing in WP-CLI switches PHP versions. That belongs to whatever runs
#       the web server: Local's UI, MAMP's, DDEV's config.
#   env_sync — the filesystem is direct, so lib-env.sh's no-op is already correct.

# Captured then cleaned, never `… | _cli_clean` as a pipeline: a pipeline returns the
# CLEANER's status, which is always 0, and that silently disables every
# `env_wp … || fallback` in every suite. The database dump path deliberately does not go
# through here — it streams, and it is judged on the file it produced instead.
env_wp() {
  local out rc
  out="$(_cli_wp "$@" 2>/dev/null)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | _cli_clean
  return "$rc"
}

env_url()  { _cli_fact home; }

env_exec() {
  [ -n "$_CLI_ABSPATH" ] || { _env_unsupported exec; return; }
  ( cd "$_CLI_ABSPATH" && "$@" )
}

# Empty for a remote alias, which is what makes env_tree report a missing docroot
# instead of silently hashing the wrong machine's files.
env_docroot() { echo "$_CLI_ABSPATH"; }

# The destructive verbs re-check the gate. env_init already refused without it, but a
# suite that sources this file directly, or one that runs long enough for someone to
# re-point it, should not get a free pass to drop a database.
env_db_reset() {
  _cli_require_disposable "${WP_AUDIT_ENV_TARGET:-$_CLI_ALIAS$_CLI_PATH}" || return 1
  _cli_wp db reset --yes >/dev/null 2>&1
}

# A real round trip: `wp db export` out, `wp db import` back. Both stream through stdout
# and stdin rather than naming a file, so a remote alias behaves exactly like a local path
# and nothing is left behind on the far end. Passing the filename to `wp db import` also
# simply does not work on this stack — WP-CLI feeds the mysql client a SOURCE statement
# and MySQL 9.6 answered "ERROR 1064 ... near 'SOURCE /Users/...'". Streaming worked.
#
# Verified rather than trusted: a dump that failed halfway still leaves a file behind, and
# a truncated snapshot is a restore point that fails at the worst possible moment.
env_db_snapshot() {
  local dir f
  dir="$(_cli_snapshot_dir)"; f="$dir/$1.sql"
  mkdir -p "$dir" || return 1
  if ! _cli_dump "$f"; then
    echo "cli: snapshot '$1' produced no usable dump — removing it" >&2
    rm -f "$f"
    return 1
  fi
}

env_db_restore() {
  local f
  f="$(_cli_snapshot_dir)/$1.sql"
  [ -s "$f" ] || { echo "cli: no snapshot '$1' at $f" >&2; return 1; }
  _cli_require_disposable "${WP_AUDIT_ENV_TARGET:-$_CLI_ALIAS$_CLI_PATH}" || return 1
  _cli_wp db import - < "$f" >/dev/null 2>&1
}

# Accepts a version string ("6.9", "nightly") or a build URL — `wp core download` takes a
# URL positionally, so both shapes work over an alias too.
#
# VERIFIES the outcome instead of trusting the exit status, for the reason in header note
# 1: the OOM leaves the previous version in place and this is exactly the failure that
# turns into "6.9 behaves identically to 6.8" in a report.
env_core_install() {
  local target="$1" before after
  _cli_require_disposable "${WP_AUDIT_ENV_TARGET:-$_CLI_ALIAS$_CLI_PATH}" || return 1
  before="$(env_wp core version)"
  case "$target" in
    http://*|https://*) _cli_wp_big core download "$target" --force >/dev/null 2>&1 ;;
    *)                  _cli_wp_big core download --version="$target" --force >/dev/null 2>&1 ;;
  esac
  after="$(env_wp core version)"
  if [ -z "$after" ]; then
    echo "cli: core install left no readable version (was '$before')" >&2; return 1
  fi
  case "$target" in
    "$after"*|http*) ;;
    nightly|trunk)
      # A nightly reports a version string nobody can predict, so all that can be
      # asserted is that something moved.
      [ "$after" = "$before" ] && { echo "cli: still on '$before' after a $target install" >&2; return 1; } ;;
    *) echo "cli: asked for '$target', got '$after' — install did not take" >&2; return 1 ;;
  esac
  echo "$after"
}

env_multisite_convert() {
  local want="subdir" have
  [ "${1:-}" = "--subdomains" ] && want="subdomain"
  have="$(_cli_fact multisite)"

  if [ "$have" = "$want" ]; then
    echo "cli: already $want multisite — nothing to convert" >&2
    return 0
  fi
  if [ "$have" != "none" ]; then
    echo "cli: this is $have multisite; there is no conversion from $have to $want" >&2
    return 3
  fi
  _cli_require_disposable "${WP_AUDIT_ENV_TARGET:-$_CLI_ALIAS$_CLI_PATH}" || return 1

  if [ "$want" = "subdomain" ]; then
    env_has multisite-subdomain || {
      echo "cli: subdomain multisite needs real hostnames — '$(_cli_fact home)' will be refused" >&2
      return 3; }
    env_wp core multisite-convert --subdomains
  else
    env_has multisite-subdir || {
      echo "cli: cannot convert — wp-config.php is not writable" >&2
      return 3; }
    env_wp core multisite-convert
  fi
}
