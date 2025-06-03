local M = {}

local core = require('annotation-tool.core')
local lsp = require('annotation-tool.lsp')
local search = require('annotation-tool.search')
local pvw_manager = require('annotation-tool.preview.manager')
local logger = require('annotation-tool.logger')

-- 设置命令
function M.setup()
	logger.debug("Setting up annotation commands")
	local function create_command(name, fn)
		vim.api.nvim_create_user_command(name, fn, {})
	end

	local commands = {
		{ "AnnotationEnable",            core.enable_annotation_mode },
		{ "AnnotationDisable",           core.disable_annotation_mode },
		{ "AnnotationToggle",            core.toggle_annotation_mode },
		{ "AnnotationCreate",            lsp.create_annotation },
		{ "AnnotationList",              lsp.list_annotations },
		{ "AnnotationDelete",            lsp.delete_annotation },
		{ "AnnotationTree",              pvw_manager.show_annotation_tree },
		-- 搜索命令
		{ "AnnotationFindTelescope",     function() search.find_annotations({ backend = search.BACKEND.TELESCOPE }) end },
		{ "AnnotationFindFzf",           function() search.find_annotations({ backend = search.BACKEND.FZF_LUA }) end },
		{ "AnnotationFindCurrentFile",   search.find_current_file },
		{ "AnnotationFindProject",       search.find_current_project },
		{ "AnnotationFindAll",           search.find_all_projects },
		-- 调试命令
		{ "AnnotationDebugTree",         pvw_manager.debug_print_tree },
		{ "AnnotationDebugInvalidNodes", pvw_manager.debug_check_invalid_nodes },
		{ "AnnotationDebugListNodes",    pvw_manager.debug_list_nodes },
	}

	for _, cmd in ipairs(commands) do
		create_command(cmd[1], cmd[2])
	end

	-- 带参数的命令需要特殊处理
	vim.api.nvim_create_user_command("AnnotationDebugNode", function(opts)
		if opts.args and opts.args ~= "" then
			pvw_manager.debug_node_info(opts.args)
		else
			logger.debug("请提供节点ID作为参数\n例如: :AnnotationDebugNode node_123")
		end
	end, { nargs = "?" })

	logger.debug("Annotation commands setup complete")
end

return M
