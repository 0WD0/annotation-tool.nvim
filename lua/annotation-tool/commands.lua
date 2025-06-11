local M = {}

-- 延迟加载依赖
local function load_deps()
	local core = require('annotation-tool.core')
	local lsp = require('annotation-tool.lsp')
	local search = require('annotation-tool.search')
	local pvw_manager = require('annotation-tool.preview.manager')
	local config = require('annotation-tool.config')
	local logger = require('annotation-tool.logger')

	return {
		core = core,
		lsp = lsp,
		search = search,
		pvw_manager = pvw_manager,
		config = config,
		logger = logger
	}
end

-- 设置命令
function M.setup()
	local deps = load_deps()
	deps.logger.debug("Setting up annotation commands")
	local function create_command(name, fn)
		vim.api.nvim_create_user_command(name, fn, {})
	end

	local commands = {
		{ "AnnotationEnable",  deps.core.enable_annotation_mode },
		{ "AnnotationDisable", deps.core.disable_annotation_mode },
		{ "AnnotationToggle",  deps.core.toggle_annotation_mode },
		{ "AnnotationCreate",  deps.lsp.create_annotation },
		{ "AnnotationList",    deps.lsp.list_annotations },
		{ "AnnotationDelete",  deps.lsp.delete_annotation },
		{ "AnnotationTree",    deps.pvw_manager.show_annotation_tree },
		-- 搜索命令
		{ "AnnotationFind", function()
			local backend = deps.config.get_best_backend()
			local scope = deps.config.get_smart_scope()
			if backend then
				deps.search.find_current_project({ backend = backend, scope = scope })
			else
				deps.logger.error("没有可用的搜索后端")
			end
		end },
		{ "AnnotationFindTelescope", function()
			if deps.config.is_backend_available('telescope') then
				deps.search.find_current_project({ backend = deps.search.BACKEND.TELESCOPE })
			else
				deps.logger.error("Telescope 后端不可用")
			end
		end },
		{ "AnnotationFindFzf", function()
			if deps.config.is_backend_available('fzf-lua') then
				deps.search.find_current_project({ backend = deps.search.BACKEND.FZF_LUA })
			else
				deps.logger.error("fzf-lua 后端不可用")
			end
		end },
		{ "AnnotationFindCurrentFile", function()
			local backend = deps.config.get_best_backend()
			if backend then
				deps.search.find_current_project({ backend = backend, scope = deps.search.SCOPE.CURRENT_FILE })
			else
				deps.logger.error("没有可用的搜索后端")
			end
		end },
		{ "AnnotationFindProject", function()
			local backend = deps.config.get_best_backend()
			if backend then
				deps.search.find_current_project({ backend = backend, scope = deps.search.SCOPE.CURRENT_WORKSPACE })
			else
				deps.logger.error("没有可用的搜索后端")
			end
		end },
		{ "AnnotationFindAll", function()
			local backend = deps.config.get_best_backend()
			if backend then
				deps.search.find_current_project({ backend = backend, scope = deps.search.SCOPE.CURRENT_PROJECT })
			else
				deps.logger.error("没有可用的搜索后端")
			end
		end },
		-- 配置命令
		{ "AnnotationConfigShow",        function() vim.print(deps.config.get()) end },
		{ "AnnotationConfigStats",       function() vim.print(deps.config.get_stats()) end },
		-- 调试命令
		{ "AnnotationDebugTree",         deps.pvw_manager.debug_print_tree },
		{ "AnnotationDebugInvalidNodes", deps.pvw_manager.debug_check_invalid_nodes },
		{ "AnnotationDebugListNodes",    deps.pvw_manager.debug_list_nodes },
	}

	for _, cmd in ipairs(commands) do
		create_command(cmd[1], cmd[2])
	end

	-- 带参数的命令需要特殊处理
	vim.api.nvim_create_user_command("AnnotationDebugNode", function(opts)
		if opts.args and opts.args ~= "" then
			deps.pvw_manager.debug_node_info(opts.args)
		else
			deps.logger.debug("请提供节点ID作为参数\n例如: :AnnotationDebugNode node_123")
		end
	end, { nargs = "?" })

	-- 搜索命令带参数版本
	vim.api.nvim_create_user_command("AnnotationFindWithBackend", function(opts)
		local deps_local = load_deps()
		local backend = opts.args or deps_local.config.get('search.default_backend')
		if not deps_local.config.is_backend_available(backend) then
			deps_local.logger.error("后端不可用: " .. backend)
			return
		end
		deps_local.search.find_current_project({ backend = backend })
	end, {
		nargs = "?",
		complete = function()
			local deps_local = load_deps()
			local available = {}
			if deps_local.config.is_backend_available('telescope') then
				table.insert(available, deps_local.search.BACKEND.TELESCOPE)
			end
			if deps_local.config.is_backend_available('fzf-lua') then
				table.insert(available, deps_local.search.BACKEND.FZF_LUA)
			end
			return available
		end
	})

	vim.api.nvim_create_user_command("AnnotationFindWithScope", function(opts)
		local deps_local = load_deps()
		local args = vim.split(opts.args or "", "%s+", { trimempty = true })
		local scope = args[1] or deps_local.config.get('search.default_scope')
		local backend = args[2] or deps_local.config.get_best_backend()

		-- 验证范围
		local valid_scopes = {
			deps_local.search.SCOPE.CURRENT_FILE,
			deps_local.search.SCOPE.CURRENT_WORKSPACE,
			deps_local.search.SCOPE.CURRENT_PROJECT,
		}
		if not vim.tbl_contains(valid_scopes, scope) then
			deps_local.logger.error("不支持的搜索范围: " .. scope .. "\n支持的范围: current_file, current_project, all_projects")
			return
		end

		-- 验证后端
		if not deps_local.config.is_backend_available(backend) then
			deps_local.logger.error("后端不可用: " .. backend)
			return
		end

		deps_local.search.find_current_project({ scope = scope, backend = backend })
	end, {
		nargs = "*",
		complete = function(arg_lead, cmd_line, cursor_pos)
			local deps_local = load_deps()
			local args = vim.split(cmd_line, "%s+", { trimempty = true })
			local arg_count = #args - 1 -- 减去命令本身

			-- 如果当前正在输入第一个参数（scope）
			if arg_count == 1 then
				local scopes = {
					deps_local.search.SCOPE.CURRENT_FILE,
					deps_local.search.SCOPE.CURRENT_WORKSPACE,
					deps_local.search.SCOPE.CURRENT_PROJECT,
				}
				return vim.tbl_filter(function(scope)
					return vim.startswith(scope, arg_lead)
				end, scopes)
				-- 如果当前正在输入第二个参数（backend）
			elseif arg_count == 2 then
				local available = {}
				if deps_local.config.is_backend_available('telescope') then
					table.insert(available, deps_local.search.BACKEND.TELESCOPE)
				end
				if deps_local.config.is_backend_available('fzf-lua') then
					table.insert(available, deps_local.search.BACKEND.FZF_LUA)
				end
				return vim.tbl_filter(function(backend)
					return vim.startswith(backend, arg_lead)
				end, available)
			end
			return {}
		end
	})

	-- 配置导出命令
	vim.api.nvim_create_user_command("AnnotationConfigExport", function(opts)
		local deps_local = load_deps()
		local file_path = opts.args or "annotation-config.lua"
		deps_local.config.export_config(file_path)
		deps_local.logger.info("配置已导出到: " .. file_path)
	end, {
		nargs = "?",
		complete = "file"
	})

	-- 配置导入命令
	vim.api.nvim_create_user_command("AnnotationConfigImport", function(opts)
		local deps_local = load_deps()
		if not opts.args or opts.args == "" then
			deps_local.logger.error("请提供配置文件路径")
			return
		end
		if deps_local.config.import_config(opts.args) then
			deps_local.logger.info("配置已从文件导入: " .. opts.args)
		else
			deps_local.logger.error("导入配置失败")
		end
	end, {
		nargs = 1,
		complete = "file"
	})

	deps.logger.debug("Annotation commands setup complete")
end

return M
