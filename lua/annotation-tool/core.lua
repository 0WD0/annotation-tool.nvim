local M = {}

-- 检查是否为 markdown 文件
function M.is_markdown_file()
	return vim.bo.filetype == "markdown"
end

function M.get_current_position()
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= 'n' then
		vim.notify("Please get_current_position in normal mode", vim.log.levels.WARN)
		return nil
	end
	local pos = vim.fn.getcharpos('.')

	local result = {
		line = pos[2]-1,
		character = pos[3]-1
	}
	return result
end

function M.make_position_params()
	local params = {
		textDocument = {
			uri = vim.uri_from_bufnr(0)
		},
		position = M.get_current_position()
	}
	return params
end

-- 获取选中区域
function M.get_visual_selection()
	-- 获取当前选区
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= 'v' and mode ~= 'V' then
		vim.notify("Please select text in visual mode or visual line mode first", vim.log.levels.WARN)
		return nil
	end

	local start_pos = vim.fn.getcharpos('v')
	local end_pos = vim.fn.getcharpos('.')

	if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
		start_pos, end_pos = end_pos, start_pos
	end

	if mode == 'V' then
		start_pos[3]= 1
		end_pos[3]= vim.fn.virtcol({end_pos[2],'$'})-1
	end

	-- 转换为 LSP 位置格式
	local result = {
		start = {
			line = start_pos[2]-1,
			character = start_pos[3]-1
		},
		['end'] = {
			line = end_pos[2]-1,
			character = end_pos[3]
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

-- 将 UTF-8 位置转换为字节位置
function M.convert_range_to_bytes(bufnr, range)
	bufnr = bufnr or 0
	local lines = vim.api.nvim_buf_get_lines(bufnr, range.start.line, range['end'].line + 1, false)

	-- 转换开始位置
	local start_byte = vim.str_byteindex(lines[1], range.start.character + 1)

	-- 转换结束位置
	local end_byte
	if range.start.line == range['end'].line then
		end_byte = vim.str_byteindex(lines[1], range['end'].character)
	else
		end_byte = vim.str_byteindex(lines[#lines], range['end'].character)
	end

	return {
		start = { line = range.start.line, character = start_byte },
		['end'] = { line = range['end'].line, character = end_byte }
	}
end

return M
