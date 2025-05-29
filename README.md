# Annotation Tool

一个基于 Neovim 的文本批注工具，支持嵌套批注、实时预览和全文搜索。


![Version](https://img.shields.io/badge/version-0.13.0-blue)
![Neovim](https://img.shields.io/badge/Neovim-0.11+-green)
![License](https://img.shields.io/badge/license-MIT-orange)

## 目录

- [特性](#特性)
- [依赖](#依赖)
- [安装](#安装)
- [使用方法](#使用方法)
  - [基本操作](#基本操作)
  - [批注格式](#批注格式)
- [配置选项](#配置选项)
  - [调试模式](#调试模式)
- [项目结构](#项目结构)
  - [批注文件格式](#批注文件格式)
- [数据库设计](#数据库设计)
- [常见问题](#常见问题)
- [贡献指南](#贡献指南)
- [许可证](#许可证)

## 特性

✅ **核心功能**
- 支持在任意纯文本文件中添加批注
- 批注区间可以嵌套
- 自动同步批注文件 frontmatter，支持双向跳转
- 光标下的批注区间高亮

✅ **用户体验**
- 悬停预览
- 在右侧窗口预览和切换批注文件
- 内置调试模式，方便排查问题

✅ **项目管理**
- 同一个 nvim session 中多项目多文件支持
- 支持项目移动和嵌套

🚧 **计划中的功能**
- 自动备份数据库
- 支持文件移动和文件重命名
- 支持通过文件路径、原文内容或批注内容进行模糊搜索

## 依赖

### 必需依赖

- **Neovim**: >= 0.11
- **Python**: >= 3.7
- **nvim-lspconfig**: [neovim/nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)

### 可选依赖

- **telescope.nvim**: [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (用于全局搜索功能)

### Python 依赖

插件会自动创建和管理 Python 虚拟环境，你不需要手动安装任何 Python 包。虚拟环境会被创建在插件目录下的 `.venv` 目录中，包含以下主要依赖：

- **pygls** >= 1.1.1：LSP 服务器实现
- **lsprotocol** >= 2023.0.1：LSP 协议定义
- **python-frontmatter** >= 1.1.0：Markdown frontmatter 处理

## 安装

### 使用 [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
	'annotation-tool',
	dependencies = {
		'neovim/nvim-lspconfig',
		'nvim-telescope/telescope.nvim', -- 可选
	},
	opts = {
		-- 可选配置
		-- python_path = '/path/to/your/python',
		-- debug = true, -- 启用调试模式
	}
}
```

### 使用 [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
	'annotation-tool',
	requires = {
		'neovim/nvim-lspconfig',
		'nvim-telescope/telescope.nvim', -- 可选
	},
	config = function()
		require('annotation-tool').setup({
			-- 可选配置
			-- python_path = '/path/to/your/python',
			-- debug = true, -- 启用调试模式
		})
	end
}
```

### 首次启动

首次启动时，插件会：

1. 创建 Python 虚拟环境（在插件目录下的 `.venv` 目录）
2. 安装必要的依赖
3. 启动 LSP 服务器

## 使用方法

### 基本操作

| 快捷键 | 模式 | 功能 |
|--------|------|------|
| `<Leader>na` | Visual | 创建新批注（在选中文本后使用） |
| `<Leader>nd` | Normal | 删除当前光标下的批注 |
| `<Leader>nl` | Normal | 显示当前文件的批注列表 |
| `<Leader>np` | Normal | 预览当前光标下的批注 |
| `K` | Normal | 显示当前光标下批注的悬浮窗口 |

### Telescope 集成

如果安装了 [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)，可以使用以下快捷键：

| 快捷键 | 模式 | 功能 |
|--------|------|------|
| `<Leader>nf` | Normal | 使用 Telescope 查找所有批注 |
| `<Leader>ns` | Normal | 使用 Telescope 搜索批注内容 |

### 预览窗口操作

| 快捷键 | 功能 |
|--------|------|
| `<A-k>` | 跳转到上一个批注文件 |
| `<A-j>` | 跳转到下一个批注文件 |

### 批注格式

批注使用日语半角括号（｢｣）来标记区间。在 annotation mode 下，这些括号会被隐藏以保持文本的可读性。你也可以自己选择左右括号的标识（见[配置选项](#配置选项)）。

> **注意**：目前 Neovim 和 LSP 端的括号配置还未同步。

### 示例

#### 创建新批注

1. 选中文本。
2. 按 `<Leader>na` 创建批注。

#### 删除批注

1. 将光标放在要删除的批注上。
2. 按 `<Leader>nd` 删除批注。

#### 查看批注列表

1. 按 `<Leader>nl` 显示当前文件的所有批注。

#### 预览批注

1. 将光标放在要预览的批注上。
2. 按 `<Leader>np` 预览批注内容。

#### 使用 Telescope 查找批注

1. 确保安装了 [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)。
2. 按 `<Leader>nf` 查找所有批注。
3. 按 `<Leader>ns` 搜索批注内容。

#### 使用预览窗口

1. 在预览窗口中按 `<A-k>` 跳转到上一个批注文件。
2. 在预览窗口中按 `<A-j>` 跳转到下一个批注文件。

## 配置选项

在 `setup` 函数中可以自定义以下选项：

```lua
require('annotation-tool').setup({
    -- Python 解释器路径，默认使用系统 Python
    python_path = '/path/to/your/python',
    
    -- 是否启用调试模式，默认为 false
    debug = false,
    
    -- 左右括号标识，默认使用日语半角括号
    left_mark = '｢',  -- 可选配置项
    right_mark = '｣',  -- 可选配置项
})
```

### 调试模式

启用调试模式后，插件会输出更详细的日志信息，帮助你排查问题。日志信息包括：

- LSP 服务器的初始化过程
- 批注操作的详细信息（创建、删除、查询等）
- 文件读写操作
- 错误和警告信息

启用调试模式的配置示例：

```lua
require('annotation-tool').setup({
	debug = true
})
```

## 项目结构

默认情况下，你需要手动创建一个 `.annotation` 目录，否则插件不会启动。
annotation-tool 将以它所在的目录作为这个批注项目的根目录。

annotation-tool 会在 `.annotation` 目录填充以下文件内容：

```
.annotation/
├── db/
│   ├── annotations.db
│   └── backups/
└── notes/
	└── note_*.md
```

### 批注文件格式

每个批注文件（`.md`）包含以下内容：

````markdown
---
file: /source/file/path/relative/to/project/root
id: 1
---
```
原文内容
```
你的批注内容
````

## 数据库设计

数据库使用 SQLite，包含两个主要表：

### files 表

存储文件信息：

```sql
CREATE TABLE files (
	id INTEGER PRIMARY KEY,   -- 文件ID
	path TEXT UNIQUE,		 -- 文件路径（唯一）
	last_modified TIMESTAMP   -- 最后修改时间
)
```

### annotations 表

存储标注信息：

```sql
CREATE TABLE annotations (
	id INTEGER PRIMARY KEY,   -- 标注在数据库中的唯一ID
	file_id INTEGER,		  -- 关联的文件ID
	annotation_id INTEGER,	-- 标注在文件中的序号（基于左括号顺序）
	note_file TEXT,		   -- 关联的笔记文件名
	FOREIGN KEY (file_id) REFERENCES files(id)  -- 和 files 表中的id关联
	UNIQUE (file_id, annotation_id)
)
```

## 常见问题

### 批注文件备份

- 批注文件使用 `.md` 格式，可以使用所有 Markdown 的功能
- 数据库会自动备份，默认保留最近 10 个备份
- 建议定期备份 `.annotation` 目录

### 性能考虑

- 对于大型项目，建议使用调试模式进行初始设置和排查问题，然后在日常使用时关闭调试模式以提高性能

## 贡献指南

欢迎贡献代码、报告问题或提出新功能建议。请通过 GitHub Issues 和 Pull Requests 参与项目开发。

## 许可证

[MIT](LICENSE)
