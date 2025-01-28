from dataclasses import dataclass
from typing import Optional

@dataclass
class AnnotationConfig:
	"""标注工具的配置类"""
	# left_bracket: str = '｢'  # 默认使用日语半角左括号
	# right_bracket: str = '｣'  # 默认使用日语半角右括号
	left_bracket: str = '['
	right_bracket: str = ']'

	@classmethod
	def from_initialization_options(cls, options: Optional[dict] = None) -> 'AnnotationConfig':
		"""从LSP客户端的初始化选项创建配置实例"""
		if not options:
			return cls()
			
		return cls(
			left_bracket=options.get('leftBracket', cls.left_bracket),
			right_bracket=options.get('rightBracket', cls.right_bracket)
		)

config: AnnotationConfig
