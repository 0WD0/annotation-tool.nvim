local M = {}

-- 检查是否为 markdown 文件
function M.is_markdown_file()
	return vim.bo.filetype == "markdown"
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

	-- 调试输出
	-- vim.notify(string.format(
	-- 	"Selection: start=[bufnum=%d, line=%d, col=%d, off=%d] end=[bufnum=%d, line=%d, col=%d, off=%d]",
	-- 	start_pos[1], start_pos[2], start_pos[3], start_pos[4],
	-- 	end_pos[1], end_pos[2], end_pos[3], end_pos[4]
	-- ), vim.log.levels.INFO)

	-- 确保 start_pos 在 end_pos 之前
	if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
		start_pos, end_pos = end_pos, start_pos
	end

	-- 转换为 LSP 位置格式
	return {
		start = {
			line = start_pos[2] - 1,
			character = start_pos[3] - 1
		},
		['end'] = {
			line = end_pos[2] - 1,
			character = end_pos[3] - 1
		}
	}
end

-- 切换标注模式
function M.toggle_mode(bufnr)
	local enabled = vim.b[bufnr].annotation_mode

	if enabled then
		-- 禁用标注模式
		vim.b[bufnr].annotation_mode = false
		vim.wo.conceallevel = 0
		vim.cmd([[syntax clear AnnotationBracket]])
		vim.notify("Annotation mode disabled", vim.log.levels.INFO)
	else
		-- 启用标注模式
		vim.b[bufnr].annotation_mode = true
		vim.wo.conceallevel = 2
		vim.cmd([[syntax match AnnotationBracket "｢\|｣" conceal]])
		vim.notify("Annotation mode enabled", vim.log.levels.INFO)
	end
end

return M
