#!/usr/bin/env python3

import os
import re
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

from pygls.server import LanguageServer
from lsprotocol import types

from .db_manager import DatabaseManager, DatabaseError
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
	
	# 设置工作目录
	if params.root_uri:
		root_path = urlparse(params.root_uri).path
		os.chdir(root_path)
		db_manager.init_db(root_path)
		note_manager.init_project(root_path)
	
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
		),
	)
	
	return types.InitializeResult(capabilities=capabilities)

@server.feature("workspace/didChangeWorkspaceFolders")
def did_change_workspace_folders(params: types.DidChangeWorkspaceFoldersParams):
	"""处理工作区变化事件"""
	if params.event.added:
		# 使用新添加的第一个工作区
		root_uri = params.event.added[0].uri
		root_path = urlparse(root_uri).path
		db_manager.init_db(root_path)
		note_manager.init_project(root_path)

@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
def did_open(params: types.DidOpenTextDocumentParams):
	"""文档打开时的处理"""
	server.show_message(f"Document opened: {params.text_document.uri}")

@server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
def did_change(params: types.DidChangeTextDocumentParams):
	"""文档变化时的处理"""
	server.show_message(f"Document changed: {params.text_document.uri}")

@server.feature(types.TEXT_DOCUMENT_HOVER)
def hover(params: types.HoverParams) -> types.Hover:
	"""处理悬停事件，显示标注内容"""
	doc = server.workspace.get_document(params.text_document.uri)
	
	# 获取当前位置的标注
	annotation = get_annotation_at_position(doc.source, params.position)
	if not annotation:
		return types.Hover(contents=[])
	
	start_line, start_char, end_line, end_char, annotation_id = annotation
	
	# 获取笔记文件
	note_file = db_manager.get_annotation_note_file(params.text_document.uri, annotation_id)
	if not note_file:
		return types.Hover(contents=[])
	
	# 读取笔记内容
	note_content = note_manager.get_note_content(note_file)
	if not note_content:
		return types.Hover(contents=[])
	
	return types.Hover(contents=[types.MarkupContent(
		kind=types.MarkupKind.Markdown,
		value=note_content
	)])

@server.command("createAnnotation")
def create_annotation(ls: LanguageServer, params: dict) -> dict:
	"""处理创建标注的逻辑"""
	try:
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
		annotation_id, note_file = db_manager.create_annotation(
			doc_uri=params["textDocument"]["uri"],
			start_line=selection_range.start.line,
			start_char=selection_range.start.character,
			end_line=selection_range.end.line,
			end_char=selection_range.end.character,
			text=selected_text
		)
		
		# 在原文中插入日语半角括号
		edits = [
			types.TextEdit(
				range=types.Range(
					start=types.Position(line=selection_range.start.line, character=selection_range.start.character),
					end=types.Position(line=selection_range.start.line, character=selection_range.start.character)
				),
				new_text="｢"
			),
			types.TextEdit(
				range=types.Range(
					start=types.Position(line=selection_range.end.line, character=selection_range.end.character),
					end=types.Position(line=selection_range.end.line, character=selection_range.end.character)
				),
				new_text="｣"
			)
		]
		
		edit = types.WorkspaceEdit(
			changes={params["textDocument"]["uri"]: edits}
		)
		ls.apply_edit(edit)
		
		# 创建笔记文件
		note_manager.create_annotation_note(
			file_path=params["textDocument"]["uri"],
			annotation_id=annotation_id,
			text=selected_text,
			note_file=note_file
		)
		
		return {"success": True, "annotationId": annotation_id}
	except DatabaseError as e:
		ls.show_message(f"Database error: {str(e)}", types.MessageType.Error)
		return {"success": False, "error": str(e)}
	except Exception as e:
		ls.show_message(f"Failed to create annotation: {str(e)}", types.MessageType.Error)
		return {"success": False, "error": str(e)}

@server.command("listAnnotations")
def list_annotations(ls: LanguageServer, params: dict) -> dict:
	"""处理列出标注的逻辑"""
	try:
		# params 是一个列表，第一个元素才是我们需要的字典
		params = params[0]
		doc = ls.workspace.get_document(params["textDocument"]["uri"])
		annotations = db_manager.get_file_annotations(doc.uri)
		return {"success": True, "annotations": annotations}
	except DatabaseError as e:
		ls.show_message(f"Database error: {str(e)}", types.MessageType.Error)
		return {"success": False, "error": str(e)}
	except Exception as e:
		ls.show_message(f"Failed to list annotations: {str(e)}", types.MessageType.Error)
		return {"success": False, "error": str(e)}

@server.command("deleteAnnotation")
def delete_annotation(ls: LanguageServer, params: dict) -> dict:
	"""处理删除标注的逻辑"""
	try:
		# params 是一个列表，第一个元素才是我们需要的字典
		params = params[0]
		doc_uri = params["textDocument"]["uri"]
		annotation_id = params["annotationId"]
		
		# 获取笔记文件名
		note_file = db_manager.get_annotation_note_file(doc_uri, annotation_id)
		if not note_file:
			return {"success": False, "error": "Annotation not found"}
		
		# 删除标注记录
		if not db_manager.delete_annotation(doc_uri, annotation_id):
			return {"success": False, "error": "Failed to delete annotation"}
		
		# 删除笔记文件
		note_manager.delete_note(note_file)
		
		return {"success": True}
	except DatabaseError as e:
		ls.show_message(f"Database error: {str(e)}", types.MessageType.Error)
		return {"success": False, "error": str(e)}
	except Exception as e:
		ls.show_message(f"Failed to delete annotation: {str(e)}", types.MessageType.Error)
		return {"success": False, "error": str(e)}
