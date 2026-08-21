#!/usr/bin/env bash
# Hook-key-type probe: walk $wp_filter on a live fixture and report the PHP type
# of every callback key, plus which plugins and themes register closures on which
# hooks at which priorities.
#
# Why this exists: WordPress 7.1 changed _wp_filter_build_unique_id() from
# spl_object_hash() (32-char hex string) to spl_object_id() (small integer cast
# to string). PHP silently converts numeric string array keys to int, so hook
# callback keys that were always strings became integers — and plugin code doing
# string operations on those keys fatals under strict_types (the WP Rocket 7.1
# release-day outage; Trac #65919). The fatal needs a THIRD party registering a
# closure on the right hook, which is exactly what this probe enumerates. See
# method/ecosystem-compatibility-lane.md.
#
# Usage — same conventions as assert_multisite_denominator.sh:
#   scripts/hook-key-type-probe.sh [site-path]
#   WP_AUDIT_WP="ddev wp" scripts/hook-key-type-probe.sh ~/fixture
#
#   --control positive   register a closure on deleted_post@10 in-process and
#                        require the probe to SEE it (exit 4 if it doesn't)
#   --control negative   register a named function there instead and require the
#                        probe to report NO closure at that hook (exit 4 if it
#                        finds one)
#
# The controls ship in the probe because a detector that has never failed a
# control has never been calibrated. Run both before trusting a reading.
#
# Exit codes: 0 probe ran (report only) · 2 setup error · 4 control miscalibration
set -uo pipefail

CONTROL=""
SITE="."
while [ $# -gt 0 ]; do
  case "$1" in
    --control) CONTROL="${2:?--control needs positive|negative}"; shift 2 ;;
    *) SITE="$1"; shift ;;
  esac
done

read -r -a WP <<< "${WP_AUDIT_WP:-wp}"
run_wp() { "${WP[@]}" --path="$SITE" "$@"; }

if ! run_wp core is-installed >/dev/null 2>&1; then
  echo "ERROR: no WordPress install at $SITE (or wp not runnable)"; exit 2
fi

# The probe file goes INSIDE the site path, not in host tmp: wrapped CLIs
# (ddev/lando/studio) run wp in a container that can only see the mounted
# docroot. A host mktemp path made eval-file fail on the first live run.
PROBE="$SITE/.wp-audit-hook-key-probe.$$.php"
trap 'rm -f "$PROBE"' EXIT
cat > "$PROBE" <<'PHP'
<?php
// Controls register in-process so the probe must detect a registration made
// through the same add_action() path a real third plugin would use.
// The control mode arrives as an eval-file positional arg, NOT an env var —
// wrapped CLIs (ddev/lando) do not forward arbitrary host env into the
// container. The first live run proved it: the env-var version registered
// nothing, and the negative control "passed" vacuously.
$control = isset( $args[0] ) ? $args[0] : '';
$control_closure = null;
$control_registered = 0;
if ( 'positive' === $control ) {
	$control_closure = function ( $post_id ) {};
	add_action( 'deleted_post', $control_closure, 10 );
	$control_registered = 1;
} elseif ( 'negative' === $control ) {
	function wp_audit_probe_named_cb() {}
	add_action( 'deleted_post', 'wp_audit_probe_named_cb', 10 );
	$control_registered = ( false !== has_action( 'deleted_post', 'wp_audit_probe_named_cb' ) ) ? 1 : 0;
}
$saw_control_closure = 0;

global $wp_filter;
$int_keys = 0;
$string_keys = 0;
$closures = array();
$mixed = array();
foreach ( $wp_filter as $hook_name => $hook ) {
	if ( ! ( $hook instanceof WP_Hook ) ) {
		continue;
	}
	foreach ( $hook->callbacks as $priority => $cbs ) {
		$pri_int = 0;
		$pri_str = 0;
		foreach ( $cbs as $idx => $cb ) {
			if ( is_int( $idx ) ) { $int_keys++; $pri_int++; } else { $string_keys++; $pri_str++; }
			$fn = $cb['function'];
			if ( null !== $control_closure && $fn === $control_closure ) {
				// Identity comparison, not source matching — eval-file runs
				// through eval(), so the closure has no usable file name.
				$saw_control_closure = 1;
			}
			if ( $fn instanceof Closure ) {
				$r = new ReflectionFunction( $fn );
				$file = $r->getFileName() ? $r->getFileName() : '(internal)';
				$owner = '(core or unattributed)';
				if ( preg_match( '#/(mu-plugins|plugins|themes)/([^/]+)#', $file, $m ) ) {
					$owner = $m[1] . '/' . $m[2];
				}
				$closures[] = sprintf(
					'CLOSURE hook=%s priority=%s key_type=%s owner=%s source=%s:%d',
					$hook_name, $priority, is_int( $idx ) ? 'int' : 'string',
					$owner, $file, (int) $r->getStartLine()
				);
			}
		}
		if ( $pri_int && $pri_str ) {
			$mixed[] = sprintf( 'MIXED-KEYS hook=%s priority=%s int=%d string=%d', $hook_name, $priority, $pri_int, $pri_str );
		}
	}
}
printf( "wp_version=%s\n", get_bloginfo( 'version' ) );
printf( "callback_keys int=%d string=%d\n", $int_keys, $string_keys );
printf( "closure_registrations=%d\n", count( $closures ) );
foreach ( $closures as $c ) { echo $c, "\n"; }
foreach ( $mixed as $m2 ) { echo $m2, "\n"; }
if ( '' !== $control ) {
	printf( "CONTROL mode=%s registered=%d saw_control_closure=%d\n", $control, $control_registered, $saw_control_closure );
}
if ( $int_keys > 0 ) {
	echo "NOTE: int keys present — this tree carries the 7.1 spl_object_id() behavior.\n";
	echo "      Plugin code doing string ops on \$wp_filter keys fatals here under strict_types.\n";
} else {
	echo "NOTE: all keys are strings — pre-7.1 spl_object_hash() behavior.\n";
}
PHP

OUT=$(run_wp eval-file "$PROBE" "$CONTROL" 2>&1) || {
  echo "ERROR: probe did not run:"; echo "$OUT"; exit 2; }
echo "$OUT"

case "$CONTROL" in
  positive)
    # The PHP asserts by closure IDENTITY (the walk saw the exact closure the
    # control registered) — file-name matching is impossible through eval-file.
    if echo "$OUT" | grep -q 'CONTROL mode=positive registered=1 saw_control_closure=1'; then
      echo "CONTROL-PASS positive: the walk saw the exact closure the control registered"
    else
      echo "CONTROL-FAIL positive: a closure was registered on deleted_post@10 and the walk missed it"
      exit 4
    fi ;;
  negative)
    if echo "$OUT" | grep -q 'CONTROL mode=negative registered=1 saw_control_closure=0'; then
      echo "CONTROL-PASS negative: named-function registration present, not misread as a closure"
    else
      echo "CONTROL-FAIL negative: either the registration failed or it was misread as a closure"
      exit 4
    fi ;;
esac
exit 0
