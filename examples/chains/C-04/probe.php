<?php
$viewer_id = (int) getenv( 'CHAIN_VIEWER_ID' );
$scope     = getenv( 'CHAIN_SCOPE' );

if ( 'network' === $scope && ! defined( 'WP_NETWORK_ADMIN' ) ) {
	define( 'WP_NETWORK_ADMIN', true );
}

wp_set_current_user( $viewer_id );

require_once ABSPATH . 'wp-admin/includes/plugin.php';
require_once ABSPATH . 'wp-admin/includes/plugin-install.php';
WP_Plugin_Dependencies::initialize();

$dependency_file = 'codex-dependency/codex-dependency.php';
$dependent_file  = 'codex-dependent/codex-dependent.php';
$data            = array(
	'name'              => 'Codex Dependent',
	'slug'              => 'codex-dependent',
	'version'           => '1.0.0',
	'requires_plugins'  => array( 'codex-dependency' ),
	'download_link'     => '',
);
$button          = wp_get_plugin_action_button(
	'Codex Dependent',
	$data,
	true,
	true
);
$request         = new WP_REST_Request(
	'GET',
	'/wp/v2/plugins/codex-dependent/codex-dependent'
);
$response        = rest_do_request( $request );
$response_data   = $response->get_data();

echo wp_json_encode(
	array(
		'viewer_id'                    => $viewer_id,
		'scope'                        => $scope,
		'is_super_admin'               => is_super_admin( $viewer_id ),
		'can_activate_plugins'         => current_user_can( 'activate_plugins' ),
		'can_manage_network_plugins'   => current_user_can( 'manage_network_plugins' ),
		'dependency_active_effective'  => is_plugin_active( $dependency_file ),
		'dependency_active_site'       => in_array(
			$dependency_file,
			get_option( 'active_plugins', array() ),
			true
		),
		'dependency_active_network'    => is_plugin_active_for_network( $dependency_file ),
		'dependency_unmet_for_runtime' => WP_Plugin_Dependencies::has_unmet_dependencies(
			$dependent_file
		),
		'action_button_disabled'       => str_contains( $button, 'disabled=' ),
		'action_button_activate_link'  => str_contains( $button, 'activate-now' ),
		'action_button_text'           => wp_strip_all_tags( $button ),
		'rest_status'                  => $response->get_status(),
		'rest_plugin_status'           => is_array( $response_data ) && isset( $response_data['status'] )
			? $response_data['status']
			: null,
		'rest_error_code'              => is_array( $response_data ) && isset( $response_data['code'] )
			? $response_data['code']
			: null,
	),
	JSON_UNESCAPED_SLASHES
) . PHP_EOL;
