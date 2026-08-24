<?php
/**
 * Plugin Name: FX Strict Consumer
 * Description: Stands in for WP Rocket's Cloudflare module — a string operation on a
 *   $wp_filter callback key, under strict_types, on init. Fine while keys are strings.
 * Version: 1.0.0
 */

declare(strict_types=1);

add_action(
	'init',
	function () {
		global $wp_filter;

		if ( ! isset( $wp_filter['deleted_post'] ) ) {
			return;
		}

		$method = 'purge_cache';

		// The shape WP Rocket used: inc/ThirdParty/Plugins/CDN/Cloudflare.php:562
		foreach ( $wp_filter['deleted_post']->callbacks as $priority => $callbacks ) {
			foreach ( $callbacks as $key => $callback ) {
				if ( substr( $key, -strlen( $method ) ) === $method ) {
					return;
				}
			}
		}
	},
	5
);
