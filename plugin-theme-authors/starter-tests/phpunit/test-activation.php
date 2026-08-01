<?php
/**
 * Activation, deactivation, reactivation.
 *
 * A fatal here affects every user instantly, so this is test one of five.
 * EDIT: replace MYPLUGIN_ constants and the plugin file path.
 */

class Test_Activation extends WP_UnitTestCase {

	/** EDIT: path relative to the plugins directory. */
	const PLUGIN_FILE = 'my-plugin/my-plugin.php';

	public function test_plugin_file_exists() {
		$this->assertFileExists(
			WP_PLUGIN_DIR . '/' . self::PLUGIN_FILE,
			'Plugin file not found — check PLUGIN_FILE.'
		);
	}

	public function test_activation_produces_no_fatal_and_no_output() {
		// Output during activation breaks the redirect and shows "headers already
		// sent" to the user. Catch it here rather than in a support ticket.
		ob_start();
		activate_plugin( self::PLUGIN_FILE );
		$output = ob_get_clean();

		$this->assertSame( '', trim( $output ), 'Plugin printed output during activation.' );
		$this->assertTrue( is_plugin_active( self::PLUGIN_FILE ) );
	}

	public function test_activation_registers_expected_state() {
		activate_plugin( self::PLUGIN_FILE );

		// EDIT: assert whatever activation is supposed to create.
		// Options, tables, roles, capabilities, scheduled events.
		$this->assertNotFalse( get_option( 'myplugin_version' ), 'Version option not set on activation.' );
	}

	public function test_deactivate_then_reactivate_is_clean() {
		activate_plugin( self::PLUGIN_FILE );
		deactivate_plugins( self::PLUGIN_FILE );
		$this->assertFalse( is_plugin_active( self::PLUGIN_FILE ) );

		// Reactivation is a different path from first activation: state already
		// exists. Upgrade routines that assume a clean slate break here.
		ob_start();
		activate_plugin( self::PLUGIN_FILE );
		$output = ob_get_clean();

		$this->assertSame( '', trim( $output ), 'Plugin printed output on reactivation.' );
		$this->assertTrue( is_plugin_active( self::PLUGIN_FILE ) );
	}

	public function test_no_php_notices_on_load() {
		$errors = array();
		set_error_handler(
			static function ( $no, $str ) use ( &$errors ) {
				$errors[] = $str;
				return true;
			},
			E_ALL
		);

		activate_plugin( self::PLUGIN_FILE );
		do_action( 'init' );
		do_action( 'wp_loaded' );

		restore_error_handler();
		$this->assertEmpty( $errors, "PHP notices during load:\n" . implode( "\n", $errors ) );
	}
}
