<?php
/**
 * Plugin Name: FX Closure Registrar
 * Description: The third ingredient — registers a CLOSURE on deleted_post, which is what
 *   gets keyed by object id. Harmless on its own; supplies the trigger state.
 * Version: 1.0.0
 */

add_action(
	'deleted_post',
	function ( $post_id ) {
		// Deliberately does nothing. Its existence is the whole contribution.
		return $post_id;
	},
	10,
	1
);
