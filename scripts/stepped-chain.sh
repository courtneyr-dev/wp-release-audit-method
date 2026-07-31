#!/bin/bash
# Stepped legacy upgrade chain: 4.9.29 through every major series up to 7.1-beta4.
# Each hop is a real wp core update + update-db, carrying the SAME database forward.
PROJ="$1"; URL="$2"
BETA4="https://wordpress.org/wordpress-7.1-beta4.zip"
CHAIN="5.0.25 5.2.24 5.5.18 5.9.13 6.0.12 6.2.9 6.5.8 6.8.6 6.9.5 7.0.2"
cd "$PROJ" || exit 1

q() { npx --yes @wordpress/env@latest run tests-cli -- "$@" 2>/dev/null \
      | grep -vE "^(ℹ|✔|npm warn)" | tr -d '\r' | sed '/^$/d'; }

echo "### STEPPED CHAIN 4.9.29 -> ... -> 7.1-beta4 (PHP 7.4, same DB carried through)"
q wp db reset --yes >/dev/null
q wp core download --version=4.9.29 --force >/dev/null
q wp core install --url="$URL" --title="Stepped chain" --admin_user=admin \
     --admin_password=password --admin_email=a@example.com --skip-email >/dev/null

# seed content so we can prove data survives every hop
q wp post create --post_title="Canary post" --post_content="canary-body-marker" --post_status=publish >/dev/null
q wp user create canary canary@example.com --role=editor >/dev/null
SEED_POSTS=$(q wp post list --format=count)
echo "seeded: version=$(q wp core version) db=$(q wp option get db_version) posts=$SEED_POSTS"
echo

for V in $CHAIN; do
  OUT=$(q wp core update --version="$V" --force | tail -1)
  DB=$(q wp core update-db | tail -1)
  VER=$(q wp core version)
  DBV=$(q wp option get db_version)
  HTTP=$(curl -s -o /dev/null -w '%{http_code}' "$URL/")
  CANARY=$(curl -s "$URL/" | grep -c "Canary post")
  printf "hop -> %-8s version=%-10s db=%-6s http=%s canary_on_frontend=%s | %s\n" \
     "$V" "$VER" "$DBV" "$HTTP" "$CANARY" "$OUT"
  if [ "$VER" != "$V" ]; then echo "  !! VERSION MISMATCH: asked $V got $VER"; fi
done

echo
echo "--- final hop to 7.1-beta4"
q wp core update "$BETA4" --force | tail -1
q wp core update-db | tail -1
echo "final_version=$(q wp core version)"
echo "final_db=$(q wp option get db_version)"
echo "final_posts=$(q wp post list --format=count)  (seeded $SEED_POSTS)"
echo "canary_intact=$(q wp post list --post_status=publish --format=csv --fields=post_title | grep -c 'Canary post')"
echo "users=$(q wp user list --format=count)"
echo "frontend_http=$(curl -s -o /dev/null -w '%{http_code}' "$URL/")"
echo "login_http=$(curl -s -o /dev/null -w '%{http_code}' "$URL/wp-login.php")"
echo "frontend_fatal=$(curl -s "$URL/" | grep -ciE 'fatal error|parse error')"
echo "db_check=$(q wp db check | tail -1)"
echo "siteurl=$(q wp option get siteurl)"
