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

-- 获取当前工作区的所有标注
function M.find_annotations()
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

	-- 从 LSP 服务器获取所有标注
	vim.lsp.buf_request(0, 'workspace/executeCommand', {
		command = "listAnnotations",
		arguments = { {
			textDocument = vim.lsp.util.make_text_document_params()
		} }
	}, function(err, result)
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

			-- 从每个标注文件中提取信息
			local annotations = {}
			local workspace_path = result.workspace_path
			local current_file = vim.fn.expand('%:p')

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
				local position = { line = 0, character = 0 }
				local range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }

				-- 尝试从文件名中提取行号和列号
				-- local line_num, char_num = note_file:match("L(%d+)C(%d+)")
				-- if line_num and char_num then
				-- 	position.line = tonumber(line_num) - 1
				-- 	position.character = tonumber(char_num) - 1
				-- 	range.start = { line = position.line, character = position.character }
				-- 	range["end"] = { line = position.line, character = position.character + 1 }
				-- end

				for _, line in ipairs(file_content) do
					if line:match("^## Content") then
						in_notes_section = false
					elseif line:match("^## Notes") then
						in_notes_section = true
					elseif in_notes_section then
						if note ~= "" then
							note = note .. "\n"
						end
						note = note .. line
					elseif not in_notes_section and not line:match("^#") then
						if content ~= "" then
							content = content .. " "
						end
						content = content .. line:gsub("^%s*(.-)%s*$", "%1")
					end
				end

				table.insert(annotations, {
					file = current_file,
					content = content,
					note = note,
					position = position,
					range = range,
					note_file = note_file,
					workspace_path = workspace_path
				})
			end

			-- 创建预览器
			local annotation_previewer = previewers.new_buffer_previewer({
				title = "标注预览",
				define_preview = function(self, entry, status)
					local lines = {}

					-- 添加标注内容
					table.insert(lines, "# 标注内容")
					table.insert(lines, "")
					table.insert(lines, entry.value.content)
					table.insert(lines, "")

					-- 添加笔记内容
					table.insert(lines, "# 笔记")
					table.insert(lines, "")
					if entry.value.note and entry.value.note ~= "" then
						for note_line in entry.value.note:gmatch("[^\r\n]+") do
							table.insert(lines, note_line)
						end
					else
						table.insert(lines, "（无笔记）")
					end

					-- 添加文件信息
					table.insert(lines, "")
					table.insert(lines, "# 文件信息")
					table.insert(lines, "")
					table.insert(lines, "文件: " .. entry.value.file)
					-- table.insert(lines, string.format("位置: 第 %d 行, 第 %d 列",
					-- 	entry.value.position.line + 1,
					-- 	entry.value.position.character + 1))

					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
					vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
				end
			})

			-- 创建 Telescope 选择器
			pickers.new({}, {
				prompt_title = '查找标注',
				finder = finders.new_table({
					results = annotations,
					entry_maker = function(entry)
						local display_text = entry.content
						if #display_text > 50 then
							display_text = display_text:sub(1, 47) .. "..."
						end

						local filename = vim.fn.fnamemodify(entry.file, ":t")

						return {
							value = entry,
							display = string.format("%s: %s", filename, display_text),
							ordinal = string.format("%s %s %s",
								entry.file,
								entry.content,
								entry.note or ""),
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				previewer = annotation_previewer,
				attach_mappings = function(prompt_bufnr, map)
					-- 定义打开标注的动作
					local open_annotation = function()
						actions.close(prompt_bufnr)
						local selection = action_state.get_selected_entry()

						-- 输出调试信息
						deps.logger.debug_obj("选中的标注", selection.value)

						-- 打开文件并跳转到标注位置
						vim.cmd('edit ' .. selection.value.file)
						local deps = load_deps()
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

						-- 确认删除
						vim.ui.select(
							{"是", "否"},
							{prompt = "确定要删除这个标注吗？"},
							function(choice)
								if choice == "是" then
									actions.close(prompt_bufnr)

									-- 打开文件并跳转到标注位置
									vim.cmd('edit ' .. selection.value.file)
									local deps = load_deps()
									local cursor_pos = deps.core.convert_utf8_to_bytes(0, selection.value.position)
									vim.api.nvim_win_set_cursor(0, cursor_pos)

									-- 删除标注
									deps.lsp.delete_annotation()
								end
							end
						)
					end

					-- 映射按键
					actions.select_default:replace(open_annotation)
					map("i", "<C-d>", delete_annotation)
					map("n", "d", delete_annotation)
					map("i", "<C-o>", open_annotation)
					map("n", "o", open_annotation)

					return true
				end,
			}):find()
		end)
end

-- 搜索标注内容
function M.search_annotations()
	if not check_annotation_mode() then return end

	local deps = load_deps()
	local client = deps.lsp.get_client()
	if not client then
		deps.logger.error("LSP 客户端未连接")
		return
	end

	-- 弹出输入框让用户输入搜索关键词
	vim.ui.input(
		{prompt = "输入搜索关键词: "},
		function(query)
			if not query or query == "" then
				return
			end

			-- 实现搜索功能
			deps.logger.info("正在搜索: " .. query)

			-- TODO:
			-- 这里可以实现搜索逻辑，类似于 server.py 中的 queryAnnotations 函数
			-- 由于当前 LSP 服务器没有实现 queryAnnotations 命令，这里使用 listAnnotations 然后在客户端过滤

			M.find_annotations()  -- 临时使用 find_annotations 代替
		end
	)
end

return M
