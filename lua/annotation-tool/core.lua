local M = {}

-- 检查是否为 markdown 文件
function M.is_markdown_file()
	return vim.bo.filetype == "markdown"
end

-- 获取选中区域
function M.get_visual_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	
	if start_pos[2] == 0 or end_pos[2] == 0 then
		vim.notify("No text selected", vim.log.levels.ERROR)
		return nil
	end
	
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
