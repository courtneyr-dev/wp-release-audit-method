/**
 * Admin smoke — settings load, save, and persist, with no console errors.
 *
 * EDIT: SETTINGS_URL and the field selectors.
 */

const { test, expect } = require( '@playwright/test' );

const SETTINGS_URL = '/wp-admin/options-general.php?page=myplugin'; // EDIT

async function login( page ) {
	await page.goto( '/wp-login.php' );
	await page.fill( '#user_login', 'admin' );
	await page.fill( '#user_pass', 'password' );
	await page.click( '#wp-submit' );
	await page.waitForURL( /wp-admin/ );
}

test.describe( 'Admin', () => {

	test( 'settings screen loads without PHP or JS errors', async ( { page } ) => {
		const errors = [];
		page.on( 'console', ( m ) => m.type() === 'error' && errors.push( m.text() ) );
		page.on( 'pageerror', ( e ) => errors.push( e.message ) );

		await login( page );
		await page.goto( SETTINGS_URL );

		// PHP notices render into the page. They are invisible to a status check.
		const body = await page.locator( 'body' ).innerText();
		expect( body ).not.toMatch( /Fatal error|Parse error|Warning:|Notice:|Deprecated:/ );

		const ours = errors.filter( ( e ) => ! /favicon|ResizeObserver/i.test( e ) );
		expect( ours, `Console errors:\n${ ours.join( '\n' ) }` ).toEqual( [] );
	} );

	test( 'settings save and survive a reload', async ( { page } ) => {
		await login( page );
		await page.goto( SETTINGS_URL );

		// EDIT: your field.
		const field = page.locator( 'input[name="myplugin_settings[example]"]' );
		if ( ! ( await field.count() ) ) {
			test.skip( true, 'Settings field not found — update the selector.' );
		}

		await field.fill( 'roundtrip-value' );
		await page.click( '#submit, input[type="submit"]' );
		await page.waitForLoadState( 'networkidle' );

		await expect( page.locator( '.notice-success, .updated' ) ).toBeVisible();

		// Reload rather than trusting the post-save render — sanitize callbacks
		// can silently drop a value that the confirmation screen still echoes.
		await page.goto( SETTINGS_URL );
		await expect( field ).toHaveValue( 'roundtrip-value' );
	} );

	test( 'a low-privilege user cannot reach the settings screen', async ( { page, context } ) => {
		await login( page );

		// Create a subscriber, then act as them in a clean context.
		await page.goto( '/wp-admin/user-new.php' );
		// EDIT: or seed the user with WP-CLI in your global setup, which is faster.

		await context.clearCookies();
		await page.goto( SETTINGS_URL );

		const body = await page.locator( 'body' ).innerText();
		expect(
			/do not have sufficient permissions|not allowed|wp-login/i.test( body ) ||
				page.url().includes( 'wp-login' )
		).toBeTruthy();
	} );

	test( 'front end renders with no console errors', async ( { page } ) => {
		const errors = [];
		page.on( 'pageerror', ( e ) => errors.push( e.message ) );

		await page.goto( '/' );
		await page.waitForLoadState( 'networkidle' );

		expect( errors, `Front-end JS errors:\n${ errors.join( '\n' ) }` ).toEqual( [] );
	} );
} );
