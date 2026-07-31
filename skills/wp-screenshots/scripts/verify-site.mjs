#!/usr/bin/env node
/**
 * wp-screenshots / verify-site
 *
 * Sanity-check a WordPress site before capturing screenshots.
 * Verifies homepage reachability, admin login (if credentials given),
 * and surfaces red bubbles, update nags, error notices, and PHP warnings.
 *
 * Exits non-zero on any FAIL so a CI runner / cron / agent can stop.
 *
 * Usage:
 *   node verify-site.mjs --site https://example.com
 *   node verify-site.mjs --site https://example.com --user admin --pass-env WP_PASS
 *
 * If --user / password is not supplied, only the homepage check runs.
 */

import puppeteer from 'puppeteer-core';
import { existsSync, mkdtempSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseArgs } from 'node:util';

const CHROMIUM_CANDIDATES = [
  process.env.WP_SCREENSHOTS_CHROMIUM,
  process.env.PUPPETEER_EXECUTABLE_PATH,
  '/usr/bin/chromium-browser',
  '/usr/bin/chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
].filter(Boolean);

function findChromium() {
  const cacheRoot = join(process.env.HOME || '', '.cache/puppeteer/chrome');
  if (existsSync(cacheRoot)) {
    try {
      const dirs = readdirSync(cacheRoot).sort().reverse();
      for (const d of dirs) {
        const p = join(cacheRoot, d, 'chrome-linux64/chrome');
        if (existsSync(p)) return p;
        const m = join(cacheRoot, d, 'chrome-mac/Chromium.app/Contents/MacOS/Chromium');
        if (existsSync(m)) return m;
      }
    } catch {}
  }
  for (const c of CHROMIUM_CANDIDATES) if (c && existsSync(c)) return c;
  return null;
}

const { values } = parseArgs({
  options: {
    site:       { type: 'string' },
    user:       { type: 'string' },
    pass:       { type: 'string' },
    'pass-env': { type: 'string' },
    help:       { type: 'boolean' },
  },
  strict: false,
});

if (values.help || !values.site) {
  console.log(`Usage: node verify-site.mjs --site <url> [--user <u>] [--pass-env <ENV>]`);
  process.exit(values.help ? 0 : 1);
}

const SITE = values.site.replace(/\/+$/, '');
const USER = values.user || '';
const PASS = values.pass || (values['pass-env'] ? process.env[values['pass-env']] : '') || '';

const chromium = findChromium();
if (!chromium) {
  console.error('FAIL: no Chromium/Chrome binary found.');
  console.error('  Set WP_SCREENSHOTS_CHROMIUM=/path/to/chrome or install chromium-browser.');
  process.exit(2);
}

const checks = [];
function note(level, msg) { checks.push({ level, msg }); console.log(`[${level}] ${msg}`); }

async function main() {
  const browser = await puppeteer.launch({
    executablePath: chromium,
    headless: true,
    args: ['--no-sandbox', '--ignore-certificate-errors', '--disable-dev-shm-usage'],
    defaultViewport: { width: 1600, height: 1000, deviceScaleFactor: 2 },
  });

  const page = await browser.newPage();
  page.on('dialog', d => d.dismiss().catch(() => {}));

  // 1. Homepage reachable.
  try {
    const resp = await page.goto(`${SITE}/`, { waitUntil: 'domcontentloaded', timeout: 15000 });
    if (!resp || !resp.ok()) {
      note('FAIL', `homepage HTTP ${resp ? resp.status() : 'no response'}`);
    } else {
      note('OK', `homepage ${resp.status()}`);
    }
  } catch (e) {
    note('FAIL', `homepage: ${e.message}`);
  }

  // 2. Login + dashboard health (only if credentials given).
  if (USER && PASS) {
    try {
      await page.goto(`${SITE}/wp-login.php`, { waitUntil: 'domcontentloaded', timeout: 15000 });
      await page.waitForSelector('#user_login', { timeout: 5000 });
      await page.type('#user_login', USER);
      await page.type('#user_pass', PASS);
      await Promise.all([
        page.click('#wp-submit'),
        page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 30000 }),
      ]);
      if (page.url().includes('/wp-admin/')) {
        note('OK', 'logged in');
      } else {
        note('FAIL', `login did not reach /wp-admin (now at ${page.url()})`);
      }
    } catch (e) {
      note('FAIL', `login: ${e.message}`);
    }

    try {
      await page.goto(`${SITE}/wp-admin/`, { waitUntil: 'networkidle2', timeout: 30000 });
      const findings = await page.evaluate(() => {
        const out = { updateBubble: 0, errorNotices: 0, php_warnings: 0 };
        const updates = document.querySelector('.update-plugins .update-count, .menu-counter');
        if (updates) {
          const n = parseInt(updates.textContent || '0', 10);
          if (n > 0) out.updateBubble = n;
        }
        out.errorNotices = document.querySelectorAll('.notice-error, .notice-warning').length;
        const txt = document.body.innerText || '';
        if (/Warning:.*on line \d+/.test(txt)) out.php_warnings = 1;
        if (/Notice:.*on line \d+/.test(txt))  out.php_warnings += 1;
        return out;
      });
      if (findings.updateBubble > 0) note('WARN', `${findings.updateBubble} pending plugin/core updates`);
      else                            note('OK',   'no pending updates');
      if (findings.errorNotices > 0)  note('WARN', `${findings.errorNotices} error/warning notices on dashboard`);
      else                            note('OK',   'no error notices');
      if (findings.php_warnings > 0)  note('WARN', `${findings.php_warnings} PHP warnings on page`);
    } catch (e) {
      note('FAIL', `dashboard check: ${e.message}`);
    }

    try {
      const dir = mkdtempSync(join(tmpdir(), 'wp-verify-'));
      const ref = join(dir, 'dashboard.png');
      await page.screenshot({ path: ref, type: 'png' });
      note('OK', `reference shot saved: ${ref}`);
    } catch (e) {
      note('WARN', `reference shot: ${e.message}`);
    }
  } else {
    note('OK', 'no credentials supplied — skipping admin checks');
  }

  await browser.close();

  const failures = checks.filter(c => c.level === 'FAIL').length;
  const warnings = checks.filter(c => c.level === 'WARN').length;
  console.log(`\nSummary: ${checks.length - failures - warnings} OK, ${warnings} warn, ${failures} fail`);
  process.exit(failures > 0 ? 1 : 0);
}

main().catch(e => { console.error('FAIL:', e); process.exit(2); });
