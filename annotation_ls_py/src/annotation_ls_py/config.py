from dataclasses import dataclass, field
from typing import Optional, Dict, Any

# 默认配置
DEFAULT_CONFIG = {
	"left_bracket": "｢",
	"right_bracket": "｣",
}


@dataclass(frozen=True)
class AnnotationConfig:
	"""标注工具的配置类"""

	left_bracket: str = field(default=DEFAULT_CONFIG["left_bracket"])
	right_bracket: str = field(default=DEFAULT_CONFIG["right_bracket"])

	@classmethod
	def from_dict(cls, data: Optional[Dict[str, Any]] = None) -> "AnnotationConfig":
		"""
		从可选字典创建 AnnotationConfig 配置实例。
		
		如果未提供字典或字典为空，则返回默认配置；否则根据字典中的 "leftBracket" 和 "rightBracket" 键覆盖默认括号字符。
		"""
		if not data:
			return cls()

		config_data = DEFAULT_CONFIG.copy()
		config_data.update(
			{
				"left_bracket": data.get("leftBracket", DEFAULT_CONFIG["left_bracket"]),
				"right_bracket": data.get("rightBracket", DEFAULT_CONFIG["right_bracket"]),
			}
		)

		return cls(**config_data)


class _ConfigManager:
	"""配置管理器，用于全局配置管理"""

	_instance = None
	_config: Optional[AnnotationConfig] = None

	def __new__(cls):
		if cls._instance is None:
			cls._instance = super().__new__(cls)
		return cls._instance

	@property
	def config(self) -> AnnotationConfig:
		"""获取当前配置"""
		if self._config is None:
			self._config = AnnotationConfig()
		return self._config

	def initialize(self, options: Optional[dict] = None) -> None:
		"""
		初始化全局注释配置，仅在首次调用时生效。
		
		如果已初始化，则不会重复设置。可接受来自LSP客户端的初始化选项字典。
		"""
		if self._config is not None:
			return

		self._config = AnnotationConfig.from_dict(options)


# 创建全局配置管理器实例
_config_manager = _ConfigManager()

# 导出全局配置对象
config = _config_manager.config


# 导出初始化函数
def initialize_config(options: Optional[dict] = None) -> None:
	"""
	初始化全局注释配置。
	
	如果未初始化，则使用提供的选项进行配置，否则保持现有配置不变。
	"""
	_config_manager.initialize(options)
