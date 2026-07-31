<?php
$cases = array(
	'legacy-url'          => 'background-image: url("https://example.test/image.jpg")',
	'legacy-shorthand'    => 'background: url("https://example.test/image.jpg") center / cover no-repeat',
	'gradient-only'       => 'background-image: linear-gradient(red, blue)',
	'gradient-plus-url'   => 'background-image: linear-gradient(red, blue), url("https://example.test/image.jpg")',
	'gradient-url-tight'  => 'background-image: linear-gradient(red,blue),url(https://example.test/image.jpg)',
	'background-repeat'   => 'background-repeat: no-repeat',
	'background-position' => 'background-position: center',
	'ordinary-color'      => 'color: red',
	'unsafe-js-url'       => 'background-image: url("javascript:alert(1)")',
	'unsafe-js-shorthand' => 'background: url("javascript:alert(1)")',
);

foreach ( $cases as $case => $input ) {
	echo wp_json_encode(
		array(
			'case'     => $case,
			'input'    => $input,
			'observed' => safecss_filter_attr( $input ),
		),
		JSON_UNESCAPED_SLASHES
	) . PHP_EOL;
}

