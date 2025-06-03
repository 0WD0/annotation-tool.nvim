local M = {}

-- 延迟加载依赖，避免循环依赖
local function load_deps()
	local core = require('annotation-tool.core')
	local preview = require('annotation-tool.preview')
	local logger = require('annotation-tool.logger')
	local lsp = require('annotation-tool.lsp')
	local config = require('annotation-tool.config')

	return {
		core = core,
		preview = preview,
		logger = logger,
		lsp = lsp,
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

---安全地截断 UTF-8 字符串，避免在多字节字符中间截断
---@param str string 要截断的字符串
---@param max_chars number 最大字符数（不是字节数）
---@param suffix string 截断后的后缀，默认为 "..."
---@return string 截断后的字符串
local function safe_truncate_utf8(str, max_chars, suffix)
	suffix = suffix or "..."

	-- 使用 vim.fn.strchars 计算实际字符数（支持多字节字符）
	local char_count = vim.fn.strchars(str)

	if char_count <= max_chars then
		return str
	end

	-- 使用 vim.fn.strcharpart 安全地截断字符串
	-- 这个函数会确保不在多字节字符中间截断
	local truncated = vim.fn.strcharpart(str, 0, max_chars - vim.fn.strchars(suffix))
	return truncated .. suffix
end

---解析 LSP 返回的标注数据，提取并拆分为内容和笔记的条目列表。
---@param result table LSP 返回的标注结果，包含 note_files 和 workspace_path 字段。
---@return table 标注条目列表，每个条目包含内容或笔记的单行文本、完整内容、文件信息及元数据。
local function parse_annotations_result(result)
	local deps = load_deps()
	local annotations = {}

	if not result or not result.note_files or #result.note_files == 0 then
		return annotations
	end

	local workspace_path = result.workspace_path
	local current_file = vim.fn.expand('%:p')

	---将原始标注内容和笔记分割为按行的条目，并生成包含元数据的内容和笔记条目列表。
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
	display_text = safe_truncate_utf8(display_text, 80, "...")

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
---  - scope_display_name: 搜索范围显示名称
---  - annotations_result: LSP 返回的标注数据
function M.search_annotations(options)
	local deps = load_deps()

	-- 检查 fzf-lua 是否可用
	local ok, fzf_lua = check_fzf_lua()
	if not ok then
		deps.logger.error(fzf_lua)
		return
	end

	-- 输出调试信息
	deps.logger.debug_obj("服务器返回结果", options.annotations_result)

	if not options.annotations_result or not options.annotations_result.note_files or #options.annotations_result.note_files == 0 then
		deps.logger.info("未找到标注")
		-- 显示空的 fzf picker
		fzf_lua.fzf_exec({}, {
			prompt = string.format('🔍 查找%s批注 (无结果) > ', options.scope_display_name),
		})
		return
	end

	-- 输出第一个标注的信息
	deps.logger.debug_obj("第一个标注", options.annotations_result.note_files[1])

	-- 解析标注数据
	local annotations = parse_annotations_result(options.annotations_result)

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
					-- 重新获取标注数据
					local scope = options.scope

					-- 根据搜索范围获取标注数据
					if scope == 'current_file' then
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
							annotations = parse_annotations_result(new_result)
							deps.logger.info("标注删除成功，列表已刷新")

							-- 重新启动搜索
							M.search_annotations(vim.tbl_extend("force", options, {
								annotations_result = new_result
							}))
						end)
					end
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
	local fzf_opts = deps.config.get_backend_opts('fzf_lua')
	local search_keys = deps.config.get('keymaps.search_keys') or {}

	-- 构建动作映射（使用配置中的快捷键）
	local actions_map = {}
	actions_map['default'] = open_annotation

	-- 使用配置中的快捷键
	local open_alt_key = search_keys.open_alt or 'ctrl-o'
	local delete_key = search_keys.delete or 'ctrl-d'
	local toggle_key = search_keys.toggle_mode or 'ctrl-t'
	local exit_key = search_keys.exit or 'ctrl-c'

	-- 映射快捷键（转换为 fzf-lua 格式）
	local function normalize_key(key)
		return key:gsub('<C%-(.-)>', 'ctrl-%1'):gsub('<(.-)>', '%1')
	end

	actions_map[normalize_key(open_alt_key)] = open_annotation
	actions_map[normalize_key(delete_key)] = delete_annotation
	actions_map[normalize_key(toggle_key)] = toggle_search_mode

	-- 构建 fzf-lua picker 选项
	local mode_display = search_mode == 'content' and '内容' or '笔记'
	local picker_opts = vim.tbl_deep_extend('force', {
		prompt = string.format('🔍 查找%s批注[%s] - %s切换模式 > ',
			options.scope_display_name,
			mode_display,
			search_keys.toggle_mode or '<C-t>'),
		-- 保存条目映射
		_entry_map = entry_map,
		actions = actions_map,
		-- 使用 fzf 原生预览
		preview = {
			type = 'cmd',
			fn = function(items)
				-- 在预览函数中，使用全局条目映射获取数据
				if not items or #items == 0 or not items[1] then
					return { "无可预览的项目" }
				end
				
				local entry = global_entry_map[items[1]]
				if entry then
					return create_preview_lines(entry)
				end
				return { "预览数据无效: " .. tostring(items[1]) }
			end
		},
	}, fzf_opts)

	-- 创建 fzf-lua picker
	fzf_lua.fzf_exec(formatted_entries, picker_opts)
end

return M
