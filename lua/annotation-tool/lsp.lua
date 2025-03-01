local M = {}
local core = require('annotation-tool.core')
local preview = require('annotation-tool.preview')
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

-- LSP 回调函数
local function on_attach(client, bufnr)
	-- 创建标注（可视模式）
	vim.keymap.set('v', '<Leader>na', M.create_annotation, {
		buffer = bufnr,
		desc = "Create annotation at selection",
		noremap = true,
		silent = true
	})

	-- 列出标注
	vim.keymap.set('n', '<Leader>nl', M.list_annotations, {
		buffer = bufnr,
		desc = "List annotations",
		noremap = true,
		silent = true
	})

	vim.keymap.set('n', '<Leader>nd', M.delete_annotation, {
		buffer = bufnr,
		desc = "Delete annotation at position",
		noremap = true,
		silent = true
	})

	vim.keymap.set('n', '<Leader>np', M.preview_annotation, {
		buffer = bufnr,
		desc = "Preview current annotation",
		noremap = true,
		silent = true
	})

	-- 显示标注内容
	vim.keymap.set('n', 'K', M.hover_annotation, {
		buffer = bufnr,
		desc = "Show hover information",
		noremap = true,
		silent = true
	})

	-- Telescope 相关快捷键
	local ok, telescope_module = pcall(require, 'annotation-tool.telescope')
	if ok then
		-- 使用 Telescope 查找标注
		vim.keymap.set('n', '<Leader>nf', telescope_module.find_annotations, {
			buffer = bufnr,
			desc = "Find annotations with Telescope",
			noremap = true,
			silent = true
		})

		-- 使用 Telescope 搜索标注内容
		vim.keymap.set('n', '<Leader>ns', telescope_module.search_annotations, {
			buffer = bufnr,
			desc = "Search annotation contents",
			noremap = true,
			silent = true
		})
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
			local mode = vim.api.nvim_get_mode().mode
			if mode ~= 'n' then
				return
			end

			vim.lsp.buf.clear_references()
			local params = core.make_position_params()
			request(ms.textDocument_documentHighlight, params)
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
				-- TODO: 在 quickfix 窗口中显示标注列表
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
				if preview.is_previewing(result.note_file) then
					preview.close_preview(true)
				end
				logger.info('Annotation deleted successfully')
			end
		end)
end

function M.preview_annotation()
	local client = M.get_client()
	if not client then
		return
	end
	preview.goto_current_annotation_note()
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
			"--connection",
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
					local byte_range = core.convert_range_to_bytes(0, highlight.range)
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
