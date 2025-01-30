#!/usr/bin/env python3

from typing import Dict, Optional, List

from pygls.server import LanguageServer
from lsprotocol import types

from .config import initialize_config
from .workspace_manager import workspace_manager
from .utils import *
from .logger import *

class AnnotationServer(LanguageServer):
	def __init__(self):
		super().__init__("annotation-ls", "v1.0")
		logger.set_server(self)

server = AnnotationServer()

@server.feature(types.INITIALIZE)
def initialize(params: types.InitializeParams) -> types.InitializeResult:
	"""初始化 LSP 服务器"""
	info("Initializing annotation LSP server...")
	
	# 初始化配置
	init_options = params.initialization_options if hasattr(params, 'initialization_options') else None
	initialize_config(init_options)

	# 初始化工作区
	root_uri = params.root_uri
	if root_uri:
		info(f"Building workspace tree from root: {root_uri}")
		workspace_manager.add_workspace(root_uri)

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
				"deleteAnnotation",
				"getAnnotationNote",
				# "queryAnnotations"
			]
		),
		document_highlight_provider=True
	)
	
	return types.InitializeResult(capabilities=capabilities)

@server.feature("workspace/didChangeWorkspaceFolders")
def did_change_workspace_folders(params: types.DidChangeWorkspaceFoldersParams):
	"""处理工作区变化事件"""
	try:
		if params.event.added:
			for folder in params.event.added:
				workspace_manager.add_workspace(folder.uri)
		
		if params.event.removed:
			for folder in params.event.removed:
				workspace_manager.remove_workspace(folder.uri)
	except Exception as e:
		error(f"Error handling workspace folders change: {str(e)}")

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
			return None

		# 获取工作区
		workspace = workspace_manager.get_workspace(doc.uri)
		if not workspace:
			error(f"No workspace found for {doc.uri}")
			return None
		db_manager = workspace.db_manager
		note_manager = workspace.note_manager
		
		# 获取笔记文件
		note_file = db_manager.get_annotation_note_file(doc.uri, annotation_id)
		if not note_file:
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
			
		return types.Hover(
			contents=types.MarkupContent(
				kind=types.MarkupKind.Markdown,
				value=notes_content
			)
		)
	except Exception as e:
		error(f"Error in hover: {str(e)}")
		return None

@server.feature(types.TEXT_DOCUMENT_DOCUMENT_HIGHLIGHT)
def document_highlight(ls: LanguageServer, params: types.DocumentHighlightParams) -> Optional[List[types.DocumentHighlight]]:
	"""处理文档高亮请求，返回需要高亮的区域"""
	try:
		doc = ls.workspace.get_document(params.text_document.uri)
		position = params.position
		
		# 获取光标位置的标注
		annotation_id = get_annotation_at_position(doc, position)
		if annotation_id == None:
			return None

		annotations = find_annotation_Ranges(doc)
		if annotations == None:
			raise Exception("Failed to get annotation ranges")

		current_annotation_range = annotations[annotation_id-1]
			
		# 返回标注范围的高亮
		return [types.DocumentHighlight(
			range=current_annotation_range
		)]
		
	except Exception as e:
		error(f"Error highlighting document: {str(e)}")
		return None

@server.command("createAnnotation")
def create_annotation(ls: LanguageServer, params: Dict) -> Optional[Dict]:
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

		# 获取工作区
		workspace = workspace_manager.get_workspace(doc.uri)
		if not workspace:
			raise Exception(f"No workspace found for {doc.uri}")
		db_manager = workspace.db_manager
		note_manager = workspace.note_manager
		db_manager.increase_annotation_ids(doc.uri,annotation_id)
		
		# 创建标注
		note_file = db_manager.create_annotation(doc.uri, annotation_id)
		
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
		note_path = note_manager.create_annotation_note(
			doc.uri, annotation_id, selected_text, note_file
		)
		if not note_path:
			raise Exception("Failed to create note file")

		return {"success": True, "note_file": note_path}

	except Exception as e:
		error(f"Failed to create annotation: {str(e)}")
		return {"success": False, "error": str(e)}

@server.command("listAnnotations")
def list_annotations(ls: LanguageServer, params: Dict) -> Optional[Dict]:
	"""处理列出标注的逻辑"""
	try:
		params = params[0]
		doc = ls.workspace.get_document(params["textDocument"]["uri"])
		# 获取工作区
		workspace = workspace_manager.get_workspace(doc.uri)
		if not workspace:
			raise Exception(f"No workspace found for {doc.uri}")

		# 获取文件的所有标注
		annotations = workspace.db_manager.get_file_annotations(doc.uri)
		return {"annotations": annotations}

	except Exception as e:
		error(f"Failed to list annotations: {str(e)}")
		return {"success": False, "error": str(e)}

@server.command("deleteAnnotation")
def delete_annotation(ls: LanguageServer, params: Dict) -> Dict:
	"""处理删除标注的逻辑"""
	try:
		params = params[0]
		doc = ls.workspace.get_document(params["textDocument"]["uri"])
		position = types.Position(
			line=params['position']['line'],
			character=params['position']['character']
		)
		annotation_id = get_annotation_at_position(doc,position)
		if annotation_id == None:
			raise Exception("Failed to get annotation_id")
		
		# 获取工作区
		workspace = workspace_manager.get_workspace(doc.uri)
		if not workspace:
			raise Exception(f"No workspace found for {doc.uri}")
		db_manager = workspace.db_manager
		note_manager = workspace.note_manager

		# 获取笔记文件路径
		note_file = db_manager.get_annotation_note_file(doc.uri, annotation_id)
		if not note_file:
			raise Exception("Annotation not found")

		# 删除标注记录
		if not db_manager.delete_annotation(doc.uri, annotation_id):
			raise Exception("Failed to delete annotation in database")

		annotations = find_annotation_Ranges(doc)
		if annotations == None:
			raise Exception("Failed to get annotation ranges")

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
		
		return {"note_file": note_file}
	except Exception as e:
		error(f"Failed to delete annotation: {str(e)}")
		return {"success": False, "error": str(e)}

@server.command("getAnnotationNote")
def get_annotation_note(ls: LanguageServer, params: Dict) -> Optional[Dict]:
	"""获取当前位置的批注文件"""
	try:
		params = params[0]
		# 获取文档和位置
		doc = ls.workspace.get_document(params["textDocument"]["uri"])
		position = types.Position(
			line=params['position']['line'],
			character=params['position']['character']
		)
		
		# 获取当前位置的批注
		annotation_id = get_annotation_at_position(doc, position)
		if not annotation_id:
			raise Exception("No annotation found at current position")
			
		# 获取工作区
		workspace = workspace_manager.get_workspace(doc.uri)
		if not workspace:
			raise Exception(f"No workspace found for {doc.uri}")
			
		# 获取笔记文件路径
		note_file = workspace.db_manager.get_annotation_note_file(doc.uri, annotation_id)
		if not note_file:
			raise Exception("Annotation note file not found")
			
		return {
			"note_file": note_file,
			"workspace_path": workspace.root_path,  
			"annotation_id": annotation_id
		}
			
	except Exception as e:
		error(f"Error getting annotation note: {str(e)}")
		return None

# @server.command("queryAnnotations")
# def query_annotations(ls: LanguageServer, params: Dict) -> Optional[Dict]:
# 	"""处理查询标注的命令"""
# 	try:
# 		query_params = params[0]
# 		current_workspace = workspace_manager.get_workspace(query_params['textDocument']['uri'])
# 		if not current_workspace:
# 			return {"annotations": []}

# 		# 根据查询范围获取工作区列表
# 		workspaces_to_query = []
# 		query_scope = query_params.get('scope', 'current')  # current, subtree, ancestors, all
# 		
# 		if query_scope == 'current':
# 			workspaces_to_query = [current_workspace]
# 		elif query_scope == 'subtree':
# 			workspaces_to_query = current_workspace.get_subtree_workspaces()
# 		elif query_scope == 'ancestors':
# 			workspaces_to_query = current_workspace.get_ancestor_workspaces()
# 		elif query_scope == 'all':
# 			workspaces_to_query = workspace_manager.root.get_subtree_workspaces()

# 		# 在所有相关工作区中查询
# 		all_annotations = []
# 		for workspace in workspaces_to_query:
# 			annotations = workspace.db_manager.query_annotations(
# 				query_params.get('query', ''),
# 				query_params.get('file_pattern', '*')
# 			)
# 			all_annotations.extend(annotations)

# 		return {"annotations": all_annotations}

# 	except Exception as e:
# 		error(f"Error querying annotations: {str(e)}")
# 		return {"success": False, "error": str(e)}
