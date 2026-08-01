<?php
/**
 * Uninstall — does it actually remove everything?
 *
 * Guideline-relevant and almost never tested. Users who uninstall and reinstall
 * to "start fresh" get their old broken state back, and orphaned rows accumulate
 * in every database your plugin has ever touched.
 *
 * EDIT: your option names, meta keys, table name, and cron hooks.
 */

class Test_Uninstall extends WP_UnitTestCase {

	/** EDIT: everything your plugin persists. */
	const OPTIONS   = array( 'myplugin_settings', 'myplugin_version' );
	const META_KEY  = '_myplugin_data';
	const CRON_HOOK = 'myplugin_daily_sync';

	private function seed_state() {
		foreach ( self::OPTIONS as $o ) {
			update_option( $o, 'seeded' );
		}
		set_transient( 'myplugin_cache', 'x', HOUR_IN_SECONDS );

		$post_id = self::factory()->post->create();
		update_post_meta( $post_id, self::META_KEY, 'seeded' );

		if ( ! wp_next_scheduled( self::CRON_HOOK ) ) {
			wp_schedule_event( time() + 3600, 'daily', self::CRON_HOOK );
		}
		return $post_id;
	}

	private function run_uninstall() {
		// uninstall.php runs with WP_UNINSTALL_PLUGIN defined and NOT in normal
		// plugin context — a common source of fatals nobody sees until a user
		// deletes the plugin.
		$file = WP_PLUGIN_DIR . '/my-plugin/uninstall.php'; // EDIT
		if ( ! file_exists( $file ) ) {
			$this->markTestSkipped( 'No uninstall.php found.' );
		}
		if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
			define( 'WP_UNINSTALL_PLUGIN', 'my-plugin/my-plugin.php' ); // EDIT
		}
		include $file;
	}

	public function test_uninstall_removes_options() {
		$this->seed_state();
		$this->run_uninstall();

		foreach ( self::OPTIONS as $o ) {
			$this->assertFalse( get_option( $o ), "Option {$o} survived uninstall." );
		}
	}

	public function test_uninstall_removes_transients() {
		$this->seed_state();
		$this->run_uninstall();

		$this->assertFalse( get_transient( 'myplugin_cache' ), 'Transient survived uninstall.' );
	}

	public function test_uninstall_removes_post_meta() {
		$post_id = $this->seed_state();
		$this->run_uninstall();

		$this->assertSame(
			'',
			get_post_meta( $post_id, self::META_KEY, true ),
			'Post meta survived uninstall — this is the one that accumulates.'
		);
	}

	public function test_uninstall_clears_scheduled_events() {
		$this->seed_state();
		$this->run_uninstall();

		$this->assertFalse(
			wp_next_scheduled( self::CRON_HOOK ),
			'Scheduled event survived uninstall. It will keep firing against code that no longer exists.'
		);
	}

	public function test_uninstall_drops_custom_tables() {
		global $wpdb;
		$table = $wpdb->prefix . 'myplugin_items'; // EDIT

		// Only meaningful if you create tables.
		$exists_before = $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $table ) );
		if ( ! $exists_before ) {
			$this->markTestSkipped( 'No custom table to test.' );
		}

		$this->run_uninstall();

		$exists_after = $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $table ) );
		$this->assertNull( $exists_after, 'Custom table survived uninstall.' );
	}

	public function test_uninstall_does_not_touch_unrelated_data() {
		// The control that stops an over-eager cleanup routine from deleting
		// someone else's options because they share a prefix fragment.
		update_option( 'unrelated_plugin_settings', 'keep me' );
		$post_id = self::factory()->post->create();
		update_post_meta( $post_id, '_someone_elses_meta', 'keep me' );

		$this->seed_state();
		$this->run_uninstall();

		$this->assertSame( 'keep me', get_option( 'unrelated_plugin_settings' ), 'Uninstall deleted an unrelated option.' );
		$this->assertSame( 'keep me', get_post_meta( $post_id, '_someone_elses_meta', true ), 'Uninstall deleted unrelated post meta.' );
	}
}
