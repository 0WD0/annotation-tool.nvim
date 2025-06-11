#!/usr/bin/env python3

import os
from pathlib import Path
from typing import Optional, Dict
from urllib.parse import urlparse, unquote
import frontmatter

from .logger import *


class NoteManager:
	def __init__(self, project_root: Optional[Path] = None):
		"""
		初始化 NoteManager 实例，可选地设置项目根目录。

		如果提供了 project_root，则自动初始化项目目录结构并创建注释笔记存储目录。
		"""
		self.project_root: Optional[Path] = None
		self.notes_dir: Optional[Path] = None
		if project_root:
			self.init_project(project_root)

	def init_project(self, project_root: Path):
		"""
		初始化项目根目录，并在其中创建用于存放批注笔记的 `.annotation/notes` 子目录。
		"""
		self.project_root = project_root
		self.notes_dir = self.project_root / ".annotation" / "notes"
		self.notes_dir.mkdir(parents=True, exist_ok=True)

	def _uri_to_path(self, uri: str) -> Path:
		"""
		将 URI 字符串转换为本地文件系统的 Path 对象。

		在 Windows 系统上，如果路径以斜杠开头，会自动去除首个斜杠以保证路径格式正确。
		"""
		parsed = urlparse(uri)
		path = unquote(parsed.path)
		if os.name == "nt" and path.startswith("/"):
			path = path[1:]
		return Path(path)

	def _uri_to_relative_path(self, uri: str) -> Path:
		"""
		将 URI 转换为相对于项目根目录的路径对象。

		如果 URI 对应的路径不在项目根目录下，则返回其绝对路径。
		"""
		if not self.project_root:
			raise Exception("Project root not set")

		path = self._uri_to_path(uri)
		try:
			return path.relative_to(self.project_root)
		except ValueError:
			return path

	def uri_to_path(self, uri: str) -> str:
		"""
		将URI字符串转换为对应的绝对文件路径字符串。
		"""
		return str(self._uri_to_path(uri))

	def uri_to_relative_path(self, uri: str) -> str:
		"""
		将URI转换为相对于项目根目录的路径字符串。
		"""
		return str(self._uri_to_relative_path(uri))

	def create_annotation_note(
		self, file_uri: str, annotation_id: int, text: str, note_file: str
	) -> Optional[str]:
		"""
		为指定标注创建带有元数据的批注笔记文件。

		根据给定的文件 URI、标注 ID 和文本内容，在 notes 目录下指定的相对路径创建 Markdown 格式的批注文件，并写入前置元数据、选中文本和批注内容部分。

		Args:
		    file_uri: 需要添加批注的源文件 URI。
		    annotation_id: 标注的唯一标识符。
		    text: 被标注的文本内容。
		    note_file: 批注笔记文件在 notes 目录下的相对路径。

		Returns:
		    创建成功时返回笔记文件的绝对路径字符串，失败时返回 None。
		"""
		try:
			if not self.notes_dir:
				raise Exception("Notes directory not set")

			relative_path = self._uri_to_relative_path(file_uri)
			note_path = self.notes_dir / note_file
			note_path.parent.mkdir(parents=True, exist_ok=True)

			with note_path.open("w", encoding="utf-8") as f:
				f.write(f"---\nfile: {relative_path}\nid: {annotation_id}\n---\n\n")
				f.write("## Selected Text\n")
				f.write("```\n")
				f.write(text)
				f.write("\n```\n")
				f.write("## Notes\n")

			return str(note_path)

		except Exception as e:
			error(f"Failed to create note file: {str(e)}")
			return None

	def get_notes_dir(self) -> Optional[Path]:
		"""
		返回笔记存储目录的路径。

		Returns:
			笔记目录的 Path 对象，如果未设置则返回 None。
		"""
		return self.notes_dir

	def delete_note(self, note_file: str) -> bool:
		"""
		删除指定的批注笔记文件。

		如果笔记文件存在于 notes 目录下，则将其删除。若目录未设置或文件不存在，则返回 False。

		Args:
		    note_file: 相对于 notes 目录的笔记文件路径。

		Returns:
		    删除成功返回 True，否则返回 False。
		"""
		try:
			if not self.notes_dir:
				raise Exception("Notes directory not set")

			note_path = self.notes_dir / note_file
			if not note_path.exists():
				raise Exception("Note file does not exist")

			note_path.unlink()
			return True

		except Exception as e:
			error(f"Failed to delete note file: {str(e)}")
			return False

	def get_note_frontmatter(self, note_file: str) -> Optional[Dict]:
		"""
		读取指定笔记文件的 frontmatter 元数据。

		Args:
		    note_file: 笔记文件在笔记目录下的相对路径。

		Returns:
		    包含 frontmatter 元数据的字典，读取失败时返回 None。
		"""
		try:
			if not self.notes_dir:
				raise Exception("Notes directory not set")

			note_path = self.notes_dir / note_file
			if not note_path.exists():
				raise Exception("Note file does not exist")

			post = frontmatter.load(str(note_path))
			return post.metadata

		except Exception as e:
			error(f"Failed to read note file: {str(e)}")
			return None

	def get_note_content(self, note_file: str) -> Optional[str]:
		"""
		读取指定注释笔记文件的正文内容（不包含 frontmatter 元数据）。

		Args:
			note_file: 笔记文件在注释目录下的相对路径。

		Returns:
			返回笔记正文内容字符串，若读取失败则返回 None。
		"""
		try:
			if not self.notes_dir:
				raise Exception("Notes directory not set")

			note_path = self.notes_dir / note_file
			if not note_path.exists():
				raise Exception("Note file does not exist")

			post = frontmatter.load(str(note_path))
			return post.content

		except Exception as e:
			error(f"Failed to read note file: {str(e)}")
			return None

	def get_annotation_id_by_note_uri(self, note_uri: str) -> Optional[int]:
		"""
		根据笔记文件的 URI，获取其对应的注释 ID。

		如果笔记文件存在且包含注释 ID 元数据，则返回该注释 ID 的整数值；否则返回 None。
		"""
		try:
			# 将 URI 转换为文件路径
			note_path = Path(self._uri_to_path(note_uri))
			if not self.notes_dir:
				raise Exception("Notes directory not set")
			# 检查路径是否在笔记目录下
			note_path.relative_to(self.notes_dir)

			# 读取笔记内容获取 annotation id
			post = frontmatter.load(str(note_path))
			result = post.metadata.get("id")
			if result is None:
				raise Exception("Annotation id not found")
			return int(str(result))
		except (ValueError, Exception) as e:
			error(f"Failed to get annotation id: {str(e)}")
			return None

	def get_source_path_by_note_uri(self, note_uri: str) -> Optional[str]:
		"""
		根据笔记文件的 URI，返回与该笔记关联的源文件的绝对路径。

		如果笔记文件的 frontmatter 中未包含源文件路径，或路径无法解析，则返回 None。
		"""
		try:
			# 将 URI 转换为文件路径
			note_path = Path(self._uri_to_path(note_uri))
			if not self.notes_dir:
				raise Exception("Notes directory not set")
			# 检查路径是否在笔记目录下
			note_path.relative_to(self.notes_dir)

			# 读取笔记内容
			post = frontmatter.load(str(note_path))
			source_path = post.metadata.get("file")
			if not source_path:
				return None

			# 确保返回绝对路径
			source_path = Path(str(source_path))
			if not source_path.is_absolute():
				if not self.project_root:
					raise Exception("Project root not set")
				source_path = self.project_root / source_path
			return str(source_path)
		except (ValueError, Exception) as e:
			error(f"Failed to get source path: {str(e)}")
			return None
