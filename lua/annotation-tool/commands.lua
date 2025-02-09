local M = {}

local core = require('annotation-tool.core')
local lsp = require('annotation-tool.lsp')

-- 设置命令
function M.setup()
	vim.api.nvim_create_user_command('AnnotationEnable', function()
		core.enable_annotation_mode()
	end, {})

	vim.api.nvim_create_user_command('AnnotationDisable', function()
		core.disable_annotation_mode()
	end, {})

	vim.api.nvim_create_user_command('AnnotationToggle', function()
		core.toggle_annotation_mode()
	end, {})

	vim.api.nvim_create_user_command('AnnotationCreate', function()
		lsp.create_annotation()
	end, {})

	vim.api.nvim_create_user_command('AnnotationList', function()
		lsp.list_annotations()
	end, {})

	vim.api.nvim_create_user_command('AnnotationDelete', function()
		lsp.delete_annotation()
	end, {})
end

return M
