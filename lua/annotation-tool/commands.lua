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

	-- 搜索命令带参数版本
	vim.api.nvim_create_user_command("AnnotationFindWithBackend", function(opts)
		local backend = opts.args or search.BACKEND.TELESCOPE
		if backend ~= search.BACKEND.TELESCOPE and backend ~= search.BACKEND.FZF_LUA then
			logger.error("不支持的后端: " .. backend .. "\n支持的后端: telescope, fzf-lua")
			return
		end
		search.find_annotations({ backend = backend })
	end, {
		nargs = "?",
		complete = function()
			return { search.BACKEND.TELESCOPE, search.BACKEND.FZF_LUA }
		end
	})

	vim.api.nvim_create_user_command("AnnotationFindWithScope", function(opts)
		local args = vim.split(opts.args or "", "%s+", { trimempty = true })
		local scope = args[1] or search.SCOPE.CURRENT_FILE
		local backend = args[2] or search.BACKEND.TELESCOPE

		-- 验证范围
		local valid_scopes = { search.SCOPE.CURRENT_FILE, search.SCOPE.CURRENT_PROJECT, search.SCOPE.ALL_PROJECTS }
		if not vim.tbl_contains(valid_scopes, scope) then
			logger.error("不支持的搜索范围: " .. scope .. "\n支持的范围: current_file, current_project, all_projects")
			return
		end

		-- 验证后端
		if backend ~= search.BACKEND.TELESCOPE and backend ~= search.BACKEND.FZF_LUA then
			logger.error("不支持的后端: " .. backend .. "\n支持的后端: telescope, fzf-lua")
			return
		end

		search.find_annotations({ scope = scope, backend = backend })
	end, {
		nargs = "*",
		complete = function(arg_lead, cmd_line, cursor_pos)
			local args = vim.split(cmd_line, "%s+", { trimempty = true })
			local arg_count = #args - 1 -- 减去命令本身

			-- 如果当前正在输入第一个参数（scope）
			if arg_count == 1 then
				local scopes = { search.SCOPE.CURRENT_FILE, search.SCOPE.CURRENT_PROJECT, search.SCOPE.ALL_PROJECTS }
				return vim.tbl_filter(function(scope)
					return vim.startswith(scope, arg_lead)
				end, scopes)
				-- 如果当前正在输入第二个参数（backend）
			elseif arg_count == 2 then
				local backends = { search.BACKEND.TELESCOPE, search.BACKEND.FZF_LUA }
				return vim.tbl_filter(function(backend)
					return vim.startswith(backend, arg_lead)
				end, backends)
			end
			return {}
		end
	})

	logger.debug("Annotation commands setup complete")
end

return M
