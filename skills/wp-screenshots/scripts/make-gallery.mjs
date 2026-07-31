#!/usr/bin/env node
/**
 * wp-screenshots / make-gallery
 *
 * Build a standalone HTML gallery of captured shots so a reviewer can flip
 * through them in a browser. Writes `index.html` directly into the output
 * folder (no upload, no server, no coupling to any host dashboard).
 *
 * Usage:
 *   node make-gallery.mjs --dir ./screenshots/my-topic
 *   node make-gallery.mjs --dir ./screenshots/my-topic \
 *                        --title "My release shots" \
 *                        --subtitle "example.com staging"
 *
 * If a sibling brief exists at briefs/<topic>.json (where <topic> is the
 * dir basename), shot labels and `section` tags from the brief are used
 * to caption + group images.
 */

import {
  readdirSync, writeFileSync, existsSync, readFileSync, statSync,
} from 'node:fs';
import { parseArgs } from 'node:util';
import { join, basename, resolve, dirname } from 'node:path';

const { values } = parseArgs({
  options: {
    dir:      { type: 'string' },
    brief:    { type: 'string' },
    title:    { type: 'string' },
    subtitle: { type: 'string' },
    help:     { type: 'boolean' },
  },
  strict: false,
});

if (values.help || !values.dir) {
  console.log(`Usage: node make-gallery.mjs --dir <screenshots-folder> [--brief <path>] [--title "..."] [--subtitle "..."]`);
  process.exit(values.help ? 0 : 1);
}

const dir = resolve(values.dir);
if (!existsSync(dir) || !statSync(dir).isDirectory()) {
  console.error(`FAIL: ${dir} is not a directory`);
  process.exit(1);
}

const topic = basename(dir);
const title = values.title || `${topic} screenshots`;
const subtitle = values.subtitle || '';

// Try to find the brief: explicit --brief, or briefs/<topic>.json next to dir's parent.
let briefPath = values.brief ? resolve(values.brief) : null;
if (!briefPath) {
  const guess1 = resolve(dirname(dir), '..', 'briefs', `${topic}.json`);
  const guess2 = resolve(dirname(dir), 'briefs', `${topic}.json`);
  if (existsSync(guess1)) briefPath = guess1;
  else if (existsSync(guess2)) briefPath = guess2;
}

const labels = new Map();
const sections = new Map();
if (briefPath && existsSync(briefPath)) {
  try {
    const brief = JSON.parse(readFileSync(briefPath, 'utf-8'));
    for (const s of brief.shots || []) {
      labels.set(s.slug, s.label || s.slug);
      if (s.section) sections.set(s.slug, String(s.section));
    }
    console.log(`Using brief: ${briefPath}`);
  } catch (e) {
    console.log(`WARN: brief at ${briefPath} unreadable: ${e.message}`);
  }
}

const pngs = readdirSync(dir).filter(f => f.endsWith('.png')).sort();
if (pngs.length === 0) {
  console.error(`FAIL: no PNGs in ${dir}`);
  process.exit(1);
}

const shots = pngs.map(f => {
  const slug = f.replace(/\.png$/, '');
  return {
    file: f,
    slug,
    label: labels.get(slug) || slug.replace(/^\d+-/, '').replace(/-/g, ' '),
    section: sections.get(slug) || 'general',
  };
});

const sectionOrder = [...new Set(shots.map(s => s.section))];

const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${escapeHtml(title)}</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: #0f1115; color: #d4d6db; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; min-height: 100vh; padding: 32px; }
header { display: flex; justify-content: space-between; align-items: baseline; border-bottom: 1px solid #232733; padding-bottom: 16px; margin-bottom: 24px; }
h1 { font-size: 16px; font-weight: 600; color: #fff; }
.subtitle { font-size: 12px; color: #8a8f9c; margin-top: 4px; }
.count { font-size: 12px; color: #8a8f9c; }
.section-label { font-size: 11px; letter-spacing: 0.12em; color: #6b7280; text-transform: uppercase; margin: 28px 0 12px; padding-bottom: 6px; border-bottom: 1px dashed #232733; }
.section-label:first-of-type { margin-top: 0; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 14px; }
figure { border: 1px solid #232733; background: #161922; border-radius: 6px; cursor: zoom-in; transition: border-color 0.15s, transform 0.15s; overflow: hidden; }
figure:hover { border-color: #3b82f6; transform: translateY(-2px); }
figure img { display: block; width: 100%; height: 190px; object-fit: cover; object-position: top center; background: #0f1115; }
figcaption { font-size: 12px; color: #d4d6db; padding: 10px 12px; border-top: 1px solid #232733; }
.tag { display: inline-block; font-size: 10px; color: #8a8f9c; margin-left: 8px; padding: 1px 6px; border: 1px solid #2c313d; border-radius: 3px; }
#lightbox { position: fixed; inset: 0; background: rgba(0,0,0,0.95); display: none; align-items: center; justify-content: center; z-index: 100; cursor: zoom-out; padding: 24px; }
#lightbox.open { display: flex; }
#lightbox img { max-width: 100%; max-height: 100%; object-fit: contain; border: 1px solid #232733; }
#lightbox .label { position: absolute; bottom: 22px; left: 50%; transform: translateX(-50%); font-size: 12px; color: #d4d6db; background: rgba(15,17,21,0.85); padding: 6px 14px; border: 1px solid #232733; border-radius: 4px; }
.close-hint { position: absolute; top: 22px; right: 22px; font-size: 11px; color: #6b7280; }
</style>
</head>
<body>

<header>
  <div>
    <h1>${escapeHtml(title)}</h1>
    ${subtitle ? `<div class="subtitle">${escapeHtml(subtitle)}</div>` : ''}
  </div>
  <div class="count">${shots.length} shots</div>
</header>

${sectionOrder.map(sec => `
<div class="section-label">${escapeHtml(sec)}</div>
<div class="grid">
${shots.filter(s => s.section === sec).map(s => `
  <figure data-src="${escapeHtml(s.file)}" data-label="${escapeHtml(s.label)}">
    <img src="${escapeHtml(s.file)}" alt="${escapeHtml(s.label)}" loading="lazy">
    <figcaption>${escapeHtml(s.label)}<span class="tag">${escapeHtml(s.section)}</span></figcaption>
  </figure>
`).join('')}
</div>
`).join('')}

<div id="lightbox">
  <span class="close-hint">ESC / click to close</span>
  <img src="" alt="">
  <div class="label"></div>
</div>

<script>
const lb = document.getElementById('lightbox');
const lbImg = lb.querySelector('img');
const lbLabel = lb.querySelector('.label');
document.querySelectorAll('figure').forEach(fig => {
  fig.addEventListener('click', () => {
    lbImg.src = fig.dataset.src;
    lbLabel.textContent = fig.dataset.label;
    lb.classList.add('open');
  });
});
lb.addEventListener('click', () => lb.classList.remove('open'));
document.addEventListener('keydown', e => { if (e.key === 'Escape') lb.classList.remove('open'); });
</script>

</body>
</html>
`;

const outPath = join(dir, 'index.html');
writeFileSync(outPath, html);
console.log(`Gallery: ${outPath}`);
console.log(`Open: file://${outPath}`);

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
