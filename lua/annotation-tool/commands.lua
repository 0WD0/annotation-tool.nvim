local M = {}
local core = require('annotation-tool.core')
local lsp = require('annotation-tool.lsp')

-- 创建用户命令
function M.setup()
	vim.api.nvim_create_user_command('AnnotationLspAttach', function()
		lsp.attach()
	end, {})
	
	vim.api.nvim_create_user_command('AnnotationModeEnable', function()
		local bufnr = vim.api.nvim_get_current_buf()
		if not vim.tbl_contains({ "markdown", "text", "annot" }, vim.bo[bufnr].filetype) then
			vim.notify("Annotation mode only supports markdown, text and annot files", vim.log.levels.WARN)
			return
		end
		
		vim.b[bufnr].annotation_mode = true
		vim.cmd([[
			highlight default link AnnotationMarker Comment
			highlight default link AnnotationText String
		]])
		
		-- 设置自动命令组
		local augroup = vim.api.nvim_create_augroup("AnnotationMode_" .. bufnr, { clear = true })
		
		-- 当光标移动时更新预览窗口
		vim.api.nvim_create_autocmd("CursorMoved", {
			group = augroup,
			buffer = bufnr,
			callback = function()
				require('annotation-tool.preview').update()
			end,
		})
		
		vim.notify("Annotation mode enabled", vim.log.levels.INFO)
	end, {})
	
	vim.api.nvim_create_user_command('AnnotationModeDisable', function()
		local bufnr = vim.api.nvim_get_current_buf()
		vim.b[bufnr].annotation_mode = false
		vim.wo.conceallevel = 0
		vim.cmd([[syntax clear AnnotationBracket]])
		vim.notify("Annotation mode disabled", vim.log.levels.INFO)
	end, {})
	
	vim.api.nvim_create_user_command('AnnotationModeToggle', function()
		local bufnr = vim.api.nvim_get_current_buf()
		core.toggle_mode(bufnr)
	end, {})
end

return M
