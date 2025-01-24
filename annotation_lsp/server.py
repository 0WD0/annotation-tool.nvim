#!/usr/bin/env python3

import os
import re
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from pathlib import Path

from pygls.server import LanguageServer
from pygls.lsp.methods import (
    TEXT_DOCUMENT_DID_CHANGE,
    TEXT_DOCUMENT_DID_OPEN,
    TEXT_DOCUMENT_HOVER,
)
from pygls.lsp.types import (
    Hover,
    Position,
    Range,
    MarkupContent,
    MarkupKind,
)

from .db_manager import DatabaseManager
from .note_manager import NoteManager

class AnnotationServer(LanguageServer):
    def __init__(self):
        super().__init__()
        self.annotation_brackets = ('｢', '｣')  # 使用日语半角括号作为标注区间
        self.db_manager = DatabaseManager()
        self.note_manager = NoteManager()
        
    def get_project_root(self, file_path: str) -> Optional[str]:
        """查找包含.annotation目录的最近父目录"""
        current = Path(file_path).parent
        while current != current.parent:
            if (current / '.annotation').is_dir():
                return str(current)
            current = current.parent
        return None

    def find_annotation_ranges(self, text: str) -> List[Tuple[Range, int]]:
        """找出所有标注区间及其ID（基于左括号出现顺序）"""
        left_bracket, right_bracket = self.annotation_brackets
        ranges = []
        stack = []
        annotation_id = 1
        
        lines = text.split('\n')
        for line_num, line in enumerate(lines):
            pos = 0
            while pos < len(line):
                if line[pos:].startswith(left_bracket):
                    stack.append((line_num, pos, annotation_id))
                    annotation_id += 1
                elif line[pos:].startswith(right_bracket) and stack:
                    start_line, start_char, aid = stack.pop()
                    ranges.append((
                        Range(
                            start=Position(line=start_line, character=start_char),
                            end=Position(line=line_num, character=pos + len(right_bracket))
                        ),
                        aid
                    ))
                pos += 1
                
        return ranges

    def get_annotation_at_position(self, text: str, position: Position) -> Optional[Tuple[Range, int]]:
        """获取给定位置所在的标注区间"""
        ranges = self.find_annotation_ranges(text)
        for range_obj, aid in ranges:
            if (range_obj.start.line < position.line or 
                (range_obj.start.line == position.line and range_obj.start.character <= position.character)) and \
               (range_obj.end.line > position.line or 
                (range_obj.end.line == position.line and range_obj.end.character >= position.character)):
                return (range_obj, aid)
        return None

server = AnnotationServer()

@server.feature(TEXT_DOCUMENT_DID_OPEN)
def did_open(ls: AnnotationServer, params):
    """文档打开时的处理"""
    doc = ls.workspace.get_document(params.text_document.uri)
    ranges = ls.find_annotation_ranges(doc.source)
    # TODO: Validate annotations and update database

@server.feature(TEXT_DOCUMENT_DID_CHANGE)
def did_change(ls: AnnotationServer, params):
    """文档变化时的处理"""
    doc = ls.workspace.get_document(params.text_document.uri)
    ranges = ls.find_annotation_ranges(doc.source)
    # TODO: Update database with new ranges

@server.feature(TEXT_DOCUMENT_HOVER)
async def hover(ls: AnnotationServer, params):
    """处理悬停事件，显示标注内容"""
    doc = ls.workspace.get_document(params.text_document.uri)
    annotation = ls.get_annotation_at_position(doc.source, params.position)
    
    if annotation:
        range_obj, aid = annotation
        # TODO: Get annotation content from database/file
        content = "Annotation #" + str(aid)  # Placeholder
        return Hover(
            contents=MarkupContent(kind=MarkupKind.Markdown, value=content),
            range=range_obj
        )
    return None

def main():
    server.start_io()
