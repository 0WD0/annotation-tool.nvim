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
└── notes/
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

## 数据库设计

数据库使用 SQLite，包含两个主要表：

### files 表

存储文件信息：

```sql
CREATE TABLE files (
    id INTEGER PRIMARY KEY,   -- 文件ID
    path TEXT UNIQUE,         -- 文件路径（唯一）
    last_modified TIMESTAMP   -- 最后修改时间
)
```

### annotations 表

存储标注信息：

```sql
CREATE TABLE annotations (
    id INTEGER PRIMARY KEY,   -- 标注在数据库中的唯一ID
    file_id INTEGER,          -- 关联的文件ID
    annotation_id INTEGER,    -- 标注在文件中的序号（基于左括号顺序）
    start_line INTEGER,       -- 开始行
    start_char INTEGER,       -- 开始字符位置
    end_line INTEGER,         -- 结束行
    end_char INTEGER,         -- 结束字符位置
    note_file TEXT,           -- 关联的笔记文件名
    created_at TIMESTAMP,     -- 创建时间
    FOREIGN KEY (file_id) REFERENCES files(id)  -- 外键约束
)
```

说明：
- `annotation_id` 是标注在文件中的序号，基于左括号（｢）在文件中出现的顺序，从1开始编号
- 每个标注都有一个对应的笔记文件（`note_file`），存储在 `.annotation/notes` 目录下
- 标注的位置使用行号和字符位置来定位，支持跨行标注
- 使用外键约束确保数据完整性，每个标注必须关联到一个有效的文件

### 外键约束说明

外键约束（Foreign Key Constraint）是一种数据库完整性约束，用于确保数据的一致性和完整性。在我们的设计中：

1. `annotations` 表中的 `file_id` 是一个外键，它引用了 `files` 表的 `id` 字段
2. 这个约束确保：
   - 不能创建指向不存在文件的标注（插入约束）
   - 不能删除还有标注的文件（删除约束）
   - 如果文件的 ID 发生变化，相关标注的 `file_id` 也会自动更新（更新约束）

例如：
```sql
-- 这个操作会失败，因为 file_id=999 在 files 表中不存在
INSERT INTO annotations (file_id, ...) VALUES (999, ...);

-- 这个操作会失败，因为该文件还有关联的标注
DELETE FROM files WHERE id = 1;
```

这样的设计可以防止：
- 孤立的标注（没有对应文件的标注）
- 数据不一致（文件和标注的关联关系混乱）
- 意外删除（防止删除还在使用的文件）

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

