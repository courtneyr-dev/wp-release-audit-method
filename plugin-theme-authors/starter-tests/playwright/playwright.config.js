/**
 * Playwright config for WordPress extension testing.
 *
 * Assumes wp-env at http://localhost:8888 with admin/password.
 * EDIT baseURL if yours differs.
 */

const { defineConfig, devices } = require( '@playwright/test' );

module.exports = defineConfig( {
	testDir: '.',
	// The editor is slow to boot, especially on a cold container.
	timeout: 60_000,
	expect: { timeout: 15_000 },

	// Serial by default: these tests mutate shared site state, and parallel
	// runs against one WordPress install produce failures that look like
	// product bugs but are test interference.
	fullyParallel: false,
	workers: 1,

	forbidOnly: !! process.env.CI,
	retries: process.env.CI ? 1 : 0,

	reporter: process.env.CI
		? [ [ 'github' ], [ 'html', { open: 'never' } ] ]
		: [ [ 'list' ] ],

	use: {
		baseURL: process.env.WP_BASE_URL || 'http://localhost:8888',
		trace: 'retain-on-failure',
		screenshot: 'only-on-failure',
		video: 'retain-on-failure',
		actionTimeout: 15_000,
	},

	projects: [
		{
			name: 'chromium',
			use: { ...devices[ 'Desktop Chrome' ] },
		},
		// Uncomment to check the browsers where client-side features fall back
		// to server-side paths — behavior can differ meaningfully.
		// { name: 'firefox', use: { ...devices[ 'Desktop Firefox' ] } },
		// { name: 'webkit',  use: { ...devices[ 'Desktop Safari' ] } },
	],
} );
