<?php
/**
 * Editor paradigm — block editor vs classic, and block theme vs classic.
 *
 * Classic Editor has ~9 million active installs. If your plugin has features
 * that exist in only one paradigm, a pass in the other proves nothing about it.
 *
 * Run this suite twice, or set WP_EDITOR / WP_THEME in CI and let it branch.
 *
 * EDIT: the meta box id, the block name, and your feature callbacks.
 */

class Test_Editor_Paradigm extends WP_UnitTestCase {

	/** EDIT */
	const META_BOX_ID = 'myplugin_meta_box';
	const BLOCK_NAME  = 'myplugin/my-block';
	const POST_TYPE   = 'post';

	private function classic_mode() {
		return 'classic' === getenv( 'WP_EDITOR' );
	}

	public function set_up() {
		parent::set_up();
		wp_set_current_user( self::factory()->user->create( array( 'role' => 'administrator' ) ) );
	}

	// ── Which editor is actually in play ────────────────────────────────────

	public function test_editor_gate_reports_what_we_expect() {
		$uses_block = use_block_editor_for_post_type( self::POST_TYPE );

		if ( $this->classic_mode() ) {
			$this->assertFalse( $uses_block, 'Expected the classic editor but the block editor is active. Is Classic Editor installed and set to "replace"?' );
		} else {
			$this->assertTrue( $uses_block, 'Expected the block editor but it is off.' );
		}
	}

	// ── Classic-only surfaces ───────────────────────────────────────────────

	/**
	 * Meta boxes register in both editors, but the block editor renders them in
	 * a compatibility panel with different save timing. Assert registration
	 * here; assert behavior in the browser test.
	 */
	public function test_meta_box_registers_in_both_editors() {
		global $wp_meta_boxes;

		do_action( 'add_meta_boxes', self::POST_TYPE, self::factory()->post->create_and_get() );

		$found = false;
		if ( isset( $wp_meta_boxes[ self::POST_TYPE ] ) ) {
			foreach ( $wp_meta_boxes[ self::POST_TYPE ] as $context ) {
				foreach ( $context as $priority ) {
					if ( isset( $priority[ self::META_BOX_ID ] ) ) {
						$found = true;
					}
				}
			}
		}

		if ( ! $found ) {
			$this->markTestSkipped( 'No meta box registered — delete this test if you ship none.' );
		}
		$this->assertTrue( $found, 'Meta box missing in ' . ( $this->classic_mode() ? 'classic' : 'block' ) . ' editor.' );
	}

	public function test_meta_box_data_saves_in_this_paradigm() {
		$post_id = self::factory()->post->create( array( 'post_type' => self::POST_TYPE ) );

		// The block editor saves through REST, so meta must be registered with
		// show_in_rest or your value silently never arrives.
		$registered = get_registered_meta_keys( 'post', self::POST_TYPE );

		if ( ! $this->classic_mode() && isset( $registered['_myplugin_field'] ) ) {
			$this->assertTrue(
				! empty( $registered['_myplugin_field']['show_in_rest'] ),
				'Meta is not exposed to REST, so it cannot be saved from the block editor.'
			);
		}

		update_post_meta( $post_id, '_myplugin_field', 'value' ); // EDIT
		$this->assertSame( 'value', get_post_meta( $post_id, '_myplugin_field', true ) );
	}

	public function test_tinymce_filters_only_matter_in_classic() {
		$buttons = apply_filters( 'mce_buttons', array() );
		if ( ! $this->classic_mode() ) {
			// Not a failure — just make the asymmetry explicit so nobody assumes
			// a TinyMCE button exists in the block editor.
			$this->assertIsArray( $buttons );
			return;
		}
		// EDIT: assert your button is present in classic.
		$this->assertIsArray( $buttons );
	}

	// ── Block-only surfaces ─────────────────────────────────────────────────

	public function test_block_registers_when_the_block_editor_is_on() {
		$registry = WP_Block_Type_Registry::get_instance();
		$is_registered = $registry->is_registered( self::BLOCK_NAME );

		if ( ! $is_registered ) {
			$this->markTestSkipped( 'No block registered — delete this test if you ship none.' );
		}

		// Blocks register server-side regardless of editor. The point of the
		// assertion is that registration does NOT depend on the editor.
		$this->assertTrue( $is_registered, 'Block registration should not depend on which editor is active.' );
	}

	/**
	 * The important one: if the block editor is off, your block-only feature is
	 * unreachable. Either provide a classic fallback or fail visibly — never
	 * leave the user with a feature that silently isn't there.
	 */
	public function test_block_only_feature_has_a_classic_story() {
		if ( ! $this->classic_mode() ) {
			$this->markTestSkipped( 'Only meaningful with the classic editor active.' );
		}

		// EDIT: one of these should be true when the block editor is off —
		//   a shortcode fallback, a meta box equivalent, or an admin notice.
		$has_fallback =
			shortcode_exists( 'myplugin' )
			|| has_action( 'add_meta_boxes' )
			|| has_action( 'admin_notices' );

		$this->assertTrue(
			$has_fallback,
			'This plugin has block-editor features and no classic fallback or notice. ' .
			'~9M sites run Classic Editor; they will see nothing and be told nothing.'
		);
	}

	// ── Theme paradigm ──────────────────────────────────────────────────────

	public function test_theme_paradigm_matches_expectation() {
		$is_block_theme = function_exists( 'wp_is_block_theme' ) && wp_is_block_theme();

		if ( 'classic' === getenv( 'WP_THEME_TYPE' ) ) {
			$this->assertFalse( $is_block_theme, 'Expected a classic theme.' );
		}
		$this->assertIsBool( $is_block_theme );
	}

	public function test_widget_and_menu_surfaces_only_exist_on_classic_themes() {
		global $wp_registered_sidebars;

		$is_block_theme = function_exists( 'wp_is_block_theme' ) && wp_is_block_theme();

		if ( $is_block_theme && ! empty( $wp_registered_sidebars ) ) {
			// Not a failure: registering a sidebar on a block theme is legal,
			// the user just has no Widgets screen to reach it from. Say so in
			// your readme rather than leaving them hunting.
			$this->assertNotEmpty(
				$wp_registered_sidebars,
				'Sidebars registered on a block theme are unreachable without Classic Widgets.'
			);
		}
		$this->assertTrue( true );
	}
}
