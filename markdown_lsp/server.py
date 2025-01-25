#!/usr/bin/env python3

import re
from typing import List, Optional

from pygls.server import LanguageServer
from lsprotocol import types
from markdown_it import MarkdownIt

server = LanguageServer("markdown-server", "v0.1")

@server.feature(types.TEXT_DOCUMENT_COMPLETION)
def completions(params: types.CompletionParams) -> types.CompletionList:
    """Provide completion items."""
    items = []
    
    # Basic Markdown syntax completions
    markdown_completions = [
        ("**", "Bold text"),
        ("*", "Italic text"),
        ("```", "Code block"),
        ("#", "Heading 1"),
        ("##", "Heading 2"),
        ("###", "Heading 3"),
        ("- [ ]", "Task list item"),
        ("|", "Table cell"),
        ("---", "Horizontal rule"),
        ("![", "Image"),
        ("[", "Link"),
        (">", "Blockquote"),
    ]
    
    for text, detail in markdown_completions:
        items.append(
            types.CompletionItem(
                label=text,
                detail=detail,
                kind=types.CompletionItemKind.Snippet
            )
        )
    
    return types.CompletionList(
        is_incomplete=False,
        items=items
    )

@server.feature(types.TEXT_DOCUMENT_HOVER)
def hover(params: types.HoverParams) -> Optional[types.Hover]:
    """Provide hover information."""
    document = server.workspace.get_document(params.text_document.uri)
    position = params.position
    
    word = get_word_at_position(document, position)
    if not word:
        return None
    
    # Provide hover information for common Markdown syntax
    hover_info = {
        "**": "Bold text: Wrap text with double asterisks",
        "*": "Italic text: Wrap text with single asterisks",
        "#": "Heading: Use 1-6 hash symbols for different heading levels",
        "```": "Code block: Wrap code with triple backticks",
        "-": "List item: Start a line with hyphen for unordered list",
        "1.": "Numbered list: Start a line with number and dot",
        ">": "Blockquote: Start a line with greater than symbol",
        "[": "Link: [Link text](URL)",
        "!": "Image: ![Alt text](URL)",
    }
    
    if word in hover_info:
        return types.Hover(
            contents=types.MarkupContent(
                kind=types.MarkupKind.Markdown,
                value=hover_info[word]
            )
        )
    
    return None

def get_word_at_position(document, position):
    """Get the word at the given position."""
    line = document.lines[position.line]
    
    # Simple word extraction
    word_match = re.match(r'[\w\*\#\`\-\>\[\!]+', line[position.character:])
    if word_match:
        return word_match.group(0)
    return None

if __name__ == "__main__":
    server.start_io()
