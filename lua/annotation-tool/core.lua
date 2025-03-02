local M = {}
local logger = require('annotation-tool.logger')

-- 检查是否为 markdown 文件
function M.is_markdown_file()
	return vim.bo.filetype == "markdown"
end

function M.get_current_position()
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= 'n' then
		logger.warn("Please get_current_position in normal mode")
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
		logger.warn("Please select text in visual mode or visual line mode first")
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
	logger.info(string.format(
		"Selection: start=[line=%d, col=%d] end=[line=%d, col=%d]",
		result.start.line, result.start.character, result['end'].line, result['end'].character
	))

	return result
end

function M.make_selection_params()
	local params = {
		textDocument = {
			uri = vim.uri_from_bufnr(0)
		},
		range = M.get_visual_selection()
	}
	return params
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
	logger.info("Annotation mode enabled")
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
	logger.info("Annotation mode disabled")
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

function M.convert_utf8_to_bytes(bufnr, pos_or_range)
	bufnr = bufnr or 0

	local function convert_position(line, character)
		local line_content = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
		return vim.str_byteindex(line_content, character)
	end

	if pos_or_range.start then
		-- 转换 range 类型
		local start_line = pos_or_range.start.line
		local end_line = pos_or_range['end'].line

		local start_byte = convert_position(start_line, pos_or_range.start.character + 1)
		local end_byte = convert_position(end_line, pos_or_range['end'].character)

		return {
			start = { line = start_line, character = start_byte },
			['end'] = { line = end_line, character = end_byte }
		}
	else
		-- 转换 single position 类型
		local line = pos_or_range.line
		local byte_index = convert_position(line, pos_or_range.character)
		return {line + 1, byte_index}
	end
end

return M
