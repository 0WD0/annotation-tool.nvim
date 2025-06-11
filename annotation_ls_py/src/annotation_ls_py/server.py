#!/usr/bin/env python3

from typing import Dict, Optional, List

from pygls.server import LanguageServer
from lsprotocol import types

from .config import initialize_config
from .workspace_manager import workspace_manager
from .utils import *
from .logger import *
import pathlib


class AnnotationServer(LanguageServer):
	def __init__(self):
		"""
		初始化 AnnotationServer 实例，设置服务器名称和版本，并关联日志记录器到该服务器实例。
		"""
		super().__init__("annotation_ls", "v0.1.0")
		logger.set_server(self)


server = AnnotationServer()


@server.feature(types.INITIALIZE)
def initialize(params: types.InitializeParams) -> types.InitializeResult:
	"""
	初始化并配置注解 LSP 服务器，设置服务器能力并添加工作区。

	Args:
		params: LSP 初始化参数，包含初始化选项和根目录 URI。

	Returns:
		服务器能力的初始化结果，用于告知客户端支持的功能。
	"""
	info("Initializing annotation LSP server...")

	# 初始化配置
	init_options = (
		params.initialization_options if hasattr(params, "initialization_options") else None
	)
	initialize_config(init_options)

	# 初始化工作区
	root_uri = params.root_uri
	if root_uri:
		info(f"Building workspace tree from root: {root_uri}")
		workspace_manager.add_workspace(root_uri)

	capabilities = types.ServerCapabilities(
		text_document_sync=types.TextDocumentSyncOptions(
			open_close=True, change=types.TextDocumentSyncKind.Full, save=True
		),
		hover_provider=True,
		execute_command_provider=types.ExecuteCommandOptions(
			commands=[
				"createAnnotation",
				"listAnnotations",
				"deleteAnnotation",
				"deleteAnnotationR",
				"getAnnotationNote",
				"getAnnotationSource",
				"queryAnnotations",
			]
		),
		document_highlight_provider=True,
	)

	return types.InitializeResult(capabilities=capabilities)


@server.feature("workspace/didChangeWorkspaceFolders")
def did_change_workspace_folders(params: types.DidChangeWorkspaceFoldersParams):
	"""
	处理工作区文件夹变更事件。

	根据 LSP 通知，添加或移除相应的工作区文件夹。
	"""
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
	"""
	处理文档打开事件。

	当文档被打开时，显示包含文档 URI 的提示消息。
	"""
	server.show_message(f"Document opened: {params.text_document.uri}")


@server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
def did_change(params: types.DidChangeTextDocumentParams):
	"""
	处理文档内容变更事件。

	在文档发生更改时触发，显示变更文档的 URI 信息。
	"""
	server.show_message(f"Document changed: {params.text_document.uri}")


@server.feature(types.TEXT_DOCUMENT_HOVER)
def hover(ls: LanguageServer, params: types.HoverParams) -> Optional[types.Hover]:
	"""
	在悬停于标注位置时，显示对应注释笔记的内容。

	当用户将光标悬停在带有标注的文本上时，检索并展示该标注关联的笔记内容（仅显示“## Notes”标题后的部分），以 Markdown 格式返回。如果未找到标注或笔记内容为空，则不显示悬停信息。
	"""
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
			contents=types.MarkupContent(kind=types.MarkupKind.Markdown, value=notes_content)
		)
	except Exception as e:
		error(f"Error in hover: {str(e)}")
		return None


@server.feature(types.TEXT_DOCUMENT_DOCUMENT_HIGHLIGHT)
def document_highlight(
	ls: LanguageServer, params: types.DocumentHighlightParams
) -> Optional[List[types.DocumentHighlight]]:
	"""
	处理文档高亮请求，根据光标位置返回对应标注的高亮区域。

	Args:
		params: 包含文档 URI 和光标位置信息的参数。

	Returns:
		若光标处存在标注，则返回该标注范围的高亮列表；否则返回 None。
	"""
	try:
		doc = ls.workspace.get_document(params.text_document.uri)
		position = params.position

		# 获取光标位置的标注
		annotation_id = get_annotation_at_position(doc, position)
		if annotation_id is None:
			return None

		annotations = find_annotation_Ranges(doc)
		if annotations is None:
			raise Exception("Failed to get annotation ranges")

		current_annotation_range = annotations[annotation_id - 1]

		# 返回标注范围的高亮
		return [types.DocumentHighlight(range=current_annotation_range)]

	except Exception as e:
		error(f"Error highlighting document: {str(e)}")
		return None


@server.command("createAnnotation")
def create_annotation(ls: LanguageServer, params: Dict) -> Optional[Dict]:
	"""
	创建新的文本标注并生成对应的笔记文件。

	处理选中文本范围的标注创建，包括分配标注ID、插入标注括号、更新数据库、生成笔记文件，并返回操作结果。

	参数:
		params: 包含文档URI和选中范围等信息的字典。

	返回:
		包含操作是否成功、笔记文件路径和工作区根路径的字典；若失败则包含错误信息。
	"""
	try:
		# params 是一个列表，第一个元素才是我们需要的字典
		params = params[0]
		doc = ls.workspace.get_document(params["textDocument"]["uri"])
		selection_range = types.Range(
			start=types.Position(
				line=params["range"]["start"]["line"],
				character=params["range"]["start"]["character"],
			),
			end=types.Position(
				line=params["range"]["end"]["line"],
				character=params["range"]["end"]["character"],
			),
		)

		selected_text = get_text_in_range(doc, selection_range)
		annotation_id = get_annotation_id_before_position(doc, selection_range.start)
		if annotation_id is None:
			error("Failed to get annotation_id before left bracket")
			return {"success": False, "error": "1"}
		annotation_id += 1

		# 获取工作区
		workspace = workspace_manager.get_workspace(doc.uri)
		if not workspace:
			raise Exception(f"No workspace found for {doc.uri}")
		db_manager = workspace.db_manager
		note_manager = workspace.note_manager
		db_manager.increase_annotation_ids(doc.uri, annotation_id)

		# 创建标注
		note_file = db_manager.create_annotation(doc.uri, annotation_id)

		# 在原文中插入日语半角括号
		edits = [
			types.TextEdit(
				range=types.Range(start=selection_range.start, end=selection_range.start),
				new_text=config.left_bracket,
			),
			types.TextEdit(
				range=types.Range(start=selection_range.end, end=selection_range.end),
				new_text=config.right_bracket,
			),
		]

		edit = types.WorkspaceEdit(changes={params["textDocument"]["uri"]: edits})
		ls.apply_edit(edit)
		# 创建笔记文件
		note_path = note_manager.create_annotation_note(
			doc.uri, annotation_id, selected_text, note_file
		)
		if not note_path:
			raise Exception("Failed to create note file")

		return {
			"success": True,
			"note_file": note_file,
			"workspace_path": workspace.root_path,
		}

	except Exception as e:
		error(f"Failed to create annotation: {str(e)}")
		return {"success": False, "error": str(e)}


@server.command("deleteAnnotation")
def delete_annotation(ls: LanguageServer, params: Dict) -> Dict:
	"""
	从源文档指定位置删除标注及其关联的笔记文件。

	接收包含文档 URI 和光标位置的参数，定位并删除该位置的标注。同步移除数据库中的标注记录、源文档中的标注括号，并删除对应的笔记文件。若操作成功，返回被删除的笔记文件路径；若失败，返回错误信息。

	返回:
	    包含被删除笔记文件路径的字典，或包含错误信息的字典（success: False）。
	"""
	try:
		params = params[0]
		doc = ls.workspace.get_document(params["textDocument"]["uri"])
		position = types.Position(
			line=params["position"]["line"], character=params["position"]["character"]
		)
		logger.info("uri:" + params["textDocument"]["uri"])
		annotation_id = get_annotation_at_position(doc, position)
		if annotation_id is None:
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
		if annotations is None:
			raise Exception("Failed to get annotation ranges")

		current_annotation_range = annotations[annotation_id - 1]

		edits = [
			types.TextEdit(
				range=types.Range(
					start=current_annotation_range.start,
					end=types.Position(
						line=current_annotation_range.start.line,
						character=current_annotation_range.start.character + 1,
					),
				),
				new_text="",
			),
			types.TextEdit(
				range=types.Range(
					start=current_annotation_range.end,
					end=types.Position(
						line=current_annotation_range.end.line,
						character=current_annotation_range.end.character + 1,
					),
				),
				new_text="",
			),
		]

		edit = types.WorkspaceEdit(changes={doc.uri: edits})
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
	"""
	获取指定文档位置处的批注笔记文件信息。

	根据给定的文档 URI 和光标位置，查找该位置关联的批注，并返回对应的笔记文件路径、工作区根路径及批注 ID。

	返回:
	    包含 note_file（笔记文件路径）、workspace_path（工作区根路径）、annotation_id（批注 ID）的字典；若未找到则返回 None。
	"""
	try:
		params = params[0]
		# 获取文档和位置
		doc = ls.workspace.get_document(params["textDocument"]["uri"])
		position = types.Position(
			line=params["position"]["line"], character=params["position"]["character"]
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
			"annotation_id": annotation_id,
		}

	except Exception as e:
		error(f"Error getting annotation note: {str(e)}")
		return None


@server.command("deleteAnnotationR")
def delete_annotation_r(ls: LanguageServer, params: List[Dict]) -> Dict:
	"""
	从批注笔记文件侧删除对应的源代码批注。

	该命令根据当前批注笔记文件定位源代码中的批注位置，并调用源文件侧的批注删除操作。返回删除结果或错误信息。
	"""
	try:
		# 先获取批注的源文件位置信息
		params[0]["offset"] = 0  # 确保获取当前批注
		source_info = get_annotation_source(ls, params)
		if not source_info:
			raise Exception("Failed to get annotation source information")

		# source_path已经是绝对路径，直接转换为URI格式
		source_path = source_info["source_path"]
		# 转换为URI格式
		if not source_path.startswith("file://"):
			source_uri = pathlib.Path(source_path).as_uri()
		else:
			source_uri = source_path

		# 构建delete_annotation需要的参数格式
		delete_params = [
			{
				"textDocument": {"uri": source_uri},
				"position": {
					"line": source_info["position"].line,
					"character": source_info["position"].character,
				},
			}
		]

		# 调用delete_annotation删除批注
		result = delete_annotation(ls, delete_params)

		return result

	except Exception as e:
		error(f"Failed to delete annotation R: {str(e)}")
		return {"success": False, "error": str(e)}


@server.command("getAnnotationSource")
def get_annotation_source(ls: LanguageServer, params: List[Dict]) -> Optional[Dict]:
	"""
	根据笔记文件和偏移量，跳转到源文件中对应的批注位置。

	参数说明：
	    params: 包含当前笔记文件的 textDocument 字段和偏移量 offset（1 表示下一个批注，-1 表示上一个批注，0 表示当前批注）。

	返回值：
	    包含工作区路径、源文件路径、目标批注的笔记文件路径、批注 ID 及其在源文件中的位置的字典；若查找失败则返回 None。
	"""
	try:
		param = params[0]

		info(f"params = {param}")

		note = ls.workspace.get_document(param["textDocument"]["uri"])
		offset = param.get("offset", 1)  # 默认获取下一个

		info(f"Getting annotation source with offset {offset}")

		# 从笔记文件路径解析出原始文件路径和批注 ID
		workspace = workspace_manager.get_workspace(note.uri)
		if not workspace:
			return None

		current_id = workspace.note_manager.get_annotation_id_by_note_uri(note.uri)
		if not current_id:
			return None

		# 获取源文件路径
		source_path = workspace.note_manager.get_source_path_by_note_uri(note.uri)
		if not source_path:
			return None

		# 获取所有批注并按位置排序
		note_files = workspace.db_manager.get_note_files_from_source_uri(source_path)
		if not note_files:
			return None

		source = ls.workspace.get_document(source_path)
		annotations = find_annotation_Ranges(source)
		if annotations is None:
			raise Exception("Failed to get annotation ranges")

		n = len(annotations)
		# 计算目标索引
		target_id = (n + (current_id - 1 + offset) % n) % n + 1
		target_annotation = annotations[target_id - 1]

		# 获取目标笔记文件
		note_file = workspace.db_manager.get_annotation_note_file(source_path, target_id)
		if not note_file:
			raise Exception("Failed to get annotation note file")

		return {
			"workspace_path": workspace.root_path,
			"source_path": source_path,
			"note_file": note_file,
			"annotation_id": target_id,
			"position": target_annotation.start,
		}

	except Exception as e:
		error(f"Error getting annotation source: {str(e)}")
		return None


@server.command("listAnnotations")
def list_annotations(ls: LanguageServer, params: Dict) -> List:
	"""
	列出与指定文档关联的所有标注笔记文件。

	接收文档 URI，返回该文档所在工作区路径及其所有标注笔记文件路径列表。

	返回:
	    包含工作区路径和标注笔记文件路径列表的字典；如出错则返回错误信息。
	"""
	try:
		params = params[0]
		doc = ls.workspace.get_document(params["textDocument"]["uri"])
		# 获取工作区
		workspace = workspace_manager.get_workspace(doc.uri)
		if not workspace:
			raise Exception(f"No workspace found for {doc.uri}")

		# 获取文件的所有标注
		note_files = workspace.db_manager.get_note_files_from_source_uri(doc.uri)
		return [{"workspace_path": str(workspace.root_path), "note_files": note_files}]

	except Exception as e:
		error(f"Failed to list annotations: {str(e)}")
		return []


@server.command("queryAnnotations")
def query_annotations(ls: LanguageServer, params: Dict) -> List:
	"""
	查询标注的命令，支持三种查询范围：
	1. current_file - 对于单个文件
	2. current_workspace - 对于当前workspace
	3. current_project - 对于当前项目（当前workspace树）

	参考原来的实现逻辑，直接复用 @list_annotations 函数。
	"""
	try:
		query_params = params[0]
		current_workspace = workspace_manager.get_workspace(query_params["textDocument"]["uri"])
		if not current_workspace:
			return []

		# 根据查询范围获取工作区列表
		query_scope = query_params.get("scope", "current_file")  # file, workspace, all

		if query_scope == "current_file":
			return list_annotations(ls, params)

		workspaces_to_query = []
		if query_scope == "current_workspace":
			workspaces_to_query = [current_workspace]
		elif query_scope == "current_project":
			# 获取当前工作区的所有祖先工作区（包括自身）
			ancestor_workspaces = current_workspace.get_ancestor_workspaces()
			# 找到根工作区
			root_workspace = ancestor_workspaces[-1] if ancestor_workspaces else current_workspace
			# 获取根工作区的所有子树工作区
			workspaces_to_query = root_workspace.get_subtree_workspaces()

		res = []

		for workspace in workspaces_to_query:
			# 扫描工作区的 .annotation/notes 目录
			notes_dir = workspace.note_manager.get_notes_dir()
			if not notes_dir or not notes_dir.exists():
				continue

			note_files = []

			# 遍历所有 .md 文件
			for note_file in notes_dir.glob("*.md"):
				try:
					note_files.append({"note_file": note_file.name})
				except Exception as e:
					error(f"Error reading note file {note_file}: {str(e)}")
					continue
			res.extend({"workspace_path": str(workspace.root_path), "note_files": note_files})

		return res

	except Exception as e:
		error(f"Error querying annotations: {str(e)}")
		return []


def start_server(transport: str = "stdio", host: str = "127.0.0.1", port: int = 2087):
	"""
	启动 LSP 服务器，支持 stdio 或 TCP 传输模式。

	Args:
	    transport: 服务器传输方式，可选 "stdio" 或 "tcp"。
	    host: 当使用 TCP 模式时的主机地址。
	    port: 当使用 TCP 模式时的端口号。
	"""
	if transport == "tcp":
		server.start_tcp(host, port)
	else:
		server.start_io()
