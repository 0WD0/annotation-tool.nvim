local M = {}

-- 延迟加载依赖，避免循环依赖
local function load_deps()
	local lsp = require('annotation-tool.lsp')
	local core = require('annotation-tool.core')
	local preview = require('annotation-tool.preview')
	local logger = require('annotation-tool.logger')

	return {
		lsp = lsp,
		core = core,
		preview = preview,
		logger = logger
	}
end

---检查当前缓冲区是否已启用标注模式。
---@return boolean 若已启用标注模式则返回 true，否则返回 false。未启用时会记录警告日志。
local function check_annotation_mode()
	local deps = load_deps()
	if not vim.b.annotation_mode then
		deps.logger.warn("请先启用标注模式（:AnnotationEnable）")
		return false
	end
	return true
end

---向当前缓冲区的LSP客户端发送请求以获取注释列表，并在响应后调用回调函数。
---@param callback function 接收LSP响应结果的回调函数。
local function fetch_annotations(callback)
	vim.lsp.buf_request(0, 'workspace/executeCommand', {
		command = "listAnnotations",
		arguments = { {
			textDocument = vim.lsp.util.make_text_document_params()
		} }
	}, callback)
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

			local lines = {}
			local value = entry.value

			-- 添加标注内容（使用完整内容）
			table.insert(lines, "# 📝 标注内容")
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
			table.insert(lines, "# 💡 笔记")
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
				table.insert(lines, "# 🎯 当前选中")
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
			table.insert(lines, "# 📂 文件信息")
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

		-- 添加类型指示符
		local type_icon = (mode == 'content') and "📄" or "📝"

		-- 限制显示长度
		if #display_text > 80 then
			display_text = display_text:sub(1, 77) .. "..."
		end

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

---在当前文件中查找、预览、打开和删除所有批注内容与笔记，并通过 Telescope 交互式界面展示。
---
---该函数会：
---1. 检查当前缓冲区是否启用批注模式；
---2. 通过 LSP 请求获取当前文件的所有批注数据，并解析为内容行和笔记行两类条目；
---3. 使用 Telescope 创建可切换"内容/笔记"搜索模式的选择器，支持预览完整批注内容与笔记；
---4. 支持通过快捷键打开批注位置、预览批注详情、删除批注（删除后自动刷新列表）。
---
---如未启用批注模式或 LSP 客户端未连接，则不会执行任何操作。
function M.find_atn_lc()
	if not check_annotation_mode() then return end

	local deps = load_deps()
	local client = deps.lsp.get_client()
	if not client then
		deps.logger.error("LSP 客户端未连接")
		return
	end

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

	---解析 LSP 返回的标注数据，提取并拆分为内容和笔记的条目列表。
	---@param result table LSP 返回的标注结果，包含 note_files 和 workspace_path 字段。
	---@return table 标注条目列表，每个条目包含内容或笔记的单行文本、完整内容、文件信息及元数据。
	---@desc
	---遍历所有标注 note 文件，读取并解析其内容，将"Selected Text"与"Notes"部分分别按行拆分为独立条目。
	---每个条目包含所属文件、位置、范围、原始 note 文件路径、工作区路径、行号、条目类型（内容或笔记）等元数据。
	---仅当内容或笔记存在有效非空行时才生成对应条目。
	local function parse_annotations_result(result)
		local annotations = {}

		if not result or not result.note_files or #result.note_files == 0 then
			return annotations
		end

		local workspace_path = result.workspace_path
		local current_file = vim.fn.expand('%:p')

		---将原始标注内容和笔记分割为按行的条目，并生成包含元数据的内容和笔记条目列表。
		---@param og_content string 原始标注内容。
		---@param og_note string 原始笔记内容。
		---@param base_info table 包含文件、位置、范围、笔记文件路径等元数据的信息表。
		---@return table content_entries 按行拆分的内容条目列表，每个条目包含元数据。
		---@return table note_entries 按行拆分的笔记条目列表，每个条目包含元数据。
		local function create_annotation_entries(og_content, og_note, base_info)
			local content_entries = {}
			local note_entries = {}

			-- 处理内容行 - 只有有内容时才创建content条目
			if og_content and og_content ~= "" then
				local content_lines = {}
				for line in og_content:gmatch("[^\r\n]+") do
					local trimmed = line:gsub("^%s*(.-)%s*$", "%1")
					if trimmed ~= "" then -- 跳过空行
						table.insert(content_lines, trimmed)
					end
				end

				-- 只有当有有效内容行时才创建条目
				if #content_lines > 0 then
					for i, line in ipairs(content_lines) do
						table.insert(content_entries, {
							file = base_info.file,
							content = line, -- 单行内容
							full_content = og_content, -- 完整内容用于预览
							full_note = og_note, -- 完整笔记用于预览
							position = base_info.position,
							range = base_info.range,
							note_file = base_info.note_file,
							workspace_path = base_info.workspace_path,
							line_info = string.format("内容第%d行", i),
							is_content_line = true,
							line_number = i,
							entry_type = "content"
						})
					end
				end
			end

			-- 处理笔记行 - 只有有笔记时才创建note条目
			if og_note and og_note ~= "" then
				local note_lines = {}
				for line in og_note:gmatch("[^\r\n]+") do
					local trimmed = line:gsub("^%s*(.-)%s*$", "%1")
					if trimmed ~= "" then -- 跳过空行
						table.insert(note_lines, trimmed)
					end
				end

				-- 只有当有有效笔记行时才创建条目
				if #note_lines > 0 then
					for i, line in ipairs(note_lines) do
						table.insert(note_entries, {
							file = base_info.file,
							note = line, -- 单行笔记
							full_content = og_content, -- 完整内容用于预览
							full_note = og_note, -- 完整笔记用于预览
							position = base_info.position,
							range = base_info.range,
							note_file = base_info.note_file,
							workspace_path = base_info.workspace_path,
							line_info = string.format("笔记第%d行", i),
							is_note_line = true,
							line_number = i,
							entry_type = "note"
						})
					end
				end
			end

			return content_entries, note_entries
		end

		for _, note_file_info in ipairs(result.note_files) do
			local note_file = note_file_info.note_file

			-- 获取标注内容
			local file_path = workspace_path .. "/.annotation/notes/" .. note_file

			-- 使用 pcall 进行错误处理
			local ok, file_content = pcall(vim.fn.readfile, file_path)
			if not ok then
				deps.logger.warn("无法读取文件: " .. file_path)
				goto continue
			end

			-- 输出调试信息
			deps.logger.debug("尝试读取文件: " .. file_path)
			deps.logger.debug_obj("文件内容", file_content)

			-- 提取标注内容和笔记
			local content = ""
			local note = ""
			local in_notes_section = false
			local in_selected_text_section = false
			local in_code_block = false
			local in_frontmatter = false
			local position = { line = 0, character = 0 }
			local range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }

			for _, line in ipairs(file_content) do
				-- 处理 frontmatter
				if line:match("^%-%-%-") then
					in_frontmatter = not in_frontmatter
				elseif in_frontmatter then
					-- 跳过 frontmatter 内容
					goto inner_continue
				elseif line:match("^## Selected Text") then
					in_selected_text_section = true
					in_notes_section = false
				elseif line:match("^## Notes") then
					in_notes_section = true
					in_selected_text_section = false
					in_code_block = false
				elseif in_selected_text_section then
					-- 在 Selected Text 部分
					if line:match("^```") then
						in_code_block = not in_code_block
					elseif in_code_block then
						-- 提取代码块内的内容，保持原始格式
						if content ~= "" then
							content = content .. "\n"
						end
						content = content .. line
					end
				elseif in_notes_section then
					-- 在 Notes 部分
					if note ~= "" then
						note = note .. "\n"
					end
					note = note .. line
				end
				::inner_continue::
			end

			-- 使用新的拆分逻辑
			local base_info = {
				file = current_file,
				position = position,
				range = range,
				note_file = note_file,
				workspace_path = workspace_path
			}

			local content_entries, note_entries = create_annotation_entries(content, note, base_info)

			-- 将content和note条目都添加到annotations中，但标记类型
			for _, entry in ipairs(content_entries) do
				table.insert(annotations, entry)
			end
			for _, entry in ipairs(note_entries) do
				table.insert(annotations, entry)
			end

			::continue::
		end

		return annotations
	end

	fetch_annotations(function(err, result)
		if err then
			deps.logger.error("获取标注列表失败: " .. vim.inspect(err))
			return
		end

		-- 输出调试信息
		deps.logger.debug_obj("服务器返回结果", result)

		if not result or not result.note_files or #result.note_files == 0 then
			deps.logger.info("未找到标注")
			-- 显示空的 telescope picker
			pickers.new({}, {
				prompt_title = '🔍 查找标注 (无结果)',
				finder = finders.new_table({
					results = {},
					entry_maker = function() return nil end,
				}),
				sorter = conf.generic_sorter({}),
			}):find()
			return
		end

		-- 输出第一个标注的信息
		deps.logger.debug_obj("第一个标注", result.note_files[1])

		-- 解析标注数据
		local annotations = parse_annotations_result(result)

		if #annotations == 0 then
			deps.logger.info("解析后无有效标注")
			return
		end

		-- 创建预览器
		local annotation_previewer = create_annotation_previewer()

		-- 搜索模式状态（'content' 或 'note'）
		local search_mode = 'content'

		-- 创建 Telescope 选择器
		pickers.new({}, {
			prompt_title = "🔍 查找当前文件批注 - <C-t>切换模式",
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
								fetch_annotations(function(err, result)
									if err then
										deps.logger.error("刷新标注列表失败: " .. vim.inspect(err))
										return
									end

									-- 更新全局annotations变量
									annotations = parse_annotations_result(result)

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
							end)
						end,
						on_cancel = function()
							-- 取消删除，什么都不做，picker保持打开
							deps.logger.info("删除操作已取消")
						end
					})
				end

				-- 映射按键
				actions.select_default:replace(open_annotation)
				map("i", "<C-d>", delete_annotation)
				map("n", "d", delete_annotation)
				map("i", "<C-o>", open_annotation)
				map("n", "o", open_annotation)
				map("i", "<C-t>", toggle_search_mode)
				map("n", "t", toggle_search_mode)

				return true
			end,
		}):find()
	end)
end

return M
