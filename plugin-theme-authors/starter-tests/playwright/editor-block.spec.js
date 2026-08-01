/**
 * Block validation — the failure PHPUnit structurally cannot see.
 *
 * When core changes a block's saved markup, existing content throws
 * "This block contains unexpected or invalid content" in the editor while the
 * front end still renders fine. It is a JS-side error: nothing reaches
 * debug.log, and no PHP test will ever catch it.
 *
 * EDIT: BLOCK_NAME and BLOCK_TITLE.
 */

const { test, expect } = require( '@playwright/test' );

const BLOCK_NAME  = 'myplugin/my-block';   // EDIT
const BLOCK_TITLE = 'My Block';            // EDIT

async function login( page ) {
	await page.goto( '/wp-login.php' );
	await page.fill( '#user_login', 'admin' );
	await page.fill( '#user_pass', 'password' );
	await page.click( '#wp-submit' );
	await page.waitForURL( /wp-admin/ );
}

async function newPost( page ) {
	await page.goto( '/wp-admin/post-new.php' );
	// Dismiss the welcome guide if it appears — it blocks the canvas.
	const close = page.locator( '.components-modal__header button[aria-label="Close"]' );
	if ( await close.count() ) {
		await close.first().click();
	}
	await page.waitForSelector( '.block-editor-writing-flow', { timeout: 30000 } );
}

test.describe( 'Block lifecycle', () => {

	test( 'block is registered in the editor', async ( { page } ) => {
		await login( page );
		await newPost( page );

		const registered = await page.evaluate(
			( name ) => !! window.wp?.blocks?.getBlockType( name ),
			BLOCK_NAME
		);
		expect( registered, `${ BLOCK_NAME } is not registered` ).toBe( true );
	} );

	test( 'block inserts, saves, and reloads without a validation error', async ( { page } ) => {
		await login( page );
		await newPost( page );

		// Insert via the API rather than the UI — the UI changes between
		// releases, and this test is about validation, not the inserter.
		await page.evaluate( ( name ) => {
			const block = window.wp.blocks.createBlock( name );
			window.wp.data.dispatch( 'core/block-editor' ).insertBlock( block );
		}, BLOCK_NAME );

		await page.fill( '.editor-post-title__input, .wp-block-post-title', 'Block validation test' );

		// Save, then reload — validation runs on parse, so it only surfaces
		// after a round trip.
		await page.keyboard.press( 'Control+s' );
		await page.waitForTimeout( 2000 );
		await page.reload();
		await page.waitForSelector( '.block-editor-writing-flow', { timeout: 30000 } );

		const invalid = await page.evaluate( () =>
			window.wp.data
				.select( 'core/block-editor' )
				.getBlocks()
				.filter( ( b ) => ! b.isValid )
				.map( ( b ) => b.name )
		);

		expect(
			invalid,
			`Blocks failed validation after reload: ${ invalid.join( ', ' ) }. ` +
			'If core changed this block\'s markup, you need a block deprecation.'
		).toEqual( [] );

		// The user-visible symptom, asserted directly.
		await expect(
			page.locator( '.block-editor-block-list__block-crash-warning, .block-editor-warning' )
		).toHaveCount( 0 );
	} );

	test( 'editor loads with no console errors', async ( { page } ) => {
		const errors = [];
		page.on( 'console', ( m ) => m.type() === 'error' && errors.push( m.text() ) );
		page.on( 'pageerror', ( e ) => errors.push( e.message ) );

		await login( page );
		await newPost( page );
		await page.waitForTimeout( 2000 );

		// Filter noise that isn't yours.
		const ours = errors.filter(
			( e ) => ! /favicon|third-party cookie|ResizeObserver/i.test( e )
		);
		expect( ours, `Console errors in the editor:\n${ ours.join( '\n' ) }` ).toEqual( [] );
	} );
} );
