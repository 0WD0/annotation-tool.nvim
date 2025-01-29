from typing import Dict, List, Optional, Tuple
from pygls.workspace.text_document import TextDocument
from lsprotocol import types
from bisect import bisect_left
from .config import config
from .logger import *

def tuple_to_range(origin: Tuple[int, int, int, int]) -> types.Range:
	return types.Range(
		start=types.Position(
			line=origin[0],
			character=origin[1]
		),
		end=types.Position(
			line=origin[2],
			character=origin[3]
		)
	)

def find_annotation_ranges_raw(doc: TextDocument) -> Optional[List[Tuple[int, int, int, int]]]:
	"""找出所有标注区间及其ID（基于右括号出现顺序）"""
	annotations = []
	start_stack = []
	lines = doc.lines
	
	# 从服务器配置中获取括号
	left_bracket = config.left_bracket
	right_bracket = config.right_bracket
	
	# 遍历每一行
	for line_num, line in enumerate(lines):
		for i, char in enumerate(line):
			if char == left_bracket:
				start_stack.append((line_num,i))
			if char == right_bracket:
				if start_stack == []: return None
				left_pos = start_stack.pop()
				right_pos = (line_num,i)
				annotations.append(left_pos+right_pos)
	if start_stack != []: return None
	return annotations

def find_annotation_ranges(doc: TextDocument) -> Optional[List[Tuple[int, int, int, int]]]:
	"""找出所有标注区间及其ID（基于左括号出现顺序）"""
	annotations = find_annotation_ranges_raw(doc)
	if annotations == None: return None
	return sorted(annotations)

def find_annotation_Ranges(doc: TextDocument) -> Optional[List[types.Range]]:
	"""用lsprotocol.Range来表示找到的批注区间（基于左括号出现顺序）"""
	annotations=find_annotation_ranges(doc)
	if annotations == None: return None
	return [tuple_to_range(t) for t in annotations]

def get_text_in_range(doc: TextDocument, selection_range: types.Range) -> str:
	# 获取选中的文本
	lines = doc.lines
	if selection_range.start.line == selection_range.end.line:
		# 单行选择
		line = lines[selection_range.start.line]
		selected_text = ''.join(c for c in line[selection_range.start.character:selection_range.end.character] if c != config.left_bracket and c != config.right_bracket)
	else:
		# 多行选择
		selected_text = []
		for i in range(selection_range.start.line, selection_range.end.line + 1):
			if i == selection_range.start.line:
				line = lines[i][selection_range.start.character:]
			elif i == selection_range.end.line:
				line = lines[i][:selection_range.end.character]
			else:
				line = lines[i]
			# 过滤掉半角括号
			filtered_line = ''.join(c for c in line if c != config.left_bracket and c != config.right_bracket)
			selected_text.append(filtered_line)
		selected_text = '\n'.join(selected_text)
	return selected_text

def get_annotation_id_before_position(doc: TextDocument, position: types.Position) -> Optional[int]:
	"""获取给定位置上一个批注区间的id"""
	annotations = find_annotation_ranges(doc)
	if annotations == None: return None
	pos_line = position.line
	pos_char = position.character
	return bisect_left(annotations,(pos_line, pos_char))

def get_annotation_at_position(doc: TextDocument, position: types.Position) -> Optional[int]:
	"""获取给定位置所在的批注区间"""
	annotation_R = find_annotation_ranges_raw(doc)
	if annotation_R == None: return None
	annotation_L = sorted(annotation_R)

	for i,annotation in enumerate(annotation_L):
		start_line, start_char, end_line, end_char = annotation
		info(f"Annotation_L {i}: L{start_line}C{start_char}-L{end_line}C{end_char}")

	for i,annotation in enumerate(annotation_R):
		start_line, start_char, end_line, end_char = annotation
		info(f"Annotation_R {i}: L{start_line}C{start_char}-L{end_line}C{end_char}")

	pos_line = position.line
	pos_char = position.character
	
	for annotation in annotation_R:
		start_line, start_char, end_line, end_char = annotation
		if (start_line <= pos_line <= end_line and
			(start_line != pos_line or start_char <= pos_char) and
			(end_line != pos_line or pos_char <= end_char)):
			return annotation_L.index(annotation)+1
	
	return None

def extract_notes_content(content: str) -> str:
	"""从笔记内容中提取 ## Notes 后面的内容
	Args:
		content: 完整的笔记内容
	Returns:
		## Notes 后面的内容，如果没有找到则返回空字符串
	"""
	# 按行分割并查找 ## Notes
	lines = content.splitlines()
	for i, line in enumerate(lines):
		if line.strip() == "## Notes":
			# 返回 ## Notes 后面的所有内容
			return "\n".join(lines[i+1:]).strip()
	
	return ""
