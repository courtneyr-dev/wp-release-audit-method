#!/usr/bin/env node
// T2 browser cells of pilots/release-day/sweep-matrix.csv (T2-73 to T2-88), driven in a real admin UI.
//
//   node scripts/t2-browser-cells.mjs single  <base-url> <site-path> <out.jsonl>   # T2-73 to T2-86
//   node scripts/t2-browser-cells.mjs network <base-url> <site-path> <out.jsonl>   # T2-87, T2-88
//
// Run it twice, once against the build under test and once against the prior stable, on identical scratch
// content, then compare the two .jsonl files. The matrix expectation is "behaves as on the prior stable; no
// console errors", so a cell is a PASS only when both builds succeed and the build under test records no
// console error that the prior stable did not.
//
// Each cell acts in the UI and then reads the outcome back through WP-CLI, so a page that looks right but
// saved nothing fails. A failing cell keeps a screenshot next to the output file.
//
// Environment
//   WP_AUDIT_PASS             required. Password of the admin user (create a throwaway user on a scratch site).
//   WP_AUDIT_USER             admin user name. Default t2admin.
//   WP_AUDIT_WP               WP-CLI command, split on spaces. Default "wp". For a container, for example
//                             "docker exec -u www-data <name> php /usr/local/bin/wp" with <site-path> as the path in it.
//   WP_AUDIT_PLAYWRIGHT_FROM  a directory with node_modules/playwright. Default the current directory.
//   WP_AUDIT_CHROME           a browser executable. Default Playwright's own bundled Chromium. Never a branded Chrome.
//   WP_AUDIT_ONLY             comma list of cell ids to run, for example T2-79,T2-80.
//   WP_AUDIT_SUBSITE          network mode only. Slug of an existing subsite. Default t2sub.
//
// Preconditions, all on a scratch site
//   Served over HTTP with a router that handles pretty permalinks (wp server, or Apache for multisite; wp server
//   cannot route a subdirectory network). WP-Cron off (DISABLE_WP_CRON). Pretty permalinks on. Network mode needs a
//   subdirectory network with a super admin and one subsite. The classic theme twentytwentyone is installed from
//   WordPress.org when missing, so the machine needs network access.
//
// Known limits
//   Headless Chromium stalls on cross-document view transitions in the classic menu screen, on both builds, so they
//   are switched off at launch. A transition problem in a real browser would not show here. Each cell exercises one
//   path, not every control on the screen.
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [, , MODE, BASE_ARG, SITE, OUT] = process.argv;
if (!['single', 'network'].includes(MODE) || !BASE_ARG || !SITE || !OUT) {
  console.error('usage: t2-browser-cells.mjs <single|network> <base-url> <site-path> <out.jsonl>');
  process.exit(2);
}
const PASS = process.env.WP_AUDIT_PASS;
if (!PASS) { console.error('WP_AUDIT_PASS is required'); process.exit(2); }
const USER = process.env.WP_AUDIT_USER || 't2admin';
const BASE = BASE_ARG.replace(/\/$/, '');
const HOST = new URL(BASE).host;
const ONLY = process.env.WP_AUDIT_ONLY ? process.env.WP_AUDIT_ONLY.split(',') : null;
const SUBSITE = process.env.WP_AUDIT_SUBSITE || 't2sub';
const require = createRequire(path.resolve(process.env.WP_AUDIT_PLAYWRIGHT_FROM || process.cwd(), 'package.json'));
const { chromium } = require('playwright');
const [WP_BIN, ...WP_PRE] = (process.env.WP_AUDIT_WP || 'wp').split(/\s+/);
const wp = (...a) => execFileSync(WP_BIN, [...WP_PRE, `--path=${SITE}`, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
const evalPhp = (code) => wp('eval', code);
const ensureTheme = (slug) => { try { wp('theme', 'is-installed', slug); } catch { wp('theme', 'install', slug); } };

fs.mkdirSync(path.dirname(path.resolve(OUT)), { recursive: true });
const SHOTS = path.join(path.dirname(path.resolve(OUT)), 'shots');
fs.mkdirSync(SHOTS, { recursive: true });
fs.writeFileSync(OUT, '');

const launch = { headless: true, args: ['--no-first-run', '--disable-default-apps', '--disable-features=ViewTransitionOnNavigation,ViewTransition'] };
if (process.env.WP_AUDIT_CHROME) launch.executablePath = process.env.WP_AUDIT_CHROME;
const browser = await chromium.launch(launch);
const ctx = await browser.newContext({ viewport: { width: 1400, height: 900 } });
await ctx.addInitScript(() => { try { delete Document.prototype.startViewTransition; Document.prototype.startViewTransition = undefined; } catch {} });

let page; let errs = []; let results = [];
const scrub = (s) => String(s).split(HOST).join('HOST').slice(0, 160);
async function freshPage() {
  if (page) { try { await page.close({ runBeforeUnload: false }); } catch {} }
  page = await ctx.newPage(); page.setDefaultTimeout(20000);
  page.on('dialog', (d) => d.dismiss().catch(() => {}));
  page.on('console', (m) => { if (m.type() === 'error') errs.push('console: ' + scrub(m.text())); });
  page.on('pageerror', (e) => errs.push('pageerror: ' + scrub(e.message)));
}
const must = (cond, msg) => { if (!cond) throw new Error(msg); };
async function cell(id, fn) {
  if (ONLY && !ONLY.includes(id)) return;
  await freshPage(); errs = []; let ok = false; let detail = '';
  try { detail = (await fn()) || ''; ok = true; } catch (e) {
    detail = 'FAILED at: ' + String(e.message).split('\n')[0].slice(0, 220);
    try { detail += ' @ ' + page.url().split(HOST).join('HOST'); await page.screenshot({ path: path.join(SHOTS, `${id}.png`), timeout: 5000 }); } catch {}
  }
  const rec = { cell: id, ok, detail, errors: [...new Set(errs)] };
  results.push(rec); fs.appendFileSync(OUT, JSON.stringify(rec) + '\n');
  console.log(`${id} ${ok ? 'OK' : 'FAIL'} ${detail.slice(0, 110)} console_errors=${rec.errors.length}`);
}
async function login() {
  await freshPage();
  await page.goto(`${BASE}/wp-login.php`);
  await page.fill('#user_login', USER); await page.fill('#user_pass', PASS);
  await Promise.all([page.waitForURL(/wp-admin/), page.click('#wp-submit')]);
}
const stamp = Date.now() % 100000;
const mk = (type, title, status = 'publish') => wp('post', 'create', `--post_type=${type}`, `--post_title=${title}`, `--post_status=${status}`, '--porcelain');
const canvas = () => page.frameLocator('iframe[name="editor-canvas"]');

await login();

if (MODE === 'single') {
  const uid = wp('user', 'get', USER, '--field=ID');
  evalPhp(`update_user_meta(${uid},'wp_persisted_preferences',array('core/edit-post'=>array('welcomeGuide'=>false,'fullscreenMode'=>false),'core/edit-widgets'=>array('welcomeGuide'=>false),'core/edit-site'=>array('welcomeGuide'=>false,'isComplementaryAreaVisible'=>false),'core'=>array('enableChoosePatternModal'=>false)));`);

  await cell('T2-73', async () => {
    await page.goto(`${BASE}/wp-admin/post-new.php?post_type=page`);
    const title = canvas().locator('.editor-post-title__input, h1.wp-block-post-title').first();
    await title.waitFor({ timeout: 45000 });
    await title.click(); await page.keyboard.type(`T2 editor page ${stamp}`); await page.keyboard.press('Enter'); await page.keyboard.type('T2 body text.');
    await page.getByRole('button', { name: 'Publish', exact: true }).first().click();
    await page.locator('.editor-post-publish-panel__header-publish-button button, .editor-post-publish-panel__header-publish-button').last().click();
    await page.locator('.components-snackbar, .editor-post-publish-panel__postpublish-header').first().waitFor({ timeout: 30000 });
    const r = wp('post', 'list', '--post_type=page', `--s=T2 editor page ${stamp}`, '--fields=post_status', '--format=csv');
    must(/publish/.test(r), 'page not published: ' + r.replace(/\n/g, ' '));
    return 'published';
  });

  await cell('T2-74', async () => {
    const a = mk('page', `T2 quick A ${stamp}`, 'draft'); const b = mk('page', `T2 bulk B ${stamp}`); const c = mk('page', `T2 bulk C ${stamp}`);
    await page.goto(`${BASE}/wp-admin/edit.php?post_type=page&s=T2+&post_status=all`);
    const row = page.locator(`#post-${a}`); await row.hover(); await row.locator('.editinline').click();
    await page.fill(`#edit-${a} input[name="post_title"]`, `T2 quick A edited ${stamp}`); await page.click(`#edit-${a} .save`);
    await page.waitForFunction((id) => !document.querySelector(`#edit-${id}`), a, { timeout: 20000 });
    must(wp('post', 'get', a, '--field=post_title').includes('edited'), 'quick edit did not save');
    await page.goto(`${BASE}/wp-admin/edit.php?post_type=page&s=T2+bulk&post_status=all`);
    await page.check(`#cb-select-${b}`); await page.check(`#cb-select-${c}`);
    await page.selectOption('#bulk-action-selector-top', 'edit'); await page.click('#doaction');
    await page.selectOption('#bulk-edit select[name="_status"]', 'draft');
    await Promise.all([page.waitForLoadState('load'), page.click('#bulk_edit')]);
    const sb = wp('post', 'get', b, '--field=post_status'); const sc = wp('post', 'get', c, '--field=post_status');
    must(sb === 'draft' && sc === 'draft', `bulk status ${sb}/${sc}`);
    return 'quick edit and bulk edit saved';
  });

  const pid = mk('post', `T2 comment host ${stamp}`);
  const c1 = evalPhp(`echo wp_insert_comment(array('comment_post_ID'=>${pid},'comment_content'=>'T2 approve me','comment_author'=>'T2','comment_approved'=>0));`);
  const c2 = evalPhp(`echo wp_insert_comment(array('comment_post_ID'=>${pid},'comment_content'=>'T2 spam me','comment_author'=>'T2','comment_approved'=>0));`);
  await cell('T2-75', async () => {
    await page.goto(`${BASE}/wp-admin/edit-comments.php?comment_status=moderated`);
    const r1 = page.locator(`#comment-${c1}`); await r1.hover(); await r1.locator('.approve a').first().click();
    await page.waitForTimeout(2500);
    const r2 = page.locator(`#comment-${c2}`); await r2.hover(); await r2.locator('.spam a').first().click();
    await page.waitForTimeout(2500);
    const s1 = wp('comment', 'get', c1, '--field=comment_approved'); const s2 = wp('comment', 'get', c2, '--field=comment_approved');
    must(s1 === '1' && s2 === 'spam', `approve=${s1} spam=${s2}`);
    return 'approved one, spammed one';
  });
  await cell('T2-76', async () => {
    await page.goto(`${BASE}/wp-admin/edit-comments.php?comment_status=approved`);
    const row = page.locator(`#comment-${c1}`); await row.hover(); await row.locator('.reply button, button.vim-r').first().click();
    await page.fill('#replycontent', 'T2 admin reply'); await page.click('#replybtn');
    await page.waitForTimeout(2500);
    must(Number(wp('comment', 'list', `--parent=${c1}`, '--format=count')) >= 1, 'no reply stored');
    return 'reply stored under parent';
  });
  await cell('T2-77', async () => {
    await page.goto(`${BASE}/wp-admin/profile.php`);
    await page.fill('#first_name', `T2first${stamp}`); await Promise.all([page.waitForLoadState('load'), page.click('#submit')]);
    must(wp('user', 'meta', 'get', uid, 'first_name') === `T2first${stamp}`, 'profile not saved');
    return 'first name saved';
  });
  await cell('T2-78', async () => {
    const u = wp('user', 'create', `t2u${stamp}`, `t2u${stamp}@example.test`, '--role=subscriber', '--porcelain');
    await page.goto(`${BASE}/wp-admin/users.php?s=t2u${stamp}`);
    await page.check(`#user_${u}`); await page.selectOption('#new_role', 'editor');
    await Promise.all([page.waitForLoadState('load'), page.click('#changeit')]);
    must(wp('user', 'get', u, '--field=roles') === 'editor', 'role not changed');
    return 'subscriber to editor';
  });

  ensureTheme('twentytwentyone'); wp('theme', 'activate', 'twentytwentyone');
  await cell('T2-79', async () => {
    let stage = 'start';
    try {
      await page.goto(`${BASE}/wp-admin/nav-menus.php?action=edit&menu=0`);
      stage = 'name'; await page.fill('#menu-name', `T2 menu ${stamp}`);
      stage = 'create'; await page.click('#save_menu_footer', { noWaitAfter: true });
      stage = 'wait redirect'; await page.waitForURL((u) => /menu=(?!0\b)\d+/.test(u.href), { timeout: 30000 });
      await page.waitForLoadState('load'); await page.waitForTimeout(1500);
      stage = 'open custom links'; await page.click('#add-custom-links .accordion-section-title', { noWaitAfter: true });
      stage = 'fill url'; await page.fill('#custom-menu-item-url', 'https://example.test/t2');
      stage = 'fill name'; await page.fill('#custom-menu-item-name', 'T2 link');
      stage = 'add to menu'; await page.click('#submit-customlinkdiv', { noWaitAfter: true });
      stage = 'item appears'; await page.waitForSelector('#menu-to-edit li');
      stage = 'tick location'; const loc = page.locator('input[name^="menu-locations"]').first(); if (await loc.count()) await loc.check({ noWaitAfter: true });
      stage = 'save'; await page.click('#save_menu_footer', { noWaitAfter: true }); await new Promise((r) => setTimeout(r, 4000));
    } catch (e) { throw new Error(`stage "${stage}": ${String(e.message).split('\n')[0]}`); }
    must(Number(wp('menu', 'item', 'list', `T2 menu ${stamp}`, '--format=count')) === 1, 'menu item not stored');
    return 'menu saved with one item';
  });
  await cell('T2-80', async () => {
    await page.goto(`${BASE}/`);
    must((await page.content()).includes('T2 link'), 'menu link not on the front end');
    return 'menu link rendered';
  });

  await cell('T2-81', async () => {
    await page.goto(`${BASE}/wp-admin/widgets.php`);
    await page.locator('.edit-widgets-header, .edit-widgets-layout__header').first().waitFor({ timeout: 45000 });
    await page.getByRole('button', { name: /Block Inserter|Toggle block inserter/i }).first().click();
    await page.getByPlaceholder(/Search/i).first().fill('Paragraph');
    await page.locator('.block-editor-block-types-list__item').filter({ hasText: 'Paragraph' }).first().click();
    await page.waitForTimeout(800);
    await page.locator('[data-type="core/paragraph"]').last().click();
    await page.keyboard.type(`T2 widget text ${stamp}`);
    await page.getByRole('button', { name: 'Update', exact: true }).click();
    await page.waitForTimeout(3000);
    must(evalPhp("echo wp_json_encode(get_option('widget_block'));").includes(`T2 widget text ${stamp}`), 'widget not stored');
    return 'block widget saved';
  });
  await cell('T2-82', async () => {
    await page.goto(`${BASE}/`);
    must((await page.content()).includes(`T2 widget text ${stamp}`), 'widget text not on the front end');
    return 'widget rendered';
  });

  ensureTheme('twentytwentyfive'); wp('theme', 'activate', 'twentytwentyfive');
  await cell('T2-83', async () => {
    await page.goto(`${BASE}/wp-admin/site-editor.php?p=%2Fwp_template%2Ftwentytwentyfive%2F%2Findex&canvas=edit`);
    await canvas().locator('[data-block]').first().waitFor({ timeout: 60000 });
    await canvas().getByText('Blog', { exact: true }).first().click();
    await page.keyboard.press('End'); await page.keyboard.type(` T2edit${stamp}`);
    await page.getByRole('button', { name: 'Save', exact: true }).first().click();
    await page.getByRole('button', { name: /^Save$/ }).last().click().catch(() => {});
    await page.waitForTimeout(3000);
    must(Number(wp('post', 'list', '--post_type=wp_template', '--format=count')) >= 1, 'no customized template stored');
    return 'template customization saved';
  });
  await cell('T2-84', async () => {
    await page.goto(`${BASE}/wp-admin/site-editor.php?p=%2Ftemplate`);
    await page.getByPlaceholder(/Search/i).first().fill('Index'); await page.waitForTimeout(2000);
    await page.getByRole('button', { name: /Actions/i }).first().click();
    await page.getByRole('menuitem', { name: /Reset|Clear customizations|Delete/i }).first().click();
    await page.getByRole('button', { name: /Reset|Clear|Delete|Confirm/i }).last().click().catch(() => {});
    await page.waitForTimeout(3000);
    const n = wp('post', 'list', '--post_type=wp_template', '--format=count');
    must(Number(n) === 0, 'customized template still stored: ' + n);
    return 'template reverted to the theme default';
  });

  await cell('T2-85', async () => {
    await page.goto(`${BASE}/wp-admin/options-general.php`);
    await page.fill('#blogdescription', `T2 tagline ${stamp}`); await Promise.all([page.waitForLoadState('load'), page.click('#submit')]);
    must(wp('option', 'get', 'blogdescription') === `T2 tagline ${stamp}`, 'tagline not saved');
    return 'general settings saved';
  });
  await cell('T2-86', async () => {
    await page.goto(`${BASE}/wp-admin/options-reading.php`);
    await page.fill('#posts_per_page', '7'); await Promise.all([page.waitForLoadState('load'), page.click('#submit')]);
    must(wp('option', 'get', 'posts_per_page') === '7', 'reading settings not saved');
    return 'reading settings saved';
  });
} else {
  const slug = `t2new${stamp}`;
  await cell('T2-87', async () => {
    await page.goto(`${BASE}/wp-admin/network/site-new.php`);
    await page.fill('#site-address', slug); await page.fill('#site-title', `T2 new ${slug}`); await page.fill('#admin-email', 't2new@example.test');
    await Promise.all([page.waitForLoadState('load'), page.click('#add-site')]);
    const rows = wp('site', 'list', '--fields=blog_id,path', '--format=csv').split('\n');
    const line = rows.find((l) => l.includes(slug));
    must(line, 'new site not created');
    const id = line.split(',')[0];
    await page.goto(`${BASE}/wp-admin/network/sites.php?s=${slug}`);
    const row = page.locator('table.sites tbody tr').first(); await row.hover();
    await row.locator('.archive a, .archiveblog a').first().click();
    await page.getByRole('button', { name: /Yes|Confirm|Archive/i }).first().click().catch(async () => { await page.locator('input[type="submit"]').last().click(); });
    await page.waitForTimeout(1500);
    const archived = wp('site', 'list', `--site__in=${id}`, '--field=archived');
    must(archived === '1', 'archived flag is ' + archived);
    return `created ${slug} and archived it`;
  });
  await cell('T2-88', async () => {
    const seen = [];
    for (const p of [`/${SUBSITE}/wp-admin/`, `/${SUBSITE}/wp-admin/edit.php`, `/${SUBSITE}/wp-admin/options-general.php`, `/${SUBSITE}/wp-admin/themes.php`]) {
      const r = await page.goto(`${BASE}${p}`); const body = await page.content();
      must(r && r.status() === 200, `${p} http ${r && r.status()}`);
      must(!/Fatal error|Parse error|<b>Warning<\/b>|You do not have sufficient permissions|Error establishing/i.test(body), `${p} shows an error`);
      must(await page.locator('#wpadminbar').count() > 0, `${p} has no admin bar`);
      seen.push(p.split('/').pop() || 'dashboard');
    }
    return 'subsite admin screens load: ' + seen.join(', ');
  });
}

await browser.close();
const bad = results.filter((r) => !r.ok).length;
console.log(`${results.length - bad} OK, ${bad} FAIL`);
process.exit(bad ? 1 : 0);
