#!/usr/bin/env python3

import os
import sqlite3
import shutil
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Tuple, Dict

class DatabaseError(Exception):
	"""数据库相关错误"""
	pass

class DatabaseManager:
	def __init__(self):
		self.connections = {}  # 项目路径 -> sqlite3.Connection
		self.current_db = None
		self.max_connections = 5  # 最大保持的连接数
		
	def init_db(self, project_root: str):
		"""初始化或连接到项目的数据库"""
		db_path = Path(project_root) / '.annotation' / 'db' / 'annotations.db'
		
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
				start_line INTEGER,
				start_char INTEGER,
				end_line INTEGER,
				end_char INTEGER,
				note_file TEXT,
				created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
				FOREIGN KEY (file_id) REFERENCES files(id)
			)
		''')
		
		# 管理连接池
		if len(self.connections) >= self.max_connections:
			# 移除最旧的连接
			oldest = next(iter(self.connections))
			self.connections[oldest].close()
			del self.connections[oldest]
		
		self.connections[str(db_path)] = conn
		self.current_db = str(db_path)

	def _get_current_conn(self) -> sqlite3.Connection:
		"""获取当前数据库连接，如果没有则在当前目录初始化一个"""
		if not self.current_db:
			# 在当前目录初始化数据库
			cwd = os.getcwd()
			self.init_db(cwd)
			if not self.current_db:
				raise DatabaseError(f"Failed to initialize database in {cwd}")
		
		if self.current_db not in self.connections:
			raise DatabaseError(f"Database connection not found: {self.current_db}")
		
		return self.connections[self.current_db]
	
	def _backup_db(self, db_path: str):
		"""备份数据库"""
		backup_dir = Path(db_path).parent / 'backups'
		backup_dir.mkdir(exist_ok=True)
		
		timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
		backup_path = backup_dir / f'annotations_{timestamp}.db'
		
		shutil.copy2(db_path, backup_path)
		
		# 保留最近的10个备份
		backups = sorted(backup_dir.glob('annotations_*.db'))
		if len(backups) > 10:
			for old_backup in backups[:-10]:
				old_backup.unlink()
	
	def update_file_annotations(self, file_path: str, annotations: List[Tuple[int, int, int, int, int]]):
		"""更新文件的标注信息"""
		conn = self._get_current_conn()
		
		# 获取或创建文件记录
		cursor = conn.execute(
			'INSERT OR IGNORE INTO files (path, last_modified) VALUES (?, ?)',
			(file_path, datetime.now())
		)
		conn.execute(
			'UPDATE files SET last_modified = ? WHERE path = ?',
			(datetime.now(), file_path)
		)
		
		cursor = conn.execute('SELECT id FROM files WHERE path = ?', (file_path,))
		file_id = cursor.fetchone()[0]
		
		# 删除旧的标注
		conn.execute('DELETE FROM annotations WHERE file_id = ?', (file_id,))
		
		# 插入新的标注
		for aid, start_line, start_char, end_line, end_char in annotations:
			note_file = f'note_{aid}.md'
			conn.execute('''
				INSERT INTO annotations 
				(file_id, annotation_id, start_line, start_char, end_line, end_char, note_file, created_at)
				VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now', 'localtime'))
			''', (file_id, aid, start_line, start_char, end_line, end_char, note_file))
		
		conn.commit()
		if self.current_db:
			self._backup_db(self.current_db)
	
	def get_annotation_note_file(self, doc_uri: str, annotation_id: int) -> Optional[str]:
		"""获取标注对应的笔记文件路径"""
		conn = self._get_current_conn()
		cursor = conn.execute('''
			SELECT a.note_file
			FROM annotations a
			JOIN files f ON a.file_id = f.id
			WHERE f.path = ? AND a.annotation_id = ?
		''', (doc_uri, annotation_id))
		result = cursor.fetchone()
		return result[0] if result else None
	
	def create_annotation(self, doc_uri: str, start_line: int, start_char: int, end_line: int, end_char: int, text: str) -> Tuple[int, str]:
		"""创建新的标注，返回 (annotation_id, note_file)"""
		conn = self._get_current_conn()
		
		# 获取或创建文件记录
		cursor = conn.execute(
			'INSERT OR IGNORE INTO files (path, last_modified) VALUES (?, ?)',
			(doc_uri, datetime.now())
		)
		conn.execute(
			'UPDATE files SET last_modified = ? WHERE path = ?',
			(datetime.now(), doc_uri)
		)
		
		cursor = conn.execute('SELECT id FROM files WHERE path = ?', (doc_uri,))
		file_id = cursor.fetchone()[0]
		
		# 获取新的标注 ID
		cursor = conn.execute(
			'SELECT COALESCE(MAX(annotation_id), 0) + 1 FROM annotations WHERE file_id = ?',
			(file_id,)
		)
		annotation_id = cursor.fetchone()[0]
		
		# 创建标注记录，让数据库自动设置创建时间
		cursor = conn.execute('''
			INSERT INTO annotations 
			(file_id, annotation_id, start_line, start_char, end_line, end_char, created_at)
			VALUES (?, ?, ?, ?, ?, ?, datetime('now', 'localtime'))
		''', (file_id, annotation_id, start_line, start_char, end_line, end_char))
		
		# 生成笔记文件名
		now = datetime.now()
		note_file = f"note_{now.strftime('%Y%m%d_%H%M%S')}.md"
		
		# 更新笔记文件名
		conn.execute('''
			UPDATE annotations
			SET note_file = ?
			WHERE id = ?
		''', (note_file, annotation_id))
		
		conn.commit()
		if self.current_db:
			self._backup_db(self.current_db)
		
		return annotation_id, note_file
	
	def get_file_annotations(self, file_path: str) -> List[Dict]:
		"""获取文件中的所有标注"""
		conn = self._get_current_conn()
		cursor = conn.execute('''
			SELECT a.annotation_id, a.start_line, a.start_char, a.end_line, a.end_char, a.note_file, a.created_at
			FROM annotations a
			JOIN files f ON a.file_id = f.id
			WHERE f.path = ?
		''', (file_path,))
		
		annotations = []
		for row in cursor:
			annotation_id, start_line, start_char, end_line, end_char, note_file, created_at = row
			
			annotations.append({
				'id': annotation_id,
				'range': {
					'start': {'line': start_line, 'character': start_char},
					'end': {'line': end_line, 'character': end_char}
				},
				'note_file': note_file,
				'created_at': created_at
			})
		
		return annotations
	
	def delete_annotation(self, doc_uri: str, annotation_id: int) -> bool:
		"""删除标注"""
		conn = self._get_current_conn()
		
		# 获取文件 ID
		cursor = conn.execute('SELECT id FROM files WHERE path = ?', (doc_uri,))
		result = cursor.fetchone()
		if not result:
			return False
		file_id = result[0]
		
		# 删除标注记录
		conn.execute(
			'DELETE FROM annotations WHERE file_id = ? AND annotation_id = ?',
			(file_id, annotation_id)
		)
		
		conn.commit()
		if self.current_db:
			self._backup_db(self.current_db)
		
		return True
	
	def __del__(self):
		"""关闭所有数据库连接"""
		for conn in self.connections.values():
			try:
				conn.close()
			except:
				pass
