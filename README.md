# Annotation Tool

一个基于Neovim的文本批注工具，支持嵌套批注、实时预览和全文搜索。

## 特性

- 支持在任意文本文件中添加批注
- 悬停预览
- 自动备份数据库
- 批注区间可以嵌套
- 多项目多文件支持
- [ ] 支持项目移动
- [ ] 支持在右侧窗口实时预览当前批注
- [ ] 光标下的批注区间高亮
- [ ] 自动同步批注文件frontmatter，支持双向跳转
- [ ] 支持文件重命名和移动后的自动同步
- [ ] 支持通过文件路径、原文内容或批注内容进行模糊搜索

## 依赖

- Neovim >= 0.8.0
- Python >= 3.7
- 以下 Neovim 插件：
  - neovim/nvim-lspconfig
  - nvim-telescope/telescope.nvim（可选，用于全局搜索功能）

插件会自动创建和管理 Python 虚拟环境，你不需要手动安装任何 Python 包。虚拟环境会被创建在插件目录下的 `.venv` 目录中，包含以下主要依赖：

- pygls >= 1.1.1：LSP 服务器实现
- lsprotocol >= 2023.0.1：LSP 协议定义

如果你想使用自己的 Python 环境，可以在配置中指定：

```lua
require('annotation-tool').setup({
    python_path = '/path/to/your/python'
})
```

## 安装

在你的 Neovim 配置中添加插件（使用你喜欢的插件管理器）：

```lua
-- 使用 lazy.nvim
return {
    'annotation-tool',
    dependencies = {
        'neovim/nvim-lspconfig',
        'nvim-telescope/telescope.nvim', -- 可选
    },
    opts = {
        -- 可选配置
        -- python_path = '/path/to/your/python'
    }
}
```

首次启动时，插件会：
1. 创建 Python 虚拟环境（在插件目录下的 `.venv` 目录）
2. 安装必要的依赖
3. 启动 LSP 服务器

## 使用方法

### 基本操作

- `<Leader>na`: 创建新批注（在visual mode下选中文本后使用）
- `<Leader>nd`: 删除当前光标下的批注（默认删除批注的笔记文件）
- `<Leader>nl`: 显示当前文件的批注个数（使用数据库统计，不是括号对数）
- [ ] `<Leader>aa`: 切换annotation mode（启用/禁用批注功能）
- [ ] `<Leader>nf`: 搜索批注（使用telescope）

### 批注格式

批注使用日语半角括号（｢｣）来标记区间。在annotation mode下，这些括号会被隐藏以保持文本的可读性。
你也可以自己选择左右括号的标识。

nvim 和 lsp 端的括号设置还未同步。

### 项目结构

默认情况下，你需要手动创建一个 `.annotation` 目录，annotation-tool将以它所在的目录作为这个批注项目的根目录

annotation-tool 会在`.annotation`目录填充以下文件内容：

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
file: /relative/path/to/source/file
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
    note_file TEXT,           -- 关联的笔记文件名
    created_at TIMESTAMP,     -- 创建时间
    FOREIGN KEY (file_id) REFERENCES files(id)  -- 外键约束
)
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
