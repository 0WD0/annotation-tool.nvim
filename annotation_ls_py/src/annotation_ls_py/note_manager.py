#!/usr/bin/env python3

import os
from pathlib import Path
from typing import Optional, List, Dict
from urllib.parse import urlparse, unquote
import frontmatter

from .logger import *


class NoteManager:
	def __init__(self, project_root: Optional[Path] = None):
		self.project_root: Optional[Path] = None
		self.notes_dir: Optional[Path] = None
		if project_root:
			self.init_project(project_root)

	def init_project(self, project_root: Path):
		"""初始化项目目录"""
		self.project_root = project_root
		self.notes_dir = self.project_root / ".annotation" / "notes"
		self.notes_dir.mkdir(parents=True, exist_ok=True)

	def _uri_to_path(self, uri: str) -> Path:
		"""将 URI 转换为 Path 对象"""
		parsed = urlparse(uri)
		path = unquote(parsed.path)
		if os.name == "nt" and path.startswith("/"):
			path = path[1:]
		return Path(path)

	def _uri_to_relative_path(self, uri: str) -> Path:
		"""将 URI 转换为相对于项目根目录的路径"""
		if not self.project_root:
			raise Exception("Project root not set")

		path = self._uri_to_path(uri)
		try:
			return path.relative_to(self.project_root)
		except ValueError:
			return path

	def uri_to_path(self, uri: str) -> str:
		"""Convert a URI to a file path"""
		return str(self._uri_to_path(uri))

	def uri_to_relative_path(self, uri: str) -> str:
		"""Convert a URI to a path relative to project root"""
		return str(self._uri_to_relative_path(uri))

	def create_annotation_note(
		self, file_uri: str, annotation_id: int, text: str, note_file: str
	) -> Optional[str]:
		"""为标注创建批注文件

		Args:
		        file_uri: 文件的 URI
		        annotation_id: 标注 ID
		        text: 标注的文本内容
		        note_file: 笔记文件的相对路径（相对于 notes 目录）

		Returns:
		        笔记文件的绝对路径（字符串形式），如果创建失败则返回 None
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
		"""获取笔记目录"""
		return self.notes_dir

	def delete_note(self, note_file: str) -> bool:
		"""删除批注文件

		Args:
		        note_file: 笔记文件的相对路径（相对于 notes 目录）

		Returns:
		        删除是否成功
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

	def search_notes(self, query: str, search_type: str = "all") -> List[Dict]:
		"""搜索批注文件
		search_type可以是：'file_path', 'content', 'note', 'all'
		"""
		notes_dir = self.get_notes_dir()
		if not notes_dir:
			return []

		results = []
		for note_file in notes_dir.glob("*.md"):
			post = frontmatter.load(str(note_file))
			file_path = str(post.metadata.get("file"))

			note_content = post.content

			# 根据搜索类型进行匹配
			matched = False
			if search_type in ("file_path", "all") and query.lower() in file_path.lower():
				matched = True
			elif search_type in ("content", "all") and query.lower() in note_content.lower():
				matched = True
			elif search_type in ("note", "all") and query.lower() in note_content.lower():
				matched = True

			if matched:
				results.append(
					{
						"file": file_path,
						"note_file": str(note_file),
						"original_text": "",
						"note_content": note_content,
					}
				)

		return results

	def get_annotation_id_by_note_uri(self, note_uri: str) -> Optional[int]:
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
