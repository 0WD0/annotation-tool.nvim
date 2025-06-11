local M = {}

local logger = require('annotation-tool.logger')

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

---解析 LSP 返回的标注数据，提取并拆分为内容和笔记的条目列表。
---@param result table LSP 返回的标注结果，包含 note_files 和 workspace_path 字段。
---@return table 标注条目列表，每个条目包含内容或笔记的单行文本、完整内容、文件信息及元数据。
function M.parse_annotations_result(result)
	local annotations = {}

	if not result or #result == 0 then
		logger.warn("没有找到任何标注结果")
		return annotations
	end

	for _, item in ipairs(result) do
		local workspace_path = item.workspace_path
		for _, note_file_info in ipairs(item.note_files) do
			local note_file = note_file_info.note_file

			-- 获取标注内容
			local file_path = workspace_path .. "/.annotation/notes/" .. note_file

			-- 使用 pcall 进行错误处理
			local ok, file_content = pcall(vim.fn.readfile, file_path)
			if not ok then
				logger.warn("无法读取文件: " .. file_path)
				goto continue
			end

			-- 输出调试信息
			logger.debug("尝试读取文件: " .. file_path)
			logger.debug_obj("文件内容", file_content)

			-- 提取标注内容和笔记
			local content = ""
			local note = ""
			local source_file = vim.fn.expand('%:p') -- 默认使用当前文件
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
					-- 解析 frontmatter 中的 file 字段
					local key, value = line:match('^([^:]+):%s*(.*)$')
					if key and value then
						key = vim.trim(key)
						value = vim.trim(value)
						if key == 'file' then
							source_file = value
						end
					end
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
			end

			-- 使用新的拆分逻辑
			local base_info = {
				file = source_file,
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
	end

	return annotations
end

return M
