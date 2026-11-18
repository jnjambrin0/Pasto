"""Converts release notes written in a small subset of Markdown into an HTML fragment.

Used by scripts/release.sh: Sparkle embeds a fragment without DOCTYPE or <body> into the
appcast item. Supported: `#`–`###` headings, `-`/`*` bullet lists, paragraphs separated by
blank lines, **bold**, *italic*, `code` and [links](https://…). Anything else is kept as text.

Usage: python3 -I scripts/release-notes-html.py <notes.md> <output.html>
"""

import html
import re
import sys

INLINE_RULES = [
    (re.compile(r"`([^`]+)`"), r"<code>\1</code>"),
    (re.compile(r"\*\*([^*]+)\*\*"), r"<strong>\1</strong>"),
    (re.compile(r"(?<![*\w])\*([^*]+)\*(?![*\w])"), r"<em>\1</em>"),
    (re.compile(r"\[([^\]]+)\]\((https?://[^)\s]+)\)"), r'<a href="\2">\1</a>'),
]


def inline(text):
    text = html.escape(text, quote=False)
    for pattern, replacement in INLINE_RULES:
        text = pattern.sub(replacement, text)
    return text


def convert(markdown):
    out = []
    paragraph = []
    in_list = False

    def flush_paragraph():
        if paragraph:
            out.append("<p>" + inline(" ".join(paragraph)) + "</p>")
            paragraph.clear()

    def close_list():
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    for raw in markdown.splitlines():
        line = raw.strip()
        heading = re.match(r"^(#{1,3})\s+(.*)$", line)
        bullet = re.match(r"^[-*]\s+(.*)$", line)
        if not line:
            flush_paragraph()
            close_list()
        elif heading:
            flush_paragraph()
            close_list()
            level = len(heading.group(1)) + 1  # the update window has its own title: start at <h2>
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
        elif bullet:
            flush_paragraph()
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append("<li>" + inline(bullet.group(1)) + "</li>")
        else:
            close_list()
            paragraph.append(line)
    flush_paragraph()
    close_list()
    return "\n".join(out) + "\n"


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: release-notes-html.py <notes.md> <output.html>")
    with open(sys.argv[1], encoding="utf-8") as source:
        fragment = convert(source.read())
    with open(sys.argv[2], "w", encoding="utf-8") as target:
        target.write(fragment)


if __name__ == "__main__":
    main()
