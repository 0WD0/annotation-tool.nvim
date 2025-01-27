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

	def create_annotation(self, doc_uri: str, annotation_id: int) -> str:
		"""创建新的标注，返回 note_file"""
		# TODO: rebuild all
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
		
		# 创建标注记录，让数据库自动设置创建时间
		cursor = conn.execute('''
			INSERT INTO annotations 
			(file_id, annotation_id, created_at)
			VALUES (?, ?, datetime('now', 'localtime'))
		''', (file_id, annotation_id))
		
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
		
		return note_file
	
	def get_file_annotations(self, file_path: str) -> List[Dict]:
		"""获取文件中的所有标注"""
		conn = self._get_current_conn()
		cursor = conn.execute('''
			SELECT a.annotation_id, a.note_file, a.created_at
			FROM annotations a
			JOIN files f ON a.file_id = f.id
			WHERE f.path = ?
		''', (file_path,))
		
		annotations = []
		for row in cursor:
			annotation_id, note_file, created_at = row
			annotations.append({
				'id': annotation_id,
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
		
	def update_file_annotation_ids(self, doc_uri: str, file_content: str) -> None:
		"""根据文件内容中左括号的顺序更新所有标注的 ID
		
		Args:
			doc_uri: 文档 URI
			file_content: 文件内容
		"""
		# TODO: 完全错了
		conn = self._get_current_conn()
		cursor = conn.cursor()
		
		try:
			# 获取文件 ID
			cursor.execute('SELECT id FROM files WHERE path = ?', (doc_uri,))
			file_id = cursor.fetchone()[0]
			
			# 获取文件中所有标注的位置信息
			cursor.execute('''
				SELECT id
				FROM annotations
				WHERE file_id = ?
				ORDER BY start_line, start_char
			''', (file_id,))
			annotations = cursor.fetchall()
			
			# 构建位置到数据库 ID 的映射
			positions = []
			id_map = {}
			# for ann in annotations:
			# 	db_id, start_line, start_char, end_line, end_char = ann
			# 	pos = (start_line, start_char)
			# 	positions.append((pos, db_id))
			
			# 获取文件中所有左括号的位置，按顺序排列
			lines = file_content.splitlines()
			bracket_positions = []
			for line_num, line in enumerate(lines):
				for char_num, char in enumerate(line):
					if char == '｢':
						bracket_positions.append((line_num, char_num))
			
			# 为每个标注分配新的 ID
			for new_id, (bracket_pos, db_id) in enumerate(zip(bracket_positions, positions), 1):
				cursor.execute('''
					UPDATE annotations
					SET annotation_id = ?
					WHERE id = ?
				''', (new_id, db_id[1]))
			
			conn.commit()
			
		except sqlite3.Error as e:
			conn.rollback()
			raise e

	def update_file_annotations(self, file_path: str, annotations: List[int]):
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
		for aid in annotations:
			note_file = f'note_{aid}.md'
			conn.execute('''
				INSERT INTO annotations 
				(file_id, annotation_id, note_file, created_at)
				VALUES (?, ?, ?, datetime('now', 'localtime'))
			''', (file_id, aid, note_file))
		
		conn.commit()
		if self.current_db:
			self._backup_db(self.current_db)
	
	def increment_annotation_ids(self, doc_uri: str, from_id: int) -> None:
		"""将指定文件中大于等于from_id的所有标注id加1"""
		conn = self._get_current_conn()
		cursor = conn.cursor()
		
		# 获取文件 ID
		cursor.execute('SELECT id FROM files WHERE path = ?', (doc_uri,))
		file_id = cursor.fetchone()[0]
		
		with conn:
			cursor = conn.cursor()
			# 从大到小更新，避免id冲突
			cursor.execute('''
				UPDATE annotations
				SET annotation_id = annotation_id + 1
				WHERE file_id = ? AND annotation_id >= ?
				ORDER BY annotation_id DESC
			''', (file_id, from_id))

	def __del__(self):
		"""关闭所有数据库连接"""
		for conn in self.connections.values():
			try:
				conn.close()
			except:
				pass
