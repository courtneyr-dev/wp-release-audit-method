# Screenshots for WordPress.org documentation

How the Docs team makes, names, stores and hands over screenshots, and how to produce them with [`wp-screenshots`](../../wp-screenshots/SKILL.md). Read 2026-11-17: the written rules, then 109 images on 9 live HelpHub articles and 4 handbook pages. Labels: **stated** (a page says it), **observed** (counted on live pages), **choice** (the sources are silent; this skill picks and says so).

## Where screenshots live

- HelpHub images sit in the documentation site's own Media Library: `wordpress.org/documentation/files/YYYY/MM/name.ext`. All 109 sampled images were there. The Docs handbook and blog use `make.wordpress.org/docs/files/`; the developer handbooks use `developer.wordpress.org/files/`. (observed)
- Contributors don't upload to those libraries. They attach images to the tracker issue as comments, with an `ALT:` line, and an editor with HelpHub access uploads them. (observed in 8 issues; the upload step is inferred)
- Never hotlink. In Oct to Nov 2026 dozens of HelpHub block pages lost images that had been linked from Google, and maintainers asked for retakes uploaded to the page (tracker issues 2080, 2540 and 2541). (stated by maintainers in those issues)
- Block Editor Handbook images must be hosted on developer.wordpress.org, not linked from GitHub. (stated in the Gutenberg contributing doc)

## When to make or replace one

- Replace a screenshot when anything visible differs on a fresh install of the latest release: a control added, removed, moved or restyled, including icon and default-theme changes. (stated)
- A replacement covers the same screen area as the old one. If the interface moved, cover the same interface. (stated)
- Use the same annotation style as the image you replace. (stated, "preferred")
- A page about a UI element has a screenshot of it. (stated) Use an image only when it adds what words can't. The text must carry the same information. (stated)
- For a complex feature, a short video converted to GIF plus one or two screenshots is acceptable. (stated; the handbook's accessibility note prefers video or a click-to-play GIF)

## Environment

- A fresh install of the release the page documents. For pre-release work name the exact build in your hand-off, as contributors do ("7.2-beta3 with Twenty Twenty-Five"). (stated, observed)
- The **current default theme**. It changes by release; read `WP_DEFAULT_THEME` in the build's `default-constants.php` (Ipsum at 7.2 RC1). No extra plugins. Language English. (stated)
- A throwaway site: [WordPress Playground](https://playground.wordpress.net/) or InstaWP. A dummy account is fine. (stated)
- One operating system throughout a page's images. (stated)
- The default admin color scheme (choice; every sampled image uses it, no page states one).
- No personal data. Seed generic sample content; the admin bar reads "Howdy, admin". If something must be hidden, cover it with a solid, fully opaque fill. Never blur or pixelate; both can be reversed. (stated)
- Everything published is CC0 (the docs license). Use sample images you made or that are CC0, and no real people, third-party logos or copyrighted characters.

## Capture with wp-screenshots

Write a brief and run `capture.mjs` against the throwaway site (see that skill for setup and the notice-hiding it does by default). Per-shot `viewport` is how you frame the region, because the handbook's advice is to resize the window to the area you mean.

```json
{
  "topic": "media-library-7-2",
  "site": "https://your-test-site.example",
  "auth": { "user": "admin", "passEnv": "WP_SITE_PASS" },
  "dpr": 2,
  "shots": [
    {
      "slug": "media-library-grid-view",
      "label": "Media Library, grid view",
      "url": "/wp-admin/upload.php?mode=grid",
      "viewport": [1200, 700],
      "delay": 2000
    }
  ]
}
```

- `dpr` 2 (choice). No page sets a density; many 2026 uploads are 2x captures displayed at 450 to 850 px. Live widths run from 254 to 3022 px.
- Look at every PNG before it goes anywhere: no update bubble, notice, tooltip or loading state, and the right build visible.
- Crop to the control or region after capture, in any image editor. The wp-screenshots harness doesn't crop. Keep PNG.
- Annotation: there is no standard (the one request for one, in 2013, got no answer). Prefer none. Reuse the style of the image you replace. If you must add marks, numbered callouts that the text also explains are fine; keep any text short, in sentence case, and not the only carrier of meaning (4.5:1 contrast, never color alone). Don't bake captions or descriptions into the image.

## Format, naming, size

- PNG for screenshots (88% of sampled images), SVG for diagrams. JPG is in live use for photo-heavy shots. Flatten layers. (stated: PNG or SVG; observed)
- Filename: lowercase ASCII words joined by hyphens, descriptive: `media-library-grid-view.png`. Live files are mixed; the Style Guide's rule is for new files. (stated for files in general; applied to images by inference)
- Full size, not click-to-enlarge thumbnails. Don't wrap the image in a link to itself. (stated)
- No rule exists on pixel size, file size or compression. (gap)

## Alt text and captions

- Every image has alt text. Empty alt is only for decorative images. (stated)
- Full sentences with punctuation, specific to the image and its context, no "Image of" or "Photo of", never replaced by the caption. Say what it shows and what matters: "Media items in grid view." (stated)
- 155 characters at most (Media page); the Accessibility page says 50. Live alt text averages 29 to 78. Aim under 50. (stated, conflicting)
- Captions are optional. If used, they go in a `figcaption` with the image. The 37 live captions sampled are short phrases in sentence case with no "Figure N." (observed; the Style Guide says "Figure NUMBER. DESCRIPTION", observed practice differs). Omit captions unless the page already uses them.
- Introduce an image with a full sentence, unless the heading says what it shows. Don't point at it with "above", "below", "left" or "right".
- Alignment: the Style Guide says left or right, not centered. About 63 of 109 live images are centered. Leave alignment to the editor and note the conflict in your hand-off.

## Hand-off comment

Post one comment per image in the tracker issue (the operator posts them), headed by the article section the image goes in:

```markdown
### Media Library > Grid view

Replaces `media-library-grid-view-1.png`. Taken on WordPress 7.2-RC1 with the default theme, no extra plugins, English.

(attach media-library-grid-view.png to the comment)

ALT: Media items in grid view.
```

Then the operator comments `/review`. Name unchanged images too ("Unchanged: attachment details"), so the reviewer sees full coverage.

## Gaps and conflicts

- No rule for pixel size, density, file size, filename pattern, admin color scheme, browser, viewport or annotation style.
- Style Guide: full window with title bar. Handbook: crop to the area. Observed: no title bar or browser chrome on any sampled image. This skill follows the handbook.
- Alt length: 50, 100 and 155 appear on three pages. Empty alt appears on 7 content screenshots on 3 live pages (older ones).
- There is a 2022 training video, "Update screenshots in WordPress documentation" (WordPress.tv), linked from every `needs screenshots` issue. It wasn't watched; check it for rules the text doesn't carry.
- One contributor produced a 2026 batch with Playwright, and a maintainer called that part of the process they're developing. It's an emerging practice, not a written rule.
