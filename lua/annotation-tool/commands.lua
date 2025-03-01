local M = {}

local core = require('annotation-tool.core')
local lsp = require('annotation-tool.lsp')
local telescope = require('annotation-tool.telescope')
local logger = require('annotation-tool.logger')

-- 设置命令
function M.setup()
	logger.debug("Setting up annotation commands")
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

	vim.api.nvim_create_user_command('AnnotationFind', function()
		telescope.find_annotations()
	end, {})

	vim.api.nvim_create_user_command('AnnotationSearch', function()
		telescope.search_annotations()
	end, {})

	vim.api.nvim_create_user_command('AnnotationNote', function()
		telescope.goto_current_annotation_note()
	end, {})

	logger.debug("Annotation commands setup complete")
end

return M
