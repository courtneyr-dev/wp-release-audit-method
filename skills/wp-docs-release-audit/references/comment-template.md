# Comment template

One comment, pasted by the operator. It contains only what the issue doesn't say. Run `scripts/topic-overlap.py` first and again before pasting.

## Structure

1. **Opening, three sentences.** What you checked and how much (tickets, dev notes, Gutenberg links, the RC commit), as sums from the subagent reports: "Matched N tickets by title and read M in full." Never write "checked all N" when M is smaller. Link the RC commit as `https://github.com/WordPress/wordpress-develop/commit/<full sha>`, not a branch listing. What held up. "Everything below is something the issue doesn't say yet."
2. **A. Update items already on the checklist.** Three groups, each a task list the author can fold into the body:
   - *Stale or wrong:* a reverted feature, a wrong ticket, a cited issue that isn't a PR, a source list that stops early.
   - *Items marked "(verify)", now checked:* one line each, CONFIRMED, REFUTED or UNCLEAR, with the ticket or source.
   - *Add detail to existing items:* the item's name, then what to add, then the page it affects.
3. **B. New checklist items.** One per missing change: what changed, the ticket, the page it affects.
4. **C. Page links for checklist items that have none.** Only verified URLs. Note deprecated or moved pages.
5. **D. Question: other documentation.** Only when the issue has no section for it and the tracker README says it takes it (for 7.2: developer docs). Ask whether the checklist should grow a section or another owner covers it, then list what's missing.
6. **How this was checked.** What you read in full, what you read from titles only, what you skipped and why, what you didn't test.

## Rules

- Say "checklist item" or "item". Never "row".
- Every ticket, changeset, PR and page is a link. Title-only items say "(read from the title only)".
- Name the exact thing to change: the page, the setting, the default, the ticket. A line with no page and no ticket gets cut.
- Don't restate an item that's already on the issue. A correction to it counts; agreement doesn't.
- Hold a feature that might be reverted ("hold, re-check before the release date"); don't delete it.
- Tag a person only when a line affects their task (the Field Guide author, for a stale dev note).
- Use checkboxes (`- [ ]`) so the issue's author can copy lines into the body.
- Plain American English, active voice, no marketing words. See the repo's [`GLOSSARY.md`](https://github.com/courtneyr-dev/wp-release-audit-method/blob/main/GLOSSARY.md) for repo terms; don't use them in the comment, because the tracker's readers haven't seen them.
- Don't mention the tools that did the work. Say what was checked, not who checked it.
