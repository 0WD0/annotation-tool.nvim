#!/usr/bin/env python3

import os
from pathlib import Path
from typing import Optional, List, Dict
from urllib.parse import urlparse, unquote
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
		self.notes_dir = self.project_root / '.annotation' / 'notes'
		self.notes_dir.mkdir(parents=True, exist_ok=True)
	
	def _uri_to_path(self, uri: str) -> Path:
		"""将 URI 转换为 Path 对象"""
		parsed = urlparse(uri)
		path = unquote(parsed.path)
		if os.name == 'nt' and path.startswith('/'):
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
	
	def create_annotation_note(self, file_uri: str, annotation_id: int, text: str, note_file: str) -> Optional[str]:
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
			
			with note_path.open('w', encoding='utf-8') as f:
				f.write(f'---\nfile: {relative_path}\nid: {annotation_id}\n---\n\n')
				f.write(f'## Selected Text\n\n')
				f.write('```\n')
				f.write(text)
				f.write('\n```\n\n')
				f.write('## Notes\n\n')
			
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
	
	def update_note_source(self, note_file: str, file_path: str):
		"""更新批注文件中记录的源文件路径"""
		note_path = Path(note_file)
		if not note_path.exists():
			return
			
		with note_path.open('r', encoding='utf-8') as f:
			lines = f.readlines()
			
		# 更新文件路径
		for i, line in enumerate(lines):
			if line.startswith('file:'):
				lines[i] = f'file: {file_path}\n'
				break
				
		with note_path.open('w', encoding='utf-8') as f:
			f.writelines(lines)
	
	def update_note_aid(self, note_file: str, annotation_id: int):
		"""更新批注文件中记录的id"""
		note_path = Path(note_file)
		if not note_path.exists():
			return
			
		with note_path.open('r', encoding='utf-8') as f:
			lines = f.readlines()
			
		# 更新文件路径
		for i, line in enumerate(lines):
			if line.startswith('id:'):
				lines[i] = f'id: {annotation_id}\n'
				break
				
		with note_path.open('w', encoding='utf-8') as f:
			f.writelines(lines)
	

	def get_note_content(self, note_file: str) -> Optional[str]:
		"""读取笔记文件内容
		
		Args:
			note_file: 笔记文件的相对路径（相对于 notes 目录）
			
		Returns:
			笔记文件的内容，如果读取失败则返回 None
		"""
		try:
			if not self.notes_dir:
				raise Exception("Notes directory not set")
				
			note_path = self.notes_dir / note_file
			if not note_path.exists():
				raise Exception("Note file does not exist")
				
			with note_path.open('r', encoding='utf-8') as f:
				return f.read()
				
		except Exception as e:
			error(f"Failed to read note file: {str(e)}")
			return None
	def search_notes(self, query: str, search_type: str = 'all') -> List[Dict]:
		"""搜索批注文件
		search_type可以是：'file_path', 'content', 'note', 'all'
		"""
		notes_dir = self.get_notes_dir()
		if not notes_dir:
			return []
		
		results = []
		for note_file in notes_dir.glob('*.md'):
			with note_file.open('r', encoding='utf-8') as f:
				content = f.read()
				
			# 解析front matter
			file_path = None
			for line in content.split('\n'):
				if line.startswith('file:'):
					file_path = line.split(':', 1)[1].strip()
					break
			if file_path == None:
				return results
					
			# 分离原文和批注
			parts = content.split('---', 2)
			if len(parts) >= 3:
				note_content = parts[2].strip()
				original_text = ''
				for line in note_content.split('\n'):
					if line.startswith('>'):
						original_text += line[1:].strip() + '\n'
				
				# 根据搜索类型进行匹配
				matched = False
				if search_type in ('file_path', 'all') and query.lower() in file_path.lower():
					matched = True
				elif search_type in ('content', 'all') and query.lower() in original_text.lower():
					matched = True
				elif search_type in ('note', 'all') and query.lower() in note_content.lower():
					matched = True
					
				if matched:
					results.append({
						'file': file_path,
						'note_file': str(note_file),
						'original_text': original_text.strip(),
						'note_content': note_content
					})
					
		return results
