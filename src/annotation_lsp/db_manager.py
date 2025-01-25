#!/usr/bin/env python3

import os
import sqlite3
import shutil
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Tuple

class DatabaseManager:
	def __init__(self):
		self.current_db = None
		self.conn = None
		
	def init_db(self, project_root: str):
		"""初始化或连接到项目的数据库"""
		db_path = Path(project_root) / '.annotation' / 'db' / 'annotations.db'
		if self.current_db != str(db_path):
			if self.conn:
				self.conn.close()
			
			db_path.parent.mkdir(parents=True, exist_ok=True)
			self.conn = sqlite3.connect(str(db_path))
			self.current_db = str(db_path)
			
			# 创建必要的表
			self.conn.execute('''
				CREATE TABLE IF NOT EXISTS files (
					id INTEGER PRIMARY KEY,
					path TEXT UNIQUE,
					last_modified TIMESTAMP
				)
			''')
			
			self.conn.execute('''
				CREATE TABLE IF NOT EXISTS annotations (
					id INTEGER PRIMARY KEY,
					file_id INTEGER,
					annotation_id INTEGER,
					start_line INTEGER,
					start_char INTEGER,
					end_line INTEGER,
					end_char INTEGER,
					note_file TEXT,
					FOREIGN KEY (file_id) REFERENCES files(id),
					UNIQUE (file_id, annotation_id)
				)
			''')
			
			self.conn.commit()
			self._backup_db()
	
	def _backup_db(self):
		"""备份数据库"""
		if not self.current_db:
			return
			
		backup_dir = Path(self.current_db).parent / 'backups'
		backup_dir.mkdir(exist_ok=True)
		
		timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
		backup_path = backup_dir / f'annotations_{timestamp}.db'
		
		shutil.copy2(self.current_db, backup_path)
		
		# 保留最近的10个备份
		backups = sorted(backup_dir.glob('annotations_*.db'))
		if len(backups) > 10:
			for old_backup in backups[:-10]:
				old_backup.unlink()
	
	def update_file_annotations(self, file_path: str, annotations: List[Tuple[int, int, int, int, int]]):
		"""更新文件的标注信息"""
		if not self.conn:
			return
			
		# 获取或创建文件记录
		cursor = self.conn.execute(
			'INSERT OR IGNORE INTO files (path, last_modified) VALUES (?, ?)',
			(file_path, datetime.now())
		)
		self.conn.execute(
			'UPDATE files SET last_modified = ? WHERE path = ?',
			(datetime.now(), file_path)
		)
		
		cursor = self.conn.execute('SELECT id FROM files WHERE path = ?', (file_path,))
		file_id = cursor.fetchone()[0]
		
		# 删除旧的标注
		self.conn.execute('DELETE FROM annotations WHERE file_id = ?', (file_id,))
		
		# 插入新的标注
		for aid, start_line, start_char, end_line, end_char in annotations:
			note_file = f'note_{aid}.md'
			self.conn.execute('''
				INSERT INTO annotations 
				(file_id, annotation_id, start_line, start_char, end_line, end_char, note_file)
				VALUES (?, ?, ?, ?, ?, ?, ?)
			''', (file_id, aid, start_line, start_char, end_line, end_char, note_file))
		
		self.conn.commit()
		self._backup_db()
	
	def get_annotation_note_file(self, file_path: str, annotation_id: int) -> Optional[str]:
		"""获取标注对应的笔记文件路径"""
		if not self.conn:
			return None
			
		cursor = self.conn.execute('''
			SELECT a.note_file
			FROM annotations a
			JOIN files f ON a.file_id = f.id
			WHERE f.path = ? AND a.annotation_id = ?
		''', (file_path, annotation_id))
		
		result = cursor.fetchone()
		return result[0] if result else None
