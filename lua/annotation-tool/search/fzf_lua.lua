local M = {}

-- 延迟加载依赖，避免循环依赖
local function load_deps()
	local core = require('annotation-tool.core')
	local preview = require('annotation-tool.preview')
	local logger = require('annotation-tool.logger')
	local lsp = require('annotation-tool.lsp')
	local config = require('annotation-tool.config')
	local search = require('annotation-tool.search')

	return {
		core = core,
		preview = preview,
		logger = logger,
		lsp = lsp,
		search = search,
		config = config
	}
end

---检查 fzf-lua 是否可用
---@return boolean, table|string 是否可用，fzf-lua 模块或错误信息
local function check_fzf_lua()
	local ok, fzf_lua = pcall(require, 'fzf-lua')
	if not ok then
		return false, "fzf-lua 模块未安装或加载失败"
	end
	return true, fzf_lua
end

---过滤标注条目根据搜索模式
---@param annotations table 所有标注条目
---@param mode string 搜索模式，'content' 或 'note'
---@return table 过滤后的条目
local function filter_annotations(annotations, mode)
	local filtered = {}
	for _, entry in ipairs(annotations) do
		if mode == 'content' and entry.entry_type == "content" then
			table.insert(filtered, entry)
		elseif mode == 'note' and entry.entry_type == "note" then
			table.insert(filtered, entry)
		end
	end
	return filtered
end

---格式化条目用于 fzf-lua 显示
---@param entry table 标注条目
---@param mode string 搜索模式
---@return string 格式化后的字符串
local function format_entry_for_fzf(entry, mode)
	local deps = load_deps()
	local display_text = ""
	local icons = deps.config.get('theme.icons') or {}
	local type_icon = (mode == 'content') and (icons.content or "📄") or (icons.note or "📝")

	if mode == 'content' then
		display_text = entry.content or ""
	else
		display_text = entry.note or ""
	end

	-- 安全地限制显示长度
	display_text = deps.core.safe_truncate_utf8(display_text, 80, "...")

	return string.format("%s %s", type_icon, display_text)
end

---创建预览函数，用于 fzf-lua 预览
---@param entry table 标注条目
---@return table 预览内容行
local function create_preview_lines(entry)
	local deps = load_deps()
	local lines = {}
	local preview_format = deps.config.get('preview.format') or {}

	-- 添加标注内容（使用完整内容）
	table.insert(lines, "# " .. (preview_format.content_title or "📝 标注内容"))
	table.insert(lines, "")
	if entry.full_content and entry.full_content ~= "" then
		for content_line in entry.full_content:gmatch("[^\r\n]+") do
			table.insert(lines, content_line)
		end
	else
		table.insert(lines, "*（无内容）*")
	end
	table.insert(lines, "")

	-- 添加笔记内容（使用完整笔记）
	table.insert(lines, "# " .. (preview_format.notes_title or "💡 笔记"))
	table.insert(lines, "")
	if entry.full_note and entry.full_note ~= "" then
		for note_line in entry.full_note:gmatch("[^\r\n]+") do
			table.insert(lines, note_line)
		end
	else
		table.insert(lines, "*（无笔记）*")
	end

	-- 添加当前选中信息
	if entry.line_info then
		table.insert(lines, "")
		table.insert(lines, "# " .. (preview_format.current_title or "🎯 当前选中"))
		table.insert(lines, "")
		table.insert(lines, entry.line_info)
		if entry.entry_type == "content" then
			table.insert(lines, "📄 内容: " .. (entry.content or ""))
		else
			table.insert(lines, "📝 笔记: " .. (entry.note or ""))
		end
	end

	-- 添加文件信息
	table.insert(lines, "")
	table.insert(lines, "# " .. (preview_format.meta_title or "📂 文件信息"))
	table.insert(lines, "")
	table.insert(lines, "源文件: " .. (entry.file or "未知"))
	table.insert(lines, "笔记文件: " .. (entry.note_file or "未知"))

	return lines
end

---使用 fzf-lua 进行标注搜索
---@param options table 搜索选项
---  - scope: 搜索范围
---  - annotations_result: LSP 返回的标注数据
function M.search_annotations(options)
	local deps = load_deps()

	-- 检查 fzf-lua 是否可用
	local ok, fzf_lua = check_fzf_lua()
	if not ok then
		deps.logger.error(fzf_lua)
		return
	end

	if not vim.tbl_contains(deps.search.SCOPE, options.scope) then
		deps.logger.error("不支持的搜索范围: " .. options.scope .. "\n支持的范围: " .. table.concat(deps.search.SCOPE, ", "))
		return
	end

	local scope_display_name = deps.search.get_scope_display_name(options.scope)

	if not options.annotations_result then
		deps.logger.info("未找到标注")
		-- 显示空的 fzf picker
		fzf_lua.fzf_exec({}, {
			prompt = string.format('🔍 查找%s批注 (无结果) > ', scope_display_name),
		})
		return
	end

	-- 解析标注数据
	local annotations = deps.search.parser.parse_annotations_result(options.annotations_result)

	if #annotations == 0 then
		deps.logger.info("解析后无有效标注")
		return
	end

	-- 搜索模式状态（'content' 或 'note'）
	-- 支持从 options 中传入初始模式
	local search_mode = options._initial_mode or 'content'
	-- 全局条目映射，供预览函数使用
	local global_entry_map = {}

	---切换搜索模式的动作
	local function toggle_search_mode(selected, opts)
		-- 切换搜索模式
		local new_mode = search_mode == 'content' and 'note' or 'content'
		local mode_name = new_mode == 'content' and '内容' or '笔记'

		deps.logger.info(string.format("正在切换到%s模式...", mode_name))

		-- 延迟执行，避免在当前 picker 操作中重新创建
		vim.schedule(function()
			-- 重新调用搜索，但传入新的搜索模式
			local new_options = vim.tbl_extend('force', options, {
				_initial_mode = new_mode
			})
			M.search_annotations(new_options)
		end)

		-- 关闭当前 picker
		-- 由于 fzf-lua 的实现，这里不需要返回任何值
	end

	---打开标注的动作
	local function open_annotation(selected, opts)
		if not selected or #selected == 0 then
			deps.logger.warn("未选中有效条目")
			return
		end

		-- 从映射中获取原始条目
		local entry = opts._entry_map and opts._entry_map[selected[1]]
		if not entry then
			deps.logger.warn("无法找到条目数据")
			return
		end

		-- 输出调试信息
		deps.logger.debug_obj("选中的标注", entry)

		if not entry.file or not entry.position then
			deps.logger.warn("条目缺少必要的文件或位置信息")
		else
			-- 打开文件并跳转到标注位置
			local buf = vim.fn.bufadd(entry.file)
			if not vim.api.nvim_buf_is_valid(buf) then
				deps.logger.error("无法创建有效缓冲区")
				return
			end
			vim.api.nvim_set_option_value('buflisted', true, { buf = buf })
			vim.api.nvim_win_set_buf(0, buf)
			local cursor_pos = deps.core.convert_utf8_to_bytes(0, entry.position)
			if cursor_pos and cursor_pos[1] > 0 and cursor_pos[2] >= 0 then
				vim.api.nvim_win_set_cursor(0, cursor_pos)
			end
		end

		-- 打开预览窗口
		deps.preview.goto_annotation_note({
			workspace_path = entry.workspace_path,
			note_file = entry.note_file
		})
	end

	---删除标注的动作
	local function delete_annotation(selected, opts)
		if not selected or #selected == 0 then
			deps.logger.warn("未选中有效条目")
			return
		end

		-- 从映射中获取原始条目
		local entry = opts._entry_map and opts._entry_map[selected[1]]
		if not entry then
			deps.logger.warn("无法找到条目数据")
			return
		end

		deps.logger.debug_obj("尝试删除标注", entry)
		local file_path = entry.workspace_path .. '/.annotation/notes/' .. entry.note_file

		-- 使用新的delete_annotation API，传入位置信息和回调
		deps.lsp.delete_annotation({
			buffer = vim.fn.bufadd(file_path),
			rev = true,
			on_success = function(result)
				-- 删除成功后刷新列表
				vim.schedule(function()
					-- 使用通用的刷新标注函数
					local scope = options.scope
					deps.search.refresh_annotations(scope, function(err, new_result)
						if err then
							deps.logger.error("刷新标注列表失败: " .. vim.inspect(err))
							return
						end

						-- 更新全局annotations变量
						annotations = deps.search.parser.parse_annotations_result(new_result)
						deps.logger.info("标注删除成功，列表已刷新")

						-- 重新启动搜索
						M.search_annotations(vim.tbl_extend("force", options, {
							annotations_result = new_result
						}))
					end)
				end)
			end,
			on_cancel = function()
				-- 取消删除，什么都不做
				deps.logger.info("删除操作已取消")
			end
		})
	end

	-- 初始化数据
	local filtered = filter_annotations(annotations, search_mode)
	local formatted_entries = {}
	local entry_map = {}

	for _, entry in ipairs(filtered) do
		local formatted = format_entry_for_fzf(entry, search_mode)
		table.insert(formatted_entries, formatted)
		entry_map[formatted] = entry
	end

	-- 初始化全局条目映射
	global_entry_map = entry_map

	-- 获取 fzf-lua 配置
	local fzf_opts = deps.config.get_backend_opts('fzf_lua') or {}
	local search_keys = deps.config.get('keymaps.search_keys') or {}

	-- 构建动作映射（使用配置中的快捷键）
	local actions_map = {}
	actions_map['default'] = open_annotation

	-- 使用配置中的快捷键
	local delete_key = search_keys.delete or 'ctrl-d'
	local toggle_key = search_keys.toggle_mode or 'ctrl-t'

	-- 映射快捷键（转换为 fzf-lua 格式）
	local function normalize_key(key)
		return key:gsub('<C%-(.-)>', 'ctrl-%1'):gsub('<(.-)>', '%1')
	end

	actions_map[normalize_key(delete_key)] = delete_annotation
	actions_map[normalize_key(toggle_key)] = toggle_search_mode

	-- 构建 fzf-lua picker 选项
	local mode_display = search_mode == 'content' and '内容' or '笔记'
	local picker_opts = vim.tbl_deep_extend('force', {
		prompt = string.format('🔍 查找%s批注[%s] - %s切换模式 > ',
			scope_display_name,
			mode_display,
			search_keys.toggle_mode or '<C-t>'),
		-- 保存条目映射
		_entry_map = entry_map,
		actions = actions_map,
		-- 使用 fzf-lua 预览
		preview = function(items)
			-- 在预览函数中，使用全局条目映射获取数据
			if not items or #items == 0 or not items[1] then
				return "无可预览的项目"
			end

			local entry = global_entry_map[items[1]]
			if entry then
				local lines = create_preview_lines(entry)
				return table.concat(lines, "\n")
			end
			return "预览数据无效: " .. tostring(items[1])
		end,
	}, fzf_opts)

	-- 创建 fzf-lua picker
	fzf_lua.fzf_exec(formatted_entries, picker_opts)
end

return M
