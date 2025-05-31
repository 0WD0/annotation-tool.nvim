from typing import List, Optional, Tuple
from pygls.workspace.text_document import TextDocument
from lsprotocol import types
from bisect import bisect_left
from pathlib import Path
import frontmatter
from .config import config
from .logger import *


def tuple_to_range(origin: Tuple[int, int, int, int]) -> types.Range:
	"""
	将四元组表示的起止位置转换为 Range 对象。
	
	参数:
	    origin: 包含起始行、起始字符、结束行、结束字符的四元组。
	
	返回:
	    对应的 lsprotocol.types.Range 对象。
	"""
	return types.Range(
		start=types.Position(line=origin[0], character=origin[1]),
		end=types.Position(line=origin[2], character=origin[3]),
	)


def find_annotation_ranges_raw(
	doc: TextDocument,
) -> Optional[List[Tuple[int, int, int, int]]]:
	"""
	扫描文档，查找由配置括号包围的所有标注区间。
	
	遍历文档内容，按右括号出现顺序返回每个标注区间的起止行列元组列表。如果括号不匹配，返回 None。
	
	返回:
	    标注区间的四元组列表（起始行、起始列、结束行、结束列），或在括号不匹配时返回 None。
	"""
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
				start_stack.append((line_num, i))
			if char == right_bracket:
				if start_stack == []:
					return None
				left_pos = start_stack.pop()
				right_pos = (line_num, i)
				annotations.append(left_pos + right_pos)
	if start_stack != []:
		return None
	return annotations


def find_annotation_ranges(
	doc: TextDocument,
) -> Optional[List[Tuple[int, int, int, int]]]:
	"""
	查找文档中所有标注区间，并按左括号出现顺序返回其位置元组列表。
	
	返回值为每个标注区间的起止位置元组（start_line, start_char, end_line, end_char）组成的列表，按左括号出现顺序排序；若未找到有效标注区间则返回 None。
	"""
	annotations = find_annotation_ranges_raw(doc)
	if annotations is None:
		return None
	return sorted(annotations)


def find_annotation_Ranges(doc: TextDocument) -> Optional[List[types.Range]]:
	"""
	返回文档中所有批注区间的lsprotocol.types.Range对象列表，按左括号出现顺序排列。
	
	如果未找到批注区间，则返回None。
	"""
	annotations = find_annotation_ranges(doc)
	if annotations is None:
		return None
	return [tuple_to_range(t) for t in annotations]


def get_text_in_range(doc: TextDocument, selection_range: types.Range) -> str:
	# 获取选中的文本
	"""
	提取指定范围内的文本，并过滤掉配置的左右括号字符。
	
	Args:
		selection_range: 指定的文本范围。
	
	Returns:
		去除左右括号后的选中文本内容，支持单行和多行选择。
	"""
	lines = doc.lines
	if selection_range.start.line == selection_range.end.line:
		# 单行选择
		line = lines[selection_range.start.line]
		selected_text = "".join(
			c
			for c in line[selection_range.start.character : selection_range.end.character]
			if c != config.left_bracket and c != config.right_bracket
		)
	else:
		# 多行选择
		selected_text = []
		for i in range(selection_range.start.line, selection_range.end.line + 1):
			if i == selection_range.start.line:
				line = lines[i][selection_range.start.character :]
			elif i == selection_range.end.line:
				line = lines[i][: selection_range.end.character]
			else:
				line = lines[i]
			# 过滤掉半角括号
			filtered_line = "".join(
				c for c in line if c != config.left_bracket and c != config.right_bracket
			)
			selected_text.append(filtered_line)
		selected_text = "\n".join(selected_text)
	return selected_text


def get_annotation_id_before_position(doc: TextDocument, position: types.Position) -> Optional[int]:
	"""
	返回紧邻给定位置之前的批注区间的索引id。
	
	如果文档中不存在批注区间，则返回None。
	"""
	annotations = find_annotation_ranges(doc)
	if annotations is None:
		return None
	pos_line = position.line
	pos_char = position.character
	return bisect_left(annotations, (pos_line, pos_char))


def get_annotation_at_position(doc: TextDocument, position: types.Position) -> Optional[int]:
	"""
	返回给定位置所在的批注区间的编号。
	
	如果指定位置位于某个批注区间内，则返回该区间在排序后列表中的1-based编号；如果不在任何批注区间内，则返回None。
	"""
	annotation_R = find_annotation_ranges_raw(doc)
	if annotation_R is None:
		return None
	annotation_L = sorted(annotation_R)

	for _, annotation in enumerate(annotation_L):
		start_line, start_char, end_line, end_char = annotation
		# info(f"Annotation_L {i}: L{start_line}C{start_char}-L{end_line}C{end_char}")

	for _, annotation in enumerate(annotation_R):
		start_line, start_char, end_line, end_char = annotation
		# info(f"Annotation_R {i}: L{start_line}C{start_char}-L{end_line}C{end_char}")

	pos_line = position.line
	pos_char = position.character

	for annotation in annotation_R:
		start_line, start_char, end_line, end_char = annotation
		if (
			start_line <= pos_line <= end_line
			and (start_line != pos_line or start_char <= pos_char)
			and (end_line != pos_line or pos_char <= end_char)
		):
			return annotation_L.index(annotation) + 1

	return None


def extract_notes_content(content: str) -> str:
	"""
	提取笔记内容中紧随“## Notes”标题之后的所有文本。
	
	Args:
	    content: 包含完整笔记内容的字符串。
	
	Returns:
	    “## Notes”所在行之后的所有内容字符串；若未找到该标题，则返回空字符串。
	"""
	# 按行分割并查找 ## Notes
	lines = content.splitlines()
	for i, line in enumerate(lines):
		if line.strip() == "## Notes":
			# 返回 ## Notes 后面的所有内容
			return "\n".join(lines[i + 1 :]).strip()

	return ""


def update_note_source(note_file: Path, file_path: str):
	"""
	更新批注笔记文件的元数据中的源文件路径字段。
	
	如果指定的笔记文件存在，则加载其 frontmatter 元数据，将 "file" 字段更新为给定的文件路径，并保存更改。若文件不存在则不执行任何操作。
	"""
	if not note_file.exists():
		return
	note_path = str(note_file)
	post = frontmatter.load(note_path)
	post.metadata["file"] = file_path
	frontmatter.dump(post, note_path)


def update_note_aid(note_file: Path, annotation_id: int):
	"""
	更新批注笔记文件的元数据字段"id"为指定的批注编号。
	
	如果文件不存在，则不进行任何操作。
	"""
	if not note_file.exists():
		return
	note_path = str(note_file)
	post = frontmatter.load(note_path)
	post.metadata["id"] = annotation_id
	frontmatter.dump(post, note_path)
