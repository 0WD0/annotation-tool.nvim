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
	ServerCapabilities,
	TextDocumentSyncOptions,
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
def initialize(params):
	"""初始化 LSP 服务器"""
	server.show_message("Initializing annotation LSP server...")
	
	capabilities = ServerCapabilities(
		text_document_sync=TextDocumentSyncOptions(
			open_close=True,
			change=TextDocumentSyncKind.FULL,
			save=True
		),
		hover_provider=True,
		execute_command_provider={
			"commands": [
				"textDocument/createAnnotation",
				"textDocument/listAnnotations",
				"textDocument/deleteAnnotation"
			]
		}
	)
	
	return {"capabilities": capabilities}

@server.feature(TEXT_DOCUMENT_DID_OPEN)
def did_open(params: DidOpenTextDocumentParams):
	"""文档打开时的处理"""
	server.show_message(f"Document opened: {params.text_document.uri}")

@server.feature(TEXT_DOCUMENT_DID_CHANGE)
def did_change(params: DidChangeTextDocumentParams):
	"""文档变化时的处理"""
	server.show_message(f"Document changed: {params.text_document.uri}")

@server.feature(TEXT_DOCUMENT_HOVER)
def hover(params):
	"""处理悬停事件，显示标注内容"""
	doc = server.workspace.get_document(params.text_document.uri)
	position = params.position
	
	# 检查当前位置是否在标注区间内
	annotations = server.find_annotation_ranges(doc.source)
	for start_line, start_char, end_line, end_char, annotation_id in annotations:
		if (start_line <= position.line <= end_line and
			(start_line != position.line or start_char <= position.character) and
			(end_line != position.line or position.character <= end_char)):
			
			note = server.note_manager.get_note(annotation_id)
			if note:
				return Hover(
					contents=MarkupContent(
						kind=MarkupKind.MARKDOWN,
						value=f"**Annotation {annotation_id}**\n\n{note}"
					),
					range=Range(
						start=Position(line=start_line, character=start_char),
						end=Position(line=end_line, character=end_char)
					)
				)
	
	return None

@server.command("textDocument/createAnnotation")
def create_annotation(params):
	"""处理创建标注的逻辑"""
	doc = server.workspace.get_document(params.textDocument.uri)
	range = params.range
	
	# 获取选中的文本
	lines = doc.source.splitlines()
	if range.start.line == range.end.line:
		# 单行选择
		selected_text = lines[range.start.line][range.start.character:range.end.character]
	else:
		# 多行选择
		selected_text = []
		for i in range(range.start.line, range.end.line + 1):
			if i == range.start.line:
				selected_text.append(lines[i][range.start.character:])
			elif i == range.end.line:
				selected_text.append(lines[i][:range.end.character])
			else:
				selected_text.append(lines[i])
		selected_text = '\n'.join(selected_text)
	
	# 创建标注
	annotation_id = server.db_manager.create_annotation(
		doc_uri=params.textDocument.uri,
		start_line=range.start.line,
		start_char=range.start.character,
		end_line=range.end.line,
		end_char=range.end.character,
		text=selected_text
	)
	
	return {"success": True, "annotation_id": annotation_id}

@server.command("textDocument/listAnnotations")
def list_annotations(params):
	"""处理列出标注的逻辑"""
	doc = server.workspace.get_document(params.textDocument.uri)
	return {"success": True}

@server.command("textDocument/deleteAnnotation")
def delete_annotation(params):
	"""处理删除标注的逻辑"""
	doc = server.workspace.get_document(params.textDocument.uri)
	annotation_id = params.annotationId
	return {"success": True}
