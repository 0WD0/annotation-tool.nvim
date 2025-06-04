local M = {}

-- 延迟加载依赖，避免循环依赖
local function load_deps()
	local core = require('annotation-tool.core')
	local preview = require('annotation-tool.preview')
	local logger = require('annotation-tool.logger')
	local lsp = require('annotation-tool.lsp')
	local config = require('annotation-tool.config')
	local parser = require('annotation-tool.search.parser')

	return {
		core = core,
		preview = preview,
		logger = logger,
		lsp = lsp,
		parser = parser,
		config = config
	}
end

---创建自定义的标注预览器，使用 telescope 的预览器构建函数
---@return table telescope 预览器对象
local function create_annotation_previewer()
	local previewers = require('telescope.previewers')

	return previewers.new_buffer_previewer({
		title = "标注预览",
		dyn_title = function(_, entry)
			if entry and entry.value then
				return string.format("标注预览 - %s", entry.value.note_file or "未知文件")
			end
			return "标注预览"
		end,

		define_preview = function(self, entry, status)
			if not entry or not entry.value then
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "预览数据无效" })
				return
			end

			local deps = load_deps()
			local lines = {}
			local value = entry.value
			local preview_format = deps.config.get('preview.format') or {}

			-- 添加标注内容（使用完整内容）
			table.insert(lines, "# " .. (preview_format.content_title or "📝 标注内容"))
			table.insert(lines, "")
			if value.full_content and value.full_content ~= "" then
				for content_line in value.full_content:gmatch("[^\r\n]+") do
					table.insert(lines, content_line)
				end
			else
				table.insert(lines, "*（无内容）*")
			end
			table.insert(lines, "")

			-- 添加笔记内容（使用完整笔记）
			table.insert(lines, "# " .. (preview_format.notes_title or "💡 笔记"))
			table.insert(lines, "")
			if value.full_note and value.full_note ~= "" then
				for note_line in value.full_note:gmatch("[^\r\n]+") do
					table.insert(lines, note_line)
				end
			else
				table.insert(lines, "*（无笔记）*")
			end

			-- 添加当前选中信息
			if value.line_info then
				table.insert(lines, "")
				table.insert(lines, "# " .. (preview_format.current_title or "🎯 当前选中"))
				table.insert(lines, "")
				table.insert(lines, value.line_info)
				if value.entry_type == "content" then
					table.insert(lines, "📄 内容: " .. (value.content or ""))
				else
					table.insert(lines, "📝 笔记: " .. (value.note or ""))
				end
			end

			-- 添加文件信息
			table.insert(lines, "")
			table.insert(lines, "# " .. (preview_format.meta_title or "📂 文件信息"))
			table.insert(lines, "")
			table.insert(lines, "源文件: " .. (value.file or "未知"))
			table.insert(lines, "笔记文件: " .. (value.note_file or "未知"))

			-- 使用标准 vim API 设置缓冲区内容
			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
			vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
		end
	})
end

---创建动态entry_maker函数，支持不同的搜索模式
---@param mode string 搜索模式，'content' 或 'note'
---@return function entry_maker函数
local function create_entry_maker(mode)
	return function(entry)
		-- 确保entry有效
		if not entry or not entry.entry_type then
			return nil
		end

		local display_text = ""
		local ordinal_text = ""

		if mode == 'content' then
			-- content模式只处理content条目
			if entry.entry_type ~= "content" then
				return nil -- 过滤掉非content条目
			end
			ordinal_text = entry.content or ""
			display_text = entry.content or ""
		else -- note模式
			-- note模式只处理note条目
			if entry.entry_type ~= "note" then
				return nil -- 过滤掉非note条目
			end
			ordinal_text = entry.note or ""
			display_text = entry.note or ""
		end

		-- 添加类型指示符（使用配置中的图标）
		local deps = load_deps()
		local icons = deps.config.get('theme.icons') or {}
		local type_icon = (mode == 'content') and (icons.content or "📄") or (icons.note or "📝")

		-- 安全地限制显示长度，避免在多字节字符中间截断
		display_text = deps.core.safe_truncate_utf8(display_text, 80, "...")

		return {
			value = entry,
			display = string.format("%s %s", type_icon, display_text),
			ordinal = ordinal_text,
		}
	end
end

---获取过滤后的结果
---@param annotations table 所有标注数据
---@param mode string 过滤模式
---@return table 过滤后的结果列表
local function get_filtered_results(annotations, mode)
	local filtered = {}
	for _, entry in ipairs(annotations or {}) do
		if mode == 'content' and entry.entry_type == "content" then
			table.insert(filtered, entry)
		elseif mode == 'note' and entry.entry_type == "note" then
			table.insert(filtered, entry)
		end
	end
	return filtered
end

---使用 Telescope 进行标注搜索
---@param options table 搜索选项
---  - scope: 搜索范围
---  - scope_display_name: 搜索范围显示名称
---  - annotations_result: LSP 返回的标注数据
function M.search_annotations(options)
	local deps = load_deps()

	-- 检查 telescope 是否可用
	local ok, telescope_modules = pcall(function()
		return {
			pickers = require('telescope.pickers'),
			finders = require('telescope.finders'),
			conf = require('telescope.config').values,
			actions = require('telescope.actions'),
			action_state = require('telescope.actions.state')
		}
	end)

	if not ok then
		deps.logger.error("Telescope 模块加载失败")
		return
	end

	local pickers = telescope_modules.pickers
	local finders = telescope_modules.finders
	local conf = telescope_modules.conf
	local actions = telescope_modules.actions
	local action_state = telescope_modules.action_state

	-- 输出调试信息
	deps.logger.debug_obj("服务器返回结果", options.annotations_result)

	if not options.annotations_result or not options.annotations_result.note_files or #options.annotations_result.note_files == 0 then
		deps.logger.info("未找到标注")
		-- 显示空的 telescope picker
		pickers.new({}, {
			prompt_title = string.format('🔍 查找%s批注 (无结果)', options.scope_display_name),
			finder = finders.new_table({
				results = {},
				entry_maker = function() return nil end,
			}),
			sorter = conf.generic_sorter({}),
		}):find()
		return
	end

	-- 输出第一个标注的信息
	deps.logger.debug_obj("第一个标注", options.annotations_result.note_files[1])

	-- 解析标注数据
	local annotations = deps.parser.parse_annotations_result(options.annotations_result)

	if #annotations == 0 then
		deps.logger.info("解析后无有效标注")
		return
	end

	-- 创建预览器
	local annotation_previewer = create_annotation_previewer()

	-- 搜索模式状态（'content' 或 'note'）
	local search_mode = 'content'

	-- 获取 telescope 配置
	local telescope_opts = deps.config.get_backend_opts('telescope') or {}
	local search_keys = deps.config.get('keymaps.search_keys') or {}

	-- 创建 Telescope 选择器
	local picker_opts = vim.tbl_deep_extend('force', {
		prompt_title = string.format('🔍 查找%s批注 - %s切换模式',
			options.scope_display_name,
			search_keys.toggle_mode or '<C-t>'),
		finder = finders.new_table({
			results = get_filtered_results(annotations, search_mode),
			entry_maker = create_entry_maker(search_mode),
		}),
		sorter = conf.generic_sorter({}),
		previewer = annotation_previewer,
		attach_mappings = function(prompt_bufnr, map)
			-- 切换搜索模式的函数
			local toggle_search_mode = function()
				-- 切换模式
				search_mode = search_mode == 'content' and 'note' or 'content'
				-- 获取当前picker
				local current_picker = action_state.get_current_picker(prompt_bufnr)
				if not current_picker then
					deps.logger.error("无法获取当前picker")
					return
				end

				-- 创建新的finder
				local new_results = get_filtered_results(annotations, search_mode)
				local new_finder = finders.new_table({
					results = new_results,
					entry_maker = create_entry_maker(search_mode),
				})

				-- 刷新picker，重置选择状态
				current_picker:refresh(new_finder, {})

				deps.logger.info(string.format("已切换到%s模式，共%d个结果",
					search_mode == 'content' and '内容' or '笔记', #new_results))
			end

			-- 定义打开标注的动作
			local open_annotation = function()
				local selection = action_state.get_selected_entry()
				if not selection or not selection.value then
					deps.logger.warn("未选中有效条目")
					return
				end

				actions.close(prompt_bufnr)

				-- 输出调试信息
				deps.logger.debug_obj("选中的标注", selection.value)

				-- 打开文件并跳转到标注位置
				local buf = vim.fn.bufadd(selection.value.file)
				if not vim.api.nvim_buf_is_valid(buf) then
					deps.logger.error("无法创建有效缓冲区")
					return
				end

				vim.api.nvim_set_option_value('buflisted', true, { buf = buf })
				vim.api.nvim_win_set_buf(0, buf)

				local cursor_pos = deps.core.convert_utf8_to_bytes(0, selection.value.position)
				if cursor_pos and cursor_pos[1] > 0 and cursor_pos[2] >= 0 then
					vim.api.nvim_win_set_cursor(0, cursor_pos)
				end

				-- 打开预览窗口
				deps.preview.goto_annotation_note({
					workspace_path = selection.value.workspace_path,
					note_file = selection.value.note_file
				})
			end

			-- 定义删除标注的动作
			local delete_annotation = function()
				local selection = action_state.get_selected_entry()
				if not selection or not selection.value then
					deps.logger.warn("未选中有效条目")
					return
				end

				deps.logger.debug_obj("尝试删除标注", selection.value)
				local file_path = selection.value.workspace_path ..
					'/.annotation/notes/' .. selection.value.note_file

				-- 使用新的delete_annotation API，传入位置信息和回调
				deps.lsp.delete_annotation({
					buffer = vim.fn.bufadd(file_path),
					rev = true,
					on_success = function(result)
						-- 删除成功后刷新列表
						vim.schedule(function()
							-- 重新获取标注数据
							local search_module = require('annotation-tool.search')
							local scope = options.scope

							-- 根据搜索范围获取标注数据
							if scope == search_module.SCOPE.CURRENT_FILE then
								vim.lsp.buf_request(0, 'workspace/executeCommand', {
									command = "listAnnotations",
									arguments = { {
										textDocument = vim.lsp.util.make_text_document_params()
									} }
								}, function(err, new_result)
									if err then
										deps.logger.error("刷新标注列表失败: " .. vim.inspect(err))
										return
									end

									-- 更新全局annotations变量
									annotations = deps.parser.parse_annotations_result(new_result)

									-- 刷新picker
									local current_picker = action_state.get_current_picker(prompt_bufnr)
									if current_picker then
										local new_finder = finders.new_table({
											results = get_filtered_results(annotations, search_mode),
											entry_maker = create_entry_maker(search_mode),
										})
										current_picker:refresh(new_finder, {})
										deps.logger.info("标注删除成功，列表已刷新")
									end
								end)
							end
						end)
					end,
					on_cancel = function()
						-- 取消删除，什么都不做，picker保持打开
						deps.logger.info("删除操作已取消")
					end
				})
			end

			-- 映射按键（使用配置中的快捷键）
			actions.select_default:replace(open_annotation)

			-- 获取配置中的快捷键
			local delete_key = search_keys.delete or '<C-d>'
			local toggle_key = search_keys.toggle_mode or '<C-t>'
			local exit_key = search_keys.exit or '<C-c>'

			-- 映射删除操作
			map("i", delete_key, delete_annotation)
			map("n", string.gsub(delete_key, '<C%-(.-)>', '%1'), delete_annotation)

			-- 映射切换模式
			map("i", toggle_key, toggle_search_mode)
			map("n", string.gsub(toggle_key, '<C%-(.-)>', '%1'), toggle_search_mode)

			-- 如果配置了特殊的退出键，映射它
			if exit_key ~= '<C-c>' and exit_key ~= '<Esc>' then
				map("i", exit_key, function()
					actions.close(prompt_bufnr)
				end)
				map("n", string.gsub(exit_key, '<C%-(.-)>', '%1'), function()
					actions.close(prompt_bufnr)
				end)
			end

			return true
		end,
	}, telescope_opts)

	pickers.new({}, picker_opts):find()
end

return M
