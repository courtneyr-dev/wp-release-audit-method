#!/bin/bash
# Media type sweep: upload every type the site allows, record what WordPress does with each,
# and compare with a baseline run. The follow-up's job, not the party's (media-suite.sh is).
#
#   # baseline on the previous stable, then the build under test:
#   bash scripts/media-type-sweep.sh --env=cli ~/Studio/stable --out=evidence/sweep-7.1.4
#   bash scripts/media-type-sweep.sh --env=cli ~/Studio/rc1 --baseline=evidence/sweep-7.1.4/media-type-sweep.tsv
#
# Options:
#   --editor=gd|imagick   force the image editor; run once per stack, because the image stack
#                         decided 7.1's P0 media findings (Imagick without HEIC/AVIF delegates)
#   --baseline=<tsv>      compare: a type whose outcome, stored MIME or sub-size count differs
#                         from the baseline is FAIL, the same is PASS
#   --out=<dir>           write <dir>/media-type-sweep.tsv (use it as the next baseline)
#
# WHY A BASELINE INSTEAD OF EXPECTATIONS. WordPress checks a file's real contents against
# its extension, so a synthetic sample for an exotic type (a .key, a .rm) is rightly
# refused, and that refusal says as much about the sample as about WordPress. Judged alone,
# 94 types would bury the real signal in sample noise. Diffed against the previous stable
# with the same samples, every difference is a change in WordPress.
#
# Samples: images and audio/video from ffmpeg, HEIC from macOS sips, PDF and Office/ODF
# documents built here, text and archives with python's stdlib. Types no available tool can
# encode get a few bytes of filler and are marked synthetic in the output.
#
# Needs hostfs: the samples are written into the site's uploads directory for the payload.

DRIVER="${WP_AUDIT_ENV:-}"
ARGS=()
EDITOR=""
BASELINE=""
OUT=""
for a in "$@"; do
  case "$a" in
    --env=*)      DRIVER="${a#--env=}" ;;
    --editor=*)   EDITOR="${a#--editor=}" ;;
    --baseline=*) BASELINE="${a#--baseline=}" ;;
    --out=*)      OUT="${a#--out=}" ;;
    *)            ARGS+=("$a") ;;
  esac
done
PROJ="${ARGS[0]:-.}"
DRIVER="${DRIVER:-wp-env}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=/dev/null
. "$HERE/lib-env.sh" || exit 1
env_init "$DRIVER" "$PROJ" || exit 1
env_require hostfs || { echo "media-type-sweep: BLOCKED(hostfs) — samples must be readable by the site"; exit 3; }
W() { env_wp "$@"; }

DOCROOT="$(env_docroot)"
SAMPLES="$DOCROOT/wp-content/uploads/media-type-sweep-samples-$$"
mkdir -p "$SAMPLES"
TMP="$(mktemp -d)"
trap 'rm -rf "$SAMPLES" "$TMP"' EXIT

# Every allowed extension, from the site itself, as the administrator the payload uploads as
# (with no user, the types that need unfiltered_html drop out of the list).
W eval '$a = is_multisite() ? get_user_by( "login", current( get_super_admins() ) ) : current( get_users( array( "role" => "administrator", "number" => 1 ) ) ); wp_set_current_user( $a ? $a->ID : 0 ); foreach ( get_allowed_mime_types() as $e => $m ) foreach ( explode( "|", $e ) as $x ) echo "$x\n";' 2>/dev/null \
  | grep -E '^[a-z0-9-]+$' > "$TMP/exts"

python3 - "$SAMPLES" "$TMP/exts" <<'PY'
import os, shutil, subprocess, sys, tarfile, gzip, bz2, zipfile, io
out, exts = sys.argv[1], [l.strip() for l in open(sys.argv[2]) if l.strip()]
ff = shutil.which("ffmpeg")
def run(*a):
    return subprocess.run(a, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
IMG = {"jpg": "mjpeg", "jpeg": "mjpeg", "jpe": "mjpeg", "png": "png", "gif": "gif", "bmp": "bmp", "tif": "tiff", "tiff": "tiff"}
GD = {"webp": "imagewebp", "avif": "imageavif"}  # through the host's PHP: ffmpeg builds often lack these encoders
# Container -> encoder arguments an ffmpeg build without the optional libraries still has.
VARGS = {"3gp": ["-c:v", "mpeg4", "-s", "176x144", "-f", "3gp"], "3gpp": ["-c:v", "mpeg4", "-s", "176x144", "-f", "3gp"],
         "3g2": ["-c:v", "mpeg4", "-s", "176x144", "-f", "3g2"], "3gp2": ["-c:v", "mpeg4", "-s", "176x144", "-f", "3g2"],
         "mpeg": ["-c:v", "mpeg2video", "-f", "mpeg"], "mpg": ["-c:v", "mpeg2video", "-f", "mpeg"], "mpe": ["-c:v", "mpeg2video", "-f", "mpeg"],
         "vob": ["-c:v", "mpeg2video", "-f", "vob"], "divx": ["-c:v", "mpeg4", "-f", "avi"], "avi": ["-c:v", "mpeg4", "-f", "avi"],
         "flv": ["-c:v", "flv", "-f", "flv"], "wmv": ["-c:v", "wmv2", "-f", "asf"], "asf": ["-c:v", "wmv2", "-f", "asf"], "wm": ["-c:v", "wmv2", "-f", "asf"],
         "dv": ["-c:v", "dvvideo", "-s", "720x480", "-r", "30000/1001", "-pix_fmt", "yuv411p", "-f", "dv"], "webm": ["-c:v", "libvpx", "-f", "webm"]}
TEXT = {"srt": "1\n00:00:00,000 --> 00:00:01,000\nx\n", "dfxp": '<?xml version="1.0"?><tt xmlns="http://www.w3.org/ns/ttml"><body/></tt>',
        "c": "int main(void){return 0;}\n", "cc": "int main(){return 0;}\n", "h": "#define X 1\n", "ram": "http://example.test/a.ra\n",
        "asx": '<asx version="3.0"><entry><ref href="a.wmv"/></entry></asx>', "wax": '<asx version="3.0"/>', "wmx": '<asx version="3.0"/>'}
AUD = {"mp3", "m4a", "m4b", "ogg", "oga", "wav", "flac", "aac", "aif", "aiff", "ac3", "mka", "mp2", "wma"}
VID = {"mp4", "m4v", "mov", "qt", "webm", "ogv", "avi", "mkv", "3gp", "3g2", "3gpp", "mpeg", "mpg", "flv", "wmv", "asf", "dv", "vob", "ogm"}
FMT = {"m4a": "ipod", "m4b": "ipod", "oga": "ogg", "aif": "aiff", "mka": "matroska", "mp2": "mp2", "wma": "asf", "qt": "mov", "3gpp": "3gp", "mpg": "mpeg", "wmv": "asf", "ogm": "ogg", "mkv": "matroska", "vob": "vob", "dv": "dv"}
def ooxml(path, main, ctype):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("[Content_Types].xml", f'<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/{main}" ContentType="{ctype}"/></Types>')
        z.writestr("_rels/.rels", f'<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="{main}"/></Relationships>')
        z.writestr(main, '<?xml version="1.0"?><x/>')
def odf(path, mime):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), mime)
        z.writestr("content.xml", '<?xml version="1.0"?><office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"/>')
        z.writestr("META-INF/manifest.xml", '<?xml version="1.0"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"/>')
synthetic = []
for e in exts:
    p = f"{out}/sample.{e}"
    ok = False
    if e in IMG and ff:
        ok = run(ff, "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=1600x1200", "-frames:v", "1", "-c:v", IMG[e], "-f", "image2", p)
    elif e in GD and shutil.which("php"):
        ok = run("php", "-r", f'$i=imagecreatetruecolor(1600,1200);imagefill($i,0,0,imagecolorallocate($i,30,90,160));exit(function_exists("{GD[e]}")&&{GD[e]}($i,"{p}")?0:1);')
    elif e == "ico" and ff and run(ff, "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=64x64", "-frames:v", "1", f"{out}/ico.png"):
        png = open(f"{out}/ico.png", "rb").read(); os.remove(f"{out}/ico.png")
        import struct
        open(p, "wb").write(struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", 64, 64, 0, 0, 1, 32, len(png), 22) + png); ok = True
    elif e in ("mid", "midi"):
        open(p, "wb").write(b"MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60MTrk\x00\x00\x00\x04\x00\xff\x2f\x00"); ok = True
    elif e in TEXT:
        open(p, "w").write(TEXT[e]); ok = True
    elif e in VARGS and ff:
        ok = run(ff, "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=160x120:rate=10", "-t", "1", "-pix_fmt", "yuv420p", *VARGS[e], p)
    elif e in ("heic", "heif") and shutil.which("sips") and os.path.exists(f"{out}/sample.jpg"):
        ok = run("sips", "-s", "format", "heic", f"{out}/sample.jpg", "--out", p)
    elif e in AUD and ff:
        ok = run(ff, "-loglevel", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", *(["-f", FMT[e]] if e in FMT else []), p)
    elif e in VID and ff:
        ok = run(ff, "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=160x120:rate=10", "-t", "1", "-pix_fmt", "yuv420p", *(["-f", FMT[e]] if e in FMT else []), p)
    elif e == "pdf":
        open(p, "wb").write(b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"); ok = True
    elif e in ("docx", "docm", "dotm"):
        ooxml(p, "word/document.xml", "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"); ok = True
    elif e in ("xlsx", "xlsm", "xlsb"):
        ooxml(p, "xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"); ok = True
    elif e in ("pptx", "pptm", "ppsx", "ppsm", "sldx", "sldm"):
        ooxml(p, "ppt/presentation.xml", "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"); ok = True
    elif e in ("odt", "ods", "odp", "odg", "odc", "odb", "odf"):
        odf(p, {"odt": "application/vnd.oasis.opendocument.text", "ods": "application/vnd.oasis.opendocument.spreadsheet", "odp": "application/vnd.oasis.opendocument.presentation"}.get(e, "application/vnd.oasis.opendocument.graphics")); ok = True
    elif e in ("txt", "asc", "csv", "tsv", "rtx", "vtt", "ics", "css", "htm", "html", "js", "rtf"):
        body = {"csv": "a,b\n1,2\n", "tsv": "a\tb\n1\t2\n", "vtt": "WEBVTT\n\n00:00.000 --> 00:01.000\nx\n", "ics": "BEGIN:VCALENDAR\nEND:VCALENDAR\n", "rtf": "{\\rtf1 x}", "htm": "<p>x</p>", "html": "<p>x</p>", "css": "p{}", "js": "var x=1;"}.get(e, "media type sweep\n")
        open(p, "w").write(body); ok = True
    elif e == "zip":
        with zipfile.ZipFile(p, "w") as z: z.writestr("a.txt", "x"); ok = True
    elif e in ("gz", "tgz"):
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w") as t:
            ti = tarfile.TarInfo("a.txt"); ti.size = 1; t.addfile(ti, io.BytesIO(b"x"))
        open(p, "wb").write(gzip.compress(buf.getvalue())); ok = True
    elif e == "tar":
        with tarfile.open(p, "w") as t:
            ti = tarfile.TarInfo("a.txt"); ti.size = 1; t.addfile(ti, io.BytesIO(b"x")); ok = True
    elif e == "bz2":
        open(p, "wb").write(bz2.compress(b"x")); ok = True
    if not ok or not os.path.exists(p) or os.path.getsize(p) == 0:
        open(p, "wb").write(b"media type sweep synthetic sample\n")
        synthetic.append(e)
open(f"{out}/SYNTHETIC", "w").write(" ".join(synthetic))
PY

echo "======== media type sweep  driver=$WP_AUDIT_ENV_DRIVER editor=${EDITOR:-default}"
echo "version=$(W core version 2>/dev/null | tail -1)  extensions=$(wc -l < "$TMP/exts" | tr -d ' ')  synthetic=$(wc -w < "$SAMPLES/SYNTHETIC" | tr -d ' ')"
PAYLOAD="\$MTS_DIR = '$SAMPLES'; \$MTS_EDITOR = '$EDITOR';
$(sed '1s/^<?php//' "$HERE/media-type-sweep.php")"
W eval "$PAYLOAD" > "$TMP/run.out" 2> "$TMP/run.err"
grep -q '^BLOCKED' "$TMP/run.out" && { echo "BLOCKED($(cut -f2 "$TMP/run.out"))"; exit 3; }
grep -q '^TYPE' "$TMP/run.out" || { echo "payload failed:"; tail -20 "$TMP/run.err"; exit 2; }
grep '^ENV' "$TMP/run.out" | cut -f2-

# ext, outcome, stored mime or error, sub-sizes, synthetic flag, detail
syn=" $(cat "$SAMPLES/SYNTHETIC") "
awk -F'\t' -v syn="$syn" '$1=="TYPE" { s = index(syn, " " $2 " ") ? "synthetic" : "real"; print $2 "\t" $3 "\t" $4 "\t" $5 "\t" s "\t" $6 }' "$TMP/run.out" | sort > "$TMP/sweep.tsv"

if [ -n "$BASELINE" ]; then
  python3 - "$BASELINE" "$TMP/sweep.tsv" <<'PY'
import sys
row = lambda l: l.rstrip("\n").split("\t")
base = {r[0]: r for r in map(row, open(sys.argv[1])) if r[0]}
cur = {r[0]: r for r in map(row, open(sys.argv[2])) if r[0]}
fails = 0
for ext in sorted(set(base) | set(cur)):
    b, c = base.get(ext), cur.get(ext)
    if not b or not c:
        print(f"{'FAIL':8} {ext:6} {'only in baseline' if b else 'new type, not in baseline'}"); fails += 1; continue
    if b[1:4] != c[1:4]:
        print(f"{'FAIL':8} {ext:6} was {b[1]} {b[2]} sizes={b[3]}, now {c[1]} {c[2]} sizes={c[3]} ({c[4]} sample)"); fails += 1
    else:
        print(f"{'PASS':8} {ext:6} {c[1]} {c[2]} sizes={c[3]} ({c[4]} sample)")
print(f"\n{len(cur)} types, {fails} differ from the baseline")
sys.exit(1 if fails else 0)
PY
  rc=$?
else
  awk -F'\t' '{printf "%-8s %-6s %-9s %-46s sizes=%-3s %s\n", "INFO", $1, $2, $3, $4, $5}' "$TMP/sweep.tsv"
  echo; echo "$(wc -l < "$TMP/sweep.tsv" | tr -d ' ') types: $(grep -c $'\taccepted\t' "$TMP/sweep.tsv") accepted, $(grep -c $'\trejected\t' "$TMP/sweep.tsv") rejected (no baseline given, nothing judged)"
  rc=0
fi
if [ -n "$OUT" ]; then mkdir -p "$OUT" && cp "$TMP/sweep.tsv" "$OUT/media-type-sweep.tsv"; fi
exit $rc
