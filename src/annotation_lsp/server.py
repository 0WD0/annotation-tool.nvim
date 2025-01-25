#!/usr/bin/env python3

import os
import re
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from pathlib import Path

from pygls.server import LanguageServer
from lsprotocol import types

from .db_manager import DatabaseManager
from .note_manager import NoteManager

server = LanguageServer("annotation-lsp", "v0.1.0")
db_manager = DatabaseManager()
note_manager = NoteManager()

def find_annotation_ranges(text: str) -> List[Tuple[int, int, int, int, int]]:
	"""找出所有标注区间及其ID（基于左括号出现顺序）"""
	annotations = []
	lines = text.splitlines()
	annotation_id = 1
	
	# 使用日语半角括号作为标注区间
	left_bracket = '｢'
	right_bracket = '｣'
	
	# 遍历每一行
	for line_num, line in enumerate(lines):
		# 在当前行中查找所有左括号和右括号
		left_positions = [i for i, char in enumerate(line) if char == left_bracket]
		right_positions = [i for i, char in enumerate(line) if char == right_bracket]
		
		# 如果找到配对的括号
		if left_positions and right_positions:
			# 为每对括号创建一个标注区间
			for left_pos, right_pos in zip(left_positions, right_positions):
				if left_pos < right_pos:  # 确保左括号在右括号之前
					annotations.append((
						line_num,  # 开始行
						left_pos,  # 开始列
						line_num,  # 结束行
						right_pos,  # 结束列
						annotation_id  # 标注ID
					))
					annotation_id += 1
	
	return annotations

def get_annotation_at_position(text: str, position: types.Position) -> Optional[Tuple[int, int, int, int, int]]:
	"""获取给定位置所在的标注区间"""
	annotations = find_annotation_ranges(text)
	pos_line = position.line
	pos_char = position.character
	
	for annotation in annotations:
		start_line, start_char, end_line, end_char, aid = annotation
		if (start_line <= pos_line <= end_line and
			(start_line != pos_line or start_char <= pos_char) and
			(end_line != pos_line or pos_char <= end_char)):
			return annotation
	
	return None

@server.feature(types.INITIALIZE)
def initialize(params: types.InitializeParams) -> types.InitializeResult:
	"""初始化 LSP 服务器"""
	server.show_message("Initializing annotation LSP server...")
	
	capabilities = types.ServerCapabilities(
		text_document_sync=types.TextDocumentSyncOptions(
			open_close=True,
			change=types.TextDocumentSyncKind.FULL,
			save=True
		),
		hover_provider=True,
		execute_command_provider=types.ExecuteCommandOptions(
			commands=[
				"createAnnotation",
				"listAnnotations",
				"deleteAnnotation"
			]
		)
	)
	
	return types.InitializeResult(capabilities=capabilities)

@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
def did_open(params: types.DidOpenTextDocumentParams):
	"""文档打开时的处理"""
	server.show_message(f"Document opened: {params.text_document.uri}")

@server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
def did_change(params: types.DidChangeTextDocumentParams):
	"""文档变化时的处理"""
	server.show_message(f"Document changed: {params.text_document.uri}")

@server.feature(types.TEXT_DOCUMENT_HOVER)
def hover(params: types.HoverParams) -> Optional[types.Hover]:
	"""处理悬停事件，显示标注内容"""
	doc = server.workspace.get_document(params.text_document.uri)
	position = params.position
	
	# 检查当前位置是否在标注区间内
	annotations = find_annotation_ranges(doc.source)
	for start_line, start_char, end_line, end_char, annotation_id in annotations:
		if (start_line <= position.line <= end_line and
			(start_line != position.line or start_char <= position.character) and
			(end_line != position.line or position.character <= end_char)):
			
			note = note_manager.get_note(annotation_id)
			if note:
				return types.Hover(
					contents=types.MarkupContent(
						kind=types.MarkupKind.MARKDOWN,
						value=f"**Annotation {annotation_id}**\n\n{note}"
					),
					range=types.Range(
						start=types.Position(line=start_line, character=start_char),
						end=types.Position(line=end_line, character=end_char)
					)
				)
	
	return None

@server.command("createAnnotation")
def create_annotation(ls: LanguageServer, params: dict) -> dict:
	"""处理创建标注的逻辑"""
	# params 是一个列表，第一个元素才是我们需要的字典
	params = params[0]
	doc = ls.workspace.get_document(params["textDocument"]["uri"])
	selection_range = types.Range(
		start=types.Position(
			line=params["range"]["start"]["line"],
			character=params["range"]["start"]["character"]
		),
		end=types.Position(
			line=params["range"]["end"]["line"],
			character=params["range"]["end"]["character"]
		)
	)
	
	# 获取选中的文本
	lines = doc.source.splitlines()
	if selection_range.start.line == selection_range.end.line:
		# 单行选择
		selected_text = lines[selection_range.start.line][selection_range.start.character:selection_range.end.character]
	else:
		# 多行选择
		selected_text = []
		for i in range(selection_range.start.line, selection_range.end.line + 1):
			if i == selection_range.start.line:
				selected_text.append(lines[i][selection_range.start.character:])
			elif i == selection_range.end.line:
				selected_text.append(lines[i][:selection_range.end.character])
			else:
				selected_text.append(lines[i])
		selected_text = '\n'.join(selected_text)
	
	# 创建标注
	annotation_id = db_manager.create_annotation(
		doc_uri=params["textDocument"]["uri"],
		start_line=selection_range.start.line,
		start_char=selection_range.start.character,
		end_line=selection_range.end.line,
		end_char=selection_range.end.character,
		text=selected_text
	)
	
	server.show_message(f"Created annotation {annotation_id}")
	return {"success": True, "annotation_id": annotation_id}

@server.command("listAnnotations")
def list_annotations(ls: LanguageServer, params: dict) -> dict:
	"""处理列出标注的逻辑"""
	# params 是一个列表，第一个元素才是我们需要的字典
	params = params[0]
	doc = ls.workspace.get_document(params["textDocument"]["uri"])
	annotations = find_annotation_ranges(doc.source)
	return {"success": True, "annotations": annotations}

@server.command("deleteAnnotation")
def delete_annotation(ls: LanguageServer, params: dict) -> dict:
	"""处理删除标注的逻辑"""
	params = params[0]
	annotation_id = params["annotationId"]
	# TODO: 实现删除标注的逻辑
	ls.show_message(f"Deleted annotation {annotation_id}")
	return {"success": True}
