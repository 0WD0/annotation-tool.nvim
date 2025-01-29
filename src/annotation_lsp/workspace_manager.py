import os
from pathlib import Path
from typing import Optional, Dict
from urllib.parse import urlparse, unquote

from .db_manager import DatabaseManager
from .note_manager import NoteManager
from .logger import *

class Workspace:
	"""表示一个工作区"""
	def __init__(self, folder_uri: str):
		self.folder_uri = folder_uri
		self.folder_path = self._uri_to_path(folder_uri)
		self.db_manager = DatabaseManager()
		self.note_manager = NoteManager()
		
		# 初始化管理器
		self.db_manager.init_db(self.folder_path)
		self.note_manager.init_project(self.folder_path)
	
	def _uri_to_path(self, uri: str) -> str:
		"""将 URI 转换为文件路径"""
		parsed = urlparse(uri)
		path = unquote(parsed.path)
		if os.name == 'nt' and path.startswith('/'):
			path = path[1:]
		return path
	
	def contains_file(self, file_uri: str) -> bool:
		"""检查文件是否在此工作区内"""
		file_path = self._uri_to_path(file_uri)
		try:
			Path(file_path).relative_to(self.folder_path)
			return True
		except ValueError:
			return False
	
	def get_relative_path(self, file_uri: str) -> str:
		"""获取文件相对于工作区的路径"""
		file_path = self._uri_to_path(file_uri)
		try:
			return str(Path(file_path).relative_to(self.folder_path))
		except ValueError:
			return file_path

class WorkspaceManager:
	"""管理所有工作区"""
	def __init__(self):
		self.workspaces: Dict[str, Workspace] = {}  # folder_uri -> Workspace
	
	def add_workspace(self, folder_uri: str):
		"""添加工作区"""
		if folder_uri in self.workspaces:
			return
		
		try:
			workspace = Workspace(folder_uri)
			self.workspaces[folder_uri] = workspace
			info(f"Added workspace: {folder_uri}")
		except Exception as e:
			error(f"Failed to add workspace {folder_uri}: {str(e)}")
	
	def remove_workspace(self, folder_uri: str):
		"""移除工作区"""
		if folder_uri in self.workspaces:
			del self.workspaces[folder_uri]
			info(f"Removed workspace: {folder_uri}")

	def get_workspace(self, doc_uri: str) -> Optional[Workspace]:
		"""获取文档所在的工作区"""
		# 按路径长度降序排序工作区，确保匹配最深的工作区
		sorted_workspaces = sorted(
			self.workspaces.values(),
			key=lambda w: len(w.folder_path),
			reverse=True
		)
		
		# 返回第一个包含该文件的工作区
		for workspace in sorted_workspaces:
			if workspace.contains_file(doc_uri):
				return workspace
		
		return None
	
	def get_all_workspaces(self) -> Dict[str, Workspace]:
		"""获取所有工作区"""
		return self.workspaces

# 全局工作区管理器实例
workspace_manager = WorkspaceManager()
