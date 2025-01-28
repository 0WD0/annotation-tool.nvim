#!/usr/bin/env python3

import os
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

from pygls.server import LanguageServer
from lsprotocol import types

from .db_manager import DatabaseManager, DatabaseError
from .note_manager import NoteManager
from .config import config, initialize_config
from .utils import *
from .logger import *

class AnnotationServer(LanguageServer):
	def __init__(self):
		super().__init__("annotation-lsp", "v0.1.0")
		logger.set_server(self)

server = AnnotationServer()
db_manager = DatabaseManager()
note_manager = NoteManager()

@server.feature(types.INITIALIZE)
def initialize(params: types.InitializeParams) -> types.InitializeResult:
	"""初始化 LSP 服务器"""
	server.show_message("Initializing annotation LSP server...")
	
	# 设置工作目录
	root_path = None
	if params.root_uri:
		root_path = urlparse(params.root_uri).path
		os.chdir(root_path)
		db_manager.init_db(root_path)
		note_manager.init_project(root_path)
	
	# 初始化配置
	init_options = params.initialization_options if hasattr(params, 'initialization_options') else None
	initialize_config(init_options, root_path)

	capabilities = types.ServerCapabilities(
		text_document_sync=types.TextDocumentSyncOptions(
			open_close=True,
			change=types.TextDocumentSyncKind.Full,
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
def hover(ls: LanguageServer, params: types.HoverParams) -> Optional[types.Hover]:
	"""处理悬停请求"""
	try:
		# 获取当前位置的标注
		doc = ls.workspace.get_document(params.text_document.uri)
		annotation_id = get_annotation_at_position(doc, params.position)
		if not annotation_id:
			error("Failed to get current annotation_id")
			return None

		info(f"Current doc_uri is {doc.uri}")
		info(f"Current annotation_id is {annotation_id}")
		
		# 获取笔记内容
		note_file = db_manager.get_annotation_note_file(doc.uri, annotation_id)
		if not note_file:
			error("Failed to get note file path")
			return None
		
		note_content = note_manager.get_note_content(note_file)
		if not note_content:
			error("Failed to get note file contents")
			return types.Hover(contents=[])
			
		# 只显示 ## Notes 后面的内容
		notes_content = extract_notes_content(note_content)
		if not notes_content:
			server.show_message("Empty note", types.MessageType.Info)
			return types.Hover(contents=[])
			
		return types.Hover(contents=types.MarkupContent(
			kind=types.MarkupKind.Markdown,
			value=notes_content
		))
	except Exception as e:
		server.show_message(f"Failed to hover: {str(e)}", types.MessageType.Error)
		return None

@server.command("createAnnotation")
def create_annotation(ls: LanguageServer, params: Dict) -> Dict:
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

		selected_text = get_text_in_range(doc,selection_range)
		annotation_id = get_annotation_id_before_position(doc,selection_range.start)
		if annotation_id == None:
			error("Failed to get annotation_id before left bracket")
			return {"success": False, "error": "1"}
		annotation_id += 1

		db_manager.increase_annotation_ids(doc.uri,annotation_id)
		
		# 创建标注
		note_file = db_manager.create_annotation(
			doc_uri=doc.uri,
			annotation_id = annotation_id
		)
		
		# 在原文中插入日语半角括号
		edits = [
			types.TextEdit(
				range=types.Range(
					start=selection_range.start,
					end=selection_range.start
				),
				new_text=config.left_bracket
			),
			types.TextEdit(
				range=types.Range(
					start=selection_range.end,
					end=selection_range.end
				),
				new_text=config.right_bracket
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
def list_annotations(ls: LanguageServer, params: Dict) -> Dict:
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
def delete_annotation(ls: LanguageServer, param: Dict) -> Dict:
	"""处理删除标注的逻辑"""
	try:
		params = param[0]
		doc = ls.workspace.get_document(params["textDocument"]["uri"])
		position = types.Position(
			line=params['position']['line'],
			character=params['position']['character']
		)
		annotation_id = get_annotation_at_position(doc,position)
		if annotation_id == None:
			error("Failed to get annotation_id")
			return {"success": False}
		
		# 获取笔记文件名
		note_file = db_manager.get_annotation_note_file(doc.uri, annotation_id)
		if not note_file:
			error("Annotation not found")
			return {"success": False}
		
		# 删除标注记录
		if not db_manager.delete_annotation(doc.uri, annotation_id):
			error("Failed to delete annotation in database")
			return {"success": False}

		annotations = find_annotation_Ranges(doc)
		if annotations == None:
			error("Delete annotation: Failed to get annotations")
			return {"success": False}

		current_annotation_range = annotations[annotation_id-1]

		edits = [
			types.TextEdit(
				range=types.Range(
					start=current_annotation_range.start,
					end=types.Position(
						line=current_annotation_range.start.line,
						character=current_annotation_range.start.character+1
					)
				),
				new_text=""
			),
			types.TextEdit(
				range=types.Range(
					start=current_annotation_range.end,
					end=types.Position(
						line=current_annotation_range.end.line,
						character=current_annotation_range.end.character+1
					)
				),
				new_text=""
			)
		]
		
		edit = types.WorkspaceEdit(
			changes={doc.uri: edits}
		)
		ls.apply_edit(edit)

		db_manager.increase_annotation_ids(doc.uri, annotation_id, -1)
		
		# 删除笔记文件
		note_manager.delete_note(note_file)
		
		return {"success": True}
	except DatabaseError as e:
		error(f"Database error: {str(e)}")
		return {"success": False, "error": str(e)}
	except Exception as e:
		error(f"Failed to delete annotation: {str(e)}")
		return {"success": False, "error": str(e)}
