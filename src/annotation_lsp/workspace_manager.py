from typing import Dict, Optional, Set
from pathlib import Path
from urllib.parse import urlparse, unquote
from .db_manager import DatabaseManager
from .note_manager import NoteManager
from .logger import info, error

class WorkspaceManager:
	"""工作区管理器，用于管理多个工作区及其对应的数据库连接"""
	def __init__(self):
		self._workspace_folders: Set[Path] = set()
		self._db_managers: Dict[Path, DatabaseManager] = {}
		self._note_managers: Dict[Path, NoteManager] = {}
	
	def add_workspace(self, uri: str) -> None:
		"""添加工作区
		
		Args:
			uri: 工作区URI
		"""
		path = Path(unquote(urlparse(uri).path))
		if path in self._workspace_folders:
			return
			
		self._workspace_folders.add(path)
		self._db_managers[path] = DatabaseManager()
		self._db_managers[path].init_db(str(path))
		
		self._note_managers[path] = NoteManager()
		self._note_managers[path].init_project(str(path))
		
		info(f"Added workspace: {path}")
	
	def remove_workspace(self, uri: str) -> None:
		"""移除工作区
		
		Args:
			uri: 工作区URI
		"""
		path = Path(unquote(urlparse(uri).path))
		if path not in self._workspace_folders:
			return
			
		self._workspace_folders.remove(path)
		if path in self._db_managers:
			del self._db_managers[path]
		if path in self._note_managers:
			del self._note_managers[path]
			
		info(f"Removed workspace: {path}")
	
	def get_workspace_for_file(self, file_uri: str) -> Optional[Path]:
		"""获取文件所属的工作区路径
		
		Args:
			file_uri: 文件URI
			
		Returns:
			工作区路径，如果找不到则返回None
		"""
		file_path = Path(unquote(urlparse(file_uri).path))
		
		# 找到最长匹配的工作区路径
		matching_workspace = None
		max_parts = -1
		
		for workspace in self._workspace_folders:
			try:
				relative = file_path.relative_to(workspace)
				parts = len(relative.parts)
				if parts > max_parts:
					max_parts = parts
					matching_workspace = workspace
			except ValueError:
				continue
				
		return matching_workspace
	
	def get_db_manager(self, file_uri: str) -> Optional[DatabaseManager]:
		"""获取文件对应的数据库管理器
		
		Args:
			file_uri: 文件URI
			
		Returns:
			数据库管理器，如果找不到则返回None
		"""
		workspace = self.get_workspace_for_file(file_uri)
		if workspace:
			return self._db_managers.get(workspace)
		return None
	
	def get_note_manager(self, file_uri: str) -> Optional[NoteManager]:
		"""获取文件对应的笔记管理器
		
		Args:
			file_uri: 文件URI
			
		Returns:
			笔记管理器，如果找不到则返回None
		"""
		workspace = self.get_workspace_for_file(file_uri)
		if workspace:
			return self._note_managers.get(workspace)
		return None

# 创建全局工作区管理器实例
workspace_manager = WorkspaceManager()
