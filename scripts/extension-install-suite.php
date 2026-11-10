<?php
/**
 * Plugin and theme install payload — runs INSIDE WordPress via `wp eval`, driven by
 * extension-install-suite.sh. Exercises the install paths the admin screens and REST use,
 * through the same upgrader classes, with every zip shape people actually upload.
 *
 * Inputs (prepended by the shell):
 *   $EX_ZIPS     array "<kind>:<variant>" => base64 zip   (kind: plugin | theme)
 *   $EX_NETWORK  bool, false marks every WordPress.org and URL cell BLOCKED(no-network)
 *   $EX_TAG      run tag
 *
 * Output: CELL <id> <VERDICT> <detail>, as media-suite.php.
 *
 * Why the zip variants. An upload that works from one person's machine and fails from
 * another's is almost always the archive, not WordPress: macOS Finder adds __MACOSX/ and
 * ._ AppleDouble files, Windows Explorer writes no directory entries and DOS attributes,
 * and Windows PowerShell 5.1 Compress-Archive writes BACKSLASHES as path separators. Old
 * hosts without the zip extension unzip with PclZip instead of ZipArchive, so every
 * variant runs through both.
 */

$EX_ZIPS    = isset( $EX_ZIPS ) ? $EX_ZIPS : array();
$EX_NETWORK = isset( $EX_NETWORK ) ? $EX_NETWORK : true;
$EX_TAG     = isset( $EX_TAG ) ? $EX_TAG : 'ext-suite';

require_once ABSPATH . 'wp-admin/includes/file.php';
require_once ABSPATH . 'wp-admin/includes/plugin.php';
require_once ABSPATH . 'wp-admin/includes/theme.php';
require_once ABSPATH . 'wp-admin/includes/plugin-install.php';
require_once ABSPATH . 'wp-admin/includes/theme-install.php';
require_once ABSPATH . 'wp-admin/includes/class-wp-upgrader.php';

function ex_cell( $id, $verdict, $detail = '' ) {
	echo "CELL\t$id\t$verdict\t" . str_replace( array( "\t", "\n" ), ' ', (string) $detail ) . "\n";
}

$admins = is_multisite() ? array_map( function ( $l ) { $u = get_user_by( 'login', $l ); return $u ? $u->ID : 0; }, get_super_admins() ) : get_users( array( 'role' => 'administrator', 'fields' => 'ID', 'number' => 1 ) );
wp_set_current_user( (int) reset( $admins ) );
if ( ! current_user_can( 'install_plugins' ) ) {
	ex_cell( 'setup', 'BLOCKED(no-install-cap)', 'no user here can install plugins (DISALLOW_FILE_MODS?)' );
	return;
}
WP_Filesystem();
ex_cell( 'env', 'INFO', 'ziparchive=' . ( class_exists( 'ZipArchive' ) ? 'yes' : 'no' ) . ' transports=' . implode( ',', array_filter( array( 'curl', 'streams' ), function ( $t ) { $c = 'WpOrg\\Requests\\Transport\\' . ucfirst( $t ); return class_exists( $c ) && $c::test(); } ) ) . ' multisite=' . ( is_multisite() ? 'yes' : 'no' ) );

// WordPress 6.4.3 (r57388, Trac #60398) opens every upload with ZipArchive::CHECKCONS.
// libzip older than 1.10.1 fails that check for zips written by macOS Archive Utility
// (ditto, which Finder > Compress runs) and GNOME Files. Newer libzip passes them, so a
// host on newer libzip CANNOT show that bug: report it, so a clean run isn't read as coverage.
$libzip    = class_exists( 'ZipArchive' ) && defined( 'ZipArchive::LIBZIP_VERSION' ) ? ZipArchive::LIBZIP_VERSION : 'none';
$sensitive = 'none' !== $libzip && version_compare( $libzip, '1.10.1', '<' );
ex_cell( 'env-libzip', 'INFO', "libzip=$libzip " . ( $sensitive ? 'older than 1.10.1: can show the CHECKCONS bug class' : 'not sensitive to the CHECKCONS bug class (needs libzip < 1.10.1)' ) );

$tmpdir = trailingslashit( get_temp_dir() ) . 'ext-suite-' . getmypid();
wp_mkdir_p( $tmpdir );

/** Install a package through the upgrader the admin screens use. Returns [ok(bool), detail]. */
function ex_install( $kind, $package, $args = array() ) {
	$skin = new Automatic_Upgrader_Skin();
	$up   = 'plugin' === $kind ? new Plugin_Upgrader( $skin ) : new Theme_Upgrader( $skin );
	$res  = $up->install( $package, $args );
	$msgs = implode( ' | ', array_slice( $skin->get_upgrade_messages(), -2 ) );
	if ( is_wp_error( $res ) ) {
		return array( false, $res->get_error_code() . ': ' . $res->get_error_message() );
	}
	if ( is_wp_error( $skin->result ) ) {
		return array( false, $skin->result->get_error_code() . ': ' . $skin->result->get_error_message() );
	}
	return array( (bool) $res, $res ? 'installed' : 'install() returned false: ' . $msgs );
}
function ex_plugin_file( $folder ) {
	wp_clean_plugins_cache( false );
	foreach ( array_keys( get_plugins() ) as $f ) {
		if ( 0 === strpos( $f, "$folder/" ) ) {
			return $f;
		}
	}
	return '';
}
function ex_remove_plugin( $folder ) {
	$f = ex_plugin_file( $folder );
	if ( $f ) {
		deactivate_plugins( $f, true, is_multisite() );
		delete_plugins( array( $f ) );
	}
	global $wp_filesystem;
	if ( $wp_filesystem->exists( WP_PLUGIN_DIR . "/$folder" ) ) {
		$wp_filesystem->delete( WP_PLUGIN_DIR . "/$folder", true );
	}
	wp_clean_plugins_cache( false );
}
function ex_remove_theme( $slug ) {
	if ( wp_get_theme( $slug )->exists() ) {
		delete_theme( $slug );
	}
	global $wp_filesystem;
	if ( $wp_filesystem->exists( get_theme_root() . "/$slug" ) ) {
		$wp_filesystem->delete( get_theme_root() . "/$slug", true );
	}
	wp_clean_themes_cache();
}
/** Top-level entries under a directory, so a run can report and remove exactly what an install created. */
function ex_entries( $root ) {
	return array_map( 'basename', glob( "$root/*", GLOB_NOSORT ) ?: array() );
}
function ex_rrmdir( $p ) {
	if ( is_dir( $p ) && ! is_link( $p ) ) {
		foreach ( array_diff( scandir( $p ), array( '.', '..' ) ) as $e ) {
			ex_rrmdir( "$p/$e" );
		}
		return @rmdir( $p );
	}
	return @unlink( $p );
}
function ex_remove_new( $root, $before ) {
	global $wp_filesystem;
	$new = array_values( array_diff( ex_entries( $root ), $before ) );
	foreach ( $new as $n ) {
		$wp_filesystem->delete( "$root/$n", true );
		if ( file_exists( "$root/$n" ) ) {
			ex_rrmdir( "$root/$n" ); // the suite's own cleanup; what core managed is reported separately
		}
	}
	wp_clean_plugins_cache( false );
	wp_clean_themes_cache();
	return $new;
}
/** What an install put on disk, one line: folder/file names, with a name that has a backslash in it flagged. */
function ex_describe_new( $root, $before ) {
	$out = array();
	foreach ( array_diff( ex_entries( $root ), $before ) as $n ) {
		$inner = is_dir( "$root/$n" ) ? ex_entries( "$root/$n" ) : array();
		$out[] = $n . ( $inner ? '/{' . implode( ',', $inner ) . '}' : '' );
	}
	return $out ? implode( '; ', $out ) : 'nothing';
}
function ex_stray_files( $root ) {
	// Archive junk that should never land on the server: AppleDouble files and __MACOSX.
	$hits = array();
	foreach ( glob( "$root/*", GLOB_NOSORT ) as $p ) {
		$b = basename( $p );
		if ( '__MACOSX' === $b || 0 === strpos( $b, '._' ) || false !== strpos( $b, '\\' ) ) {
			$hits[] = $b;
		}
	}
	return $hits;
}

/* ---------------------------------------------------------------- zip variants × unzip backend */
$expected_plugin = 'ms-ext/ms-ext.php';
$expected_theme  = 'ms-ext-theme';
foreach ( $EX_ZIPS as $key => $b64 ) {
	list( $kind, $variant ) = explode( ':', $key, 2 );
	if ( in_array( $variant, array( 'v2', 'dependent', 'required' ), true ) ) {
		continue; // fixtures for the replace and dependency cells, not archive shapes
	}
	$zip = "$tmpdir/$kind-$variant.zip";
	file_put_contents( $zip, base64_decode( $b64 ) );
	// The two checks core makes before unzipping, recorded per archive shape.
	if ( class_exists( 'ZipArchive' ) ) {
		$za    = new ZipArchive();
		$cc    = $za->open( $zip, ZipArchive::CHECKCONS );
		$valid = function_exists( 'wp_zip_file_is_valid' ) ? wp_zip_file_is_valid( $zip ) : null;
		if ( true === $cc ) {
			$za->close();
		}
		if ( 'header-mismatch' === $variant ) {
			// The control must FAIL CHECKCONS (or it isn't reaching the fallback path) and still validate through PclZip.
			$judge  = ( true !== $cc && true === $valid ) ? 'PASS' : 'FAIL';
			$prefix = true === $cc ? 'control did not fire: ' : 'control fired, PclZip fallback validated it: ';
		} else {
			$ok_cc  = true === $cc && false !== $valid;
			$judge  = $ok_cc ? 'PASS' : ( in_array( $variant, array( 'windows-backslash', 'no-top-folder' ), true ) ? 'INFO' : 'FAIL' );
			$prefix = '';
		}
		ex_cell( "$kind-zip-$variant-checkcons", $judge, $prefix . 'ZipArchive::CHECKCONS=' . ( true === $cc ? 'ok' : "error $cc" ) . ' wp_zip_file_is_valid=' . var_export( $valid, true ) . " libzip=$libzip" );
	}
	foreach ( array( 'ziparchive', 'pclzip' ) as $backend ) {
		if ( 'ziparchive' === $backend && ! class_exists( 'ZipArchive' ) ) {
			ex_cell( "$kind-zip-$variant-$backend", 'BLOCKED(no-ziparchive)' );
			continue;
		}
		$force = 'pclzip' === $backend ? '__return_false' : '__return_true';
		add_filter( 'unzip_file_use_ziparchive', $force );
		$copy  = "$tmpdir/$kind-$variant-$backend.zip";
		$root  = 'plugin' === $kind ? WP_PLUGIN_DIR : get_theme_root();
		$snap  = ex_entries( $root );
		copy( $zip, $copy );
		list( $ok, $detail ) = ex_install( $kind, $copy );
		$landed = ex_describe_new( $root, $snap );
		remove_filter( 'unzip_file_use_ziparchive', $force );
		if ( 'plugin' === $kind ) {
			$f      = ex_plugin_file( 'ms-ext' );
			$strays = array_merge( ex_stray_files( WP_PLUGIN_DIR ), is_dir( WP_PLUGIN_DIR . '/ms-ext' ) ? ex_stray_files( WP_PLUGIN_DIR . '/ms-ext' ) : array() );
			$good   = $ok && $f === $expected_plugin && ! $strays;
			if ( $good ) {
				$act  = activate_plugin( $f );
				$good = ! is_wp_error( $act ) && is_plugin_active( $f );
				$detail .= is_wp_error( $act ) ? ' activate=' . $act->get_error_code() : ' activated';
			}
			$detail .= ' found=' . ( $f ? $f : 'none' ) . ( $strays ? ' strays=' . implode( ',', $strays ) : '' );
			if ( ! $good ) {
				// What a site owner sees: the Plugins list, and whether Delete on that row removes it.
				wp_clean_plugins_cache( false );
				$new_dirs = array_diff( ex_entries( WP_PLUGIN_DIR ), $snap );
				$listed   = array();
				foreach ( array_keys( get_plugins() ) as $pf ) {
					foreach ( $new_dirs as $nd ) {
						if ( 0 === strpos( $pf, "$nd/" ) ) {
							$listed[] = $pf;
						}
					}
				}
				if ( $listed ) {
					$on_disk = file_exists( WP_PLUGIN_DIR . '/' . $listed[0] ) ? 'exists' : 'missing-on-disk';
					$del     = delete_plugins( $listed );
					$left    = array_filter( $new_dirs, function ( $nd ) { return file_exists( WP_PLUGIN_DIR . "/$nd" ); } );
					$detail .= ' listed=' . preg_replace( '#^[^/]+/#', '<tmpdir>/', $listed[0] ) . " ($on_disk) delete_plugins=" . ( is_wp_error( $del ) ? $del->get_error_code() : var_export( $del, true ) ) . ( $left ? ' but-left-files' : ' removed' );
				} else {
					$detail .= ' listed=none';
				}
			}
			ex_remove_plugin( 'ms-ext' );
			ex_remove_new( $root, $snap );
		} else {
			$t      = wp_get_theme( $expected_theme );
			$strays = array_merge( ex_stray_files( get_theme_root() ), is_dir( get_theme_root() . "/$expected_theme" ) ? ex_stray_files( get_theme_root() . "/$expected_theme" ) : array() );
			$good   = $ok && $t->exists() && ! $t->errors() && ! $strays;
			$detail .= ' theme=' . ( $t->exists() ? ( $t->errors() ? 'broken:' . $t->errors()->get_error_code() : 'ok' ) : 'none' ) . ( $strays ? ' strays=' . implode( ',', $strays ) : '' );
			ex_remove_theme( $expected_theme );
			ex_remove_new( $root, $snap );
		}
		// The two shapes no OS tool should make but people upload anyway are recorded, not judged.
		$judge = in_array( $variant, array( 'windows-backslash', 'no-top-folder' ), true ) ? 'INFO' : ( $good ? 'PASS' : 'FAIL' );
		ex_cell( "$kind-zip-$variant-$backend", $judge, ( 'INFO' === $judge ? ( $good ? 'installs cleanly; ' : 'does not install cleanly; ' ) : '' ) . $detail . ( $good ? '' : " landed=$landed" ) );
	}
}

/* ---------------------------------------------------------------- replace current with uploaded (5.5+) */
foreach ( array( 'plugin', 'theme' ) as $kind ) {
	if ( empty( $EX_ZIPS[ "$kind:infozip" ] ) || empty( $EX_ZIPS[ "$kind:v2" ] ) ) {
		continue;
	}
	file_put_contents( "$tmpdir/r1.zip", base64_decode( $EX_ZIPS[ "$kind:infozip" ] ) );
	file_put_contents( "$tmpdir/r2.zip", base64_decode( $EX_ZIPS[ "$kind:v2" ] ) );
	ex_install( $kind, "$tmpdir/r1.zip" );
	list( $ok_no ) = ex_install( $kind, "$tmpdir/r2.zip" ); // without overwrite: must refuse
	copy( "$tmpdir/r2.zip", "$tmpdir/r2b.zip" );
	list( $ok_yes, $detail ) = ex_install( $kind, "$tmpdir/r2b.zip", array( 'overwrite_package' => true ) );
	if ( 'plugin' === $kind ) {
		wp_clean_plugins_cache( false );
		$f   = ex_plugin_file( 'ms-ext' );
		$ver = $f ? get_plugin_data( WP_PLUGIN_DIR . "/$f", false, false )['Version'] : '';
		ex_remove_plugin( 'ms-ext' );
	} else {
		wp_clean_themes_cache();
		$ver = wp_get_theme( $expected_theme )->get( 'Version' );
		ex_remove_theme( $expected_theme );
	}
	ex_cell( "$kind-replace-by-upload", ( ! $ok_no && $ok_yes && '2.0' === $ver ) ? 'PASS' : 'FAIL', 'without overwrite=' . ( $ok_no ? 'installed (wrong)' : 'refused' ) . " with overwrite=$detail version=$ver" );
}

/* ---------------------------------------------------------------- manual copy (FTP) and mu-plugin drop */
global $wp_filesystem;
$pdir = WP_PLUGIN_DIR . '/ms-ext-manual';
wp_mkdir_p( $pdir );
file_put_contents( "$pdir/ms-ext-manual.php", "<?php\n/**\n * Plugin Name: MS Ext Manual\n * Version: 1.0\n */\n" );
$f = ex_plugin_file( 'ms-ext-manual' );
$act = $f ? activate_plugin( $f ) : new WP_Error( 'not_found' );
ex_cell( 'plugin-manual-copy', $f && ! is_wp_error( $act ) ? 'PASS' : 'FAIL', $f ? 'listed and activated' : 'not listed by get_plugins()' );
ex_remove_plugin( 'ms-ext-manual' );

$tdir = get_theme_root() . '/ms-ext-manual-theme';
wp_mkdir_p( $tdir );
file_put_contents( "$tdir/style.css", "/*\nTheme Name: MS Ext Manual Theme\nTemplate: twentytwentyfive\nVersion: 1.0\n*/\n" );
wp_clean_themes_cache();
$t = wp_get_theme( 'ms-ext-manual-theme' );
$prev = get_stylesheet();
if ( $t->exists() && ! $t->errors() ) {
	switch_theme( 'ms-ext-manual-theme' );
	$ok = get_stylesheet() === 'ms-ext-manual-theme' && get_template() === 'twentytwentyfive';
	switch_theme( $prev );
	ex_cell( 'theme-manual-copy-child', $ok ? 'PASS' : 'FAIL', 'child theme of twentytwentyfive listed and switched to' );
} else {
	ex_cell( 'theme-manual-copy-child', wp_get_theme( 'twentytwentyfive' )->exists() ? 'FAIL' : 'BLOCKED(no-parent)', $t->exists() ? 'errors=' . $t->errors()->get_error_code() : 'not found' );
}
ex_remove_theme( 'ms-ext-manual-theme' );

$mu = WPMU_PLUGIN_DIR . '/ms-ext-mu.php';
wp_mkdir_p( WPMU_PLUGIN_DIR );
file_put_contents( $mu, "<?php\n/**\n * Plugin Name: MS Ext MU\n */\n" );
$found = isset( get_mu_plugins()['ms-ext-mu.php'] );
unlink( $mu );
ex_cell( 'plugin-mu-drop', $found ? 'PASS' : 'FAIL', $found ? 'listed by get_mu_plugins()' : 'not listed' );

/* ---------------------------------------------------------------- dependencies (Requires Plugins, 6.5+) */
if ( ! empty( $EX_ZIPS['plugin:dependent'] ) ) {
	file_put_contents( "$tmpdir/dep.zip", base64_decode( $EX_ZIPS['plugin:dependent'] ) );
	ex_install( 'plugin', "$tmpdir/dep.zip" );
	// WP_Plugin_Dependencies caches once per request, and earlier cells in this process have
	// already built it, so activation is judged by the shell, one process per step.
	if ( ! empty( $EX_ZIPS['plugin:required'] ) ) {
		// WP_Plugin_Dependencies caches per request, so the satisfied half is judged by the
		// shell in fresh processes. Leave both installed, the required one inactive.
		file_put_contents( "$tmpdir/req.zip", base64_decode( $EX_ZIPS['plugin:required'] ) );
		ex_install( 'plugin', "$tmpdir/req.zip" );
		echo "DEPTEST\tready\n";
	} else {
		ex_remove_plugin( 'ms-ext-dependent' );
	}
}

/* ---------------------------------------------------------------- WordPress.org directory, URL, REST */
if ( ! $EX_NETWORK ) {
	foreach ( array( 'plugin-directory', 'theme-directory', 'plugin-url-curl', 'plugin-url-streams', 'plugin-rest-install' ) as $c ) {
		ex_cell( $c, 'BLOCKED(no-network)', 'run without --network' );
	}
} else {
	// Directory: what Plugins > Add New > Install Now does.
	ex_remove_plugin( 'hello-dolly' );
	$api = plugins_api( 'plugin_information', array( 'slug' => 'hello-dolly', 'fields' => array( 'sections' => false ) ) );
	if ( is_wp_error( $api ) ) {
		ex_cell( 'plugin-directory', 'BLOCKED(plugins-api)', $api->get_error_message() );
	} else {
		list( $ok, $detail ) = ex_install( 'plugin', $api->download_link );
		$f = ex_plugin_file( 'hello-dolly' );
		ex_cell( 'plugin-directory', $ok && $f ? 'PASS' : 'FAIL', "$detail found=" . ( $f ? $f : 'none' ) );
		ex_remove_plugin( 'hello-dolly' );
	}
	$theme_slug = 'twentytwentytwo';
	if ( wp_get_theme( $theme_slug )->exists() ) {
		ex_cell( 'theme-directory', 'BLOCKED(already-installed)', "$theme_slug is installed; pick another slug" );
	} else {
		$api = themes_api( 'theme_information', array( 'slug' => $theme_slug, 'fields' => array( 'sections' => false ) ) );
		if ( is_wp_error( $api ) ) {
			ex_cell( 'theme-directory', 'BLOCKED(themes-api)', $api->get_error_message() );
		} else {
			list( $ok, $detail ) = ex_install( 'theme', $api->download_link );
			wp_clean_themes_cache();
			$t = wp_get_theme( $theme_slug );
			ex_cell( 'theme-directory', $ok && $t->exists() && ! $t->errors() ? 'PASS' : 'FAIL', $detail );
			ex_remove_theme( $theme_slug );
		}
	}
	// From a URL, once per HTTP transport: hosts differ in which one WordPress ends up using.
	foreach ( array( 'curl', 'streams' ) as $transport ) {
		$only = function () use ( $transport ) { return array( $transport ); };
		add_filter( 'http_api_transports', $only );
		list( $ok, $detail ) = ex_install( 'plugin', 'https://downloads.wordpress.org/plugin/hello-dolly.zip' );
		remove_filter( 'http_api_transports', $only );
		$f = ex_plugin_file( 'hello-dolly' );
		ex_cell( "plugin-url-$transport", $ok && $f ? 'PASS' : 'FAIL', $detail );
		ex_remove_plugin( 'hello-dolly' );
	}
	// REST: POST /wp/v2/plugins installs from the directory by slug (the block directory uses it).
	$req = new WP_REST_Request( 'POST', '/wp/v2/plugins' );
	$req->set_param( 'slug', 'hello-dolly' );
	$res = rest_do_request( $req );
	$f   = ex_plugin_file( 'hello-dolly' );
	ex_cell( 'plugin-rest-install', 201 === $res->get_status() && $f ? 'PASS' : 'FAIL', 'status=' . $res->get_status() );
	ex_remove_plugin( 'hello-dolly' );
	ex_cell( 'theme-rest-install', 'INFO', 'no core REST route installs themes (/wp/v2/themes is read-only)' );
}

array_map( 'unlink', glob( "$tmpdir/*" ) );
@rmdir( $tmpdir );
