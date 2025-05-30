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

-- 检查标注模式是否启用
local function check_annotation_mode()
	local deps = load_deps()
	if not vim.b.annotation_mode then
		deps.logger.warn("请先启用标注模式（:AnnotationEnable）")
		return false
	end
	return true
end

-- 简单的LSP请求函数
local function fetch_annotations(callback)
	vim.lsp.buf_request(0, 'workspace/executeCommand', {
		command = "listAnnotations",
		arguments = { {
			textDocument = vim.lsp.util.make_text_document_params()
		} }
	}, callback)
end

-- 在当前文件的所有被批注文本中查找
function M.find_atn_lc()
	if not check_annotation_mode() then return end

	local deps = load_deps()
	local client = deps.lsp.get_client()
	if not client then
		deps.logger.error("LSP 客户端未连接")
		return
	end

	local pickers = require('telescope.pickers')
	local finders = require('telescope.finders')
	local conf = require('telescope.config').values
	local actions = require('telescope.actions')
	local action_state = require('telescope.actions.state')
	local previewers = require('telescope.previewers')

	-- 解析标注数据的函数
	local function parse_annotations_result(result)
		local annotations = {}

		if not result or not result.note_files or #result.note_files == 0 then
			return annotations
		end

		local workspace_path = result.workspace_path
		local current_file = vim.fn.expand('%:p')

		-- 创建标注条目的辅助函数
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
			local file_content = vim.fn.readfile(file_path)

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
					goto continue
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
				::continue::
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
			return
		end

		-- 输出第一个标注的信息
		deps.logger.debug_obj("第一个标注", result.note_files[1])

		-- 解析标注数据
		local annotations = parse_annotations_result(result)

		-- 创建预览器
		local annotation_previewer = previewers.new_buffer_previewer({
			title = "标注预览",
			define_preview = function(self, entry, status)
				local lines = {}

				-- 添加标注内容（使用完整内容）
				table.insert(lines, "# 标注内容")
				table.insert(lines, "")
				local full_content = entry.value.full_content
				if full_content and full_content ~= "" then
					for content_line in full_content:gmatch("[^\r\n]+") do
						table.insert(lines, content_line)
					end
				else
					table.insert(lines, "（无内容）")
				end
				table.insert(lines, "")

				-- 添加笔记内容（使用完整笔记）
				table.insert(lines, "# 笔记")
				table.insert(lines, "")
				local full_note = entry.value.full_note
				if full_note and full_note ~= "" then
					for note_line in full_note:gmatch("[^\r\n]+") do
						table.insert(lines, note_line)
					end
				else
					table.insert(lines, "（无笔记）")
				end

				-- 添加当前选中信息
				if entry.value.line_info then
					table.insert(lines, "")
					table.insert(lines, "# 当前选中")
					table.insert(lines, "")
					table.insert(lines, entry.value.line_info)
					if entry.value.entry_type == "content" then
						table.insert(lines, "内容: " .. (entry.value.content or ""))
					else
						table.insert(lines, "笔记: " .. (entry.value.note or ""))
					end
				end

				-- 添加文件信息
				table.insert(lines, "")
				table.insert(lines, "# 文件信息")
				table.insert(lines, "")
				table.insert(lines, "文件: " .. entry.value.file)

				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
				vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
			end
		})

		-- 搜索模式状态（'content' 或 'note'）
		local search_mode = 'content'

		-- 创建动态entry_maker函数
		local function create_entry_maker(mode)
			return function(entry)
				-- 确保display_text是单行的
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

				-- 添加行号信息到显示文本
				-- if entry.line_info then
				-- 	display_text = string.format("[%s] %s", entry.line_info, display_text)
				-- end

				-- 限制显示长度
				if #display_text > 80 then
					display_text = display_text:sub(1, 77) .. "..."
				end

				return {
					value = entry,
					display = display_text,
					ordinal = ordinal_text,
				}
			end
		end

		-- 创建过滤后的结果函数
		local function get_filtered_results(mode)
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

		-- 创建动态标题函数
		local function create_title(mode)
			if mode == 'content' then
				return '查找标注 (搜索内容) - <C-t>切换'
			else
				return '查找标注 (搜索笔记) - <C-t>切换'
			end
		end

		-- 创建 Telescope 选择器
		pickers.new({}, {
			prompt_title = create_title(search_mode),
			finder = finders.new_table({
				results = get_filtered_results(search_mode),
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
					-- 更新标题和finder
					current_picker.prompt_title = create_title(search_mode)
					-- 创建新的finder
					local new_finder = finders.new_table({
						results = get_filtered_results(search_mode),
						entry_maker = create_entry_maker(search_mode),
					})
					-- 刷新picker，重置选择状态
					current_picker:refresh(new_finder, {})
				end

				-- 定义打开标注的动作
				local open_annotation = function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()

					-- 输出调试信息
					deps.logger.debug_obj("选中的标注", selection.value)

					-- 打开文件并跳转到标注位置
					local buf = vim.fn.bufadd(selection.value.file)
					vim.api.nvim_set_option_value('buflisted', true, { buf = buf })
					vim.api.nvim_win_set_buf(0, buf)
					local cursor_pos = deps.core.convert_utf8_to_bytes(0, selection.value.position)
					vim.api.nvim_win_set_cursor(0, cursor_pos)

					-- 打开预览窗口
					deps.preview.goto_annotation_note({
						workspace_path = selection.value.workspace_path,
						note_file = selection.value.note_file
					})
				end

				-- 定义删除标注的动作
				local delete_annotation = function()
					local selection = action_state.get_selected_entry()

					deps.logger.debug_obj("尝试删除标注", selection.value)
					local file_path = selection.value.workspace_path .. '/.annotation/notes/' .. selection.value.note_file
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
											results = get_filtered_results(search_mode),
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
