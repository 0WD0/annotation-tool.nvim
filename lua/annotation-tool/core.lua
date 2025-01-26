local M = {}

-- 检查是否为 markdown 文件
function M.is_markdown_file()
	return vim.bo.filetype == "markdown"
end

-- 将字节位置转换为 UTF-8 字符位置
local function byte_to_char(line, byte_idx)
	if byte_idx <= 1 then
		return 0
	end
	-- 截取到字节位置的子串
	local sub = line:sub(1, byte_idx - 1)
	-- 计算 UTF-8 字符数
	local pos = 1
	local chars = 0
	while pos <= #sub do
		local byte = string.byte(sub, pos)
		if byte < 0x80 then
			pos = pos + 1
		elseif byte >= 0xF0 then
			pos = pos + 4
		elseif byte >= 0xE0 then
			pos = pos + 3
		elseif byte >= 0xC0 then
			pos = pos + 2
		else
			pos = pos + 1
		end
		chars = chars + 1
	end
	return chars
end

-- 获取选中区域
function M.get_visual_selection()
	-- 获取当前选区
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= 'v' and mode ~= 'V' and mode ~= '' then
		vim.notify("Please select text in visual mode first", vim.log.levels.WARN)
		return nil
	end

	local start_pos = vim.fn.getpos('v')
	local end_pos = vim.fn.getpos('.')


	-- 确保 start_pos 在 end_pos 之前
	if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
		start_pos, end_pos = end_pos, start_pos
	end

	-- 获取行内容
	local start_line = vim.fn.getline(start_pos[2])
	local end_line = vim.fn.getline(end_pos[2])

	-- 转换为 LSP 位置格式
	local result = {
		start = {
			line = start_pos[2] - 1,
			character = mode == 'V' and 0 or byte_to_char(start_line, start_pos[3])
		},
		['end'] = {
			line = end_pos[2] - 1,
			character = mode == 'V' and byte_to_char(end_line, #end_line + 1) or byte_to_char(end_line, end_pos[3] + 1)
		}
	}

	-- 调试输出
	vim.notify(string.format(
		"Selection: start=[line=%d, col=%d] end=[line=%d, col=%d]",
		result.start.line, result.start.character, result['end'].line, result['end'].character
	), vim.log.levels.INFO)

	return result
end

-- 启用标注模式
function M.enable_annotation_mode(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- 如果已经启用，直接返回
	if vim.b[bufnr].annotation_mode then
		return
	end

	vim.b[bufnr].annotation_mode = true
	vim.wo.conceallevel = 2
	vim.cmd([[
		syn conceal on
		syn match AnnotationBracket "｢\|｣"
		syn conceal off
	]])
	vim.notify("Annotation mode enabled", vim.log.levels.INFO)
end

-- 禁用标注模式
function M.disable_annotation_mode(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- 如果已经禁用，直接返回
	if not vim.b[bufnr].annotation_mode then
		return
	end

	vim.b[bufnr].annotation_mode = false
	vim.wo.conceallevel = 0
	vim.cmd([[syntax clear AnnotationBracket]])
	vim.notify("Annotation mode disabled", vim.log.levels.INFO)
end

-- 切换标注模式
function M.toggle_annotation_mode(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if vim.b[bufnr].annotation_mode then
		M.disable_annotation_mode(bufnr)
	else
		M.enable_annotation_mode(bufnr)
	end
end

-- 查看当前 buffer 的 conceal 规则
function M.show_conceal_rules()
	local bufnr = vim.api.nvim_get_current_buf()
	vim.cmd('syn list AnnotationBracket')
end

return M
