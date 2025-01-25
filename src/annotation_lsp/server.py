#!/usr/bin/env python3

import os
import re
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from pathlib import Path

from pygls.server import LanguageServer
from lsprotocol.types import (
	TextDocumentSyncKind,
	DidChangeTextDocumentParams,
	DidOpenTextDocumentParams,
	Hover,
	Position,
	Range,
	MarkupContent,
	MarkupKind,
	TEXT_DOCUMENT_HOVER,
	TEXT_DOCUMENT_DID_OPEN,
	TEXT_DOCUMENT_DID_CHANGE,
	INITIALIZE,
)

from .db_manager import DatabaseManager
from .note_manager import NoteManager

class AnnotationServer(LanguageServer):
	def __init__(self):
		super().__init__(
			name="annotation-lsp",
			version="0.1.0",
		)
		self.annotation_brackets = ('｢', '｣')  # 使用日语半角括号作为标注区间
		self.db_manager = DatabaseManager()
		self.note_manager = NoteManager()

	def get_project_root(self, file_path: str) -> Optional[str]:
		"""查找包含.annotation目录的最近父目录"""
		current = Path(file_path).parent
		while current != current.parent:
			if (current / ".annotation").exists():
				return str(current)
			current = current.parent
		return None

	def find_annotation_ranges(self, text: str) -> List[Tuple[int, int, int, int, int]]:
		"""找出所有标注区间及其ID（基于左括号出现顺序）"""
		lines = text.splitlines()
		annotations = []
		annotation_id = 1
		
		for line_num, line in enumerate(lines):
			start_idx = 0
			while True:
				start_pos = line.find(self.annotation_brackets[0], start_idx)
				if start_pos == -1:
					break
					
				# 寻找对应的结束括号
				end_line_num = line_num
				end_pos = line.find(self.annotation_brackets[1], start_pos + 1)
				
				while end_pos == -1 and end_line_num < len(lines) - 1:
					end_line_num += 1
					end_pos = lines[end_line_num].find(self.annotation_brackets[1])
				
				if end_pos != -1:
					annotations.append((
						annotation_id,
						line_num,
						start_pos,
						end_line_num,
						end_pos
					))
					annotation_id += 1
				
				start_idx = start_pos + 1
				
		return annotations

	def get_annotation_at_position(self, text: str, position: Position) -> Optional[Tuple[int, int, int, int, int]]:
		"""获取给定位置所在的标注区间"""
		annotations = self.find_annotation_ranges(text)
		pos_line = position.line
		pos_char = position.character
		
		for annotation in annotations:
			aid, start_line, start_char, end_line, end_char = annotation
			
			# 检查位置是否在标注范围内
			if (pos_line > start_line or (pos_line == start_line and pos_char >= start_char)) and \
			   (pos_line < end_line or (pos_line == end_line and pos_char <= end_char)):
				return annotation
				
		return None

server = AnnotationServer()

@server.feature(INITIALIZE)
def initialize(ls: AnnotationServer, params):
	"""初始化 LSP 服务器"""
	ls.show_message("Initializing annotation LSP server...")
	
	# 注册自定义方法
	custom_methods = [
		'textDocument/createAnnotation',
		'textDocument/listAnnotations',
		'textDocument/deleteAnnotation',
	]
	
	capabilities = {
		'textDocumentSync': {
			'openClose': True,
			'change': TextDocumentSyncKind.INCREMENTAL,
		},
		'hoverProvider': True,
	}
	
	# 添加自定义方法到服务器能力中
	for method in custom_methods:
		capabilities[method] = True
	
	return {'capabilities': capabilities}

@server.feature(TEXT_DOCUMENT_DID_OPEN)
def did_open(ls: AnnotationServer, params: DidOpenTextDocumentParams):
	"""文档打开时的处理"""
	doc = ls.workspace.get_document(params.text_document.uri)
	ranges = ls.find_annotation_ranges(doc.source)
	ls.show_message(f"Opened {doc.uri}")
	# TODO: Validate annotations and update database

@server.feature(TEXT_DOCUMENT_DID_CHANGE)
def did_change(ls: AnnotationServer, params: DidChangeTextDocumentParams):
	"""文档变化时的处理"""
	doc = ls.workspace.get_document(params.text_document.uri)
	ranges = ls.find_annotation_ranges(doc.source)
	# TODO: Update database with new ranges

@server.feature(TEXT_DOCUMENT_HOVER)
def hover(ls: AnnotationServer, params):
	"""处理悬停事件，显示标注内容"""
	doc = ls.workspace.get_document(params.text_document.uri)
	annotation = ls.get_annotation_at_position(doc.source, params.position)
	
	if annotation:
		aid, start_line, start_char, end_line, end_char = annotation
		# TODO: Get annotation content from database/file
		content = "Annotation #" + str(aid)  # Placeholder
		return Hover(
			contents=MarkupContent(kind=MarkupKind.Markdown, value=content),
			range=Range(
				start=Position(line=start_line, character=start_char),
				end=Position(line=end_line, character=end_char + 1)
			)
		)
	return None

@server.feature('textDocument/createAnnotation')
def create_annotation(ls: AnnotationServer, params):
	"""处理创建标注的逻辑"""
	ls.show_message("Creating annotation...")
	doc = ls.workspace.get_document(params.textDocument.uri)
	start = params.range.start
	end = params.range.end
	
	# 在文本中插入标注括号
	lines = doc.source.splitlines()
	start_line = lines[start.line]
	end_line = lines[end.line]
	
	# 插入结束括号
	new_end_line = (
		end_line[:end.character] + 
		ls.annotation_brackets[1] + 
		end_line[end.character:]
	)
	lines[end.line] = new_end_line
	
	# 插入开始括号
	new_start_line = (
		start_line[:start.character] + 
		ls.annotation_brackets[0] + 
		start_line[start.character:]
	)
	lines[start.line] = new_start_line
	
	# 更新文档
	new_text = '\n'.join(lines)
	ls.apply_edit(doc.uri, new_text)
	ls.show_message("Annotation created successfully!")
	
	return {"success": True}

@server.feature('textDocument/listAnnotations')
def list_annotations(ls: AnnotationServer, params):
	"""处理列出标注的逻辑"""
	doc = ls.workspace.get_document(params.textDocument.uri)
	annotations = ls.find_annotation_ranges(doc.source)
	return {"annotations": annotations}

@server.feature('textDocument/deleteAnnotation')
def delete_annotation(ls: AnnotationServer, params):
	"""处理删除标注的逻辑"""
	doc = ls.workspace.get_document(params.textDocument.uri)
	annotation_id = params.annotationId
	return {"success": True}
