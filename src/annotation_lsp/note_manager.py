#!/usr/bin/env python3

import os
from pathlib import Path
from typing import Optional, List, Dict

class NoteManager:
	def __init__(self):
		self.current_project = None
		
	def init_project(self, project_root: str):
		"""初始化项目的笔记目录"""
		self.current_project = project_root
		notes_dir = Path(project_root) / '.annotation' / 'notes'
		notes_dir.mkdir(parents=True, exist_ok=True)
		
	def create_note(self, file_path: str, annotation_id: int, content: str) -> Optional[str]:
		"""创建新的笔记文件"""
		if not self.current_project:
			return None
			
		notes_dir = Path(self.current_project) / '.annotation' / 'notes'
		note_file = notes_dir / f'note_{annotation_id}.md'
		
		if note_file.exists():
			return None
			
		with note_file.open('w', encoding='utf-8') as f:
			f.write(f'---\nfile: {file_path}\nid: {annotation_id}\n---\n\n')
			f.write(f'> {content}\n\n')
		
		return str(note_file)
	
	def update_note_source(self, note_file: str, file_path: str):
		"""更新笔记文件中记录的源文件路径"""
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
	
	def get_note_content(self, note_file: str) -> Optional[str]:
		"""获取笔记文件的内容"""
		note_path = Path(note_file)
		if not note_path.exists():
			return None
			
		with note_path.open('r', encoding='utf-8') as f:
			content = f.read()
			
		return content
	
	def search_notes(self, query: str, search_type: str = 'all') -> List[Dict]:
		"""搜索笔记文件
		search_type可以是：'file_path', 'content', 'note', 'all'
		"""
		if not self.current_project:
			return []
			
		notes_dir = Path(self.current_project) / '.annotation' / 'notes'
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
					
			# 分离原文和笔记
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
