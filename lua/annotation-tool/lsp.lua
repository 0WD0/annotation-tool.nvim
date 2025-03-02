local M = {}
local core = require('annotation-tool.core')
local preview = require('annotation-tool.preview')
local manager = require('annotation-tool.preview.manager')
local logger = require('annotation-tool.logger')

--- copy from nvim source code
local ms= require('vim.lsp.protocol').Methods
local function request(method, params, handler)
	vim.validate({
		method = { method, 's' },
		handler = { handler, 'f', true },
	})
	return vim.lsp.buf_request(0, method, params, handler)
end

-- 确保虚拟环境存在并安装依赖
local function ensure_deps(version)
	-- 获取插件根目录
	local current_file = debug.getinfo(1, "S").source:sub(2)
	local plugin_root = vim.fn.fnamemodify(current_file, ":h:h:h")

	if version == 'python' then
		-- 获取 Python 实现目录
		local python_root = plugin_root .. "/annotation_ls_py"
		local venv_path = python_root .. "/.venv"
		local venv_python = venv_path .. "/bin/python"
		local venv_pip = venv_path .. "/bin/pip"

		-- 检查虚拟环境是否存在
		if vim.fn.isdirectory(venv_path) == 0 then
			-- 创建虚拟环境
			local python = vim.fn.exepath('python3') or vim.fn.exepath('python')
			if not python then
				logger.error("Python not found")
				return nil
			end
			logger.info("Creating virtual environment...")
			local venv_cmd = string.format("%s -m venv %s", python, venv_path)
			local venv_result = vim.fn.system(venv_cmd)
			if vim.v.shell_error ~= 0 then
				logger.error("Failed to create virtual environment: " .. venv_result)
				return nil
			end
		end

		-- 检查是否已安装依赖
		if vim.fn.executable(venv_pip) == 1 then
			-- 检查 annotation-tool 是否已安装
			local check_cmd = string.format("%s -c 'import annotation_ls_py.cli' 2>/dev/null", venv_python)
			local check_result = vim.fn.system(check_cmd)
			if vim.v.shell_error ~= 0 then
				-- 依赖未安装，进行安装
				logger.info("Installing dependencies...")
				local install_cmd = string.format("%s install -e %s", venv_pip, python_root)
				local install_result = vim.fn.system(install_cmd)
				if vim.v.shell_error ~= 0 then
					logger.error("Failed to install dependencies: " .. install_result)
					return nil
				end

				logger.info("Dependencies installed successfully")
			end
		else
			logger.error("Virtual environment is corrupted")
			return nil
		end

		return venv_python, plugin_root
	else
		-- 获取 Node.js 实现目录
		local node_root = plugin_root .. "/annotation_ls_js"
		local server_path = node_root .. "/out/cli.js"

		-- 检查编译后的文件是否存在
		if vim.fn.filereadable(server_path) == 0 then
			-- 编译 TypeScript
			local compile_cmd = string.format("cd %s && npm install && npm run compile", node_root)
			local compile_result = vim.fn.system(compile_cmd)

			if vim.v.shell_error ~= 0 then
				logger.error("Failed to compile TypeScript: " .. compile_result)
				return nil
			end
		end

		return vim.fn.exepath('node'), node_root
	end
end

-- 获取 LSP 客户端
function M.get_client()
	local clients = vim.lsp.get_clients({
		name = "annotation_ls"
	})

	if #clients == 0 then
		logger.error("LSP not attached")
		return nil
	end

	return clients[1]
end

function M.highlight()
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= 'n' then
		return
	end

	vim.lsp.buf.clear_references()
	local params = core.make_position_params()
	request(ms.textDocument_documentHighlight, params)
end

-- LSP 回调函数
local function on_attach(client, bufnr)
	local base_options = { buffer = bufnr, noremap = true, silent = true }
	local keybindings = {
		{ mode = 'v', lhs = '<Leader>na', rhs = M.create_annotation, desc = "Create annotation at selection" },
		{ mode = 'n', lhs = '<Leader>nl', rhs = M.list_annotations, desc = "List annotations" },
		{ mode = 'n', lhs = '<Leader>nd', rhs = M.delete_annotation, desc = "Delete annotation at position" },
		{ mode = 'n', lhs = '<Leader>np', rhs = M.goto_current_annotation_note, desc = "Preview current annotation" },
		{ mode = 'n', lhs = 'K', rhs = M.hover_annotation, desc = "Show hover information" },
		{ mode = 'n', lhs = '<A-k>', rhs = function() M.goto_annotation_source(-1) end, desc = "Go to previous annotation" },
		{ mode = 'n', lhs = '<A-j>', rhs = function() M.goto_annotation_source(1) end, desc = "Go to next annotation" },
	}

	local ok, telescope_module = pcall(require, 'annotation-tool.telescope')
	if ok then
		table.insert(keybindings, { mode = 'n', lhs = '<Leader>nf', rhs = telescope_module.find_annotations, desc = "Find annotations with Telescope" })
		table.insert(keybindings, { mode = 'n', lhs = '<Leader>ns', rhs = telescope_module.search_annotations, desc = "Search annotation contents" })
	end

	for _, config in ipairs(keybindings) do
		vim.keymap.set(config.mode, config.lhs, config.rhs, vim.tbl_extend('keep', base_options, { desc = config.desc }))
	end

	-- 设置高亮组
	-- 可选的下划线样式：
	-- underline: 单下划线
	-- undercurl: 波浪线
	-- underdouble: 双下划线
	-- underdotted: 点状下划线
	-- underdashed: 虚线下划线
	vim.api.nvim_set_hl(0, 'LspReferenceText', { underdouble = true, sp = '#85c1dc' })  -- 使用波浪线
	vim.api.nvim_set_hl(0, 'LspReferenceRead', { underdouble = true, sp = '#85c1dc' })
	vim.api.nvim_set_hl(0, 'LspReferenceWrite', { underdouble = true, sp = '#85c1dc' })

	-- 自动高亮
	vim.api.nvim_create_autocmd('CursorMoved', {
		buffer = bufnr,
		callback = function()
			M.highlight()
		end
	})

	-- 启用标注模式
	core.enable_annotation_mode()
	logger.info("Annotation LSP attached")
end

--- Displays hover information about the symbol under the cursor in a floating 
--- window. Calling the function twice will jump into the floating window.
function M.hover_annotation()
	local params = core.make_position_params()
	request(ms.textDocument_hover, params)
end

-- 创建标注
function M.create_annotation()
	local client = M.get_client()
	if not client then
		return
	end

	local params = core.make_selection_params()

	client.request('workspace/executeCommand', {
		command = "createAnnotation",
		arguments = { params }
	}, function(err, result)
			if err then
				logger.error("Failed to create annotation: " .. vim.inspect(err))
				return
			end
			if result and result.success then
				-- TODO: change
				preview.goto_annotation_note(result)
				logger.info("Annotation created successfully")
			end
		end)
end

-- 列出标注
function M.list_annotations()
	local client = M.get_client()
	if not client then
		return
	end

	client.request('workspace/executeCommand', {
		command = "listAnnotations",
		arguments = { {
			textDocument = vim.lsp.util.make_text_document_params()
		} }
	}, function(err, result)
			if err then
				logger.error('Failed to list annotations: ' .. vim.inspect(err))
			else
				logger.info('Found ' .. #result.note_files .. ' annotations')
				-- 输出调试信息
				logger.debug_obj('Result', result)
			end
		end)
end

-- 删除标注
function M.delete_annotation()
	local client = M.get_client()
	if not client then
		return
	end

	local params = core.make_position_params()

	logger.debug('L'..vim.inspect(params.position.line)..'C'..vim.inspect(params.position.character))

	client.request('workspace/executeCommand', {
		command = "deleteAnnotation",
		arguments = { params }
	}, function(err, result)
			if err then
				logger.error('Failed to delete annotation: ' .. vim.inspect(err))
			else
				-- 如果预览的就是这个文件，强制关闭预览窗口
				-- TODO: change
				if preview.is_previewing(result.note_file) then
					preview.close_preview(true)
				end
				logger.info('Annotation deleted successfully')
			end
		end)
end

function M.goto_current_annotation_note()
	local params = core.make_position_params()
	logger.info("Getting annotation note...")

	local client = M.get_client()
	if not client then
		logger.error("LSP client not available")
		return
	end

	-- 使用 LSP 命令获取批注文件
	client.request('workspace/executeCommand', {
		command = "getAnnotationNote",
		arguments = { params }
	}, function(err, result)
		if err then
			logger.error("Error getting annotation note: " .. err.message)
			return
		end
		if not result then
			logger.warn("No annotation note found")
			return
		end

		-- TODO: change
		preview.goto_annotation_note(result)
	end)
end

function M.goto_annotation_source(offset)
	local preview_state = preview.preview_state
	if not preview_state.buf or not vim.api.nvim_buf_is_valid(preview_state.buf) then
		logger.warn("No preview window open")
		return
	end

	local client = M.get_client()
	if not client then
		logger.error("LSP client not available")
		return
	end

	client.request('workspace/executeCommand', {
		command = "getAnnotationSource",
		arguments = { {
			textDocument = {
				uri = vim.uri_from_bufnr(preview_state.buf)
			},
			offset = offset
		} }
	}, function(err, result)
		if err then
			logger.error("Error getting annotation source: " .. err.message)
			return
		end
		if not result then
			logger.warn("No annotation source found")
			return
		end

		-- TODO: change
		preview.close_preview(false)

		-- 获取或创建源文件窗口
		local source_win = nil
		local wins = vim.api.nvim_list_wins()
		if #wins > 0 then
			source_win = wins[1]
		else
			-- 如果没有窗口，创建一个新窗口
			vim.cmd('vsplit')
			source_win = vim.api.nvim_get_current_win()
		end

		-- 在源文件窗口中打开文件并跳转到批注位置
		vim.api.nvim_set_current_win(source_win)
		-- vim.cmd('edit ' .. result.source_path)
		-- 使用core模块的函数将LSP位置转换为光标位置
		local cursor_pos = core.convert_utf8_to_bytes(0, result.position)
		vim.api.nvim_win_set_cursor(source_win, cursor_pos)

		-- 设置预览窗口
		local file_path = result.workspace_path .. '/.annotation/notes/' .. result.note_file
		preview.setup_preview_window(file_path)
	end)
end

-- 查找最顶层的项目根目录
local function find_root_project(start_path)
	local current = start_path or vim.fn.expand('%:p:h')
	local root = nil

	-- 向上查找包含 .annotation 的目录，找到最后一个
	while current do
		if vim.fn.isdirectory(current .. '/.annotation') == 1 then
			root = current
		end
		local parent = vim.fn.fnamemodify(current, ':h')
		if parent == current then
			break
		end
		current = parent
	end

	return root
end

function M.attach()
	local client_id = M.get_client();
	if not client_id then
		logger.error("LSP has not set up")
		return
	end
	logger.info("Attaching")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.lsp.buf_attach_client(bufnr,client_id)
end

-- 初始化 LSP 配置
function M.setup(opts)
	opts = opts or {}
	local lspconfig = require('lspconfig')
	local configs = require('lspconfig.configs')
	local version = opts.version or 'python'
	local connection = opts.connection or 'stdio'
	local host = opts.host or '127.0.0.1'
	local port = opts.port or 2087

	-- 获取命令路径
	local cmd_path, plugin_root = ensure_deps(version)
	if not cmd_path then
		logger.error(string.format("Failed to setup LSP client for version %s", version))
		return
	end

	-- 构建命令
	local cmd
	if version == 'python' then
		cmd = {
			cmd_path,
			"-m",
			"annotation_ls_py.cli",
			"--connection",
			connection
		}
	else
		cmd = {
			cmd_path,
			plugin_root .. "/out/cli.js",
			"--transport",
			connection
		}
	end

	-- 如果是 TCP 连接，添加 host 和 port 参数
	if connection == 'tcp' then
		table.insert(cmd, "--host")
		table.insert(cmd, host)
		table.insert(cmd, "--port")
		table.insert(cmd, tostring(port))
	end

	-- 不再需要添加 --stdio 参数，因为 cli.js 不接受这个参数
	-- 在 cli.js 中已经默认使用 stdio 作为传输方式

	-- 注册自定义 LSP
	if not configs.annotation_ls then
		configs.annotation_ls = {
			default_config = {
				cmd = cmd,
				filetypes = { 'markdown', 'text', 'annot' },
				on_attach = on_attach,
				root_dir = function(fname)
					-- 使用最顶层的项目目录作为 root_dir
					return find_root_project(vim.fn.fnamemodify(fname, ':p:h'))
				end,
				single_file_support = false,
				settings = {}
			},
		}
	end

	-- setup LSP
	logger.info("Setting up annotation_ls")
	lspconfig.annotation_ls.setup({
		handlers = {
			['textDocument/documentHighlight'] = function(err, result, ctx, config)
				if err or not result then
					return
				end

				local converted_result = {}
				for _, highlight in ipairs(result) do
					local byte_range = core.convert_utf8_to_bytes(0, highlight.range)
					table.insert(converted_result, { range = byte_range })
				end

				vim.lsp.util.buf_highlight_references(
					ctx.bufnr,
					converted_result,
					'utf-8'
				)
			end
		}
	})
end

return M
