#!/bin/bash
# Direct-jump upgrade matrix: latest of EACH release series -> target, one fresh
# install per hop (no chaining). Complements stepped-chain.sh, which carries a
# single database through every intermediate version.
#
# Usage: direct-jump-matrix.sh [--target=zip-url] <project-dir> <tests-site-url> [target-zip-url]
# Old WordPress needs old PHP — run this against the PHP 7.4 cell.

# --target= wins, then the legacy third positional, then WP_AUDIT_TARGET —
# explicit beats ambient. Default unchanged.
_FLAG=""; _ARGS=()
for _a in "$@"; do case "$_a" in --target=*) _FLAG="${_a#--target=}" ;; *) _ARGS+=("$_a") ;; esac; done
# Restore the stripped args as positionals: array INDEXING differs between
# bash (0-based) and zsh (1-based), positionals do not.
set -- "${_ARGS[@]}"
PROJ="$1"; URL="$2"
TARGET="${_FLAG:-${3:-${WP_AUDIT_TARGET:-https://wordpress.org/wordpress-7.1-beta4.zip}}}"
# What `wp core version` must report after the jump — derived from the target
# zip name so pointing at a new build can't silently fail every row.
EXPECT=$(basename "$TARGET" .zip | sed 's/^wordpress-//')
# Latest of every branch (api.wordpress.org/core/stable-check). Override with
# VERSIONS="..." in the environment to run a subset.
VERSIONS="${VERSIONS:-4.9.29 5.0.25 5.1.22 5.2.24 5.3.21 5.4.19 5.5.18 5.6.17 5.7.15 5.8.13 5.9.13 6.0.12 6.1.10 6.2.9 6.3.8 6.4.8 6.5.8 6.6.5 6.7.5 6.8.6 6.9.5 7.0.2}"
cd "$PROJ" || exit 1

t() { npx --yes @wordpress/env@latest run tests-cli -- "$@" 2>/dev/null \
      | grep -vE "^(ℹ|✔|npm warn)" | tr -d '\r' | sed '/^$/d'; }

# A previous multisite run leaves MULTISITE constants in wp-config.php. A
# single-site install on top of those 500s, and the whole matrix fails in a way
# that looks like an upgrade bug. Always strip them first.
for C in WP_ALLOW_MULTISITE MULTISITE SUBDOMAIN_INSTALL DOMAIN_CURRENT_SITE \
         PATH_CURRENT_SITE SITE_ID_CURRENT_SITE; do
  t wp config delete "$C" >/dev/null 2>&1
done
echo "multisite constants cleared; is_multisite=$(t wp eval 'echo is_multisite()?"yes":"no";' 2>/dev/null)"

printf "%-9s %-11s %-8s %-11s %-8s %-5s %-5s %-6s %s\n" \
  FROM BEFORE_VER BEFORE_DB AFTER_VER AFTER_DB FRONT LOGIN POSTS RESULT

for V in $VERSIONS; do
  # Legacy installs are intermittently flaky (a transient DB hiccup 500s the
  # install). Retry once so a flake isn't logged as an upgrade failure.
  BV=""; BD=""
  for attempt in 1 2; do
    t wp db reset --yes >/dev/null 2>&1
    # `core download --force` OVERWRITES but never DELETES, so bundled themes end
    # up mixed across versions — e.g. Twenty Twenty-Two's block-patterns.php from
    # one release requiring pattern files from another, which fatals the whole
    # site and even breaks wp-cli bootstrap. Wipe core dirs + themes each time.
    t bash -c 'rm -rf /var/www/html/wp-admin /var/www/html/wp-includes /var/www/html/wp-content/themes/*' >/dev/null 2>&1
    # NOTE: the phar + raised memory_limit is required; plain `wp core download`
    # dies at 128M extracting core and the failure is easy to swallow.
    t php -d memory_limit=1024M /usr/local/bin/wp core download --version="$V" --force --allow-root >/dev/null 2>&1
    t wp core install --url="$URL" --title="direct $V" --admin_user=admin \
         --admin_password=password --admin_email=a@example.com --skip-email >/dev/null 2>&1
    BV=$(t wp core version); BD=$(t wp option get db_version)
    # a good install has BOTH the right version and a populated db_version
    [ "$BV" = "$V" ] && [ -n "$BD" ] && break
    [ $attempt -eq 1 ] && sleep 5
  done
  # seed a canary so we can prove content survives the jump
  t wp post create --post_title="Canary $V" --post_content="canary-$V" --post_status=publish >/dev/null 2>&1

  t wp core update "$TARGET" --force >/dev/null 2>&1
  t wp core update-db >/dev/null 2>&1

  AV=$(t wp core version); AD=$(t wp option get db_version)
  FRONT=$(curl -s -o /dev/null -w '%{http_code}' -L "$URL/")
  LOGIN=$(curl -s -o /dev/null -w '%{http_code}' "$URL/wp-login.php")
  POSTS=$(t wp post list --format=count)
  FATAL=$(curl -sL "$URL/" | grep -ciE 'fatal error|parse error')
  CANARY=$(t wp post list --format=csv --fields=post_title | grep -c "Canary $V")

  # a hop only passes if it actually STARTED from the version we asked for
  if [ "$BV" != "$V" ]; then                       R="FAIL: never installed $V (got $BV)"
  elif [ "$AV" != "$EXPECT" ]; then                R="FAIL: ended on $AV"
  elif [ "$FRONT" != "200" ] || [ "$LOGIN" != "200" ]; then R="FAIL: http $FRONT/$LOGIN"
  elif [ "$FATAL" != "0" ]; then                   R="FAIL: fatal on frontend"
  elif [ "$CANARY" != "1" ]; then                  R="FAIL: canary lost"
  else                                             R="PASS"; fi

  printf "%-9s %-11s %-8s %-11s %-8s %-5s %-5s %-6s %s\n" \
    "$V" "$BV" "$BD" "$AV" "$AD" "$FRONT" "$LOGIN" "$POSTS" "$R"
done
