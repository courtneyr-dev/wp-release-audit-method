#!/bin/bash
# Media suite: one file per display path, embedded every way content carries media.
#
#   bash scripts/media-suite.sh --env=cli ~/Studio/rel-72 http://localhost:8881
#   bash scripts/media-suite.sh --env=cli ~/Studio/rel-72-ms http://localhost:8883 --site=http://localhost:8883/n1/
#
# Options:
#   --site=<url>     run against a multisite subsite (passed to every wp call as --url)
#   --oembed=<url>   URL for the oEmbed cells (default: the first video on YouTube; set it
#                    empty to mark the cells BLOCKED instead of touching the network)
#   --out=<dir>      also write the cell table to <dir>/media-suite.tsv
#   --keep           leave the uploaded attachments and test posts in place
#
# WHAT "SUPPORTED" MEANS. 7.2 Beta 5 lets an administrator upload 94 MIME types in nine
# groups, and they display four different ways: images with sub-sizes (GD resizes JPEG,
# PNG, GIF, WebP, AVIF), images the editor can't resize (HEIC, BMP, TIFF, ICO on GD),
# audio and video with a player (wp_get_audio_extensions / wp_get_video_extensions), and
# everything else as a file link. A party samples one file per display path; the full
# 94-type sweep is media-type-sweep.sh, run in the follow-up.
#
# Each sample is embedded as content really carries it: 10 blocks, 5 shortcodes, oEmbed
# (block and bare URL), site logo, site icon, attachment page. Cells assert the rendered
# markup server-side AND fetch the page over HTTP, so a theme can't hide a failure.
#
# Verdicts: PASS, FAIL, BLOCKED(<capability>) when the environment can't run the cell,
# INFO when the result is recorded without an expectation (HEIC per image stack, the
# audio shortcode's ?_=N source suffix). Exit 1 when any cell FAILs.
#
# Samples this script needs from the host: ffmpeg (mp3, mp4, mov) and macOS sips (heic).
# Without them those cells read BLOCKED(no-host-sample); everything else still runs.

DRIVER="${WP_AUDIT_ENV:-}"
ARGS=()
SITE=""
OEMBED="https://www.youtube.com/watch?v=jNQXAC9IVRw"
OUT=""
KEEP=0
for a in "$@"; do
  case "$a" in
    --env=*)    DRIVER="${a#--env=}" ;;
    --site=*)   SITE="${a#--site=}" ;;
    --oembed=*) OEMBED="${a#--oembed=}" ;;
    --out=*)    OUT="${a#--out=}" ;;
    --keep)     KEEP=1 ;;
    *)          ARGS+=("$a") ;;
  esac
done
PROJ="${ARGS[0]:-.}"
URL="${ARGS[1]:-}"
DRIVER="${DRIVER:-wp-env}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=/dev/null
. "$HERE/lib-env.sh" || exit 1
env_init "$DRIVER" "$PROJ" || exit 1
[ -n "$URL" ] || URL="$(env_url)"

# Every wp call goes through W so a subsite run can never leak onto the main site.
W() { if [ -n "$SITE" ]; then env_wp "$@" --url="$SITE"; else env_wp "$@"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- host-built samples
host_samples=""
add_sample() {  # add_sample <ext> <file>
  [ -s "$2" ] || return 0
  host_samples="$host_samples'$1' => '$(base64 < "$2" | tr -d '\n')',"
}
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=440:duration=1" -b:a 32k "$TMP/s.mp3" && add_sample mp3 "$TMP/s.mp3"
  ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=160x120:rate=10" -t 1 -pix_fmt yuv420p "$TMP/s.mp4" && add_sample mp4 "$TMP/s.mp4"
  ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=160x120:rate=10" -t 1 -pix_fmt yuv420p "$TMP/s.mov" && add_sample mov "$TMP/s.mov"
  ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=1200x900" -frames:v 1 "$TMP/h.jpg"
fi
if command -v sips >/dev/null 2>&1 && [ -s "$TMP/h.jpg" ]; then
  sips -s format heic "$TMP/h.jpg" --out "$TMP/s.heic" >/dev/null 2>&1 && add_sample heic "$TMP/s.heic"
fi

TAG="media-suite-$(date -u +%Y%m%dT%H%M%S)"
PAYLOAD="\$MS_HOST_SAMPLES = array($host_samples); \$MS_OEMBED_URL = '$OEMBED'; \$MS_TAG = '$TAG';
$(sed '1s/^<?php//' "$HERE/media-suite.php")"

echo "======== media suite  driver=$WP_AUDIT_ENV_DRIVER url=$URL${SITE:+ site=$SITE}"
echo "version=$(W core version 2>/dev/null | tail -1)  tag=$TAG"

W eval "$PAYLOAD" > "$TMP/run.out" 2> "$TMP/run.err"
rc=$?
if [ $rc -ne 0 ] && ! grep -q '^CELL' "$TMP/run.out"; then
  echo "payload failed (rc=$rc):"; tail -20 "$TMP/run.err"; exit 2
fi

: > "$TMP/cells.tsv"
cell() { printf 'CELL\t%s\t%s\t%s\n' "$1" "$2" "$3" >> "$TMP/cells.tsv"; }
grep '^CELL' "$TMP/run.out" >> "$TMP/cells.tsv"

# ---------------------------------------------------------------- front end over HTTP
BASE="${SITE:-$URL}"
# A single-worker test server (PHP's built-in one, under `wp server`) answers WordPress's
# own cron loopback first: the payload's writes spawn wp-cron.php, and that can hold the
# only worker for many seconds. Wait for it rather than call the front end unreachable.
# Starting the server with PHP_CLI_SERVER_WORKERS=4 avoids the wait.
up=0
for _ in $(seq 1 12); do
  curl -sk -o /dev/null --max-time 5 "$BASE" && { up=1; break; }
  sleep 5
done
home_code="$( [ "$up" = 1 ] && curl -sk -o /dev/null --max-time 30 -w '%{http_code}' "$BASE" )"
if [ -z "$BASE" ] || [ "$up" = 0 ]; then
  cell http-frontend "BLOCKED(no-http)" "nothing answers at '${BASE:-<none>}'; front-end cells skipped"
elif [ "$home_code" != "200" ]; then
  # A server that answers but doesn't serve this site (wp server and a subdirectory subsite)
  # can't judge the front end. That is the harness, not the release.
  cell http-frontend "BLOCKED(site-not-served)" "GET $BASE returned $home_code; front-end cells skipped"
else
  while IFS=$'\t' read -r _ key page; do
    curl -skL --max-time 60 "$page" -o "$TMP/page-$key.html" -w '%{http_code}' > "$TMP/code-$key" 2>/dev/null
    code="$(cat "$TMP/code-$key")"
    [ "$code" = "200" ] || { cell "http-$key" FAIL "GET $page returned $code"; continue; }
    cell "http-$key" PASS "GET returned 200"
    exp="$(awk -F'\t' -v k="$key" '$1=="EXPECT" && $2==k {print $3}' "$TMP/run.out")"
    [ -n "$exp" ] || continue
    python3 - "$TMP/page-$key.html" "$key" "$exp" >> "$TMP/cells.tsv" <<'PY'
import json, re, sys
html = open(sys.argv[1], encoding="utf-8", errors="replace").read()
key, exp = sys.argv[2], json.loads(sys.argv[3])
slug = lambda s: re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
for marker, label in exp.items():
    print(f"CELL\tfrontend-{key}-{slug(label)}\t{'PASS' if marker in html else 'FAIL'}\t{label}")
if key == "blocks":
    # Loading optimization, as WordPress applies it to content images on a singular view.
    imgs = re.findall(r"<img\b[^>]*>", html)
    content = [i for i in imgs if re.search(r"wp-image-\d+", i)]
    # WordPress marks the FIRST large image on the page, which is the featured image when the
    # theme prints one above the content. Judge the first media image in page order.
    media = [i for i in imgs if re.search(r"wp-image-\d+|wp-post-image", i)]
    first = media[0] if media else ""
    which = "featured image" if "wp-post-image" in first else "first content image"
    print(f"CELL\tfrontend-fetchpriority-first\t{'PASS' if 'fetchpriority=\"high\"' in first else 'FAIL'}\t{which} has fetchpriority=high")
    lazy = [i for i in content[2:] if 'loading="lazy"' in i]
    print(f"CELL\tfrontend-lazy-below-fold\t{'PASS' if content[2:] and len(lazy) >= 1 else 'FAIL'}\t{len(lazy)} of {len(content[2:])} later content images lazy")
    srcset = [i for i in content if "srcset=" in i]
    print(f"CELL\tfrontend-srcset\t{'PASS' if srcset else 'FAIL'}\t{len(srcset)} of {len(content)} content images have srcset")
PY
  done < <(grep '^URL' "$TMP/run.out")

  # Attachment page: a redirect to the file when pages are disabled (the default since 6.4), 200 when enabled.
  att_url="$(awk -F'\t' '$1=="URL" && $2=="attachment" {print $3}' "$TMP/run.out")"
  att_line="$(grep '^ATTACHMENT' "$TMP/run.out")"
  if [ -n "$att_url" ]; then
    mode="$(echo "$att_line" | cut -f2)"; file="$(echo "$att_line" | cut -f3)"
    res="$(curl -sk -o /dev/null --max-time 20 -w '%{http_code} %{redirect_url}' "$att_url")"
    code="${res%% *}"; loc="${res#* }"
    if [ "$mode" = "disabled" ]; then
      [ "${code:0:1}" = "3" ] && [ "$loc" = "$file" ] && v=PASS || v=FAIL
    else
      [ "$code" = "200" ] && v=PASS || v=FAIL
    fi
    cell attachment-page "$v" "pages $mode; GET returned $code ${loc:+-> $loc}"
  fi
fi

# ---------------------------------------------------------------- restore and clean up
old_icon="$(awk -F'\t' '$1=="RESTORE" && $2=="site_icon" {print $3}' "$TMP/run.out")"
[ -n "$old_icon" ] && W option update site_icon "$old_icon" >/dev/null 2>&1
ids="$(awk -F'\t' '$1=="CLEANUP" {print $2}' "$TMP/run.out" | tr ',' ' ')"
if [ "$KEEP" = 0 ] && [ -n "$ids" ]; then
  # shellcheck disable=SC2086
  W post delete $ids --force >/dev/null 2>&1
  W user delete media-suite-author --yes ${SITE:+--network} >/dev/null 2>&1 || W user delete media-suite-author --yes --network >/dev/null 2>&1
  cell cleanup "$( [ -z "$(W post list --post_type=any,attachment --post_status=any --post__in="$(echo "$ids" | tr ' ' ',')" --format=ids 2>/dev/null | tail -1)" ] && echo PASS || echo FAIL )" "deleted $(echo "$ids" | wc -w | tr -d ' ') objects"
else
  cell cleanup INFO "kept: $ids"
fi

# ---------------------------------------------------------------- report
echo
awk -F'\t' '{printf "%-44s %-28s %s\n", $2, $3, $4}' "$TMP/cells.tsv"
echo
for v in PASS FAIL BLOCKED INFO; do
  printf '%s=%s ' "$v" "$(awk -F'\t' -v v="$v" 'index($3, v) == 1' "$TMP/cells.tsv" | wc -l | tr -d ' ')"
done
echo
if [ -n "$OUT" ]; then mkdir -p "$OUT" && cut -f2- "$TMP/cells.tsv" > "$OUT/media-suite.tsv"; fi
! grep -q $'\tFAIL\t' "$TMP/cells.tsv"
