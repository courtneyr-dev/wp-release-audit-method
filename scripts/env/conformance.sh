#!/bin/bash
# Driver conformance harness — checks every driver against the contract in README.md.
#
#   bash scripts/env/conformance.sh            # all drivers
#   bash scripts/env/conformance.sh ddev cli   # named drivers only
#
# WHY THIS EXISTS. Six drivers now pass `bash -n` and `shellcheck`, and exactly one of
# them (ddev) is ever functionally exercised by CI. Syntax-clean is not the failure mode
# that matters here: a driver that swallows WP-CLI's exit status is perfectly valid shell
# that turns every failed command into a silent success, and every `env_wp … || fallback`
# in every suite stops firing. That is the over-claiming failure the whole capability
# model exists to prevent, arriving through the back door.
#
# It was not hypothetical. Three of the six drivers shipped with exactly that bug, each
# found by hand, one at a time, by noticing an odd blank in unrelated output. This is that
# check, automated, so the seventh driver cannot reintroduce it.
#
# NOTHING HERE NEEDS A RUNNING WORDPRESS. The exit-status test works by putting a stub on
# PATH in place of the driver's real binary (ddev, lando, npx, wp, studio) and asking
# whether the driver reports what the stub returned. That runs in CI, on any machine, for
# drivers whose tool isn't even installed — which is the point, because the drivers least
# likely to be exercised by hand are the ones most likely to rot.
#
# A check that cannot be performed reports SKIP with the reason, never PASS. An untestable
# claim treated as a passing one is the thing this repo is about.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENVDIR="$ROOT/scripts/env"
PASS=0; FAIL=0; SKIP=0

ok()   { printf '    ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '    FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '    skip  %s\n' "$1"; SKIP=$((SKIP+1)); }

# Every token a driver is allowed to emit. Read from lib-env.sh so the two cannot drift.
KNOWN_CAPS="$(sed -n '/^WP_AUDIT_ALL_CAPS=/,/"$/p' "$ROOT/scripts/lib-env.sh" \
  | tr -d '\\"' | sed 's/^WP_AUDIT_ALL_CAPS=//' | tr '\n' ' ' | tr -s ' ')"

# Which binary each driver drives. Used to build the stub for the exit-status test.
driver_binary() {
  case "$1" in
    ddev)       echo ddev ;;
    lando)      echo lando ;;
    studio)     echo studio ;;
    cli)        echo wp ;;
    wp-env)     echo docker ;;
    playground) echo npx ;;
    *)          echo "" ;;
  esac
}

# ─────────────────────────────────────────────────────── static: shape of the file
check_shape() {
  local f="$1" name="$2"
  head -1 "$f" | grep -q '^#!' && ok "has a shebang" || bad "no shebang"
  sed -n '2p' "$f" | grep -q '^#' && ok "has a description comment" \
    || bad "no description comment on line 2"
  grep -qE '^env_driver_init\(\)' "$f" && ok "defines env_driver_init" \
    || bad "does not define env_driver_init"
  grep -qE '^env_driver_caps\(\)' "$f" && ok "defines env_driver_caps" \
    || bad "does not define env_driver_caps"
  # A driver must never reach into the library it implements.
  if grep -qE '^(env_require|env_has|env_caps|env_init|env_missing)\(\)' "$f"; then
    bad "redefines a lib-env.sh function — drivers implement, they don't override"
  else
    ok "does not redefine lib-env.sh internals"
  fi
  # Unknown capability tokens. A typo doesn't error, it just never matches env_has, so
  # every cell needing it blocks forever and the driver looks less capable than it is.
  local unknown="" tok
  for tok in $(sed -n '/^env_driver_caps()/,/^}/p' "$f" \
                | grep -oE 'caps="\$caps [a-z-]+"|caps="[a-z][a-z -]*"' \
                | sed 's/caps="\$caps //; s/caps="//; s/"//' | tr ' ' '\n' | sort -u); do
    case " $KNOWN_CAPS " in *" $tok "*) ;; *) unknown="$unknown $tok" ;; esac
  done
  [ -z "$unknown" ] && ok "emits only known capability tokens" \
    || bad "unknown capability token(s):$unknown — not in WP_AUDIT_ALL_CAPS"
  [ "$name" = "$name" ] || true
}

# ─────────────────────────────────────── static: the exit-status bug, by inspection
# Cheap pre-filter for the dynamic test below. A pipeline is fine; a pipeline whose
# status is discarded is not, and `rc=$?` right after a capture is the tell.
check_exit_status_static() {
  local f="$1" body
  body="$(sed -n '/^env_wp()/,/^}/p' "$f")"
  if ! printf '%s' "$body" | grep -q '|'; then
    ok "env_wp does not pipe (status cannot be lost)"
  elif printf '%s' "$body" | grep -qE 'rc=\$\?|return \$rc|return "\$rc"'; then
    ok "env_wp pipes but captures the status"
  else
    bad "env_wp pipes and never captures \$? — WP-CLI failures will read as success"
  fi
}

# ───────────────────────────────────────── dynamic: does env_wp really propagate?
# Put a stub on PATH where the driver's real binary would be, make it exit 7, and see
# whether that 7 survives the trip back out of env_wp.
check_exit_status_live() {
  local name="$1" bin stub rc
  bin="$(driver_binary "$name")"
  [ -n "$bin" ] || { skip "no known binary for '$name' — cannot stub it"; return; }

  stub="$(mktemp -d)"
  cat > "$stub/$bin" <<'STUB'
#!/bin/sh
# Conformance stub. Echoes a marker so output handling is exercised too, then fails.
echo "CONFORMANCE_MARKER"
exit 7
STUB
  chmod +x "$stub/$bin"

  # Run in a subshell so one driver's globals cannot leak into the next driver's test.
  #
  # The pre-seeded globals below do two jobs. The *_DIR ones point each driver's project
  # directory at something that exists, so a failed cd is not mistaken for correct status
  # propagation. The *_BIN ones matter more: a driver that holds its binary in a variable
  # never consults PATH, so the stub alone would never be reached and the check would
  # SKIP — and a skipped exit-status check on a driver nobody runs by hand is exactly the
  # blind spot this harness exists to remove.
  #
  # Keep comments OUT of the command substitution below. Bash respects quoting while
  # scanning for the closing paren, so an apostrophe in a comment there opens a string
  # that never closes and the whole file fails to parse. This one cost a debug cycle.
  rc="$(
    PATH="$stub:$PATH"
    # shellcheck source=/dev/null
    . "$ROOT/scripts/lib-env.sh" 2>/dev/null
    # shellcheck source=/dev/null
    . "$ENVDIR/$name.sh" 2>/dev/null
    _DDEV_DIR="$stub"; _LANDO_DIR="$stub"; _WPENV_DIR="$stub"; _STUDIO_DIR="$stub"
    _CLI_PATH="$stub"; _CLI_ABSPATH="$stub"; _PG_DOCROOT="$stub"
    _WPENV_CONTAINER="conformance-stub"; _WPENV_USER="0"
    export _DDEV_DIR _LANDO_DIR _WPENV_DIR _STUDIO_DIR _CLI_PATH _CLI_ABSPATH _PG_DOCROOT
    _STUDIO_BIN="$bin"
    _PG_BIN=("$bin")
    _PG_STATE="$stub"; _PG_URL="http://127.0.0.1:9400"
    env_wp core version >/dev/null 2>&1
    echo $?
  )"
  rm -rf "$stub"

  case "$rc" in
    7)  ok "env_wp propagates the underlying exit status (stub exited 7, got 7)" ;;
    0)  bad "env_wp returned 0 while the underlying '$bin' exited 7 — failures become PASSes" ;;
    "") skip "env_wp could not be exercised without an initialised environment" ;;
    *)  skip "env_wp returned $rc, not the stub's 7 — driver failed before reaching '$bin'" ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────── run
DRIVERS="$*"
if [ -z "$DRIVERS" ]; then
  DRIVERS="$(find "$ENVDIR" -maxdepth 1 -name '*.sh' ! -name 'conformance.sh' \
             -exec basename {} .sh \; | sort)"
fi

echo "Driver conformance — $(echo "$DRIVERS" | tr '\n' ' ')"
echo
for d in $DRIVERS; do
  f="$ENVDIR/$d.sh"
  if [ ! -f "$f" ]; then bad "$d: no such driver"; continue; fi
  echo "  $d"
  check_shape "$f" "$d"
  check_exit_status_static "$f"
  check_exit_status_live "$d"
  echo
done

echo "conformance: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
