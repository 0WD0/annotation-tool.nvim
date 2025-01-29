#!/usr/bin/env python3

import os
import sqlite3
import shutil
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Tuple, Dict
from urllib.parse import urlparse, unquote
from .utils import *
from .logger import (error, info)

class DatabaseError(Exception):
	"""数据库相关错误"""
	pass

class DatabaseManager:
	def __init__(self):
		self.connections = {}  # 项目路径 -> sqlite3.Connection
		self.current_db = None
		self.project_root = None
		self.max_connections = 5  # 最大保持的连接数
		
	def init_db(self, project_root: str):
		"""初始化或连接到项目的数据库"""
		self.project_root = Path(project_root)
		db_path = self.project_root / '.annotation' / 'db' / 'annotations.db'
		
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
		conn.execute('''
			CREATE TABLE IF NOT EXISTS files (
				id INTEGER PRIMARY KEY,
				path TEXT UNIQUE,
				last_modified TIMESTAMP
			)
		''')
		
		conn.execute('''
			CREATE TABLE IF NOT EXISTS annotations (
				id INTEGER PRIMARY KEY,
				file_id INTEGER,
				annotation_id INTEGER,
				note_file TEXT,
				FOREIGN KEY (file_id) REFERENCES files (id),
				UNIQUE (file_id, annotation_id)
			)
		''')
		
		conn.commit()
		
		# 管理连接池大小
		if len(self.connections) >= self.max_connections:
			oldest_conn = next(iter(self.connections.values()))
			oldest_conn.close()
			del self.connections[next(iter(self.connections))]
		
		self.connections[str(db_path)] = conn
		self.current_db = str(db_path)

	def _get_conn(self) -> sqlite3.Connection:
		"""获取当前数据库连接"""
		if not self.current_db or self.current_db not in self.connections:
			raise DatabaseError("No database connection")
		return self.connections[self.current_db]
	
	def _uri_to_relative_path(self, uri: str) -> str:
		"""将 URI 转换为相对于项目根目录的路径"""
		if not self.project_root:
			raise DatabaseError("Project root not set")
			
		parsed = urlparse(uri)
		path = Path(unquote(parsed.path))
		if os.name == 'nt' and str(path).startswith('/'):
			path = Path(str(path)[1:])
			
		try:
			return str(path.relative_to(self.project_root))
		except ValueError:
			return str(path)
	
	def get_annotation_note_file(self, file_uri: str, annotation_id: int) -> Optional[str]:
		"""获取标注对应的笔记文件路径"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(file_uri)
			
			cursor = conn.execute('''
				SELECT a.note_file
				FROM annotations a
				JOIN files f ON a.file_id = f.id
				WHERE f.path = ? AND a.annotation_id = ?
			''', (relative_path, annotation_id))
			
			result = cursor.fetchone()
			return result[0] if result else None
			
		except Exception as e:
			error(f"Failed to get annotation note file: {str(e)}")
			return None
	def create_annotation(self, doc_uri: str, annotation_id: int) -> str:
		"""创建新的标注记录"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(doc_uri)
			
			# 获取或创建文件记录
			cursor = conn.execute(
				'INSERT OR IGNORE INTO files (path, last_modified) VALUES (?, ?)',
				(relative_path, datetime.now())
			)
			conn.execute(
				'UPDATE files SET last_modified = ? WHERE path = ?',
				(datetime.now(), relative_path)
			)
			
			# 获取文件ID
			cursor = conn.execute('SELECT id FROM files WHERE path = ?', (relative_path,))
			file_id = cursor.fetchone()[0]
			
			# 创建标注记录
			note_file = f"{relative_path}.{annotation_id}.md"
			conn.execute(
				'INSERT INTO annotations (file_id, annotation_id, note_file) VALUES (?, ?, ?)',
				(file_id, annotation_id, note_file)
			)
			conn.commit()
			
			return note_file
			
		except Exception as e:
			error(f"Failed to create annotation: {str(e)}")
			raise DatabaseError(str(e))
	
	def get_file_annotations(self, file_uri: str) -> List[Dict]:
		"""获取文件的所有标注"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(file_uri)
			
			cursor = conn.execute('''
				SELECT a.annotation_id, a.note_file
				FROM annotations a
				JOIN files f ON a.file_id = f.id
				WHERE f.path = ?
				ORDER BY a.annotation_id
			''', (relative_path,))
			
			return [
				{"id": row[0], "note_file": row[1]}
				for row in cursor.fetchall()
			]
			
		except Exception as e:
			error(f"Failed to get file annotations: {str(e)}")
			return []
	
	def delete_annotation(self, file_uri: str, annotation_id: int) -> bool:
		"""删除标注记录"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(file_uri)
			
			cursor = conn.execute('''
				DELETE FROM annotations
				WHERE file_id = (
					SELECT id FROM files WHERE path = ?
				) AND annotation_id = ?
			''', (relative_path, annotation_id))
			
			conn.commit()
			return cursor.rowcount > 0
			
		except Exception as e:
			error(f"Failed to delete annotation: {str(e)}")
			return False

	def increase_annotation_ids(self, file_uri: str, from_id: int, increment: int = 1) -> bool:
		"""增加或减少从指定ID开始的所有标注ID"""
		try:
			conn = self._get_conn()
			relative_path = self._uri_to_relative_path(file_uri)
			
			# 获取文件ID
			cursor = conn.execute('SELECT id FROM files WHERE path = ?', (relative_path,))
			result = cursor.fetchone()
			if not result:
				return False
				
			file_id = result[0]
			
			# 更新标注ID
			if increment > 0:
				# 从最大ID开始更新，避免唯一约束冲突
				conn.execute('''
					UPDATE annotations 
					SET annotation_id = annotation_id + ?
					WHERE file_id = ? AND annotation_id >= ?
					ORDER BY annotation_id DESC
				''', (increment, file_id, from_id))
			else:
				# 从最小ID开始更新，避免唯一约束冲突
				conn.execute('''
					UPDATE annotations 
					SET annotation_id = annotation_id + ?
					WHERE file_id = ? AND annotation_id >= ?
					ORDER BY annotation_id ASC
				''', (increment, file_id, from_id))
			
			conn.commit()
			return True
			
		except Exception as e:
			error(f"Failed to increase annotation ids: {str(e)}")
			return False
