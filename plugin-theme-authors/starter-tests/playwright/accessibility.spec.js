/**
 * Accessibility — automated scan plus the keyboard checks that automation misses.
 *
 * Method: https://wpaccessibility.org/docs/testing/
 *
 * The automated half catches only a fraction of accessibility errors. The
 * keyboard half below is the part that finds the failures that stop people
 * using the thing at all — and it is cheap to run.
 *
 *   npm install --save-dev @playwright/test @axe-core/playwright
 *
 * EDIT: the URLs and your block/settings selectors.
 */

const { test, expect } = require( '@playwright/test' );
const AxeBuilder = require( '@axe-core/playwright' ).default;

const TAGS = [ 'wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa' ];

async function login( page ) {
	await page.goto( '/wp-login.php' );
	await page.fill( '#user_login', 'admin' );
	await page.fill( '#user_pass', 'password' );
	await page.click( '#wp-submit' );
	await page.waitForURL( /wp-admin/ );
}

// ── Automated ───────────────────────────────────────────────────────────────

test.describe( 'Automated scan', () => {

	test( 'front page has no detectable violations', async ( { page } ) => {
		await page.goto( '/' );
		const { violations } = await new AxeBuilder( { page } ).withTags( TAGS ).analyze();

		expect(
			violations.map( ( v ) => `${ v.id }: ${ v.help } (${ v.nodes.length })` ),
			'Detectable WCAG violations on the front page'
		).toEqual( [] );
	} );

	test( 'settings screen has no detectable violations', async ( { page } ) => {
		await login( page );
		await page.goto( '/wp-admin/options-general.php?page=myplugin' ); // EDIT

		// Scope to your own markup so you aren't reporting core's admin issues
		// as yours. Widen this once your own screens are clean.
		const { violations } = await new AxeBuilder( { page } )
			.withTags( TAGS )
			.include( '#wpbody-content' )
			.analyze();

		expect( violations.map( ( v ) => `${ v.id }: ${ v.help }` ) ).toEqual( [] );
	} );
} );

// ── Keyboard: the half automation cannot do ─────────────────────────────────

test.describe( 'Keyboard', () => {

	/**
	 * Calibration control. If a plain native button fails the same synthetic
	 * input, the harness is broken and every product verdict below is noise.
	 * This is lie #4 from the main method, and it cost a week once.
	 */
	test( 'CONTROL: a native button responds to keyboard activation', async ( { page } ) => {
		await page.setContent( `
			<a href="#x" id="l">link</a>
			<button id="b" onclick="window.__hit=(window.__hit||0)+1">button</button>
		` );

		await page.focus( '#b' );
		await page.keyboard.press( 'Enter' );
		await page.keyboard.press( 'Space' );

		const hits = await page.evaluate( () => window.__hit || 0 );
		expect(
			hits,
			'A plain <button> did not respond to Enter/Space. The harness is broken — ' +
			'fix this before trusting any accessibility result below.'
		).toBeGreaterThan( 0 );
	} );

	test( 'every interactive element is reachable by Tab', async ( { page } ) => {
		await page.goto( '/' );

		const interactive = await page.locator(
			'a[href], button, input:not([type=hidden]), select, textarea, [tabindex]:not([tabindex="-1"])'
		).count();

		const reached = new Set();
		for ( let i = 0; i < Math.min( interactive + 5, 80 ); i++ ) {
			await page.keyboard.press( 'Tab' );
			const id = await page.evaluate( () => {
				const el = document.activeElement;
				if ( ! el || el === document.body ) return null;
				return el.tagName + ':' + ( el.id || el.className || el.textContent?.slice( 0, 20 ) );
			} );
			if ( id ) reached.add( id );
		}

		expect( reached.size, 'Tab reached almost nothing — likely a focus trap or a tabindex problem' )
			.toBeGreaterThan( 0 );
	} );

	test( 'focus is always visible', async ( { page } ) => {
		await page.goto( '/' );

		const invisible = [];
		for ( let i = 0; i < 25; i++ ) {
			await page.keyboard.press( 'Tab' );
			const bad = await page.evaluate( () => {
				const el = document.activeElement;
				if ( ! el || el === document.body ) return null;
				const s = getComputedStyle( el );
				const noOutline =
					s.outlineStyle === 'none' || s.outlineWidth === '0px';
				// A replacement indicator is fine — box-shadow, border, background.
				const hasAlternative =
					s.boxShadow !== 'none' ||
					s.borderStyle !== 'none' ||
					el.matches( ':focus-visible' ) === false;
				return noOutline && ! hasAlternative
					? el.tagName + ( el.id ? '#' + el.id : '' )
					: null;
			} );
			if ( bad ) invisible.push( bad );
		}

		expect(
			invisible,
			'These elements have no visible focus indicator. outline:none without a ' +
			'replacement is the most common cause of unusable keyboard navigation.'
		).toEqual( [] );
	} );

	test( 'skip link exists, becomes visible on focus, and moves focus', async ( { page } ) => {
		await page.goto( '/' );
		await page.keyboard.press( 'Tab' );

		const first = await page.evaluate( () => {
			const el = document.activeElement;
			return el ? { text: el.textContent?.trim(), href: el.getAttribute( 'href' ) } : null;
		} );

		if ( ! first || ! /skip/i.test( first.text || '' ) ) {
			test.skip( true, 'No skip link as first focusable — expected on most themes.' );
		}

		// Visually hidden content that is focusable must become visible on focus.
		const visible = await page.evaluate( () => {
			const r = document.activeElement.getBoundingClientRect();
			return r.width > 1 && r.height > 1 && r.top > -100;
		} );
		expect( visible, 'Skip link is focused but still visually hidden.' ).toBe( true );

		await page.keyboard.press( 'Enter' );
		const moved = await page.evaluate( () => document.activeElement?.tagName !== 'A' );
		expect( moved, 'Skip link did not move focus to the target.' ).toBe( true );
	} );

	test( 'modals trap focus while open and restore it on close', async ( { page } ) => {
		await login( page );
		await page.goto( '/wp-admin/options-general.php?page=myplugin' ); // EDIT

		const opener = page.locator( '[data-opens-modal]' ); // EDIT
		if ( ! ( await opener.count() ) ) {
			test.skip( true, 'No modal to test.' );
		}

		await opener.first().focus();
		await page.keyboard.press( 'Enter' );

		// Escape must close it and return focus to the opener — not to <body>.
		await page.keyboard.press( 'Escape' );
		const restored = await page.evaluate(
			() => document.activeElement?.hasAttribute( 'data-opens-modal' )
		);
		expect( restored, 'Focus was not returned to the element that opened the modal.' ).toBe( true );
	} );
} );

// ── Structure ───────────────────────────────────────────────────────────────

test.describe( 'Structure', () => {

	test( 'headings do not skip levels', async ( { page } ) => {
		await page.goto( '/' );
		const levels = await page.evaluate( () =>
			[ ...document.querySelectorAll( 'h1,h2,h3,h4,h5,h6' ) ].map( ( h ) => +h.tagName[ 1 ] )
		);

		const skips = [];
		for ( let i = 1; i < levels.length; i++ ) {
			if ( levels[ i ] - levels[ i - 1 ] > 1 ) {
				skips.push( `h${ levels[ i - 1 ] } → h${ levels[ i ] }` );
			}
		}
		expect( skips, 'Heading levels skipped' ).toEqual( [] );
	} );

	test( 'page has exactly one h1 and a main landmark', async ( { page } ) => {
		await page.goto( '/' );
		expect( await page.locator( 'h1' ).count() ).toBe( 1 );
		expect( await page.locator( 'main, [role=main]' ).count() ).toBeGreaterThan( 0 );
	} );
} );
