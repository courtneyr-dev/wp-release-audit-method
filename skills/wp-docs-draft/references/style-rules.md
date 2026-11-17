# Style rules for WordPress.org documentation

Rules for drafting HelpHub (wordpress.org/documentation) and the Docs handbooks. Each rule is pass/fail. A bracketed slug, like [heading-case], is a check `scripts/check-draft.py` runs; everything else needs a person.

**Sources, in precedence order.** (1) Project-specific style: the handbook pages below. (2) The official [Documentation Style Guide](https://make.wordpress.org/docs/style-guide/), built from [`WordPress/WordPress-Documentation-Style-Guide`](https://github.com/WordPress/WordPress-Documentation-Style-Guide) (GPL-2.0; `docs/` plus `manifest.json`). Pin a commit when you check against it; `scripts/style-guide-pin.sh` reports whether the repo moved. At commit `0bc0358a71` (2026-09-22, the repo's `main` on 2026-11-17) the guide has 104 subpages. The site shows one bulk "last updated" date, October 14, 2026, on all of them, so a page's date says nothing about its age. (3) Chicago Manual of Style, American Heritage Dictionary, Merriam-Webster.

Handbook pages that count as project-specific style: [Handbooks and HelpHub style and formatting guide](https://make.wordpress.org/docs/handbook/documentation-team-handbook/handbooks-style-and-formatting-guide/) (published 2013, mostly pre-block-editor), [grammar guide](https://make.wordpress.org/docs/handbook/documentation-team-handbook/handbooks-grammar-guide/) and [tone and voice guide](https://make.wordpress.org/docs/handbook/documentation-team-handbook/tone-and-voice-guide/) (both call themselves drafts), the [external linking policy](https://make.wordpress.org/docs/handbook/documentation-team-handbook/external-linking-policy/), and [writing tips](https://make.wordpress.org/docs/handbook/get-involved/writing-tips/) (Codex-era; loses every conflict).

**WordPress style governs WordPress.org drafts, including where it differs from another house style or the writer's own habits.** Transition words like "however" and "therefore" are encouraged by the guide, not required. The em dash has no spaces around it.

## Voice

- Address the reader as "you". [we-voice] [i-voice]
- Steps are bare imperatives: "Click Publish." Not "You must click…", not "Please click…". [must-click] [please]
- Friendly, informal, succinct. No idioms, slang, metaphors, humor, or cultural, seasonal or pop-culture references.
- Present tense. Active voice (passive only when the system acts, the subject doesn't matter, or active reads awkwardly). [future-will]
- Indicative mood: not "You might need to click Preview".
- No exclamation points. Use a Note, Tip, Caution or Warning notice for important content. [excl]
- Avoid simple, simply, easy, easily, just, very, "allows you to" (use "lets you"), and "latest" except when telling readers to update. Name the version instead of "new". [filler-words] [allows-you]
- Modal verbs: must (required), should (recommended), can (permitted or optional), might (possible), may (policy and legal text only).
- Document only what's in core or will be. No unreleased features. No promotion of any plugin, theme, service or host. Verify every claim.
- One topic per article, one main point per paragraph; link to other topics. Short paragraphs. [long-paragraph]
- Open with one or two paragraphs that state the purpose, before any heading. [intro-missing]

## Words and grammar

- American English. [brit-spelling]
- Contractions are fine when common (don't, you're). Not "let's", not noun-plus-verb ("Gutenberg's using").
- Serial comma in lists of three or more.
- Condition or purpose first: "To install the plugin, click Install." Location before action.
- Spell out an abbreviation at first use, in body text, not in a heading. Plural without an apostrophe: APIs.
- No Latin or slang shorthand: "for example", not e.g.; "that is", not i.e.; "such as", not etc. [latin-abbrev]
- No "and/or" and no slashes for alternatives. [and-or]
- No he, she, his, her for people in general. Rewrite, or use singular "they". [gendered-pronoun]
- Fixed forms: WordPress, website, webpage, email, multisite, permalink, log in (verb), login (noun), sign in, set up (verb), plugin (noun). [term-forms]
- Word-list words to rewrite: abort, leverage, legacy, launch, native (use "core" or "built-in"), navigate to, activate (use "turn on" in prose; the **Activate** button label stays). [avoid-words]
- Inclusive terms: blocklist and allowlist; primary and secondary. [noninclusive] [master-term]
- Versions: "WordPress 7.2", "7.2 or later", never "newer", "older", "higher". "Update" is a minor version change, "upgrade" a major one.
- Dates: "August 16, 2020", no ordinals, no all-numeric dates (ISO 8601 if unavoidable). Times: 12-hour with AM or PM, with a time zone when real. [ordinal-date] [numeric-date]
- Numbers: spell out zero to nine, numerals from 10; spell out ordinals; commas for four or more digits.

## Capitalization and headings

- Sentence case for headings, titles, list items, table headings and UI-name references. [heading-case]
- Capitalize proper nouns and official names (WordPress, Gutenberg, GitHub, Media Library as a screen name). Don't capitalize theme, plugin, page, block, user, administrator. Write "classic editor" in lowercase unless you mean the plugin.
- The page title is the H1. Sections start at H2 and go in order to H6, with no skipped level. [h1-extra] [heading-skip]
- No empty headings, no ending period, no links (HelpHub's own same-page anchors don't count), no ampersands or symbols, no abbreviations unless unavoidable. [heading-empty] [heading-period] [heading-link] [heading-symbol]
- Headings are short, specific and front-loaded. Action-plus-object works: "Create a new page".
- Refer to "the following section", not "this section".

## Lists and procedures

- Bulleted for unordered, numbered for sequences, a table for three or more data points per item. Lists have at least two items. [single-item-list]
- A lead-in that ends in a colon is a complete sentence.
- One action per step, imperative, capital first word, ending period. Purpose first, then the action. A single step becomes one sentence.
- Optional steps start with "Optional." No keyboard shortcuts in steps. Procedures end with a result.
- No directional words (above, below, left, right) to locate things; name the element or show a screenshot. [directional]

## UI text

- Bold the visible name of a UI element. No quotes, no code font for UI names. [click-on]
- Write the task, not the control: "Click Publish." Not "Click the Publish button" or "click on".
- Menu paths use ` > ` inside one bold run: **Pages > Add New**. Not arrows. [menu-arrow]
- Verbs: click (mouse), tap (touch), select (menu item, checkbox, list item), enter or type (text), go to (page, site), choose (from options), clear (a checkbox), press (a key).
- "In the X dialog", "On the X page". Say "dialog", not "dialog box"; name a text box by its label plus "box".
- Text the reader types is in code font. Keys use `<kbd>`, Windows first, Mac in parentheses, modifier names spelled out.
- Emphasis: italics for emphasis and key terms; bold for UI elements and notice labels (the handbook also allows bold for important points; sources conflict, see below). Never underline.

## Links

- Link text names the destination and stands alone. Not "here", not "this page", not a raw URL. [link-text] [link-url-text]
- Link a target once per page. Say why the reader should follow it: "For more information about uploads, see…" (about, not on).
- Same-site links are root-relative (`/documentation/article/…`). A link that downloads says so and names the file type. Don't force new tabs.
- External linking policy: every link not on the allow-list is prohibited, no new external links are added "at this time", and a linked page may not sell or promote anything. Pages on wordpress.org, developer.wordpress.org and make.wordpress.org are internal. For anything else, check the policy's allow-list (set for the Plugin Developer Handbook: iso.org, gnu.org, php.net, wordpressfoundation.org, xdebug.org); wordpress.tv and Learn workshops need a reviewer's accuracy check. [external-link]
- Functions, hooks and classes go in code font and link to the Code Reference.
- Don't copy third-party text, images, code or logos. Paraphrase and link.

## Code

- Code font for filenames, paths, functions, methods, classes, variables, attributes, parameters, text the reader types and placeholders. A method name ends in `()`.
- Blocks: fenced code with a sentence that names the file; spaces, not tabs; WordPress coding standards. Handbooks use the language shortcodes (`[php]`, `[html]`).
- Placeholders are UPPERCASE_WITH_UNDERSCORES; follow with "Replace the following:".
- No images of text or code.

## Images (full rules in `screenshots.md`)

- Alt text on every image; full sentences, no "Image of". 155 characters at most, and the Accessibility page says 50. [alt-missing] [alt-prefix] [alt-screenshot] [alt-long] [alt-over-50]
- Never hotlink; images are uploaded to the page's own media library. [image-host]
- Lowercase hyphenated filenames. PNG for screenshots, SVG for diagrams; video, not an autoplaying GIF. [image-name] [image-format]
- Text must carry the same information as the screenshot.

## Notices, tables, structure

- Notices use the shortcodes: info (Note), tip, alert (Caution), warning. Never stack two. An outdated page gets a Warning: "This page is outdated as of WordPress VERSION. It is maintained for archival purposes only."
- Tables: an intro sentence, sentence-case headings in the first row, no merged cells, no blank cells, none inside a numbered procedure.
- Use real blocks in the block editor. No Classic block.
- A HelpHub or handbook article ends with a Changelog section. [changelog-missing]
- Examples use example.com, example.org, name@example.com and reserved documentation IP ranges. No real people or numbers.
- Licensing: documentation content is CC0; code snippets are GPLv2 or later. Content you add must be yours or reusable.

## Where the sources disagree (use the governing pick)

- **Alt text length.** 50 (Accessibility page) or 155 (Media page). Keep it under 50 when you can; never over 155.
- **Bold or italic for emphasis.** Style Guide: italics for emphasis, bold for UI. Handbook: bold for important points. Use italics; reviewers may accept bold.
- **Menu paths.** The guide wants an `aria-label="and then"` span and warns screen readers may skip it. Use the plain **Pages > Add New** unless the editor supports the span.
- **Heading case.** The tutorial template uses title case. The Style Guide wins: sentence case.
- **External links.** The Style Guide prefers linking out. The external linking policy bans it. The policy wins.
- **Screenshot scope.** Style Guide: full window with title bar. Handbook: crop to the area. For HelpHub, crop to the area the old image showed (see `screenshots.md`).
- **Click and type.** The Accessibility page says avoid them; the UI-elements page and word list use them. Use click, tap, type and enter.
- **Keyboard shortcuts.** None in steps; if you must mention one, use `<kbd>`.
- **Login terms, American English, code font.** The Style Guide beats writing tips: "log in to", American spelling, `<code>`.
- **Dashboard, admin and site editor terms.** No page defines them. Match the existing article, and say so in the hand-off.

## Not specified (don't invent)

No HelpHub article template or required section list. No page-title case rule for HelpHub. No annotation standard for screenshots. No pixel-size, density or file-size rule. No terms for dashboard, site editor or "block editor" versus "Gutenberg". No policy on AI-assisted drafting (see `workflow-and-handoff.md`). No changelog format beyond "include one". No guidance on emoji or "since version" notation.

## Reading status

Research read on 2026-11-17: the Style Guide pages (word list sampled, about 330 of 814 entries), six handbook pages and the licensing page. The 43 lint checks encode the mechanical subset only. A draft that passes the linter can still be wrong, off-topic or unclear.
