<?php
/**
 * The upgrade path — the lane a fresh install can never test.
 *
 * Write data the way an OLD version of your plugin wrote it, run your upgrade
 * routine, then assert the data is still readable. This is the test that catches
 * the class of bug users actually hit, because almost nobody installs fresh.
 *
 * EDIT: the option names, the old data shapes, and the upgrade function.
 */

class Test_Upgrade_Path extends WP_UnitTestCase {

	public function test_old_option_shape_survives_upgrade() {
		// EDIT: write data in the shape your PREVIOUS release wrote it.
		update_option( 'myplugin_version', '1.4.0' );
		update_option(
			'myplugin_settings',
			array(
				'enabled' => '1',      // old: string
				'mode'    => 'simple', // old: key that was later renamed
			)
		);

		// EDIT: call your actual upgrade routine.
		if ( function_exists( 'myplugin_maybe_upgrade' ) ) {
			myplugin_maybe_upgrade();
		}

		$settings = get_option( 'myplugin_settings' );

		$this->assertIsArray( $settings, 'Settings stopped being an array after upgrade.' );
		$this->assertArrayHasKey( 'enabled', $settings, 'Upgrade dropped a setting.' );

		// A rename must carry the value across, not just add the new key.
		if ( isset( $settings['display_mode'] ) ) {
			$this->assertSame( 'simple', $settings['display_mode'], 'Renamed key lost its value.' );
		}
	}

	public function test_upgrade_is_idempotent() {
		update_option( 'myplugin_version', '1.4.0' );

		if ( function_exists( 'myplugin_maybe_upgrade' ) ) {
			myplugin_maybe_upgrade();
			$after_first = get_option( 'myplugin_settings' );

			// Running twice must not double-migrate. Upgrade routines fire on
			// every load until the version option is written; if that write
			// fails, this runs again.
			myplugin_maybe_upgrade();
			$after_second = get_option( 'myplugin_settings' );

			$this->assertEquals( $after_first, $after_second, 'Upgrade routine is not idempotent.' );
		}
	}

	public function test_post_meta_written_by_old_version_still_reads() {
		$post_id = self::factory()->post->create();

		// EDIT: the meta key and old value shape.
		update_post_meta( $post_id, '_myplugin_data', 'a:1:{s:3:"key";s:5:"value";}' );

		if ( function_exists( 'myplugin_maybe_upgrade' ) ) {
			myplugin_maybe_upgrade();
		}

		$meta = get_post_meta( $post_id, '_myplugin_data', true );
		$this->assertNotEmpty( $meta, 'Post meta from the old version disappeared.' );
	}

	public function test_fresh_install_and_upgraded_install_end_in_the_same_state() {
		// The assertion people skip. If these two diverge, half your users are
		// running a configuration you have never tested.
		delete_option( 'myplugin_settings' );
		delete_option( 'myplugin_version' );

		if ( function_exists( 'myplugin_install' ) ) {
			myplugin_install();
		}
		$fresh = get_option( 'myplugin_settings' );

		delete_option( 'myplugin_settings' );
		update_option( 'myplugin_version', '1.4.0' );
		update_option( 'myplugin_settings', array( 'enabled' => '1' ) );

		if ( function_exists( 'myplugin_maybe_upgrade' ) ) {
			myplugin_maybe_upgrade();
		}
		$upgraded = get_option( 'myplugin_settings' );

		if ( is_array( $fresh ) && is_array( $upgraded ) ) {
			$this->assertEqualSets(
				array_keys( $fresh ),
				array_keys( $upgraded ),
				'Fresh install and upgraded install have different setting keys.'
			);
		}
	}
}
