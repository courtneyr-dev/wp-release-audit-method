<?php
/**
 * Capability boundaries — the surface an admin account cannot test.
 *
 * A whole class of bug works perfectly for administrators and breaks for
 * Authors, or worse, allows something it shouldn't. Core changes to
 * map_meta_cap() move these boundaries between releases.
 *
 * EDIT: your capability strings and the functions that check them.
 */

class Test_Capabilities extends WP_UnitTestCase {

	/** EDIT: the capability your feature requires. */
	const REQUIRED_CAP = 'edit_posts';

	private function user_with( $role ) {
		return self::factory()->user->create( array( 'role' => $role ) );
	}

	public function test_roles_that_should_have_access_do() {
		// EDIT: the roles you claim to support.
		foreach ( array( 'administrator', 'editor', 'author' ) as $role ) {
			wp_set_current_user( $this->user_with( $role ) );
			$this->assertTrue(
				current_user_can( self::REQUIRED_CAP ),
				"Role {$role} lost access to " . self::REQUIRED_CAP
			);
		}
	}

	public function test_roles_that_should_not_have_access_do_not() {
		// The negative control. Without this, a capability check that starts
		// returning true for everyone looks like a passing test suite.
		foreach ( array( 'subscriber' ) as $role ) {
			wp_set_current_user( $this->user_with( $role ) );
			$this->assertFalse(
				current_user_can( self::REQUIRED_CAP ),
				"Role {$role} gained access it should not have."
			);
		}
	}

	public function test_logged_out_user_has_no_access() {
		wp_set_current_user( 0 );
		$this->assertFalse( current_user_can( self::REQUIRED_CAP ) );
	}

	public function test_author_cannot_act_on_another_users_content() {
		$alice = $this->user_with( 'author' );
		$bob   = $this->user_with( 'author' );

		$bobs_post = self::factory()->post->create(
			array(
				'post_author' => $bob,
				'post_type'   => 'post',
			)
		);

		wp_set_current_user( $alice );

		$this->assertFalse(
			current_user_can( 'edit_post', $bobs_post ),
			'An Author can edit another Author\'s post.'
		);
		$this->assertFalse(
			current_user_can( 'delete_post', $bobs_post ),
			'An Author can delete another Author\'s post.'
		);

		// EDIT: assert the same for YOUR object type and capability.
	}

	public function test_admin_screen_is_denied_to_low_roles() {
		// EDIT: point at your own admin-page callback.
		if ( ! function_exists( 'myplugin_render_settings_page' ) ) {
			$this->markTestSkipped( 'No settings page callback to test.' );
		}

		wp_set_current_user( $this->user_with( 'subscriber' ) );

		$this->expectException( WPDieException::class );
		myplugin_render_settings_page();
	}

	/**
	 * @group multisite
	 */
	public function test_super_admin_boundary_on_multisite() {
		if ( ! is_multisite() ) {
			$this->markTestSkipped( 'Multisite only.' );
		}

		$site_admin = $this->user_with( 'administrator' );
		wp_set_current_user( $site_admin );

		// A site administrator is not a super administrator. Plugins that assume
		// "administrator means unrestricted" break this boundary on networks.
		$this->assertFalse(
			is_super_admin( $site_admin ),
			'A plain site administrator was treated as a super admin.'
		);
		$this->assertFalse( current_user_can( 'manage_network_options' ) );
	}
}
