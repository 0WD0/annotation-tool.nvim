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
		default_scope = 'current_file', -- 'current_file' | 'current_project' | 'all_projects'
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
		prefix = '<leader>a',
		-- 具体快捷键映射
		mappings = {
			-- 基本操作
			enable = 'e',           -- <leader>ae
			toggle = 't',           -- <leader>at
			create = 'c',           -- <leader>ac (visual mode)

			-- 搜索操作
			find = 'f',             -- <leader>af - 使用默认后端搜索
			find_telescope = 'T',   -- <leader>aT - 强制使用 telescope
			find_fzf = 'F',         -- <leader>aF - 强制使用 fzf-lua

			-- 范围搜索
			find_current_file = '1', -- <leader>a1
			find_project = '2',      -- <leader>a2
			find_all = '3',          -- <leader>a3

			-- 智能搜索
			smart_find = 's',        -- <leader>as

			-- 管理操作
			delete = 'd',            -- <leader>ad
			list = 'l',              -- <leader>al
			tree = 'w',              -- <leader>aw
		},
		-- 搜索界面内快捷键（适用于所有后端）
		search_keys = {
			open = '<CR>',
			open_alt = '<C-o>',
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
		log_level = 'info', -- 'debug' | 'info' | 'warn' | 'error'
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
		local valid_scopes = { 'current_file', 'current_project', 'all_projects' }
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

-- 配置是否已初始化的标志
local is_setup_called = false

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

	-- 标记已初始化
	is_setup_called = true

	return current_config
end

-- 获取配置
function M.get(key)
	if not key then
		return current_config
	end

	-- 支持点号分隔的键路径，如 'search.default_backend'
	local keys = vim.split(key, '%.', { plain = true })
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
	local keys = vim.split(key, '%.', { plain = true })
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
	elseif backend == 'fzf-lua' then
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
	local perf_config = M.get('performance')
	if not perf_config or not perf_config.enable_cache then
		return M.get('search.default_scope') or 'current_file'
	end

	-- 检查项目大小
	local cwd = vim.fn.getcwd()
	local ok, files = pcall(vim.fn.glob, cwd .. '/**/*', false, true)
	if not ok then
		-- 如果获取文件列表失败，使用默认范围
		return M.get('search.default_scope') or 'current_file'
	end

	local file_count = #files
	local threshold = perf_config.large_project_threshold or 1000
	local large_scope = perf_config.large_project_scope or 'current_file'

	if file_count > threshold then
		return large_scope
	else
		return M.get('search.default_scope') or 'current_file'
	end
end

-- 获取后端特定选项
function M.get_backend_opts(backend)
	if backend == 'telescope' then
		return M.get('backends.telescope.opts') or {}
	elseif backend == 'fzf-lua' then
		return M.get('backends.fzf_lua.opts') or {}
	end
	return {}
end

-- 获取快捷键映射
function M.get_keymaps()
	local keymaps = M.get('keymaps')
	if not keymaps or not keymaps.enable_default then
		return {}
	end

	local prefix = keymaps.prefix or '<leader>a'
	local mappings = keymaps.mappings or {}
	local result = {}

	for action, key in pairs(mappings) do
		result[action] = prefix .. key
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
	local ok, config = pcall(dofile, file_path)
	if ok and type(config) == 'table' then
		M.setup(config)
		return true
	end
	return false
end

-- 获取 LSP 配置选项
function M.get_lsp_opts()
	return M.get('lsp') or {}
end

-- 获取配置统计信息
function M.get_stats()
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
	}
end

return M

