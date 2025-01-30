from pathlib import Path
from typing import Dict, List, Optional
from urllib.parse import urlparse

from .db_manager import DatabaseManager
from .note_manager import NoteManager
from .logger import error, info

class Workspace:
	"""表示一个项目树"""
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
	"""管理多个项目树的森林"""
	def __init__(self):
		self._roots: List[Workspace] = []  # 所有根项目
		self._all_workspaces: Dict[str, Workspace] = {}  # uri -> workspace

	def _find_root_project_for_path(self, path: Path) -> Optional[Workspace]:
		"""找到路径所属的根项目
		
		Args:
			path: 要查找的路径
			
		Returns:
			路径所属的根项目，如果不属于任何现有项目树则返回 None
		"""
		try:
			min_depth = 2147483647
			root = None
			
			# 遍历所有根项目，找到相对路径最短的那个
			for workspace in self._roots:
				try:
					relative = path.relative_to(workspace.root_path)
					depth = len(relative.parts)
					if depth < min_depth:
						root = workspace
						min_depth = depth
				except ValueError:
					continue
			
			return root
		except Exception as e:
			error(f"Failed to find root for path {path}: {str(e)}")
			return None

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

	def add_workspace(self, workspace_uri: str) -> Optional[Workspace]:
		"""添加新工作区，如果是新的根项目则会构建完整的项目树
		
		Args:
			workspace_uri: 工作区的 URI
			
		Returns:
			添加的工作区，如果失败则返回 None
		"""
		try:
			# 如果已存在，直接返回
			if workspace_uri in self._all_workspaces:
				return self._all_workspaces[workspace_uri]
			
			# 创建新工作区
			workspace_path = Path(urlparse(workspace_uri).path)
			
			# 查找所有子项目
			project_paths = self._find_subprojects(workspace_path)
			if not project_paths:
				return None
			
			# 按路径长度排序，确保父项目在子项目之前处理
			project_paths.sort(key=lambda p: len(str(p)))
			
			# 找到这些路径所属的根项目
			root = self._find_root_project_for_path(workspace_path)
			if root:
				info(f"Found root {Path(root.uri)} for workspace {Path(workspace_uri)}")
				
				# 将新发现的项目添加到现有树中
				for path in project_paths:
					if path.as_uri() not in self._all_workspaces:
						info(f"Adding workspace {path} to existing tree")
						# 创建工作区
						workspace = Workspace(path)
						self._all_workspaces[path.as_uri()] = workspace
						# 插入到项目树中
						self._insert_workspace(workspace)
				
				return self._all_workspaces[workspace_uri]
			else:
				# 没找到根项目，创建新的项目树
				info(f"Creating new project tree for {Path(workspace_uri)}")
				
				# 创建所有工作区
				for path in project_paths:
					info(f"Adding workspace {path} to new tree")
					workspace = Workspace(path)
					self._all_workspaces[path.as_uri()] = workspace
					# 第一个路径作为根项目
					if path == project_paths[0]:
						self._roots.append(workspace)
					else:
						self._insert_workspace(workspace)
				
				return self._all_workspaces[workspace_uri]
			
		except Exception as e:
			error(f"Failed to add workspace {workspace_uri}: {str(e)}")
			return None

	def remove_workspace(self, workspace_uri: str) -> bool:
		"""移除工作区
		
		如果是根项目，会移除整个项目树
		"""
		try:
			workspace = self._all_workspaces.get(workspace_uri)
			if not workspace:
				return False
			
			# 如果是根项目，移除整个项目树
			if workspace in self._roots:
				info(f"Removing root workspace {workspace_uri}")
				self._roots.remove(workspace)
				for child in workspace.get_subtree_workspaces():
					self._all_workspaces.pop(child.uri, None)
				return True
			
			# 否则只移除这个工作区 TODO: 改成移除子树
			info(f"Removing workspace {workspace_uri}")
			if workspace.parent:
				workspace.parent.remove_child(workspace)
			self._all_workspaces.pop(workspace_uri, None)
			return True
			
		except Exception as e:
			error(f"Failed to remove workspace {workspace_uri}: {str(e)}")
			return False

	def _insert_workspace(self, workspace: Workspace) -> None:
		"""将工作区插入到项目树中的正确位置"""
		try:
			# 找到所有可能的父工作区（路径比这个工作区短的）
			potential_parents = []
			for other in self._all_workspaces.values():
				if other == workspace:
					continue
				try:
					relative = workspace.root_path.relative_to(other.root_path)
					potential_parents.append((other, len(relative.parts)))
				except ValueError:
					continue
			
			if not potential_parents:
				# 没有找到父工作区，说明应该是根项目
				if workspace not in self._roots:
					self._roots.append(workspace)
				return
			
			# 选择路径最长的作为父工作区（最深的那个）
			parent, _ = max(potential_parents, key=lambda x: x[1])
			parent.add_child(workspace)
			
		except Exception as e:
			error(f"Failed to insert workspace {workspace.uri}: {str(e)}")

	def get_workspace(self, file_uri: str) -> Optional[Workspace]:
		"""获取文件所属的最深工作区"""
		try:
			file_path = Path(urlparse(file_uri).path)
			
			# 先找到所属的根项目
			root = self._find_root_project_for_path(file_path)
			if not root:
				return None
			
			# 在这个项目树中找最深的工作区
			deepest_workspace = None
			min_depth = 2147483647
			
			for workspace in root.get_subtree_workspaces():
				try:
					relative = file_path.relative_to(workspace.root_path)
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

	def get_first_root_uri(self) -> Optional[str]:
		"""获取第一个根项目的 URI"""
		return self._roots[0].uri if self._roots else None

# 全局工作区管理器实例
workspace_manager = WorkspaceManager()
