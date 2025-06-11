#!/usr/bin/env python3

import os
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict
from urllib.parse import urlparse, unquote
from .utils import *
from .logger import error, info


class DatabaseError(Exception):
	"""数据库相关错误"""

	pass


class DatabaseManager:
	def __init__(self, project_root: Optional[Path] = None):
		"""
		初始化 DatabaseManager 实例，可选地为指定项目根路径建立数据库连接。

		如果提供了项目根路径，则自动初始化并连接对应的注释数据库。
		"""
		self.connections = {}  # 项目路径 -> sqlite3.Connection
		self.current_db = None
		self.project_root = None
		self.max_connections = 5  # 最大保持的连接数
		if project_root:
			self.init_db(project_root)

	def init_db(self, project_root: Path):
		"""
		初始化或连接指定项目根目录下的注释数据库。

		如果数据库已连接则复用，否则创建新连接并确保所需的数据表存在。自动管理连接池，超出最大连接数时关闭最早的连接。
		"""
		self.project_root = project_root
		db_path = self.project_root / ".annotation" / "db" / "annotations.db"

		# 如果已经有连接且是当前数据库，直接返回
		if self.current_db == str(db_path):
			return

		# 如果已经在连接池中，更新为当前连接
		if str(db_path) in self.connections:
			self.current_db = str(db_path)
			return

		# 创建新连接
		db_path.parent.mkdir(parents=True, exist_ok=True)
		conn = sqlite3.connect(str(db_path))

		# 创建必要的表
		conn.execute("""
			CREATE TABLE IF NOT EXISTS files (
				id INTEGER PRIMARY KEY,
				path TEXT UNIQUE,
				last_modified TIMESTAMP
			)
		""")

		conn.execute("""
			CREATE TABLE IF NOT EXISTS annotations (
				id INTEGER PRIMARY KEY,
				file_id INTEGER,
				annotation_id INTEGER,
				note_file TEXT,
				FOREIGN KEY (file_id) REFERENCES files (id),
				UNIQUE (file_id, annotation_id)
			)
		""")

		conn.commit()

		# 管理连接池大小
		if len(self.connections) >= self.max_connections:
			oldest_conn = next(iter(self.connections.values()))
			oldest_conn.close()
			del self.connections[next(iter(self.connections))]

		self.connections[str(db_path)] = conn
		self.current_db = str(db_path)

	def _get_conn(self) -> sqlite3.Connection:
		"""
		返回当前活动的数据库连接。

		如果当前没有可用的数据库连接，则抛出 DatabaseError 异常。
		"""
		if not self.current_db or self.current_db not in self.connections:
			raise DatabaseError("No database connection")
		return self.connections[self.current_db]

	def _uri_to_relative_path(self, uri: str) -> str:
		"""
		将 URI 转换为相对于项目根目录的路径。

		如果无法相对化，则返回绝对路径。若未设置项目根目录，则抛出 DatabaseError 异常。
		"""
		if not self.project_root:
			raise DatabaseError("Project root not set")

		parsed = urlparse(uri)
		path = Path(unquote(parsed.path))
		if os.name == "nt" and str(path).startswith("/"):
			path = Path(str(path)[1:])

		try:
			return str(path.relative_to(self.project_root))
		except ValueError:
			return str(path)

	def get_annotation_note_file(self, file_uri: str, annotation_id: int) -> Optional[str]:
		"""
		根据文件 URI 和标注 ID，获取对应的笔记文件路径。

		Args:
			file_uri: 文件的 URI。
			annotation_id: 标注的唯一标识符。

		Returns:
			笔记文件的路径字符串，如果未找到则返回 None。
		"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(file_uri)

			cursor = conn.execute(
				"""
				SELECT a.note_file
				FROM annotations a
				JOIN files f ON a.file_id = f.id
				WHERE f.path = ? AND a.annotation_id = ?
			""",
				(relative_path, annotation_id),
			)

			result = cursor.fetchone()
			return result[0] if result else None

		except Exception as e:
			error(f"Failed to get annotation note file: {str(e)}")
			return None

	def create_annotation(self, doc_uri: str, annotation_id: int) -> str:
		"""
		为指定文档 URI 和标注 ID 创建新的标注记录，并生成对应的笔记文件名。

		Args:
			doc_uri: 文档的 URI 路径。
			annotation_id: 标注的唯一标识符。

		Returns:
			新创建的笔记文件名。

		Raises:
			DatabaseError: 创建标注记录失败时抛出。
		"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(doc_uri)

			# 获取或创建文件记录
			cursor = conn.execute(
				"INSERT OR IGNORE INTO files (path, last_modified) VALUES (?, ?)",
				(relative_path, datetime.now()),
			)
			conn.execute(
				"UPDATE files SET last_modified = ? WHERE path = ?",
				(datetime.now(), relative_path),
			)

			# 获取文件ID
			cursor = conn.execute("SELECT id FROM files WHERE path = ?", (relative_path,))
			file_id = cursor.fetchone()[0]

			# 生成笔记文件名
			now = datetime.now()
			note_file = f"note_{now.strftime('%Y%m%d_%H%M%S')}.md"
			conn.execute(
				"INSERT INTO annotations (file_id, annotation_id, note_file) VALUES (?, ?, ?)",
				(file_id, annotation_id, note_file),
			)
			conn.commit()

			return note_file

		except Exception as e:
			error(f"Failed to create annotation: {str(e)}")
			raise DatabaseError(str(e))

	def get_note_files_from_source_uri(self, source_uri: str) -> List[Dict]:
		"""
		获取指定源文件 URI 关联的所有标注笔记文件。

		Args:
			source_uri: 源文件的 URI。

		Returns:
			包含所有关联标注笔记文件路径的字典列表；如查询失败则返回空列表。
		"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(source_uri)

			cursor = conn.execute(
				"""
				SELECT a.note_file
				FROM annotations a
				JOIN files f ON a.file_id = f.id
				WHERE f.path = ?
				ORDER BY a.annotation_id
			""",
				(relative_path,),
			)

			return [{"note_file": row[0]} for row in cursor.fetchall()]

		except Exception as e:
			error(f"Failed to get file annotations: {str(e)}")
			return []

	def delete_annotation(self, file_uri: str, annotation_id: int) -> bool:
		"""
		删除指定文件 URI 和标注 ID 对应的标注记录。

		Args:
			file_uri: 文件的 URI。
			annotation_id: 要删除的标注 ID。

		Returns:
			若成功删除标注记录则返回 True，否则返回 False。
		"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(file_uri)

			cursor = conn.execute(
				"""
				DELETE FROM annotations
				WHERE file_id = (
					SELECT id FROM files WHERE path = ?
				) AND annotation_id = ?
			""",
				(relative_path, annotation_id),
			)

			conn.commit()
			return cursor.rowcount > 0

		except Exception as e:
			error(f"Failed to delete annotation: {str(e)}")
			return False

	def increase_annotation_ids(self, file_uri: str, from_id: int, increment: int = 1) -> bool:
		"""
		批量调整指定文件中从给定ID开始的所有标注ID，可递增或递减。

		Args:
			file_uri: 文件的URI路径。
			from_id: 起始的标注ID，包含该ID。
			increment: 调整的步长，正值为递增，负值为递减。

		Returns:
			操作成功返回True，否则返回False。
		"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(file_uri)

			# 获取文件ID
			cursor = conn.execute("SELECT id FROM files WHERE path = ?", (relative_path,))
			result = cursor.fetchone()
			if not result:
				return False

			file_id = result[0]

			cursor.execute(
				"""
				SELECT annotation_id, note_file
				FROM annotations
				WHERE file_id = ? AND annotation_id >= ?
				ORDER BY annotation_id DESC
			""",
				(file_id, from_id),
			)

			annotation_ids = cursor.fetchall()

			# 更新标注ID
			if increment < 0:
				annotation_ids.reverse()

			for annotation_id, note_file in annotation_ids:
				info(f"Updating annotation {annotation_id} for {note_file}")
				cursor.execute(
					"""
					UPDATE annotations
					SET annotation_id = annotation_id + ?
					WHERE file_id = ? AND annotation_id = ?
				""",
					(increment, file_id, annotation_id),
				)
				if not self.project_root:
					raise Exception("Project root not set")
				update_note_aid(
					Path(self.project_root) / ".annotation" / "notes" / note_file,
					annotation_id + increment,
				)

			conn.commit()
			return True

		except Exception as e:
			error(f"Failed to increase annotation ids: {str(e)}")
			return False
