from pathlib import Path
from typing import Dict, List, Optional
from urllib.parse import urlparse

from .db_manager import DatabaseManager
from .note_manager import NoteManager
from .logger import error, info

class Workspace:
	"""表示一个工作区，对应一个包含 .annotation 目录的项目"""
	def __init__(self, root_path: Path):
		self.root_path = root_path
		self.uri = root_path.as_uri()
		self.parent: Optional[Workspace] = None
		self.children: List[Workspace] = []
		
		# 初始化管理器
		self.db_manager = DatabaseManager(root_path)
		self.note_manager = NoteManager(root_path)

	def add_child(self, child: 'Workspace') -> None:
		"""添加子工作区"""
		if child.parent:
			child.parent.children.remove(child)
		child.parent = self
		self.children.append(child)

	def remove_child(self, child: 'Workspace') -> None:
		"""移除子工作区"""
		if child in self.children:
			child.parent = None
			self.children.remove(child)

	def contains_file(self, file_uri: str) -> bool:
		"""检查文件是否在此工作区中"""
		file_path = Path(urlparse(file_uri).path)
		try:
			file_path.relative_to(self.root_path)
			return True
		except ValueError:
			return False

	def get_workspace_for_file(self, file_uri: str) -> Optional['Workspace']:
		"""获取文件所属的最深工作区"""
		if not self.contains_file(file_uri):
			return None

		# 在子工作区中查找
		deepest_workspace = None
		min_depth = 2147483647  # 初始设为最大值
		
		for child in self.children:
			workspace = child.get_workspace_for_file(file_uri)
			if workspace:
				try:
					relative = Path(urlparse(file_uri).path).relative_to(workspace.root_path)
					depth = len(relative.parts)
					if depth < min_depth:
						deepest_workspace = workspace
						min_depth = depth
				except ValueError:
					continue

		# 如果没有找到更深的工作区，返回当前工作区
		if not deepest_workspace:
			try:
				relative = Path(urlparse(file_uri).path).relative_to(self.root_path)
				depth = len(relative.parts)
				if depth < min_depth:
					deepest_workspace = self
			except ValueError:
				pass

		return deepest_workspace

	def get_subtree_workspaces(self: 'Workspace') -> List['Workspace']:
		"""获取此节点及其所有子节点"""
		result = [self]
		for child in self.children:
			result.extend(child.get_subtree_workspaces())
		return result

	def get_ancestor_workspaces(self: 'Workspace') -> List['Workspace']:
		"""获取此节点的所有祖先节点（包括自己）"""
		result = [self]
		if self.parent:
			result.extend(self.parent.get_ancestor_workspaces())
		return result

class WorkspaceManager:
	"""管理所有工作区及其层级关系"""
	def __init__(self):
		self.root: Optional[Workspace] = None
		self._all_workspaces: Dict[str, Workspace] = {}  # uri -> workspace

	def _find_subprojects(self, root_path: Path) -> List[Path]:
		"""递归查找所有包含 .annotation 目录的子目录
		
		Args:
			root_path: 要搜索的根目录
			
		Returns:
			包含 .annotation 目录的子目录列表
		"""
		result = []
		try:
			# 如果当前目录包含 .annotation，加入结果
			if (root_path / '.annotation').is_dir():
				result.append(root_path)
			
			# 递归搜索子目录
			for item in root_path.iterdir():
				if item.is_dir() and not item.name.startswith('.'):
					result.extend(self._find_subprojects(item))
			
			return result
		except Exception as e:
			error(f"Failed to find subprojects in {root_path}: {str(e)}")
			return result

	def build_workspace_tree(self, root_uri: str) -> Optional[Workspace]:
		"""构建完整的工作区树
		
		Args:
			root_uri: 根工作区的 URI
			
		Returns:
			根工作区，如果创建失败则返回 None
		"""
		try:
			root_path = Path(urlparse(root_uri).path)
			
			# 查找所有子项目
			project_paths = self._find_subprojects(root_path)
			if not project_paths:
				return None
			
			# 按路径长度排序，确保父项目在子项目之前处理
			project_paths.sort(key=lambda p: len(str(p)))
			
			# 添加所有工作区
			for path in project_paths:
				info(f"Build project tree: Adding {path}")
				self.add_workspace(path.as_uri())
			
			return self.root
			
		except Exception as e:
			error(f"Failed to build workspace tree for {root_uri}: {str(e)}")
			return None

	def add_workspace(self, workspace_uri: str) -> Optional[Workspace]:
		"""添加新工作区"""
		try:
			# 将 URI 转换为 Path
			workspace_path = Path(urlparse(workspace_uri).path)
			
			# 检查是否已存在
			if workspace_uri in self._all_workspaces:
				return self._all_workspaces[workspace_uri]
			
			# 检查是否有 .annotation 目录
			if not (workspace_path / '.annotation').is_dir():
				return None
			
			# 创建新工作区
			workspace = Workspace(workspace_path)
			self._all_workspaces[workspace_uri] = workspace
			
			# 插入到合适的位置
			self._insert_workspace(workspace)
			
			return workspace
			
		except Exception as e:
			error(f"Failed to add workspace {workspace_uri}: {str(e)}")
			return None

	def remove_workspace(self, workspace_uri: str) -> bool:
		"""移除工作区"""
		try:
			if workspace_uri not in self._all_workspaces:
				return False
				
			workspace = self._all_workspaces[workspace_uri]
			
			# 处理父子关系
			if workspace.parent:
				workspace.parent.remove_child(workspace)
			
			# 将子工作区移到被删除工作区的父工作区下
			if workspace.parent:
				for child in workspace.children[:]:
					workspace.parent.add_child(child)
			
			# 如果是根工作区，需要重新设置根
			if workspace == self.root:
				if workspace.children:
					self.root = workspace.children[0]
				else:
					self.root = None
			
			del self._all_workspaces[workspace_uri]
			return True
			
		except Exception as e:
			error(f"Failed to remove workspace {workspace_uri}: {str(e)}")
			return False

	def _insert_workspace(self, workspace: Workspace) -> None:
		"""将工作区插入到合适的位置"""
		if not self.root:
			self.root = workspace
			return

		# 找到合适的父工作区
		parent = self._find_parent_workspace(workspace.root_path)
		if parent:
			parent.add_child(workspace)
		else:
			# 如果找不到父工作区，说明是新的根
			old_root = self.root
			self.root = workspace
			workspace.add_child(old_root)

	def _find_parent_workspace(self, path: Path) -> Optional[Workspace]:
		"""找到给定路径的父工作区"""
		parent_path = path.parent
		while parent_path != path:
			for ws in self._all_workspaces.values():
				if ws.root_path == parent_path:
					return ws
			path = parent_path
			parent_path = path.parent
		return None

	def get_workspace(self, file_uri: str) -> Optional[Workspace]:
		"""获取文件所属的工作区"""
		try:
			file_path = Path(urlparse(file_uri).path)
			
			# 遍历所有工作区，找到最深的包含该文件的工作区
			deepest_workspace = None
			min_depth = 2147483647
			
			for workspace in self._all_workspaces.values():
				try:
					relative = file_path.relative_to(workspace.root_path)
					info(f"Get workspace: relative path {relative}")
					depth = len(relative.parts)
					if depth < min_depth:
						deepest_workspace = workspace
						min_depth = depth
				except ValueError:
					continue
			
			return deepest_workspace
			
		except Exception as e:
			error(f"Failed to get workspace for {file_uri}: {str(e)}")
			return None

	def get_root_uri(self) -> Optional[str]:
		"""获取根工作区的 URI"""
		return self.root.uri if self.root else None

# 全局工作区管理器实例
workspace_manager = WorkspaceManager()
