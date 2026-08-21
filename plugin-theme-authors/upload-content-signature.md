# The upload-content-signature bug class

*If your plugin passes an uploaded file into Imagick without checking its content signature
independently of WordPress, you may have inherited the 7.0.4 RCE.*

WordPress 7.0.4 fixed an author-level-or-higher RCE on sites using Imagick and Ghostscript
(core fix commit
[`7daaa50`](https://github.com/WordPress/wordpress-develop/commit/7daaa50) — *"Media: Prevent
loading images into Imagick which might be PostScript"*; affects 4.7 through 7.0; no CVE or
CVSS was published in the sources available, which is itself worth encoding — **a security
release does not always come with a CVE**). The root cause is a **three-way trust-boundary
mismatch**:

1. WordPress classifies uploads mainly by **file extension**.
2. ImageMagick identifies format from **magic bytes**.
3. Ghostscript then interprets **PostScript**.

A file that WordPress believes is a `.png` by extension, that ImageMagick reads as PostScript
by magic bytes, that Ghostscript then executes — three components, three different ideas of
what the file is, and code execution in the gap.

The usual guard is `wp_check_filetype_and_ext()`, which reconciles extension against content.
Patchstack's writeup ("When a PNG Isn't a PNG," Dave Jong, 2026-08-12) names **two core paths
that bypass it** — XML-RPC `wp.uploadFile` and **MP3 cover-art extraction** — because both go
through `wp_upload_bits()`, which does not perform the same content inspection.

## Why this is a plugin-author problem, not just a core one

Core patched its own paths. But **any third-party plugin that calls `wp_upload_bits()`
directly and passes the result into Imagick inherits the same bug** — the plugin, not core,
now owns the trust boundary, and `wp_upload_bits()` never checked the content signature for
it. This is a checkable grep across a plugin corpus:

```bash
# plugins that write uploads via wp_upload_bits and then reach for Imagick
grep -rl 'wp_upload_bits' --include='*.php' . \
  | xargs grep -l -E 'new Imagick|Imagick::|->readImage|WP_Image_Editor_Imagick' 2>/dev/null
```

A hit is not a finding — it's a file to read. The question for each: **between the
`wp_upload_bits()` write and the Imagick read, does the plugin independently validate the
file's content signature (magic bytes), or does it trust the extension it was handed?** If
the latter, and an author-or-higher user can reach the upload path, it has the 7.0.4 shape.

The threat model matters (per [CONTRIBUTING](../CONTRIBUTING.md)): the original needs
**Author or higher** — a real trust boundary, not anonymous, but far below administrator, and
exactly the population a single-admin test site is blind to. Test the upload path as an
Author, not as yourself.

## Mitigation, not fix: harden the ImageMagick policy

Defense in depth, at the system level, independent of any single plugin's diligence: an
ImageMagick `policy.xml` can refuse the PostScript-family coders and the Ghostscript
delegate outright, so even a file that reaches Imagick as PostScript is never handed to
Ghostscript.

```xml
<!-- /etc/ImageMagick-7/policy.xml (path varies by IM version and OS) -->
<policymap>
  <policy domain="coder" rights="none" pattern="PS" />
  <policy domain="coder" rights="none" pattern="PS2" />
  <policy domain="coder" rights="none" pattern="PS3" />
  <policy domain="coder" rights="none" pattern="EPS" />
  <policy domain="coder" rights="none" pattern="PDF" />
  <policy domain="coder" rights="none" pattern="XPS" />
  <policy domain="delegate" rights="none" pattern="gs" />
</policymap>
```

This is **mitigation, not a fix** — flag it as such to anyone you hand it to. It reduces the
blast radius of this bug class fleet-wide, but it doesn't repair a plugin that trusts an
extension it shouldn't, and a WordPress feature that legitimately needs PDF thumbnailing will
lose it. Decide per fleet whether that trade is worth it; on most sites that never render
PostScript or PDF through Imagick, it is.

## Related

[Security releases and backports](../data/security-releases.csv) ·
[`security_fix_presence.sh`](../scripts/security_fix_presence.sh) — checks whether a build
carries this fix ·
[Release-diff method](release-diff-method.md) ·
[Co-installed plugins](co-installed-plugins.md)
