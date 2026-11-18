# Article structures

What the tracker's own templates and the live pages show about how HelpHub articles are put together. The Docs team has no official HelpHub article template; these are the closest written and observed shapes.

## Observed on live HelpHub pages

Checked 2026-11-17 on `columns-block`, `image-block` and `media-library-screen`:

- The page title renders as the H1. The body starts at H2.
- A short auto-generated "In this article" list sits first.
- Sections are H2, with H3 and H4 beneath. Block pages put "Block toolbar" and "Block settings" at H2.
- A **Changelog** H2 near the end, newest entry first, each entry "Updated YYYY-MM-DD (props to @username @username)" with a line or two on what changed. Example: "Updated 2026-08-24 (props to @kjoyner): Updated transform to properties and screenshot to include Grid."
- A "Was this article helpful?" feedback block follows; it's part of the site, not the article.
- Live headings sometimes break the written rules ("Border & Shadow", "Media → Library"). Draft to the rules, not to the exceptions.

## Block page outline

From the tracker's `guides/new-article-block-editor.md`:

1. Description of the block with an example use case.
2. A picture of the block in action.
3. How to add the block (inserter, or the Block Toolbar's More options).
4. Block toolbar.
5. Block settings.
6. Advanced block settings (reusable text).
7. Links to know more.
8. Changelog, with a "last updated" WordPress version.

The shared settings (Typography, Color, Layout, Dimensions, Border and Shadow, and the toolbar's More options) are described once, on the shared pages. List the settings your block has and link: [Typography](https://wordpress.org/documentation/article/typography-settings-overview/), [Colors](https://wordpress.org/documentation/article/colors-settings-overview/), [Dimensions](https://wordpress.org/documentation/article/dimension-controls-overview/), [Border and Shadow](https://wordpress.org/documentation/article/border-settings-overview/), [Layout](https://wordpress.org/documentation/article/layout-settings-overview/), [Background](https://wordpress.org/documentation/article/background-settings-overview/).

## Settings screen page

Observed on the Media Library screen article: one H2 per view or area of the screen (grid view, list view), H3 per control group (filters, delete, attachment details), H4 per control (search, sortable columns), a "Further reading" list at the end. Name each control by its on-screen label in bold, say what it does, and show the screen once at the top of each view.

## Release end-user update (per article)

From the tracker's `New release end-user issue` template. For each article a release touches:

- [ ] A line per Gutenberg issue or PR that changed it, with the link.
- [ ] Every screenshot is relevant to the latest version.
- [ ] Videos, if any, are up to date.
- [ ] Alt text on every image.
- [ ] Headings in sentence case.
- [ ] Convert reusable blocks to regular blocks.
- [ ] Update the changelog at the end of the article.

Pull requests sometimes carry a short video that suits the article.

## Tutorial (handbooks)

The handbook's tutorial template, for lessons rather than reference: an overview that says what the reader will do, a list of what they need, the steps (one task each, each under a short numbered heading), then a "Learn more" list. Write the headings in sentence case, not the template's title case.

## Issue shapes

- **Fix Doc Issue Report:** description, URL of the page, section of the page, why it's a problem, suggested fix.
- **New Doc Request:** what the new page is, how it will help.
- Both start with `[Status] To do`; the new-page request also adds `new document`.
