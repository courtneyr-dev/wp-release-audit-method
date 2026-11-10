<?php
/**
 * Media type sweep payload — runs INSIDE WordPress via `wp eval`, driven by media-type-sweep.sh.
 *
 * Inputs (prepended by the shell):
 *   $MTS_DIR     host-visible directory holding one sample per extension (sample.<ext>)
 *   $MTS_EDITOR  '' (WordPress's choice), 'gd' or 'imagick' — forces the image editor
 *
 * Output, one line per allowed extension:
 *   TYPE <ext> <accepted|rejected> <stored mime or error code> <sub-size count> <detail>
 * A rejected synthetic sample is a fact about the sample as much as about WordPress, which is
 * why the shell compares each line with a baseline run instead of judging it alone.
 */
require_once ABSPATH . 'wp-admin/includes/file.php';
require_once ABSPATH . 'wp-admin/includes/media.php';
require_once ABSPATH . 'wp-admin/includes/image.php';

$MTS_EDITOR = isset( $MTS_EDITOR ) ? $MTS_EDITOR : '';
if ( 'imagick' === $MTS_EDITOR && ! extension_loaded( 'imagick' ) ) {
	echo "BLOCKED\tno-imagick\n";
	return;
}
if ( $MTS_EDITOR ) {
	$only = 'gd' === $MTS_EDITOR ? 'WP_Image_Editor_GD' : 'WP_Image_Editor_Imagick';
	add_filter( 'wp_image_editors', function () use ( $only ) { return array( $only ); } );
}
$admins = is_multisite() ? array_map( function ( $l ) { $u = get_user_by( 'login', $l ); return $u ? $u->ID : 0; }, get_super_admins() ) : get_users( array( 'role' => 'administrator', 'fields' => 'ID', 'number' => 1 ) );
wp_set_current_user( (int) reset( $admins ) );
echo "ENV\teditor=" . _wp_image_editor_choose() . "\tallowed=" . count( get_allowed_mime_types() ) . "\n";

$seen = array();
foreach ( get_allowed_mime_types() as $exts => $mime ) {
	foreach ( explode( '|', $exts ) as $ext ) {
		if ( isset( $seen[ $ext ] ) ) {
			continue; // an extension listed under two MIME entries is one upload, judged once
		}
		$seen[ $ext ] = true;
		$src = "$MTS_DIR/sample.$ext";
		if ( ! file_exists( $src ) ) {
			echo "TYPE\t$ext\tno-sample\t-\t-\tno sample built for this extension\n";
			continue;
		}
		$tmp = wp_tempnam( "sample.$ext" );
		copy( $src, $tmp );
		$id = media_handle_sideload( array( 'name' => "mts-sample.$ext", 'tmp_name' => $tmp ), 0, "media-type-sweep $ext" );
		if ( is_wp_error( $id ) ) {
			@unlink( $tmp );
			echo "TYPE\t$ext\trejected\t" . $id->get_error_code() . "\t-\t" . str_replace( array( "\t", "\n" ), ' ', $id->get_error_message() ) . "\n";
			continue;
		}
		$meta  = wp_get_attachment_metadata( $id );
		$sizes = isset( $meta['sizes'] ) ? count( $meta['sizes'] ) : 0;
		$file  = get_attached_file( $id );
		$note  = file_exists( $file ) ? 'file stored' : 'FILE MISSING';
		if ( isset( $meta['original_image'] ) ) {
			$note .= '; scaled or converted from ' . $meta['original_image'];
		}
		echo "TYPE\t$ext\taccepted\t" . get_post_mime_type( $id ) . "\t$sizes\t$note\n";
		wp_delete_attachment( $id, true );
	}
}
