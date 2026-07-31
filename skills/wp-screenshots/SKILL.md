---
name: wp-screenshots
description: Capture clean, Mac-faithful WordPress admin + front-end screenshots from a JSON brief. Headless Chromium, login-aware, hides update bubbles and admin notices, defaults to 2× DPR, and writes a standalone HTML gallery alongside the PNGs. Works against any WordPress site you have credentials for.
---

# wp-screenshots

A reusable harness for taking shippable screenshots of a WordPress site for docs, release posts, marketing assets, or change-review.

You write a **brief** (a small JSON file listing each shot — URL, viewport, hover/click targets, whether to log in), then run `capture.mjs` against your site. The harness handles login, hides WP admin notices and update bubbles, captures at retina DPR, and produces PNGs in a folder you can ship or zip.

This skill is intentionally generic — it works on any WordPress site (your own, a staging site, a local docker, a custom theme demo). Don't point it at production sites you don't own.

## Why this exists

Taking marketing-quality WP screenshots by hand is fiddly:

- Update bubbles, plugin nag notices, and PMPro/Yoast banners ruin every shot.
- Login state matters — half your shots want a logged-in admin, half want a fresh anonymous visitor.
- The Customizer is async; you need to wait long enough for panels to render.
- Filenames and viewport sizes have to be consistent across a batch.
- Headless Chromium on Linux renders `system-ui` / `-apple-system` as DejaVu/Roboto by default, so the same site looks "wrong" to a Mac reviewer.

The harness handles all of that.

## Setup

```bash
bash scripts/setup.sh
```

Idempotent. Verifies node + npm, runs `npm install`, checks for Chromium/Chrome, surfaces a fontconfig advisory if Mac system fonts aren't aliased, writes a receipt at `~/.config/wp-screenshots/.installed`. Re-runs are no-ops unless `--force`.

See [skills/README.md](../README.md) for the install pattern.

### Optional: Mac-faithful fonts on Linux

If you're capturing on Linux and the resulting shots will be reviewed on macOS, install the system-font alias config so WordPress admin renders with Inter (close to SF) instead of DejaVu:

```bash
mkdir -p ~/.config/fontconfig/conf.d
cp scripts/fontconfig/50-system-ui-aliases.conf ~/.config/fontconfig/conf.d/
sudo apt install fonts-inter    # or download from https://rsms.me/inter/
fc-cache -f
```

Verify:

```bash
fc-match :family="system-ui"      # should resolve to Inter
```

If the target site uses a custom web font on its front-end (Memberlite uses Poppins, Astra uses its own stack, etc.), install that font locally too — headless Chromium won't fetch Google Fonts reliably under load. `setup.sh` warns you if the aliases are missing.

## Quick start

1. Copy `briefs/example.json` to `briefs/<your-topic>.json` and edit it.
2. Run the verifier (optional, but catches red banners early):

   ```bash
   node scripts/verify-site.mjs --site https://your-site.test \
                                --user admin --pass-env WP_SITE_PASS
   ```

3. Run the capture:

   ```bash
   WP_SITE_PASS='...' node scripts/capture.mjs \
     --brief briefs/<your-topic>.json
   ```

4. Build a quick HTML gallery of the results:

   ```bash
   node scripts/make-gallery.mjs --dir screenshots/<your-topic>
   ```

   Open `screenshots/<your-topic>/index.html` in a browser.

## Brief schema

A brief is JSON with a top-level config and an array of `shots`:

```json
{
  "topic": "my-release",
  "site": "https://staging.example.com",
  "auth": { "user": "admin", "passEnv": "WP_SITE_PASS" },
  "outDir": "screenshots/my-release",
  "dpr": 2,
  "shots": [ ... ]
}
```

### Top-level fields

| Field | Required | Notes |
|---|---|---|
| `topic` | yes | kebab-case slug. Used as the default output folder name. |
| `site` | recommended | Base URL. Can be overridden with `--site`. |
| `auth.user` | only for admin shots | WP login username. |
| `auth.passEnv` | recommended | Name of an env var holding the password (don't commit secrets to briefs). |
| `auth.pass` | discouraged | Inline password fallback. Avoid. |
| `outDir` | no | Output folder (relative paths resolve against cwd). Default: `./screenshots/<topic>/`. |
| `dpr` | no | `deviceScaleFactor` for every shot. Default 2 (retina). Per-shot `dpr` overrides this. |
| `shots` | yes | Array of shot specs. |

### Shot fields

| Field | Required | Notes |
|---|---|---|
| `slug` | yes | Filename stem. Lowercase, hyphenated. `02-customizer-colors`. |
| `label` | no | Human caption used in the gallery. Defaults to a prettified slug. |
| `url` | yes | Path (`/wp-admin/...`) or full URL. Defaults relative to `site`. |
| `viewport` | no | `[width, height]`. Default `[1600, 1000]` for admin, `[1440, 900]` for front-end. |
| `dpr` | no | Override DPR for this shot. |
| `delay` | no | Extra ms to wait after `networkidle2`. Default 1500. Bump to 4000 for the Customizer. |
| `hideNotices` | no | Inject CSS to hide WP admin notices, update bubbles, plugin nags. Default: true for `/wp-admin/`, false for front-end. |
| `loggedOut` | no | Use a fresh non-auth browser context. Default false. |
| `scrollTo` | no | CSS selector to scroll into view before capture. |
| `hover` | no | CSS selector to hover (for tooltips). |
| `click` | no | CSS selector to click before capture. |
| `evaluateBefore` | no | JS string run in the page before capture (open an inserter, dismiss a modal, etc.). Use sparingly — flaky `evaluateBefore` is the #1 cause of bad shots. |
| `fullPage` | no | Capture the full scrollable page. Default false. |
| `section` | no | Free-form group tag for the gallery. |

## Translation tips

Common asks → brief patterns:

| User asks for | Use |
|---|---|
| "Show the X settings page" | Admin URL + `hideNotices: true`. Find the slug in the plugin's `admin.php?page=...`. |
| "Show the front-end of the homepage" | `url: "/"`, `loggedOut: true`. |
| "Show the Customizer's Colors panel" | `/?customize_changeset_uuid=&autofocus[section]=colors`, `delay: 4000`. |
| "Tooltip on the X button" | `hover: '.x-button'`, `delay: 1500`. |
| "The Site Editor's template panel" | `/wp-admin/site-editor.php`, `delay: 3000`, possibly `evaluateBefore` to open the panel. |
| "A block in the inserter" | `/wp-admin/post-new.php` + `evaluateBefore` to open the inserter and search for the block. |

## Running

```bash
node scripts/capture.mjs --brief briefs/<topic>.json
```

The harness:

- Logs in once with the auth credentials, reuses the session for all admin shots.
- Opens a fresh non-auth context for `loggedOut: true` shots.
- Injects the notice-hiding CSS for admin shots when `hideNotices` is true.
- Sets viewport + DPR per shot.
- Reports `OK` or `FAIL: <reason>` per shot.

Re-running overwrites existing PNGs with the same slug (idempotent).

### Useful flags

- `--site <url>` — override `brief.site`
- `--user <u>` — override `brief.auth.user`
- `--pass <p>` — inline password (prefer `--pass-env`)
- `--pass-env <NAME>` — env var to read password from
- `--out-dir <dir>` — override output folder
- `--only slug1,slug2` — capture just these slugs
- `--no-login` — skip login (briefs where every shot is `loggedOut: true`)

## Output

```
screenshots/<topic>/
├── 01-plugins-admin.png
├── 02-customizer-colors.png
├── 03-front-page-logged-out.png
└── index.html        # generated by make-gallery.mjs
```

## Verifying a site before capture

```bash
node scripts/verify-site.mjs --site https://your-site.test \
                             --user admin --pass-env WP_SITE_PASS
```

Reports: homepage status, login success, dashboard update bubbles, error/warning notices, PHP warnings on page. Exits non-zero on FAIL. Without credentials, only the homepage check runs.

## Building a gallery

```bash
node scripts/make-gallery.mjs --dir screenshots/<topic> \
                              --title "My release shots" \
                              --subtitle "staging.example.com"
```

Writes `index.html` directly into the screenshots folder. Open it in a browser to flip through shots, click any image for a lightbox. If a sibling `briefs/<topic>.json` exists, labels and `section` tags from the brief are used.

## Verifying each shot

Always look at every PNG before declaring done. Common failure modes:

- "You don't have permission" page → wrong URL slug; look it up in the target plugin's admin pages.
- Sticky header overlapping content on a front-end shot → `loggedOut: true` or scroll a tiny bit, or hide the sticky header for that shot.
- Empty state where data should be → the site doesn't have that data; either seed it or pick a different page.
- Cookie banner / tour intro / popover visible → add a selector to `evaluateBefore` to dismiss it, or extend the notice-hiding CSS in `capture.mjs`.
- Notice still visible → the default notice-hiding CSS doesn't match it. Either add a more specific selector, or add it to your own brief via `evaluateBefore`.

If a shot is unfixable in two iterations, drop it from the brief and note the gap. Don't ship a broken shot.

## Guardrails

- **Don't capture sites you don't own** — by default this skill is for your own staging / demo / docs sites.
- **Don't bake passwords into briefs** — use `auth.passEnv` and pass the secret via env var. Briefs are commit-safe; passwords are not.
- **Don't commit `node_modules` or screenshot output** — `.gitignore` them in your project.
- **Don't ship shots with notices, update bubbles, or PII** — verify each one.

## Uninstall

```bash
rm -rf node_modules
rm -f ~/.config/wp-screenshots/.installed
```

Optionally remove the fontconfig alias if you installed it:

```bash
rm ~/.config/fontconfig/conf.d/50-system-ui-aliases.conf
fc-cache -f
```
