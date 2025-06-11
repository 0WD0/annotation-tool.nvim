local M = {}

-- 默认配置
local default_config = {
	-- LSP 配置
	lsp = {
		-- LSP 实现版本
		version = 'python', -- 'python' | 'javascript'
		-- 连接方式
		connection = 'stdio', -- 'stdio' | 'tcp'
		-- TCP 连接配置（仅在 connection = 'tcp' 时使用）
		host = '127.0.0.1',
		port = 2087,
		-- Python 解释器路径（仅在 version = 'python' 时使用）
		python_path = nil, -- 默认自动检测
		-- 调试模式
		debug = false,
	},

	-- 搜索配置
	search = {
		-- 默认搜索后端
		default_backend = 'telescope', -- 'telescope' | 'fzf-lua'
		-- 默认搜索范围
		default_scope = 'current_file', -- 'current_file' | 'current_workspace' | 'current_project'
		-- 自动检测最优后端
		auto_backend = false,
		-- 搜索历史
		enable_history = true,
		-- 最大历史记录数
		max_history = 50,
	},

	-- 后端特定配置
	backends = {
		telescope = {
			-- 是否启用
			enabled = true,
			-- telescope 特定选项
			opts = {
				prompt_title = "🔍 查找标注",
				preview_title = "📝 标注预览",
				results_title = "📋 搜索结果",
				layout_strategy = "horizontal",
				layout_config = {
					width = 0.9,
					height = 0.8,
					preview_width = 0.6,
				},
				-- 其他 telescope 配置
				sorting_strategy = "ascending",
				file_ignore_patterns = {},
			}
		},
		fzf_lua = {
			-- 是否启用
			enabled = true,
			-- fzf-lua 特定选项
			opts = {
				prompt = "🔍 查找标注 > ",
				fzf_opts = {
					['--layout'] = 'reverse',
					['--preview-window'] = 'right:50%:wrap',
					['--border'] = 'rounded',
					['--margin'] = '1,2',
				},
				winopts = {
					height = 0.8,
					width = 0.9,
					border = 'rounded',
					preview = {
						layout = 'vertical',
						border = 'border',
					}
				},
				-- 性能选项
				file_icons = true,
				color_icons = true,
			}
		}
	},

	-- 快捷键配置
	keymaps = {
		-- 是否启用默认快捷键
		enable_default = true,
		-- 快捷键前缀
		prefix = '<leader>n',
		-- 前缀标识符（可自定义，避免与实际快捷键冲突）
		prefix_symbol = '@',
		-- 具体快捷键映射
		-- 使用前缀标识符表示 prefix，不使用则为完整快捷键
		-- 例如（当 prefix_symbol = '@'）：'@c' -> '<leader>nc', '<C-x>' -> '<C-x>'
		mappings = {
			-- 基本操作
			enable = '@e', -- 启用标注模式 -> <leader>ne
			toggle = '@t', -- 切换标注模式 -> <leader>nt
			create = '@c', -- 创建标注 (visual mode) -> <leader>nc

			-- 搜索操作
			find = '@f',  -- 智能搜索标注 -> <leader>nf
			find_telescope = '@T', -- 强制使用 telescope -> <leader>nT
			find_fzf = '@F', -- 强制使用 fzf-lua -> <leader>nF

			-- 范围搜索
			find_current_file = '@1',
			find_current_workspace = '@2',
			find_current_project = '@3',

			-- 智能搜索
			smart_find = '@s', -- 智能搜索（自动选择后端和范围） -> <leader>ns

			-- 管理操作
			delete = '@d', -- 删除标注 -> <leader>nd
			tree = '@w', -- 显示标注树 -> <leader>nw

			-- 导航操作
			preview = '@p',   -- 预览当前标注 -> <leader>np
			goto_source = '@h', -- 跳转到标注源文件 -> <leader>nh
			prev_annotation = '<A-k>', -- 上一个标注（全局快捷键，不使用prefix）
			next_annotation = '<A-j>', -- 下一个标注（全局快捷键，不使用prefix）
		},
		-- 搜索界面内快捷键（适用于所有后端）
		search_keys = {
			open = '<CR>',
			delete = '<C-d>',
			toggle_mode = '<C-t>',
			exit = '<C-c>',
		}
	},

	-- 预览配置
	preview = {
		-- 预览窗口默认位置
		position = 'right', -- 'right' | 'bottom' | 'top' | 'left'
		-- 预览窗口大小（百分比）
		size = 0.5,
		-- 是否启用语法高亮
		syntax_highlighting = true,
		-- 是否显示行号
		show_line_numbers = true,
		-- 预览内容格式化
		format = {
			-- 内容部分标题
			content_title = "📝 标注内容",
			-- 笔记部分标题
			notes_title = "💡 笔记",
			-- 元信息标题
			meta_title = "📂 文件信息",
			-- 当前选中标题
			current_title = "🎯 当前选中",
		}
	},

	-- 主题配置
	theme = {
		-- 图标配置
		icons = {
			content = "📄",
			note = "📝",
			file = "📂",
			search = "🔍",
			tree = "🌳",
			annotation = "📌",
		},
		-- 颜色配置（使用 vim 高亮组）
		colors = {
			content = "String",
			note = "Comment",
			file_path = "Directory",
			line_number = "LineNr",
			match = "Search",
		}
	},

	-- 性能配置
	performance = {
		-- 搜索结果缓存
		enable_cache = true,
		-- 缓存过期时间（秒）
		cache_ttl = 300,
		-- 大项目检测阈值（文件数）
		large_project_threshold = 1000,
		-- 对于大项目的默认搜索范围
		large_project_scope = 'current_file',
		-- 异步加载
		async_loading = true,
	},

	-- 调试配置
	debug = {
		-- 是否启用调试模式
		enabled = false,
		-- 日志级别
		log_level = 4,
		-- 日志前缀
		log_prefix = '[annotation-tool]',
		-- 性能监控
		performance_monitoring = false,
	}
}

-- 当前配置
local current_config = vim.deepcopy(default_config)

-- 深度合并表
local function deep_merge(target, source)
	for key, value in pairs(source) do
		if type(value) == 'table' and type(target[key]) == 'table' then
			deep_merge(target[key], value)
		else
			target[key] = value
		end
	end
	return target
end

-- 验证配置
local function validate_config(config)
	local errors = {}

	-- 验证 LSP 配置
	if config.lsp then
		-- 验证 LSP 版本
		if config.lsp.version then
			local version = config.lsp.version
			if version ~= 'python' and version ~= 'javascript' then
				table.insert(errors, "无效的 LSP 版本: " .. version)
			end
		end

		-- 验证连接方式
		if config.lsp.connection then
			local connection = config.lsp.connection
			if connection ~= 'stdio' and connection ~= 'tcp' then
				table.insert(errors, "无效的 LSP 连接方式: " .. connection)
			end
		end

		-- 验证端口号
		if config.lsp.port then
			local port = config.lsp.port
			if type(port) ~= 'number' or port < 1 or port > 65535 then
				table.insert(errors, "无效的端口号: " .. tostring(port))
			end
		end
	end

	-- 验证搜索后端
	if config.search and config.search.default_backend then
		local backend = config.search.default_backend
		if backend ~= 'telescope' and backend ~= 'fzf-lua' then
			table.insert(errors, "无效的默认搜索后端: " .. backend)
		end
	end

	-- 验证搜索范围
	if config.search and config.search.default_scope then
		local scope = config.search.default_scope
		local valid_scopes = { 'current_file', 'current_workspace', 'current_project' }
		if not vim.tbl_contains(valid_scopes, scope) then
			table.insert(errors, "无效的默认搜索范围: " .. scope)
		end
	end

	-- 验证快捷键前缀
	if config.keymaps and config.keymaps.prefix then
		local prefix = config.keymaps.prefix
		if not prefix:match('^<[^>]+>') and not prefix:match('^[a-zA-Z0-9_%-]+$') then
			table.insert(errors, "无效的快捷键前缀: " .. prefix)
		end
	end

	return errors
end

-- 设置配置
function M.setup(user_config)
	user_config = user_config or {}

	-- 重置为默认配置
	current_config = vim.deepcopy(default_config)

	-- 合并用户配置
	deep_merge(current_config, user_config)

	-- 验证配置
	local errors = validate_config(current_config)
	if #errors > 0 then
		error("配置验证失败:\n" .. table.concat(errors, "\n"))
	end

	return current_config
end

-- 获取配置
function M.get(key)
	if not key then
		return current_config
	end

	-- 支持点号分隔的键路径，如 'backends.telescope.enabled'
	local keys = vim.split(key, '.', { plain = true })
	local value = current_config

	for _, k in ipairs(keys) do
		if type(value) == 'table' and value[k] ~= nil then
			value = value[k]
		else
			return nil
		end
	end

	return value
end

-- 设置配置值
function M.set(key, value)
	local keys = vim.split(key, '.', { plain = true })
	local current = current_config

	-- 导航到父级
	for i = 1, #keys - 1 do
		local k = keys[i]
		if type(current[k]) ~= 'table' then
			current[k] = {}
		end
		current = current[k]
	end

	-- 设置值
	current[keys[#keys]] = value
end

-- 获取默认配置
function M.get_default()
	return vim.deepcopy(default_config)
end

-- 重置配置
function M.reset()
	current_config = vim.deepcopy(default_config)
end

-- 检查后端是否可用
function M.is_backend_available(backend)
	if backend == 'telescope' then
		local ok = pcall(require, 'telescope')
		return ok and M.get('backends.telescope.enabled')
	elseif backend == 'fzf-lua' or backend == 'fzf_lua' then
		local ok = pcall(require, 'fzf-lua')
		return ok and M.get('backends.fzf_lua.enabled')
	end
	return false
end

-- 获取最佳可用后端
function M.get_best_backend()
	local default_backend = M.get('search.default_backend')

	-- 如果启用了自动检测
	if M.get('search.auto_backend') then
		-- 优先级：fzf-lua > telescope（性能考虑）
		if M.is_backend_available('fzf-lua') then
			return 'fzf-lua'
		elseif M.is_backend_available('telescope') then
			return 'telescope'
		end
	else
		-- 使用用户指定的默认后端
		if M.is_backend_available(default_backend) then
			return default_backend
		end
		-- 如果默认后端不可用，尝试其他后端
		if default_backend == 'telescope' and M.is_backend_available('fzf-lua') then
			return 'fzf-lua'
		elseif default_backend == 'fzf-lua' and M.is_backend_available('telescope') then
			return 'telescope'
		end
	end

	return nil -- 没有可用的后端
end

-- 获取智能搜索范围（根据项目大小）
function M.get_smart_scope()
	local core = require('annotation-tool.core')
	return core.get_smart_scope()
end

-- 获取后端特定选项
function M.get_backend_opts(backend)
	if backend == 'telescope' then
		return M.get('backends.telescope.opts') or {}
	elseif backend == 'fzf-lua' or backend == 'fzf_lua' then
		return M.get('backends.fzf_lua.opts') or {}
	end
	return {}
end

-- 获取快捷键映射
-- 支持可配置的前缀标识符
-- 例如：'@c' -> '<leader>nc', '<C-x>' -> '<C-x>'
function M.get_keymaps()
	local keymaps = M.get('keymaps')
	if not keymaps or not keymaps.enable_default then
		return {}
	end

	local prefix = keymaps.prefix or '<leader>n'
	local prefix_symbol = keymaps.prefix_symbol or '@'
	local mappings = keymaps.mappings or {}
	local result = {}

	for action, key in pairs(mappings) do
		if type(key) == 'string' then
			-- 如果快捷键以前缀标识符开头，替换为 prefix
			if key:sub(1, #prefix_symbol) == prefix_symbol then
				result[action] = prefix .. key:sub(#prefix_symbol + 1)
			else
				-- 否则直接使用完整的快捷键
				result[action] = key
			end
		end
	end

	return result
end

-- 导出配置到文件
function M.export_config(file_path)
	local content = string.format("-- annotation-tool 配置文件\n-- 生成时间: %s\n\nreturn %s",
		os.date("%Y-%m-%d %H:%M:%S"),
		vim.inspect(current_config, { indent = "  " }))

	vim.fn.writefile(vim.split(content, '\n'), file_path)
end

-- 从文件导入配置
function M.import_config(file_path)
	local ok, cfg_or_err = pcall(dofile, file_path)
	if ok and type(cfg_or_err) == 'table' then
		M.setup(cfg_or_err)
		return true
	else
		require('annotation-tool.logger').error(string.format("导入配置失败: %s", cfg_or_err))
		return false, cfg_or_err
	end
end

-- 获取 LSP 配置选项
function M.get_lsp_opts()
	return M.get('lsp') or {}
end

-- 获取配置统计信息
function M.get_stats()
	local core = require('annotation-tool.core')
	local cwd = vim.fn.getcwd()
	local cache_info = core.get_project_cache_info(cwd)

	return {
		available_backends = {
			telescope = M.is_backend_available('telescope'),
			fzf_lua = M.is_backend_available('fzf-lua'),
		},
		best_backend = M.get_best_backend(),
		smart_scope = M.get_smart_scope(),
		keymaps_enabled = M.get('keymaps.enable_default'),
		debug_enabled = M.get('debug.enabled'),
		lsp_version = M.get('lsp.version'),
		lsp_connection = M.get('lsp.connection'),
		project_cache = cache_info,
		plenary_available = core.is_plenary_available(),
	}
end

return M
