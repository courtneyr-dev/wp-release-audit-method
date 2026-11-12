# Preparing the post on a Make blog

Make blogs run the block editor with the o2 theme. A paste from Google Docs loses code blocks, inline code and heading levels. Rebuild the body instead of fixing blocks one by one.

## Before starting

- Use the operator's signed-in browser. The drafts list is `https://make.wordpress.org/<team>/wp-admin/edit.php?post_status=draft&post_type=post` (`post_status=pending` for posts awaiting review); open the post from there.
- Read the current blocks first, names and short text only (full content can trip the output filter on strings like `S="…"`):
  ```js
  wp.data.select('core/block-editor').getBlocks().map((b,i)=>`${i} ${b.name} ${String(b.attributes.content??'').replace(/<[^>]+>/g,'').slice(0,60)}`)
  ```

## Rebuild the body

1. Generate markup from the Markdown draft:
   ```bash
   python3 skills/wp-call-for-testing/scripts/md_to_blocks.py DRAFT.md --after "## Post" --json
   ```
   `###` becomes h2 (the title is the page h1). Add `--syntax-block` only if the site has Code Syntax Block (check below).
2. In the editor, back up the current content, parse, validate, and replace only if every block is valid:
   ```js
   window.__pastedBackup = wp.data.select('core/editor').getEditedPostContent();
   const blocks = wp.blocks.parse(MARKUP);
   const bad = blocks.flatMap(function f(b){return [b,...b.innerBlocks.flatMap(f)]}).filter(b=>!b.isValid);
   if (!bad.length) wp.data.dispatch('core/block-editor').resetBlocks(blocks);
   ```
3. Screenshot, then save as draft and confirm from the saved record. When the draft is ready for review, set it to "Pending review" the same way (`editPost({ status: 'pending' })`, then `savePost()`; the saved status reads `"pending"`); a Team Rep publishes from there:
   ```js
   await wp.data.dispatch('core/editor').savePost();
   wp.data.select('core').getEntityRecord('postType','post',POST_ID).status // "draft"
   ```

## o2 and Make quirks

- **Hashtags become tags.** o2 turns `#word` in body text into a tag link and tags the post. Link Slack channels (`<a href="https://wordpress.slack.com/archives/<channel-id>">#hosting</a>`); o2 leaves text inside links alone. Don't end the post with a `#tag` line; set tags in the sidebar.
- **Mentions are automatic.** `@username` becomes a profile link on render; write plain text.
- **Syntax highlighting is per site.** Make/Core runs Code Syntax Block (Prism); Make/Hosting, CLI, Meta and Test didn't as of 2026-11-12. Check: `wp.blocks.getBlockType('core/code').attributes.language`. If it's missing, code still renders in IBM Plex Mono; a Meta Trac request (component "Make (Get Involved) / P2") is the fix.
- **Featured images** don't show on the post page in the Make theme, but do in link previews.

## Featured image

- 1200×630, text only, no WordPress logo or other marks. Dark background, white text, one accent color; no gradients.
- Render HTML with Playwright's headless shell, not branded Chrome:
  ```bash
  BIN=$(find ~/Library/Caches/ms-playwright -type f -name chrome-headless-shell | sort | tail -1)
  "$BIN" --headless --hide-scrollbars --window-size=1200,630 --virtual-time-budget=8000 --screenshot=OUT.png file://CARD.html
  ```
- Look at the render before uploading (check line breaks: join "WordPress&nbsp;7.2"). Check contrast: text at least 4.5:1, decorative shapes 3:1.
- Upload through Set featured image with the `file_upload` tool on the modal's file input (never click the input), fill Alt Text with everything the card says, set it, save, and confirm `featured_media` and `alt_text` through `wp.apiFetch`.

## Google Docs side

- Google Docs API connectors can refuse every call (some need Workspace Developer Preview enrollment). Don't keep retrying: create the Doc blank, paste the draft in the browser, and edit in the browser: Find and replace (Cmd+Shift+H) with element refs from `find`, never coordinates; replacements take the formatting of the first matched character, so start matches on plain text.
- Select a phrase for linking or formatting with the dialog's Next button, close it, then arrow keys; the find bar alone doesn't leave a selection. Find ignores case; use a phrase whose count reads 1 of 1.
- Copy code formatting with Cmd+Option+C from an existing code span and paste with Cmd+Option+V.
- If Chrome isn't signed in to Google and the Doc is link-editable, edits show as Anonymous; tell the operator, and recommend Commenter sharing.
- Others may edit while you work. Diff the Doc's plain-text export (`/export?format=txt`) against the Markdown draft after every round, and keep their changes unless they're wrong.
