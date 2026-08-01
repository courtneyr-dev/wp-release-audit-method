<?php
/**
 * REST routes — registration, schema, and permissions.
 *
 * Schema validation tightens between releases. A field core used to accept
 * loosely may start being rejected, and the failure is a 400 your users see
 * rather than anything in your log.
 *
 * EDIT: namespace, routes, and payloads.
 */

class Test_REST extends WP_Test_REST_TestCase {

	/** EDIT */
	const NS    = 'myplugin/v1';
	const ROUTE = '/items';

	protected $server;

	public function set_up() {
		parent::set_up();
		global $wp_rest_server;
		$this->server = $wp_rest_server = new WP_REST_Server();
		do_action( 'rest_api_init' );
	}

	public function test_route_is_registered() {
		$routes = $this->server->get_routes();
		$this->assertArrayHasKey(
			'/' . self::NS . self::ROUTE,
			$routes,
			'Route disappeared. Check rest_api_init still fires for you.'
		);
	}

	public function test_route_exposes_a_schema() {
		// Without a schema, core cannot validate or sanitize for you, and your
		// route is invisible to clients that discover by schema.
		$request  = new WP_REST_Request( 'OPTIONS', '/' . self::NS . self::ROUTE );
		$response = $this->server->dispatch( $request );
		$data     = $response->get_data();

		$this->assertArrayHasKey( 'schema', $data, 'Route has no schema.' );
	}

	public function test_get_as_authorized_user_succeeds() {
		wp_set_current_user( self::factory()->user->create( array( 'role' => 'editor' ) ) );

		$request  = new WP_REST_Request( 'GET', '/' . self::NS . self::ROUTE );
		$response = $this->server->dispatch( $request );

		$this->assertSame( 200, $response->get_status() );
	}

	public function test_write_as_unauthorized_user_is_rejected() {
		// The negative control. A permission_callback that starts returning true
		// looks identical to a working test suite without this.
		wp_set_current_user( self::factory()->user->create( array( 'role' => 'subscriber' ) ) );

		$request = new WP_REST_Request( 'POST', '/' . self::NS . self::ROUTE );
		$request->set_body_params( array( 'title' => 'nope' ) ); // EDIT

		$response = $this->server->dispatch( $request );

		$this->assertContains(
			$response->get_status(),
			array( 401, 403 ),
			'An unauthorized user was allowed to write.'
		);
	}

	public function test_logged_out_write_is_rejected() {
		wp_set_current_user( 0 );

		$request  = new WP_REST_Request( 'POST', '/' . self::NS . self::ROUTE );
		$response = $this->server->dispatch( $request );

		$this->assertContains( $response->get_status(), array( 401, 403 ) );
	}

	public function test_invalid_payload_is_rejected_not_swallowed() {
		wp_set_current_user( self::factory()->user->create( array( 'role' => 'editor' ) ) );

		$request = new WP_REST_Request( 'POST', '/' . self::NS . self::ROUTE );
		// EDIT: a value your schema should refuse.
		$request->set_body_params( array( 'count' => 'not-a-number' ) );

		$response = $this->server->dispatch( $request );

		$this->assertSame(
			400,
			$response->get_status(),
			'Invalid input was accepted. Either your schema is missing a type, or you are sanitizing where you should validate.'
		);
	}

	public function test_response_shape_is_stable() {
		// Pin the shape. When core changes a serializer, this tells you before
		// a client integration does.
		wp_set_current_user( self::factory()->user->create( array( 'role' => 'editor' ) ) );

		$request  = new WP_REST_Request( 'GET', '/' . self::NS . self::ROUTE );
		$response = $this->server->dispatch( $request );
		$data     = $response->get_data();

		$this->assertIsArray( $data );
		// EDIT: assert your documented keys exist.
		// $this->assertArrayHasKey( 'items', $data );
	}
}
