#!/usr/bin/env python3
"""Convert a call-for-testing draft in Markdown to Gutenberg block markup.

Pasting from Google Docs into a Make blog loses code blocks, inline code and
heading levels. This builds clean block markup to load with wp.blocks.parse()
and resetBlocks() in the post editor.

Usage:
  md_to_blocks.py DRAFT.md [--after "## Post"] [--syntax-block] [--json]

--after         Start converting after this line (skips title and notes).
--syntax-block  Emit Code Syntax Block markup (language attribute and
                language-* class). Only for sites that run that plugin,
                such as Make/Core; check first (see references/make-editor.md).
--json          Print the markup as a JSON string, ready to paste into JS.

Handles: paragraphs, ### and #### headings (as h2 and h3, because the post
title is the page h1), ordered and bullet lists, fenced code, `inline code`,
**bold** and [links](url).
"""
import argparse
import html
import json
import re
import sys


def inline(text):
    out = []
    for part in re.split(r"(`[^`]+`)", text):
        if part.startswith("`") and part.endswith("`") and len(part) > 1:
            out.append("<code>" + html.escape(part[1:-1], quote=False) + "</code>")
            continue
        part = html.escape(part, quote=False)
        part = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", part)
        part = re.sub(r"\[([^\]]+)\]\(([^)]+)\)",
                      lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>', part)
        out.append(part)
    return "".join(out)


def convert(md, syntax_block=False):
    lines = md.strip("\n").split("\n")
    blocks, i = [], 0
    item = re.compile(r"^(\d+\.|-|\*) ")
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        fence = re.match(r"^```(\w*)", line)
        if fence:
            lang = fence.group(1) or ""
            j, code = i + 1, []
            while j < len(lines) and not lines[j].startswith("```"):
                code.append(lines[j])
                j += 1
            body = html.escape("\n".join(code), quote=False)
            if syntax_block and lang:
                blocks.append(f'<!-- wp:code {{"language":"{lang}"}} -->\n'
                              f'<pre class="wp-block-code"><code lang="{lang}" class="language-{lang}">{body}</code></pre>\n'
                              '<!-- /wp:code -->')
            else:
                blocks.append('<!-- wp:code -->\n<pre class="wp-block-code"><code>'
                              f'{body}</code></pre>\n<!-- /wp:code -->')
            i = j + 1
            continue
        head = re.match(r"^(#{1,6}) (.*)", line)
        if head:
            level = 3 if len(head.group(1)) >= 4 else 2
            attr = ' {"level":3}' if level == 3 else ""
            blocks.append(f'<!-- wp:heading{attr} -->\n<h{level} class="wp-block-heading">'
                          f'{inline(head.group(2))}</h{level}>\n<!-- /wp:heading -->')
            i += 1
            continue
        if item.match(line):
            ordered = bool(re.match(r"^\d+\.", line))
            items = []
            while i < len(lines) and item.match(lines[i]):
                items.append(item.sub("", lines[i]))
                i += 1
            tag = "ol" if ordered else "ul"
            attr = ' {"ordered":true}' if ordered else ""
            lis = "\n".join(f"<!-- wp:list-item -->\n<li>{inline(x)}</li>\n<!-- /wp:list-item -->"
                            for x in items)
            blocks.append(f'<!-- wp:list{attr} -->\n<{tag} class="wp-block-list">{lis}</{tag}>\n<!-- /wp:list -->')
            continue
        para = [line]
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r"^(#|```)", lines[i]) and not item.match(lines[i]):
            para.append(lines[i])
            i += 1
        blocks.append(f"<!-- wp:paragraph -->\n<p>{inline(' '.join(para))}</p>\n<!-- /wp:paragraph -->")
    return "\n\n".join(blocks)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("draft")
    ap.add_argument("--after", default=None)
    ap.add_argument("--syntax-block", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    md = open(a.draft, encoding="utf-8").read()
    if a.after:
        if a.after not in md:
            sys.exit(f"--after marker not found: {a.after!r}")
        md = md.split(a.after, 1)[1]
    out = convert(md, a.syntax_block)
    print(json.dumps(out) if a.json else out)


if __name__ == "__main__":
    main()
