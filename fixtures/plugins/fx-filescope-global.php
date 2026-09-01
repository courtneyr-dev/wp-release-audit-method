<?php
/**
 * Plugin Name: FX File-Scope Global
 * Description: Healthy over HTTP, fatal under WP-CLI. Reconstructs the eps-301-redirects
 *   shape: an object assigned at file scope, read back through `global` on a later hook.
 *   Under WP-CLI the assignment lands in WP_CLI\Runner->load_wordpress()'s local scope
 *   instead of the global one, so the global is null and the method call fatals.
 * Version: 1.0.0
 */

class FX_FileScope_Thing {
	public function add_admin_message() {
		return true;
	}
}

// At file scope. A global over HTTP; a local of load_wordpress() under WP-CLI.
$fx_filescope_thing = new FX_FileScope_Thing();

add_action(
	'init',
	function () {
		global $fx_filescope_thing;
		// Null under WP-CLI. Fatal: call to a member function on null.
		$fx_filescope_thing->add_admin_message();
	},
	5
);
