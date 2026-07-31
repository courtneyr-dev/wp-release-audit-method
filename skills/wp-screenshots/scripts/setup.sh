#!/usr/bin/env bash
# setup.sh — idempotent installer for wp-screenshots.
#
# What it does:
#   1. Verifies node + npm are available.
#   2. Verifies a Chromium/Chrome binary is reachable (or warns).
#   3. Runs `npm install` if node_modules is missing.
#   4. Runs a font advisory check (Inter alias for Mac-faithful admin shots).
#   5. Writes an install receipt so re-runs are fast no-ops.
#
# Safe to re-run. Pass --force to reinstall, --yes for unattended.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wp-screenshots"
RECEIPT="$CONFIG_DIR/.installed"

ASSUME_YES=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    --force) FORCE=1 ;;
    --help|-h)
      sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

log()  { printf '[wp-screenshots] %s\n' "$*"; }
warn() { printf '[wp-screenshots] WARN: %s\n' "$*" >&2; }
die()  { printf '[wp-screenshots] ERROR: %s\n' "$*" >&2; exit 1; }

# 1. Skip if already installed and node_modules still exists
if [[ -f "$RECEIPT" && -d "$SKILL_DIR/node_modules" && $FORCE -eq 0 ]]; then
  log "already installed — receipt at $RECEIPT"
  log "re-run with --force to reinstall"
  exit 0
fi

# 2. Verify node + npm
command -v node >/dev/null 2>&1 || die "node is required but not on PATH"
command -v npm  >/dev/null 2>&1 || die "npm is required but not on PATH"

# 3. Check for Chromium / Chrome
chromium_found=""
for candidate in \
  "${WP_SCREENSHOTS_CHROMIUM:-}" \
  "${PUPPETEER_EXECUTABLE_PATH:-}" \
  /usr/bin/chromium-browser \
  /usr/bin/chromium \
  /usr/bin/google-chrome \
  /usr/bin/google-chrome-stable \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    chromium_found="$candidate"
    break
  fi
done

if [[ -n "$chromium_found" ]]; then
  log "chromium: $chromium_found"
else
  warn "no Chromium/Chrome found on PATH or in known locations"
  warn "install one of:"
  warn "  Debian/Ubuntu: sudo apt install chromium-browser"
  warn "  macOS:         brew install --cask google-chrome"
  warn "  Or set WP_SCREENSHOTS_CHROMIUM=/path/to/chrome"
fi

# 4. Install npm deps
cd "$SKILL_DIR"
if [[ -d node_modules && $FORCE -eq 0 ]]; then
  log "node_modules present — skipping npm install"
else
  log "running npm install..."
  npm install --no-audit --no-fund
fi

# 5. Smoke-check: file parses, and puppeteer-core resolves
if ! node --check scripts/capture.mjs >/dev/null 2>&1; then
  warn "scripts/capture.mjs failed to parse"
fi
if ! node -e "import('puppeteer-core').then(() => process.exit(0)).catch(e => { console.error(e.message); process.exit(1); })" >/dev/null 2>&1; then
  warn "puppeteer-core failed to import — deps may be incomplete"
  warn "try: rm -rf node_modules && bash scripts/setup.sh --force"
fi

# 6. Font advisory — Mac-faithful WordPress admin rendering on Linux
if command -v fc-match >/dev/null 2>&1; then
  system_ui="$(fc-match -f '%{family}' :family='system-ui' 2>/dev/null || true)"
  apple="$(fc-match -f '%{family}' :family='-apple-system' 2>/dev/null || true)"
  if [[ "$system_ui" != *Inter* && "$apple" != *Inter* ]]; then
    log "tip: WordPress admin uses system-ui / -apple-system. On Linux these"
    log "     resolve to DejaVu/Roboto by default, which makes Mac viewers"
    log "     read shots as 'off.' To install the Inter alias config:"
    log "       mkdir -p ~/.config/fontconfig/conf.d"
    log "       cp $SKILL_DIR/scripts/fontconfig/50-system-ui-aliases.conf \\"
    log "          ~/.config/fontconfig/conf.d/"
    log "       fc-cache -f"
    log "     Plus install the Inter font if you don't have it:"
    log "       sudo apt install fonts-inter   # or download from rsms.me/inter"
  else
    log "font alias OK (system-ui -> $system_ui)"
  fi
else
  warn "fc-match not found — can't verify font aliasing. Skipping font advisory."
fi

# 7. Write install receipt
mkdir -p "$CONFIG_DIR"
{
  printf 'installed_at=%s\n' "$(date -Iseconds)"
  printf 'skill_dir=%s\n' "$SKILL_DIR"
  printf 'node_version=%s\n' "$(node --version)"
  printf 'chromium=%s\n' "${chromium_found:-not-found}"
} > "$RECEIPT"

log "done. Try:"
log "  node scripts/verify-site.mjs --site https://example.com"
log "  node scripts/capture.mjs --brief briefs/example.json --site https://example.com"
