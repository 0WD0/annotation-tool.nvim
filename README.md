# Annotation Tool

一个基于Neovim的文本批注工具，支持嵌套批注、实时预览和全文搜索。

## 特性

- 支持在任意文本文件中添加批注
- 批注区间可以嵌套
- 使用LSP实现实时高亮和悬停预览
- 支持在右侧窗口实时预览当前批注
- 支持通过文件路径、原文内容或批注内容进行搜索
- 自动管理批注文件，支持双向跳转
- 支持文件重命名和移动后的自动同步
- 自动备份数据库

## 依赖

- Neovim >= 0.8.0
- Python >= 3.8
- 以下Python包：
	- python-lsp-server
	- pygls
	- sqlalchemy
	- fuzzyfinder
	- watchdog

## 安装

1. 安装Python依赖：

```bash
pip install -r requirements.txt
```

2. 在你的Neovim配置中添加插件（使用你喜欢的插件管理器）：

```lua
-- 使用lazy.nvim
return {
	'annotation-tool',
	dependencies = {
		'neovim/nvim-lspconfig',
		'nvim-telescope/telescope.nvim',
	},
	opts = {}
}
```

## 使用方法

### 基本操作

- `<Leader>aa`: 切换annotation mode（启用/禁用批注功能）
- `<Leader>an`: 创建新批注（在visual mode下选中文本后使用）
- `<Leader>af`: 搜索批注（使用telescope）

### 批注格式

批注使用日语半角括号（｢｣）来标记区间。在annotation mode下，这些括号会被隐藏以保持文本的可读性。

### 项目结构

批注工具会在项目根目录创建一个`.annotation`目录，包含以下内容：

```
.annotation/
├── db/
│   ├── annotations.db
│   └── backups/
├── notes/
└── note_*.md
```

### 批注文件格式

每个批注文件（`.md`）包含以下内容：

```markdown
---
file: /path/to/source/file
id: 1
---

> 原文内容

你的批注内容
```

## 配置选项

在setup函数中可以自定义以下选项：

```lua
require('annotation-tool').setup({
	-- 自定义选项将在后续版本中添加
})
```

## 注意事项

- 批注文件使用`.md`格式，可以使用所有Markdown的功能
- 数据库会自动备份，默认保留最近10个备份
- 建议定期备份`.annotation`目录

## License

MIT
