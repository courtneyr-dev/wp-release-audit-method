<?php
/**
 * Media suite payload — runs INSIDE WordPress via `wp eval`, driven by media-suite.sh.
 *
 * Why one in-site payload instead of many `wp` calls: each WP-CLI call boots WordPress
 * (about 0.5 s on a SQLite fixture), and a party budget is minutes. One boot runs every
 * library, REST, editing and embedding cell; the shell side does only what has to happen
 * outside: generating audio/video/HEIC samples and fetching the front end over HTTP.
 *
 * Inputs (prepended by the shell as PHP variables before this file's body):
 *   $MS_HOST_SAMPLES  array ext => base64 bytes, for samples PHP can't make (heic, mp3, mp4, mov)
 *   $MS_OEMBED_URL    URL to embed; empty skips the oEmbed cells
 *   $MS_TAG           run tag, used in titles so a rerun's objects are findable
 *
 * Output: one line per cell, tab-separated:  CELL <id> <VERDICT> <detail>
 * plus  URL <key> <url>  lines the shell fetches. VERDICT is PASS, FAIL, BLOCKED(<why>)
 * or INFO (observed and recorded, no expectation to judge it against).
 */

$MS_HOST_SAMPLES = isset( $MS_HOST_SAMPLES ) ? $MS_HOST_SAMPLES : array();
$MS_OEMBED_URL   = isset( $MS_OEMBED_URL ) ? $MS_OEMBED_URL : '';
$MS_TAG          = isset( $MS_TAG ) ? $MS_TAG : 'media-suite';

require_once ABSPATH . 'wp-admin/includes/file.php';
require_once ABSPATH . 'wp-admin/includes/media.php';
require_once ABSPATH . 'wp-admin/includes/image.php';
require_once ABSPATH . 'wp-admin/includes/image-edit.php';
require_once ABSPATH . 'wp-admin/includes/post.php';

function ms_cell( $id, $verdict, $detail = '' ) {
	echo "CELL\t$id\t$verdict\t" . str_replace( array( "\t", "\n" ), ' ', (string) $detail ) . "\n";
}
function ms_url( $key, $url ) {
	echo "URL\t$key\t$url\n";
}

$admins = get_users( array( 'role' => 'administrator', 'number' => 1, 'fields' => 'ID' ) );
if ( is_multisite() && ! $admins ) {
	$supers = get_super_admins();
	$u      = $supers ? get_user_by( 'login', $supers[0] ) : null;
	$admins = $u ? array( $u->ID ) : array();
}
if ( ! $admins ) {
	ms_cell( 'setup-admin', 'BLOCKED(no-admin)', 'no administrator on this site' );
	return;
}
$admin_id = (int) $admins[0];
wp_set_current_user( $admin_id );

$editor_class = _wp_image_editor_choose();
$has_imagick  = extension_loaded( 'imagick' );
ms_cell( 'env-image-stack', 'INFO', 'editor=' . ( $editor_class ? $editor_class : 'none' ) . ' imagick=' . ( $has_imagick ? 'yes' : 'no' ) . ' multisite=' . ( is_multisite() ? 'yes' : 'no' ) . ' blog=' . get_current_blog_id() );

/* ---------------------------------------------------------------- samples */
$dir = trailingslashit( get_temp_dir() ) . 'media-suite-' . getmypid();
wp_mkdir_p( $dir );

function ms_gd_image( $path, $ext ) {
	$im = imagecreatetruecolor( 2000, 1500 );
	imagefill( $im, 0, 0, imagecolorallocate( $im, 30, 90, 160 ) );
	imagefilledrectangle( $im, 200, 200, 900, 700, imagecolorallocate( $im, 240, 200, 40 ) );
	switch ( $ext ) {
		case 'jpg':  return imagejpeg( $im, $path, 85 );
		case 'png':  return imagepng( $im, $path );
		case 'gif':  return imagegif( $im, $path );
		case 'webp': return function_exists( 'imagewebp' ) && imagewebp( $im, $path, 80 );
		case 'avif': return function_exists( 'imageavif' ) && imageavif( $im, $path, 60 );
	}
	return false;
}

function ms_minimal_pdf() {
	$objs   = array(
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
		null,
		"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
	);
	$stream  = "BT /F1 24 Tf 72 700 Td (Media suite PDF) Tj ET";
	$objs[3] = "<< /Length " . strlen( $stream ) . " >>\nstream\n$stream\nendstream";
	$out     = "%PDF-1.4\n";
	$offs    = array();
	foreach ( $objs as $i => $o ) {
		$offs[] = strlen( $out );
		$out   .= ( $i + 1 ) . " 0 obj\n$o\nendobj\n";
	}
	$xref = strlen( $out );
	$out .= "xref\n0 " . ( count( $objs ) + 1 ) . "\n0000000000 65535 f \n";
	foreach ( $offs as $o ) {
		$out .= sprintf( "%010d 00000 n \n", $o );
	}
	return $out . "trailer\n<< /Size " . ( count( $objs ) + 1 ) . " /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n";
}

function ms_minimal_docx( $path ) {
	if ( ! class_exists( 'ZipArchive' ) ) {
		return false;
	}
	$z = new ZipArchive();
	if ( true !== $z->open( $path, ZipArchive::CREATE | ZipArchive::OVERWRITE ) ) {
		return false;
	}
	$z->addFromString( '[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>' );
	$z->addFromString( '_rels/.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>' );
	$z->addFromString( 'word/document.xml', '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Media suite</w:t></w:r></w:p></w:body></w:document>' );
	return $z->close();
}

$samples = array(); // ext => path
foreach ( array( 'jpg', 'png', 'gif', 'webp', 'avif' ) as $ext ) {
	$p = "$dir/ms-$ext.$ext";
	if ( ms_gd_image( $p, $ext ) && filesize( $p ) ) {
		$samples[ $ext ] = $p;
	} else {
		ms_cell( "sample-$ext", 'BLOCKED(no-encoder)', "this PHP can't write $ext" );
	}
}
file_put_contents( "$dir/ms-pdf.pdf", ms_minimal_pdf() );
$samples['pdf'] = "$dir/ms-pdf.pdf";
if ( ms_minimal_docx( "$dir/ms-docx.docx" ) ) {
	$samples['docx'] = "$dir/ms-docx.docx";
} else {
	ms_cell( 'sample-docx', 'BLOCKED(no-ziparchive)', 'ZipArchive missing; docx sample not built' );
}
file_put_contents( "$dir/ms-html.html", "<!doctype html><title>x</title><p>code-type refusal probe</p>\n" );
foreach ( $MS_HOST_SAMPLES as $ext => $b64 ) {
	$p = "$dir/ms-$ext.$ext";
	file_put_contents( $p, base64_decode( $b64 ) );
	$samples[ $ext ] = $p;
}
foreach ( array( 'heic', 'mp3', 'mp4', 'mov' ) as $ext ) {
	if ( empty( $samples[ $ext ] ) ) {
		ms_cell( "sample-$ext", 'BLOCKED(no-host-sample)', 'the shell side could not build it (ffmpeg or sips missing)' );
	}
}

/* ---------------------------------------------------------------- upload, one per display path */
function ms_sideload( $path, $title, $post_parent = 0 ) {
	$tmp = wp_tempnam( basename( $path ) );
	copy( $path, $tmp );
	$file = array( 'name' => basename( $path ), 'tmp_name' => $tmp );
	$id   = media_handle_sideload( $file, $post_parent, $title );
	if ( is_wp_error( $id ) && file_exists( $tmp ) ) {
		@unlink( $tmp );
	}
	return $id;
}

$expect_mime = array(
	'jpg' => 'image/jpeg', 'png' => 'image/png', 'gif' => 'image/gif', 'webp' => 'image/webp', 'avif' => 'image/avif',
	'heic' => 'image/heic', 'mp3' => 'audio/mpeg', 'mp4' => 'video/mp4', 'mov' => 'video/quicktime',
	'pdf' => 'application/pdf', 'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
);
$expected_sizes = array( 'thumbnail', 'medium', 'medium_large', 'large', '1536x1536' );
$att            = array(); // ext => attachment ID
$created_posts  = array();

foreach ( $expect_mime as $ext => $mime ) {
	if ( empty( $samples[ $ext ] ) ) {
		continue;
	}
	$id = ms_sideload( $samples[ $ext ], "$MS_TAG $ext" );
	if ( is_wp_error( $id ) ) {
		ms_cell( "upload-$ext", 'FAIL', $id->get_error_code() . ': ' . $id->get_error_message() );
		continue;
	}
	$att[ $ext ] = $id;
	$got_mime    = get_post_mime_type( $id );
	$meta        = wp_get_attachment_metadata( $id );
	$sizes       = isset( $meta['sizes'] ) ? array_keys( $meta['sizes'] ) : array();
	if ( 'heic' === $ext ) {
		// The display path that depends on the stack: converted, kept without sizes, or rejected.
		$conv = isset( $meta['original_image'] ) || 'image/jpeg' === $got_mime ? 'converted' : 'kept-as-uploaded';
		ms_cell( 'upload-heic', 'INFO', "stored mime=$got_mime $conv sizes=" . count( $sizes ) . " editor=$editor_class" );
		continue;
	}
	if ( $got_mime !== $mime ) {
		ms_cell( "upload-$ext", 'FAIL', "stored mime=$got_mime want $mime" );
		continue;
	}
	ms_cell( "upload-$ext", 'PASS', "id=$id mime=$got_mime" );
	if ( isset( array( 'jpg' => 1, 'png' => 1, 'gif' => 1, 'webp' => 1, 'avif' => 1 )[ $ext ] ) ) {
		if ( ! wp_image_editor_supports( array( 'mime_type' => $mime ) ) ) {
			ms_cell( "subsizes-$ext", 'BLOCKED(editor-unsupported)', "$editor_class can't resize $mime" );
			continue;
		}
		$missing = array_diff( $expected_sizes, $sizes );
		$on_disk = 0;
		$base    = trailingslashit( dirname( get_attached_file( $id ) ) );
		foreach ( $sizes as $s ) {
			$on_disk += file_exists( $base . $meta['sizes'][ $s ]['file'] ) ? 1 : 0;
		}
		ms_cell( "subsizes-$ext", ( $missing || $on_disk !== count( $sizes ) ) ? 'FAIL' : 'PASS', 'sizes=' . implode( ',', $sizes ) . " on_disk=$on_disk" . ( $missing ? ' missing=' . implode( ',', $missing ) : '' ) );
	}
}

/* ---------------------------------------------------------------- code-type refusal, with a control */
$author = get_user_by( 'login', 'media-suite-author' );
$author_id = $author ? $author->ID : wp_insert_user( array( 'user_login' => 'media-suite-author', 'user_pass' => wp_generate_password( 32 ), 'user_email' => 'media-suite-author@example.test', 'role' => 'author' ) );
if ( is_multisite() && ! is_wp_error( $author_id ) ) {
	add_user_to_blog( get_current_blog_id(), $author_id, 'author' );
}
wp_set_current_user( $author_id );
$r = ms_sideload( "$dir/ms-html.html", "$MS_TAG html as author" );
ms_cell( 'code-type-refused-author', is_wp_error( $r ) ? 'PASS' : 'FAIL', is_wp_error( $r ) ? $r->get_error_code() : "accepted as id=$r" );
if ( ! is_wp_error( $r ) ) {
	wp_delete_attachment( $r, true );
}
wp_set_current_user( $admin_id );
$admin_unfiltered = current_user_can( 'unfiltered_html' );
$r = ms_sideload( "$dir/ms-html.html", "$MS_TAG html as admin" );
// Control: an admin with unfiltered_html may upload it, one without may not. Either way the rule must hold.
$ok = $admin_unfiltered ? ! is_wp_error( $r ) : is_wp_error( $r );
ms_cell( 'code-type-control-admin', $ok ? 'PASS' : 'FAIL', 'unfiltered_html=' . ( $admin_unfiltered ? 'yes' : 'no' ) . ' result=' . ( is_wp_error( $r ) ? $r->get_error_code() : "id=$r" ) );
if ( ! is_wp_error( $r ) ) {
	wp_delete_attachment( $r, true );
}

/* ---------------------------------------------------------------- library operations */
if ( ! empty( $att['jpg'] ) ) {
	$id = $att['jpg'];
	update_post_meta( $id, '_wp_attachment_image_alt', "$MS_TAG alt" );
	wp_update_post( array( 'ID' => $id, 'post_excerpt' => "$MS_TAG caption", 'post_title' => "$MS_TAG jpg edited" ) );
	clean_post_cache( $id );
	$ok = get_post_meta( $id, '_wp_attachment_image_alt', true ) === "$MS_TAG alt" && get_post_field( 'post_excerpt', $id ) === "$MS_TAG caption";
	ms_cell( 'library-edit-details', $ok ? 'PASS' : 'FAIL', 'alt, caption and title round-trip' );
	$q = new WP_Query( array( 'post_type' => 'attachment', 'post_status' => 'inherit', 's' => "$MS_TAG jpg edited", 'fields' => 'ids' ) );
	ms_cell( 'library-search', in_array( $id, $q->posts, true ) ? 'PASS' : 'FAIL', 'found ' . count( $q->posts ) );
	$q = new WP_Query( array( 'post_type' => 'attachment', 'post_status' => 'inherit', 'post_mime_type' => 'image', 'posts_per_page' => 40, 'fields' => 'ids' ) );
	ms_cell( 'library-filter-images', in_array( $id, $q->posts, true ) ? 'PASS' : 'FAIL', 'image filter returned ' . $q->found_posts );
}

/* ---------------------------------------------------------------- REST /wp/v2/media */
if ( ! empty( $samples['png'] ) ) {
	$req = new WP_REST_Request( 'POST', '/wp/v2/media' );
	$req->set_header( 'Content-Type', 'image/png' );
	$req->set_header( 'Content-Disposition', 'attachment; filename="ms-rest.png"' );
	$req->set_body( file_get_contents( $samples['png'] ) );
	$res  = rest_do_request( $req );
	$data = $res->get_data();
	$rid  = isset( $data['id'] ) ? $data['id'] : 0;
	ms_cell( 'rest-media-create', 201 === $res->get_status() && $rid ? 'PASS' : 'FAIL', 'status=' . $res->get_status() . " id=$rid" );
	if ( $rid ) {
		$req = new WP_REST_Request( 'POST', "/wp/v2/media/$rid" );
		$req->set_param( 'alt_text', "$MS_TAG rest alt" );
		$res = rest_do_request( $req );
		ms_cell( 'rest-media-update', 200 === $res->get_status() && get_post_meta( $rid, '_wp_attachment_image_alt', true ) === "$MS_TAG rest alt" ? 'PASS' : 'FAIL', 'status=' . $res->get_status() );
		$file = get_attached_file( $rid );
		$req  = new WP_REST_Request( 'DELETE', "/wp/v2/media/$rid" );
		$req->set_param( 'force', true );
		$res = rest_do_request( $req );
		ms_cell( 'rest-media-delete', 200 === $res->get_status() && ! get_post( $rid ) && ! file_exists( $file ) ? 'PASS' : 'FAIL', 'status=' . $res->get_status() . ' file_left=' . ( file_exists( $file ) ? 'yes' : 'no' ) );
	}
}

/* ---------------------------------------------------------------- image editing, through the admin save path */
if ( ! empty( $samples['jpg'] ) ) {
	$eid = ms_sideload( $samples['jpg'], "$MS_TAG edit target" );
	if ( is_wp_error( $eid ) ) {
		ms_cell( 'edit-setup', 'FAIL', $eid->get_error_code() );
	} else {
		// The crop selection is in PREVIEW pixels: the editor scales it by 1 / _image_get_preview_ratio(),
		// as the Edit Image screen does. A selection in full-size pixels runs off the image and the
		// "failure" is the test's, not the editor's.
		$sel  = array( 'x' => 20, 'y' => 20, 'w' => 200, 'h' => 150 );
		$ops  = array(
			'rotate' => array( array( 'r' => 90 ) ),
			'flip'   => array( array( 'f' => 1 ) ),
			'crop'   => array( array( 'c' => $sel ) ),
		);
		foreach ( $ops as $name => $history ) {
			$before   = wp_get_attachment_metadata( $eid );
			$_REQUEST = array( 'history' => wp_json_encode( $history ), 'do' => 'save', 'target' => 'all', 'context' => '', 'postid' => $eid );
			$_POST    = $_REQUEST;
			$ret      = wp_save_image( $eid );
			$after    = wp_get_attachment_metadata( $eid );
			$changed  = $after['width'] . 'x' . $after['height'];
			$scale    = 1 / _image_get_preview_ratio( $before['width'], $before['height'] );
			$want     = array( 'rotate' => $before['height'] . 'x' . $before['width'], 'flip' => $before['width'] . 'x' . $before['height'], 'crop' => (int) ( $sel['w'] * $scale ) . 'x' . (int) ( $sel['h'] * $scale ) )[ $name ]; // the editor truncates, as GD's crop does
			$err               = isset( $ret->error ) ? $ret->error : '';
			ms_cell( "edit-$name", ( ! $err && $changed === $want && get_attached_file( $eid ) ) ? 'PASS' : 'FAIL', "now=$changed want=$want" . ( $err ? " error=$err" : '' ) );
		}
		$ret = wp_restore_image( $eid );
		$m   = wp_get_attachment_metadata( $eid );
		ms_cell( 'edit-restore-original', ( empty( $ret->error ) && 2000 === (int) $m['width'] ) ? 'PASS' : 'FAIL', 'width=' . $m['width'] . ( empty( $ret->error ) ? '' : ' error=' . $ret->error ) );
		$_REQUEST = $_POST = array();
		wp_delete_attachment( $eid, true );
	}
}

/* ---------------------------------------------------------------- embedding */
function ms_img_block( $id, $size = 'large' ) {
	$src = wp_get_attachment_image_url( $id, $size );
	return "<!-- wp:image {\"id\":$id,\"sizeSlug\":\"$size\",\"linkDestination\":\"none\"} -->\n<figure class=\"wp-block-image size-$size\"><img src=\"$src\" alt=\"\" class=\"wp-image-$id\"/></figure>\n<!-- /wp:image -->";
}
$blocks = array();
$exp    = array(); // marker => human label, asserted in rendered content and on the front end
if ( ! empty( $att['jpg'] ) && ! empty( $att['png'] ) ) {
	$j = $att['jpg'];
	$p = $att['png'];
	$blocks[] = ms_img_block( $j );
	$exp['wp-image-' . $j] = 'image block';
	$blocks[] = "<!-- wp:gallery {\"linkTo\":\"none\"} -->\n<figure class=\"wp-block-gallery has-nested-images columns-default is-cropped\">" . ms_img_block( $j ) . ms_img_block( $p ) . "</figure>\n<!-- /wp:gallery -->";
	$exp['wp-block-gallery'] = 'gallery block';
	$jurl = wp_get_attachment_url( $j );
	$blocks[] = "<!-- wp:cover {\"url\":\"$jurl\",\"id\":$j,\"dimRatio\":50} -->\n<div class=\"wp-block-cover\"><span aria-hidden=\"true\" class=\"wp-block-cover__background has-background-dim\"></span><img class=\"wp-block-cover__image-background wp-image-$j\" alt=\"\" src=\"$jurl\" data-object-fit=\"cover\"/><div class=\"wp-block-cover__inner-container\"><!-- wp:paragraph -->\n<p>Cover text</p>\n<!-- /wp:paragraph --></div></div>\n<!-- /wp:cover -->";
	$exp['wp-block-cover'] = 'cover block';
	$purl = wp_get_attachment_url( $p );
	$blocks[] = "<!-- wp:media-text {\"mediaId\":$p,\"mediaLink\":\"$purl\",\"mediaType\":\"image\"} -->\n<div class=\"wp-block-media-text is-stacked-on-mobile\"><figure class=\"wp-block-media-text__media\"><img src=\"$purl\" alt=\"\" class=\"wp-image-$p size-full\"/></figure><div class=\"wp-block-media-text__content\"><!-- wp:paragraph -->\n<p>Media and text</p>\n<!-- /wp:paragraph --></div></div>\n<!-- /wp:media-text -->";
	$exp['wp-block-media-text'] = 'media and text block';
	$small = wp_get_attachment_image_url( $p, 'thumbnail' );
	$blocks[] = "<!-- wp:paragraph -->\n<p>Inline <img class=\"wp-image-$p\" style=\"width: 40px;\" src=\"$small\" alt=\"\"> image in text.</p>\n<!-- /wp:paragraph -->";
	$exp['style="width: 40px;"'] = 'inline image';
}
if ( ! empty( $att['mp3'] ) ) {
	$u = wp_get_attachment_url( $att['mp3'] );
	$blocks[] = "<!-- wp:audio {\"id\":{$att['mp3']}} -->\n<figure class=\"wp-block-audio\"><audio controls src=\"$u\"></audio></figure>\n<!-- /wp:audio -->";
	$exp['wp-block-audio'] = 'audio block';
}
if ( ! empty( $att['mp4'] ) ) {
	$u = wp_get_attachment_url( $att['mp4'] );
	$blocks[] = "<!-- wp:video {\"id\":{$att['mp4']}} -->\n<figure class=\"wp-block-video\"><video controls src=\"$u\"></video></figure>\n<!-- /wp:video -->";
	$exp['wp-block-video'] = 'video block';
}
if ( ! empty( $att['pdf'] ) ) {
	$u = wp_get_attachment_url( $att['pdf'] );
	$blocks[] = "<!-- wp:file {\"id\":{$att['pdf']},\"href\":\"$u\",\"displayPreview\":true} -->\n<div class=\"wp-block-file\"><object class=\"wp-block-file__embed\" data=\"$u\" type=\"application/pdf\" style=\"width:100%;height:600px\" aria-label=\"Embed of PDF.\"></object><a href=\"$u\">PDF</a><a href=\"$u\" class=\"wp-block-file__button wp-element-button\" download>Download</a></div>\n<!-- /wp:file -->";
	$exp['application/pdf'] = 'file block PDF preview';
}
if ( ! empty( $att['docx'] ) ) {
	$u = wp_get_attachment_url( $att['docx'] );
	$blocks[] = "<!-- wp:file {\"id\":{$att['docx']},\"href\":\"$u\"} -->\n<div class=\"wp-block-file\"><a href=\"$u\">Document</a><a href=\"$u\" class=\"wp-block-file__button wp-element-button\" download>Download</a></div>\n<!-- /wp:file -->";
	$exp['.docx'] = 'file block link (upload-only type)';
}
if ( ! empty( $att['mov'] ) ) {
	$u = wp_get_attachment_url( $att['mov'] );
	$blocks[] = "<!-- wp:file {\"id\":{$att['mov']},\"href\":\"$u\"} -->\n<div class=\"wp-block-file\"><a href=\"$u\">Movie</a></div>\n<!-- /wp:file -->";
	$exp['.mov'] = 'file link (video without a player)';
}
$block_post = wp_insert_post( array( 'post_title' => "$MS_TAG blocks", 'post_status' => 'publish', 'post_content' => implode( "\n\n", $blocks ) ) );
$created_posts[] = $block_post;
if ( ! empty( $att['jpg'] ) ) {
	set_post_thumbnail( $block_post, $att['jpg'] );
	$exp['wp-post-image'] = 'featured image (theme must show it)';
}
ms_url( 'blocks', get_permalink( $block_post ) );
echo "EXPECT\tblocks\t" . wp_json_encode( $exp ) . "\n";

// Shortcodes, the way classic and migrated content carries media.
$sc  = array();
$sxp = array();
if ( ! empty( $att['jpg'] ) && ! empty( $att['png'] ) ) {
	$sc[] = '[gallery ids="' . $att['jpg'] . ',' . $att['png'] . '"]';
	$sxp['gallery galleryid'] = '[gallery]';
	$cap  = wp_get_attachment_image_url( $att['png'], 'medium' );
	$sc[] = '[caption id="attachment_' . $att['png'] . '" align="alignnone" width="300"]<img class="size-medium wp-image-' . $att['png'] . '" src="' . $cap . '" alt="" width="300" /> Caption text[/caption]';
	$sxp['wp-caption'] = '[caption]';
}
if ( ! empty( $att['mp3'] ) ) {
	$sc[] = '[audio src="' . wp_get_attachment_url( $att['mp3'] ) . '"]';
	$sxp['wp-audio-shortcode'] = '[audio]';
	$sc[] = '[playlist ids="' . $att['mp3'] . '"]';
	$sxp['wp-playlist'] = '[playlist]';
}
if ( ! empty( $att['mp4'] ) ) {
	$sc[] = '[video src="' . wp_get_attachment_url( $att['mp4'] ) . '"]';
	$sxp['wp-video-shortcode'] = '[video]';
}
$sc_post = wp_insert_post( array( 'post_title' => "$MS_TAG shortcodes", 'post_status' => 'publish', 'post_content' => implode( "\n\n", $sc ) ) );
$created_posts[] = $sc_post;
ms_url( 'shortcodes', get_permalink( $sc_post ) );
echo "EXPECT\tshortcodes\t" . wp_json_encode( $sxp ) . "\n";

// Render server-side too, so a theme that hides content can't turn a FAIL into a pass or the reverse.
foreach ( array( 'blocks' => array( $block_post, $exp ), 'shortcodes' => array( $sc_post, $sxp ) ) as $k => $pair ) {
	$GLOBALS['post'] = get_post( $pair[0] );
	setup_postdata( $GLOBALS['post'] );
	$html = apply_filters( 'the_content', get_post_field( 'post_content', $pair[0] ) );
	wp_reset_postdata();
	foreach ( $pair[1] as $marker => $label ) {
		if ( 'wp-post-image' === $marker ) {
			continue; // the theme renders featured images, not the_content
		}
		ms_cell( "render-$k-" . sanitize_title( $label ), false !== strpos( $html, $marker ) ? 'PASS' : 'FAIL', $label );
	}
	if ( 'blocks' === $k && ! empty( $att['jpg'] ) ) {
		ms_cell( 'render-blocks-srcset', preg_match( '/<img[^>]+wp-image-' . $att['jpg'] . '[^>]+srcset=/', $html ) ? 'PASS' : 'FAIL', 'image block img has srcset' );
	}
	if ( 'shortcodes' === $k && ! empty( $att['mp3'] ) ) {
		// Record, don't judge: the audio and video shortcodes append ?_=N to the source today; #66639 proposes removing it.
		if ( preg_match( '/<audio[^>]*>.*?<source[^>]+src="([^"]+)"/s', $html, $m ) ) {
			ms_cell( 'render-audio-shortcode-src', 'INFO', 'src=' . preg_replace( '#^https?://[^/]+#', '', html_entity_decode( $m[1] ) ) );
		}
	}
}

// oEmbed: the block and a bare URL on its own line.
if ( $MS_OEMBED_URL ) {
	$probe = wp_oembed_get( $MS_OEMBED_URL );
	if ( ! $probe ) {
		ms_cell( 'oembed-provider', 'BLOCKED(oembed-network)', "provider returned nothing for $MS_OEMBED_URL" );
	} else {
		ms_cell( 'oembed-provider', 'PASS', 'provider answered' );
		$oe_post = wp_insert_post( array(
			'post_title'   => "$MS_TAG oembed",
			'post_status'  => 'publish',
			'post_content' => "<!-- wp:embed {\"url\":\"$MS_OEMBED_URL\",\"type\":\"video\",\"responsive\":true} -->\n<figure class=\"wp-block-embed is-type-video wp-block-embed\"><div class=\"wp-block-embed__wrapper\">\n$MS_OEMBED_URL\n</div></figure>\n<!-- /wp:embed -->\n\n$MS_OEMBED_URL\n",
		) );
		$created_posts[] = $oe_post;
		ms_url( 'oembed', get_permalink( $oe_post ) );
		echo "EXPECT\toembed\t" . wp_json_encode( array( '<iframe' => 'oEmbed iframe' ) ) . "\n";
	}
} else {
	ms_cell( 'oembed-provider', 'BLOCKED(no-url)', 'no oEmbed URL given' );
}

/* ---------------------------------------------------------------- site surfaces */
if ( ! empty( $att['png'] ) ) {
	$old_logo = get_option( 'site_logo' );
	update_option( 'site_logo', $att['png'] );
	$logo = do_blocks( '<!-- wp:site-logo /-->' );
	ms_cell( 'site-logo-block', false !== strpos( $logo, 'wp-image-' . $att['png'] ) || false !== strpos( $logo, 'custom-logo' ) ? 'PASS' : 'FAIL', 'site-logo block renders the attachment' );
	update_option( 'site_logo', $old_logo );
	$old_icon = get_option( 'site_icon' );
	update_option( 'site_icon', $att['png'] );
	$icon = get_site_icon_url( 512 );
	ms_cell( 'site-icon-url', $icon ? 'PASS' : 'FAIL', $icon ? 'site icon URL resolves' : 'get_site_icon_url() empty' );
	echo "RESTORE\tsite_icon\t" . (int) $old_icon . "\n";
	ms_url( 'home', home_url( '/' ) );
	echo "EXPECT\thome\t" . wp_json_encode( array( 'rel="icon"' => 'site icon link' ) ) . "\n";
}
foreach ( array( 'custom-header', 'custom-background' ) as $feature ) {
	ms_cell( "theme-$feature", current_theme_supports( $feature ) ? 'INFO' : 'BLOCKED(theme-support)', get_stylesheet() . ( current_theme_supports( $feature ) ? ' supports it; set it in the Customizer' : ' does not support it' ) );
}
if ( ! empty( $att['jpg'] ) ) {
	$enabled = (int) get_option( 'wp_attachment_pages_enabled', 0 );
	ms_url( 'attachment', get_attachment_link( $att['jpg'] ) );
	echo "ATTACHMENT\t" . ( $enabled ? 'enabled' : 'disabled' ) . "\t" . wp_get_attachment_url( $att['jpg'] ) . "\n";
}

echo 'CLEANUP' . "\t" . implode( ',', array_merge( array_values( $att ), $created_posts ) ) . "\n";
array_map( 'unlink', glob( "$dir/*" ) );
@rmdir( $dir );
