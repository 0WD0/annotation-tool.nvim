local M = {}

local core = require('annotation-tool.core')
local lsp = require('annotation-tool.lsp')
local telescope = require('annotation-tool.telescope')
local logger = require('annotation-tool.logger')

-- 设置命令
function M.setup()
	logger.debug("Setting up annotation commands")
	local function create_command(name, fn)
		vim.api.nvim_create_user_command(name, fn, {})
	end

	local commands = {
		{ "AnnotationEnable", core.enable_annotation_mode },
		{ "AnnotationDisable", core.disable_annotation_mode },
		{ "AnnotationToggle", core.toggle_annotation_mode },
		{ "AnnotationCreate", lsp.create_annotation },
		{ "AnnotationList", lsp.list_annotations },
		{ "AnnotationDelete", lsp.delete_annotation },
		{ "AnnotationFind", telescope.find_annotations },
		{ "AnnotationSearch", telescope.search_annotations },
	}

	for _, cmd in ipairs(commands) do
		create_command(cmd[1], cmd[2])
	end

	logger.debug("Annotation commands setup complete")
end

return M
