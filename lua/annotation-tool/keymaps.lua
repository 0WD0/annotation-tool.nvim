local M = {}

-- 延迟加载依赖，避免循环依赖
local function load_deps()
	local config = require('annotation-tool.config')
	local logger = require('annotation-tool.logger')
	return {
		config = config,
		logger = logger
	}
end

-- 已注册的快捷键映射
local registered_keymaps = {}

-- 清理快捷键映射
local function clear_keymaps()
	for _, mapping in ipairs(registered_keymaps) do
		pcall(vim.keymap.del, mapping.mode, mapping.lhs, { buffer = mapping.buffer })
	end
	registered_keymaps = {}
end

-- 注册快捷键映射
local function register_keymap(mode, lhs, rhs, opts)
	opts = opts or {}
	vim.keymap.set(mode, lhs, rhs, opts)
	table.insert(registered_keymaps, {
		mode = mode,
		lhs = lhs,
		buffer = opts.buffer
	})
end

-- 设置基本操作快捷键
local function setup_basic_keymaps()
	local deps = load_deps()
	local keymaps = deps.config.get_keymaps()
	if vim.tbl_isempty(keymaps) then
		return
	end

	local core = require('annotation-tool.core')
	local lsp = require('annotation-tool.lsp')

	-- 基本操作
	if keymaps.enable then
		register_keymap('n', keymaps.enable, ':AnnotationEnable<CR>', { desc = '启用标注模式' })
	end

	if keymaps.toggle then
		register_keymap('n', keymaps.toggle, ':AnnotationToggle<CR>', { desc = '切换标注模式' })
	end

	if keymaps.create then
		register_keymap('v', keymaps.create, ':AnnotationCreate<CR>', { desc = '创建标注' })
	end

	-- 管理操作
	if keymaps.delete then
		register_keymap('n', keymaps.delete, ':AnnotationDelete<CR>', { desc = '删除标注' })
	end

	if keymaps.list then
		register_keymap('n', keymaps.list, ':AnnotationList<CR>', { desc = '列出标注' })
	end

	if keymaps.tree then
		register_keymap('n', keymaps.tree, ':AnnotationTree<CR>', { desc = '标注树' })
	end
end

-- 设置搜索快捷键
local function setup_search_keymaps()
	local deps = load_deps()
	local keymaps = deps.config.get_keymaps()
	if vim.tbl_isempty(keymaps) then
		return
	end

	local search = require('annotation-tool.search')

	-- 智能搜索（使用配置的默认后端和智能范围）
	if keymaps.find then
		register_keymap('n', keymaps.find, function()
			local backend = deps.config.get_best_backend()
			local scope = deps.config.get_smart_scope()
			if backend then
				search.find_annotations({ backend = backend, scope = scope })
			else
				deps.logger.error("没有可用的搜索后端")
			end
		end, { desc = '智能搜索标注' })
	end

	-- 强制使用特定后端
	if keymaps.find_telescope then
		register_keymap('n', keymaps.find_telescope, function()
			if deps.config.is_backend_available('telescope') then
				search.find_annotations({ backend = search.BACKEND.TELESCOPE })
			else
				deps.logger.error("Telescope 后端不可用")
			end
		end, { desc = '使用 Telescope 搜索标注' })
	end

	if keymaps.find_fzf then
		register_keymap('n', keymaps.find_fzf, function()
			if deps.config.is_backend_available('fzf-lua') then
				search.find_annotations({ backend = search.BACKEND.FZF_LUA })
			else
				deps.logger.error("fzf-lua 后端不可用")
			end
		end, { desc = '使用 fzf-lua 搜索标注' })
	end

	-- 按范围搜索
	if keymaps.find_current_file then
		register_keymap('n', keymaps.find_current_file, function()
			local backend = deps.config.get_best_backend()
			if backend then
				search.find_annotations({ backend = backend, scope = search.SCOPE.CURRENT_FILE })
			else
				deps.logger.error("没有可用的搜索后端")
			end
		end, { desc = '搜索当前文件标注' })
	end

	if keymaps.find_project then
		register_keymap('n', keymaps.find_project, function()
			local backend = deps.config.get_best_backend()
			if backend then
				search.find_annotations({ backend = backend, scope = search.SCOPE.CURRENT_PROJECT })
			else
				deps.logger.error("没有可用的搜索后端")
			end
		end, { desc = '搜索当前项目标注' })
	end

	if keymaps.find_all then
		register_keymap('n', keymaps.find_all, function()
			local backend = deps.config.get_best_backend()
			if backend then
				search.find_annotations({ backend = backend, scope = search.SCOPE.ALL_PROJECTS })
			else
				deps.logger.error("没有可用的搜索后端")
			end
		end, { desc = '搜索所有项目标注' })
	end

	-- 智能搜索（显式版本）
	if keymaps.smart_find then
		register_keymap('n', keymaps.smart_find, function()
			local backend = deps.config.get_best_backend()
			local scope = deps.config.get_smart_scope()

			if not backend then
				deps.logger.error("没有可用的搜索后端")
				return
			end

			-- 显示选择的后端和范围
			local scope_names = {
				current_file = "当前文件",
				current_project = "当前项目",
				all_projects = "所有项目"
			}

			deps.logger.info(string.format("使用 %s 搜索 %s 的标注", backend, scope_names[scope] or scope))
			search.find_annotations({ backend = backend, scope = scope })
		end, { desc = '智能搜索标注（显示选择信息）' })
	end
end

-- 设置 Which-key 描述（如果可用）
local function setup_which_key()
	local ok, which_key = pcall(require, 'which-key')
	if not ok then
		return
	end

	local deps = load_deps()
	local keymaps = deps.config.get_keymaps()
	if vim.tbl_isempty(keymaps) then
		return
	end

	local prefix = deps.config.get('keymaps.prefix')
	local icons = deps.config.get('theme.icons')

	-- 主分组
	which_key.add({
		{ prefix, group = icons.annotation .. " Annotation" },

		-- 基本操作分组
		{ keymaps.enable, desc = "启用标注模式" },
		{ keymaps.toggle, desc = "切换标注模式" },
		{ keymaps.create, desc = "创建标注", mode = "v" },

		-- 搜索分组
		{ keymaps.find, desc = icons.search .. " 智能搜索" },
		{ keymaps.find_telescope, desc = "🔭 Telescope 搜索" },
		{ keymaps.find_fzf, desc = "⚡ fzf-lua 搜索" },
		{ keymaps.smart_find, desc = "🧠 智能搜索（详细）" },

		-- 范围搜索分组
		{ keymaps.find_current_file, desc = icons.file .. " 当前文件" },
		{ keymaps.find_project, desc = "📁 当前项目" },
		{ keymaps.find_all, desc = "🌍 所有项目" },

		-- 管理分组
		{ keymaps.delete, desc = "🗑️ 删除标注" },
		{ keymaps.list, desc = "📋 列出标注" },
		{ keymaps.tree, desc = icons.tree .. " 标注树" },
	})
end

-- 设置所有快捷键
function M.setup()
	local deps = load_deps()
	deps.logger.debug("设置快捷键映射")

	-- 清理现有映射
	clear_keymaps()

	-- 检查是否启用快捷键
	if not deps.config.get('keymaps.enable_default') then
		deps.logger.debug("默认快捷键已禁用")
		return
	end

	-- 设置各类快捷键
	setup_basic_keymaps()
	setup_search_keymaps()
	setup_which_key()

	deps.logger.debug(string.format("已注册 %d 个快捷键映射", #registered_keymaps))
end

-- 重新设置快捷键
function M.reload()
	M.setup()
end

-- 获取已注册的快捷键信息
function M.get_registered()
	return vim.deepcopy(registered_keymaps)
end

-- 检查快捷键冲突
function M.check_conflicts()
	local conflicts = {}
	local existing_maps = {}

	-- 收集现有映射
	for _, mode in ipairs({ 'n', 'v', 'i' }) do
		local maps = vim.api.nvim_get_keymap(mode)
		for _, map in ipairs(maps) do
			if not existing_maps[mode] then
				existing_maps[mode] = {}
			end
			existing_maps[mode][map.lhs] = {
				rhs = map.rhs or '',
				desc = map.desc or '',
			}
		end
	end

	-- 检查冲突
	for _, mapping in ipairs(registered_keymaps) do
		local mode = mapping.mode
		local lhs = mapping.lhs

		if existing_maps[mode] and existing_maps[mode][lhs] then
			table.insert(conflicts, {
				keymap = lhs,
				mode = mode,
				existing = existing_maps[mode][lhs],
			})
		end
	end

	return conflicts
end

-- 打印快捷键帮助
function M.show_help()
	local deps = load_deps()
	local keymaps = deps.config.get_keymaps()
	if vim.tbl_isempty(keymaps) then
		print("快捷键映射已禁用")
		return
	end

	local icons = deps.config.get('theme.icons')

	print("=== " .. icons.annotation .. " Annotation Tool 快捷键 ===")
	print("")

	-- 基本操作
	print("📋 基本操作:")
	if keymaps.enable then print("  " .. keymaps.enable .. " - 启用标注模式") end
	if keymaps.toggle then print("  " .. keymaps.toggle .. " - 切换标注模式") end
	if keymaps.create then print("  " .. keymaps.create .. " - 创建标注 (visual mode)") end
	print("")

	-- 搜索操作
	print(icons.search .. " 搜索操作:")
	if keymaps.find then print("  " .. keymaps.find .. " - 智能搜索") end
	if keymaps.find_telescope then print("  " .. keymaps.find_telescope .. " - Telescope 搜索") end
	if keymaps.find_fzf then print("  " .. keymaps.find_fzf .. " - fzf-lua 搜索") end
	if keymaps.smart_find then print("  " .. keymaps.smart_find .. " - 智能搜索（详细）") end
	print("")

	-- 范围搜索
	print("🎯 范围搜索:")
	if keymaps.find_current_file then print("  " .. keymaps.find_current_file .. " - 当前文件") end
	if keymaps.find_project then print("  " .. keymaps.find_project .. " - 当前项目") end
	if keymaps.find_all then print("  " .. keymaps.find_all .. " - 所有项目") end
	print("")

	-- 管理操作
	print("🔧 管理操作:")
	if keymaps.delete then print("  " .. keymaps.delete .. " - 删除标注") end
	if keymaps.list then print("  " .. keymaps.list .. " - 列出标注") end
	if keymaps.tree then print("  " .. keymaps.tree .. " - 标注树") end
	print("")

	-- 搜索界面快捷键
	local search_keys = deps.config.get('keymaps.search_keys')
	print("🔍 搜索界面快捷键:")
	print("  " .. search_keys.open .. " - 打开标注")
	print("  " .. search_keys.open_alt .. " - 打开标注（备选）")
	print("  " .. search_keys.delete .. " - 删除标注")
	print("  " .. search_keys.toggle_mode .. " - 切换搜索模式")
	print("  " .. search_keys.exit .. " - 退出搜索")
	print("")

	-- 后端状态
	local stats = deps.config.get_stats()
	print("⚡ 后端状态:")
	print("  Telescope: " .. (stats.available_backends.telescope and "✅ 可用" or "❌ 不可用"))
	print("  fzf-lua: " .. (stats.available_backends.fzf_lua and "✅ 可用" or "❌ 不可用"))
	print("  当前最佳: " .. (stats.best_backend or "无"))
	print("  智能范围: " .. (stats.smart_scope or "无"))
end

-- 导出快捷键配置到文件
function M.export_keymaps(file_path)
	local deps = load_deps()
	local keymaps = deps.config.get_keymaps()
	local content = {
		"-- annotation-tool 快捷键配置",
		"-- 生成时间: " .. os.date("%Y-%m-%d %H:%M:%S"),
		"",
		"local keymaps = " .. vim.inspect(keymaps, { indent = "  " }),
		"",
		"-- 设置快捷键",
		"for action, key in pairs(keymaps) do",
		"  -- 在这里添加你的快捷键设置逻辑",
		"  print(action .. ': ' .. key)",
		"end",
	}

	vim.fn.writefile(content, file_path)
end

return M

