from pathlib import Path
from typing import Dict, List, Optional
from urllib.parse import urlparse, unquote

from .db_manager import DatabaseManager
from .note_manager import NoteManager
from .logger import error, info


class Workspace:
	"""表示一个项目树"""

	def __init__(self, root_path: Path):
		"""
		初始化 Workspace 实例，表示以指定根路径为根的项目树节点。

		Args:
			root_path: 工作区的根目录路径。
		"""
		self.root_path = root_path
		self.uri = root_path.as_uri()
		self.parent: Optional[Workspace] = None
		self.children: List[Workspace] = []

		# 初始化管理器
		self.db_manager = DatabaseManager(root_path)
		self.note_manager = NoteManager(root_path)

	def add_child(self, child: "Workspace") -> None:
		"""
		将指定的子工作区添加为当前工作区的子节点。

		如果该子工作区已有父节点，则先从原父节点移除，再建立新的父子关系。
		"""
		if child.parent:
			child.parent.children.remove(child)
		child.parent = self
		self.children.append(child)

	def remove_child(self, child: "Workspace") -> None:
		"""
		从当前工作区中移除指定的子工作区。

		如果该子工作区存在于当前工作区的子节点列表中，将其解除父子关系并移除。
		"""
		if child in self.children:
			child.parent = None
			self.children.remove(child)

	def contains_file(self, file_uri: str) -> bool:
		"""
		判断指定文件是否位于当前工作区的根目录或其子目录下。

		Args:
			file_uri: 文件的URI。

		Returns:
			如果文件属于该工作区，则返回True；否则返回False。
		"""
		file_path = Path(unquote(urlparse(file_uri).path))
		try:
			file_path.relative_to(self.root_path)
			return True
		except ValueError:
			return False

	def get_workspace_for_file(self, file_uri: str) -> Optional["Workspace"]:
		"""
		返回包含指定文件的最深层（最具体）工作区。

		如果该文件属于当前工作区及其子工作区，将递归查找并返回包含该文件的最深层工作区实例；若未找到，则返回 None。

		Args:
			file_uri: 文件的 URI。

		Returns:
			包含该文件的最深层 Workspace 实例，若未找到则为 None。
		"""
		if not self.contains_file(file_uri):
			return None

		# 在子工作区中查找
		deepest_workspace = None
		min_depth = 2147483647  # 初始设为最大值

		for child in self.children:
			workspace = child.get_workspace_for_file(file_uri)
			if workspace:
				try:
					relative = Path(unquote(urlparse(file_uri).path)).relative_to(
						workspace.root_path
					)
					depth = len(relative.parts)
					if depth < min_depth:
						deepest_workspace = workspace
						min_depth = depth
				except ValueError:
					continue

		# 如果没有找到更深的工作区，返回当前工作区
		if not deepest_workspace:
			try:
				relative = Path(unquote(urlparse(file_uri).path)).relative_to(self.root_path)
				depth = len(relative.parts)
				if depth < min_depth:
					deepest_workspace = self
			except ValueError:
				pass

		return deepest_workspace

	def get_subtree_workspaces(self: "Workspace") -> List["Workspace"]:
		"""
		返回当前工作区及其所有子工作区的列表。

		该方法递归遍历当前工作区的所有子节点，收集整个子树中的所有工作区实例。
		"""
		result = [self]
		for child in self.children:
			result.extend(child.get_subtree_workspaces())
		return result

	def get_ancestor_workspaces(self: "Workspace") -> List["Workspace"]:
		"""
		返回包含自身在内的所有祖先工作区节点列表。

		返回：
		    包含当前工作区及其所有祖先的列表，顺序为从当前节点到根节点。
		"""
		result = [self]
		if self.parent:
			result.extend(self.parent.get_ancestor_workspaces())
		return result


class WorkspaceManager:
	"""管理多个项目树的森林"""

	def __init__(self):
		"""
		初始化 WorkspaceManager 实例，创建用于管理根工作区和所有工作区的内部数据结构。
		"""
		self._roots: List[Workspace] = []  # 所有根项目
		self._all_workspaces: Dict[str, Workspace] = {}  # uri -> workspace

	def _find_root_project_for_path(self, path: Path) -> Optional[Workspace]:
		"""
		查找给定路径所属的最深层根工作区。

		遍历所有根工作区，返回其根目录为给定路径最近祖先的工作区实例。如果路径不属于任何根工作区，则返回 None。
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
		"""
		递归查找指定根目录下所有包含 .annotation 目录的子目录。

		遍历 root_path 及其所有子目录，返回其中包含 .annotation 目录的所有路径列表。遇到权限或解码错误时会跳过相应目录并记录错误日志。

		Args:
		    root_path: 要递归搜索的根目录路径。

		Returns:
		    所有包含 .annotation 目录的子目录路径列表。
		"""
		result = []
		try:
			# 确保路径是有效的 Path 对象
			if not isinstance(root_path, Path):
				root_path = Path(str(root_path))

			# 检查路径是否存在
			if not root_path.exists():
				error(f"Path does not exist: {root_path}")
				return result

			# 如果当前目录包含 .annotation，加入结果
			annotation_dir = root_path / ".annotation"
			if annotation_dir.exists() and annotation_dir.is_dir():
				result.append(root_path)

			# 递归搜索子目录
			try:
				for item in root_path.iterdir():
					if item.is_dir() and not item.name.startswith("."):
						result.extend(self._find_subprojects(item))
			except PermissionError:
				error(f"Permission denied when accessing directory: {root_path}")
			except UnicodeDecodeError:
				error(f"Unicode decode error when accessing directory: {root_path}")

			return result
		except Exception as e:
			error(f"Failed to find subprojects in {root_path}: {str(e)}")
			return result

	def add_workspace(self, workspace_uri: str) -> Optional[Workspace]:
		"""
		添加一个新的工作区，并自动发现并构建其包含的所有子项目树。

		如果指定的 URI 已存在于工作区管理器中，则直接返回对应的工作区。若路径不存在或未找到任何包含 .annotation 目录的子项目，则返回 None。对于新发现的项目，会根据其父子关系插入到现有项目树或新建项目树，并确保所有相关 URI 均有映射。

		Args:
		    workspace_uri: 待添加工作区的 URI。

		Returns:
		    添加成功时返回对应的 Workspace 实例，失败时返回 None。
		"""
		try:
			# 如果已存在，直接返回
			if workspace_uri in self._all_workspaces:
				return self._all_workspaces[workspace_uri]

			# 创建新工作区
			# 解码 URL 编码的路径
			workspace_path = Path(unquote(urlparse(workspace_uri).path))

			# 确保路径存在
			if not workspace_path.exists():
				error(f"Workspace path does not exist: {workspace_path}")
				return None

			# 查找所有子项目
			project_paths = self._find_subprojects(workspace_path)
			if not project_paths:
				# 如果没找到子项目，则返回 None
				info(f"No projects with .annotation directory found in {workspace_path}")
				return None

			# 按路径长度排序，确保父项目在子项目之前处理
			project_paths.sort(key=lambda p: len(str(p)))

			# 找到这些路径所属的根项目
			root = self._find_root_project_for_path(workspace_path)
			if root:
				info(f"Found root {root.root_path} for workspace {workspace_path}")

				# 将新发现的项目添加到现有树中
				for path in project_paths:
					path_uri = path.as_uri()
					if path_uri not in self._all_workspaces:
						info(f"Adding workspace {path} to existing tree")
						# 创建工作区
						workspace = Workspace(path)
						self._all_workspaces[path_uri] = workspace
						# 插入到项目树中
						self._insert_workspace(workspace)

				# 确保原始 URI 也有映射
				if (
					workspace_uri not in self._all_workspaces
					and workspace_path.as_uri() in self._all_workspaces
				):
					self._all_workspaces[workspace_uri] = self._all_workspaces[
						workspace_path.as_uri()
					]

				return self._all_workspaces.get(workspace_uri) or self._all_workspaces.get(
					workspace_path.as_uri()
				)
			else:
				# 没找到根项目，创建新的项目树
				info(f"Creating new project tree for {workspace_path}")

				# 创建所有工作区
				for path in project_paths:
					info(f"Adding workspace {path} to new tree")
					workspace = Workspace(path)
					path_uri = path.as_uri()
					self._all_workspaces[path_uri] = workspace
					# 第一个路径作为根项目
					if path == project_paths[0]:
						self._roots.append(workspace)
					else:
						self._insert_workspace(workspace)

				# 确保原始 URI 也有映射
				if (
					workspace_uri not in self._all_workspaces
					and workspace_path.as_uri() in self._all_workspaces
				):
					self._all_workspaces[workspace_uri] = self._all_workspaces[
						workspace_path.as_uri()
					]

				return self._all_workspaces.get(workspace_uri) or self._all_workspaces.get(
					workspace_path.as_uri()
				)

		except Exception as e:
			error(f"Failed to add workspace {workspace_uri}: {str(e)}")
			return None

	def remove_workspace(self, workspace_uri: str) -> bool:
		"""
		移除指定的工作区。

		如果指定的工作区为根项目，则会移除整个项目树及其所有子工作区；否则仅移除该工作区本身。

		Args:
			workspace_uri: 要移除的工作区的 URI。

		Returns:
			移除成功返回 True，失败或未找到工作区返回 False。
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
		"""
		将指定工作区插入到项目树的正确层级位置。

		根据工作区的根路径，自动查找最深的父工作区并建立父子关系；若无父工作区，则将其作为根工作区添加。
		"""
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
		"""
		返回包含指定文件 URI 的最深层工作区。

		如果文件属于某个根项目，则在该项目树中查找包含该文件的最具体（路径最深）的工作区；若未找到，则返回 None。

		参数:
			file_uri: 文件的 URI。

		返回:
			包含该文件的最深层 Workspace 实例，若未找到则返回 None。
		"""
		try:
			file_path = Path(unquote(urlparse(file_uri).path))

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
		"""
		返回第一个根工作区的 URI。

		如果存在根工作区，则返回其 URI；否则返回 None。
		"""
		return self._roots[0].uri if self._roots else None


# 全局工作区管理器实例
workspace_manager = WorkspaceManager()
