#!/bin/bash
# Clean-capture upgrade verification. Values only, no wp-env chrome.
# Target build: --target=<zip-url> anywhere in the args, or WP_AUDIT_TARGET
# (explicit flag wins). Default unchanged — a suite never picks its own target.
_FLAG=""; _ARGS=()
for _a in "$@"; do case "$_a" in --target=*) _FLAG="${_a#--target=}" ;; *) _ARGS+=("$_a") ;; esac; done
# Restore the stripped args as positionals: array INDEXING differs between
# bash (0-based) and zsh (1-based), positionals do not.
set -- "${_ARGS[@]}"
PROJ="$1"; URL="$2"; FROM="$3"; MODE="${4:-single}"
TARGET="${_FLAG:-${WP_AUDIT_TARGET:-https://wordpress.org/wordpress-7.1-beta4.zip}}"
TARGET_VER="$(basename "$TARGET" .zip | sed 's/^wordpress-//')"
cd "$PROJ" || exit 1

# quiet wrapper: strips wp-env's status lines, keeps command stdout
q() { npx --yes @wordpress/env@latest run tests-cli -- "$@" 2>/dev/null \
      | grep -vE "^(ℹ|✔|npm warn)" | tr -d '\r' | sed '/^$/d'; }

echo "### $FROM -> $TARGET_VER [$MODE]"
q wp db reset --yes >/dev/null
q php -d memory_limit=1024M /usr/local/bin/wp core download --version="$FROM" --force --allow-root >/dev/null 2>&1 || echo "DOWNLOAD_FAILED"

if [ "$MODE" = "single" ]; then
  q wp core install --url="$URL" --title="UP" --admin_user=admin --admin_password=password \
       --admin_email=a@example.com --skip-email >/dev/null
else
  SD=""; [ "$MODE" = "subdomain" ] && SD="--subdomains"
  q wp core multisite-install $SD --url="$URL" --title="UPnet" --admin_user=admin \
       --admin_password=password --admin_email=a@example.com --skip-email >/dev/null
fi

echo "before_version=$(q wp core version)"
echo "before_db=$(q wp option get db_version)"

UPD=$(q wp core update "$TARGET" --force | tail -1)
echo "update_says=$UPD"

if [ "$MODE" = "single" ]; then
  DBOUT=$(q wp core update-db | tail -1)
else
  DBOUT=$(q wp core update-db --network | tail -1)
fi
echo "updatedb_says=$DBOUT"

echo "after_version=$(q wp core version)"
echo "after_db=$(q wp option get db_version)"
echo "is_installed=$(q wp core is-installed && echo yes || echo no)"
echo "frontend_http=$(curl -s -o /dev/null -w '%{http_code}' "$URL/")"
echo "login_http=$(curl -s -o /dev/null -w '%{http_code}' "$URL/wp-login.php")"
echo "admin_http=$(curl -s -o /dev/null -w '%{http_code}' -L --max-redirs 3 "$URL/wp-admin/")"
echo "post_count=$(q wp post list --format=count)"
echo "php_errors=$(q wp eval 'echo "ok";')"
# surface any PHP notice/fatal the loader emits on a plain front-end request
echo "frontend_fatal=$(curl -s "$URL/" | grep -ciE 'fatal error|parse error' )"
echo "---"
