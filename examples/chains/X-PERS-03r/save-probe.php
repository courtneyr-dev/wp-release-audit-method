<?php
require_once ABSPATH . 'wp-admin/includes/user.php';

$suffix   = strtolower( wp_generate_password( 8, false, false ) );
$username = 'codex-chain-kses-' . $suffix;
$user_id  = 0;
$post_id  = 0;
$admin_id = 1;
$content  = implode(
	"\n",
	array(
		'<div data-case="legacy-url" style="background-image: url(&quot;https://example.test/image.jpg&quot;)">legacy url</div>',
		'<div data-case="legacy-shorthand" style="background: url(&quot;https://example.test/image.jpg&quot;) center / cover no-repeat">legacy shorthand</div>',
		'<div data-case="gradient-only" style="background-image: linear-gradient(red, blue)">gradient</div>',
		'<div data-case="gradient-plus-url" style="background-image: linear-gradient(red, blue), url(&quot;https://example.test/image.jpg&quot;)">combined</div>',
		'<div data-case="unsafe-js-url" style="background-image: url(&quot;javascript:alert(1)&quot;)">unsafe</div>',
	)
);

function codex_chain_extract_styles( $html ) {
	$styles = array();
	preg_match_all(
		'/<div data-case="([^"]+)"(?: style="([^"]*)")?>/',
		$html,
		$matches,
		PREG_SET_ORDER
	);
	foreach ( $matches as $match ) {
		$styles[ $match[1] ] = $match[2] ?? null;
	}
	return $styles;
}

try {
	wp_set_current_user( $admin_id );
	$user_id = wp_insert_user(
		array(
			'user_login' => $username,
			'user_pass'  => wp_generate_password( 24, true, true ),
			'user_email' => $username . '@example.test',
			'role'       => 'author',
		)
	);
	if ( is_wp_error( $user_id ) ) {
		throw new RuntimeException( $user_id->get_error_message() );
	}

	$post_id = wp_insert_post(
		array(
			'post_title'   => 'Codex chain KSES ' . $suffix,
			'post_status'  => 'draft',
			'post_author'  => $user_id,
			'post_content' => $content,
		),
		true
	);
	if ( is_wp_error( $post_id ) ) {
		throw new RuntimeException( $post_id->get_error_message() );
	}

	$before = get_post_field( 'post_content', $post_id, 'raw' );
	wp_set_current_user( $user_id );
	$updated = wp_update_post(
		array(
			'ID'           => $post_id,
			'post_content' => $before,
		),
		true
	);
	if ( is_wp_error( $updated ) ) {
		throw new RuntimeException( $updated->get_error_message() );
	}
	$after = get_post_field( 'post_content', $post_id, 'raw' );

	echo wp_json_encode(
		array(
			'before'        => codex_chain_extract_styles( $before ),
			'after'         => codex_chain_extract_styles( $after ),
			'content_equal' => hash_equals( $before, $after ),
		),
		JSON_UNESCAPED_SLASHES
	) . PHP_EOL;
} finally {
	wp_set_current_user( $admin_id );
	if ( $post_id ) {
		wp_delete_post( $post_id, true );
	}
	if ( $user_id && ! is_wp_error( $user_id ) ) {
		wp_delete_user( $user_id );
	}
	echo wp_json_encode(
		array(
			'cleanup_post_exists' => $post_id ? (bool) get_post( $post_id ) : false,
			'cleanup_user_exists' => $user_id && ! is_wp_error( $user_id )
				? (bool) get_user_by( 'id', $user_id )
				: false,
		)
	) . PHP_EOL;
}
