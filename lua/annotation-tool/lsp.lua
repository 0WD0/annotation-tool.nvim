local M = {}
local core = require('annotation-tool.core')
local preview = require('annotation-tool.preview')

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
local function ensure_venv()
	-- 获取插件根目录
	local current_file = debug.getinfo(1, "S").source:sub(2)
	local plugin_root = vim.fn.fnamemodify(current_file, ":h:h:h")
	local venv_path = plugin_root .. "/.venv"
	local venv_python = venv_path .. "/bin/python"
	local venv_pip = venv_path .. "/bin/pip"

	-- 检查虚拟环境是否存在
	if vim.fn.isdirectory(venv_path) == 0 then
		-- 创建虚拟环境
		local python = vim.fn.exepath('python3') or vim.fn.exepath('python')
		if not python then
			vim.notify("Python not found", vim.log.levels.ERROR)
			return nil
		end

		vim.notify("Creating virtual environment...", vim.log.levels.INFO)
		local venv_cmd = string.format("%s -m venv %s", python, venv_path)
		local venv_result = vim.fn.system(venv_cmd)

		if vim.v.shell_error ~= 0 then
			vim.notify("Failed to create virtual environment: " .. venv_result, vim.log.levels.ERROR)
			return nil
		end
	end

	-- 检查是否已安装依赖
	if vim.fn.executable(venv_pip) == 1 then
		-- 检查 annotation-tool 是否已安装
		local check_cmd = string.format("%s -c 'import annotation_ls' 2>/dev/null", venv_python)
		local check_result = vim.fn.system(check_cmd)
		if vim.v.shell_error ~= 0 then
			-- 依赖未安装，进行安装
			vim.notify("Installing dependencies...", vim.log.levels.INFO)
			local install_cmd = string.format("%s install -e %s", venv_pip, plugin_root)
			local install_result = vim.fn.system(install_cmd)

			if vim.v.shell_error ~= 0 then
				vim.notify("Failed to install dependencies: " .. install_result, vim.log.levels.ERROR)
				return nil
			end

			vim.notify("Dependencies installed successfully", vim.log.levels.INFO)
		end
	else
		vim.notify("Virtual environment is corrupted", vim.log.levels.ERROR)
		return nil
	end

	return venv_python, plugin_root
end

-- 获取 Python 解释器路径
local function get_python_path()
	-- 确保虚拟环境和依赖存在
	local venv_python, plugin_root = ensure_venv()
	if venv_python then
		return venv_python, plugin_root
	end

	-- 如果虚拟环境创建失败，尝试使用系统 Python（不推荐）
	vim.notify("Falling back to system Python (not recommended)", vim.log.levels.WARN)
	local system_python = vim.fn.exepath('python3') or vim.fn.exepath('python')
	if system_python then
		return system_python, plugin_root
	end

	return nil, nil
end

-- 获取 LSP 客户端
function M.get_client()
	local clients = vim.lsp.get_clients({
		name = "annotation_ls"
	})

	if #clients == 0 then
		vim.notify("LSP not attached", vim.log.levels.ERROR)
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

	vim.keymap.set('n', '<Leader>np', preview.setup, {
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

	-- 设置高亮组
	vim.api.nvim_set_hl(0, 'LspReferenceText', { bg = '#626880' })
	vim.api.nvim_set_hl(0, 'LspReferenceRead', { bg = '#626880' })
	vim.api.nvim_set_hl(0, 'LspReferenceWrite', { bg = '#626880' })

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
	vim.notify("Annotation LSP attached", vim.log.levels.INFO)
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

	local range = core.get_visual_selection()
	if not range then
		return
	end

	-- 创建请求参数
	local params = {
		textDocument = {
			uri = vim.uri_from_bufnr(0)
		},
		range = range
	}

	-- 发送请求到 LSP 服务器
	client.request('workspace/executeCommand', {
		command = "createAnnotation",
		arguments = { params }
	}, function(err, result)
		if err then
			vim.notify("Failed to create annotation: " .. vim.inspect(err), vim.log.levels.ERROR)
			return
		end
		if result and result.success then
			vim.notify("Annotation created successfully", vim.log.levels.INFO)
		end
	end)
end

-- 列出标注
function M.list_annotations()
	local client = M.get_client()
	if not client then
		return
	end

	local params = {
		textDocument = vim.lsp.util.make_text_document_params()
	}

	client.request('workspace/executeCommand', {
		command = "listAnnotations",
		arguments = { params }
	}, function(err, result)
		if err then
			vim.notify('Failed to list annotations: ' .. vim.inspect(err), vim.log.levels.ERROR)
		else
			vim.notify('Found ' .. #result.annotations .. ' annotations', vim.log.levels.INFO)
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

	-- local params = vim.lsp.util.make_position_params()
	local params = core.make_position_params()

	vim.notify('L'..vim.inspect(params.position.line)..'C'..vim.inspect(params.position.character),vim.log.levels.INFO)

	client.request('workspace/executeCommand', {
		command = "deleteAnnotation",
		arguments = { params }
	}, function(err, result)
		if err then
			vim.notify('Failed to delete annotation: ' .. vim.inspect(err), vim.log.levels.ERROR)
		else
			vim.notify('Annotation deleted successfully', vim.log.levels.INFO)
		end
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
		vim.notify("LSP has not set up", vim.log.levels.ERROR)
		return
	end
	vim.notify("Attaching")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.lsp.buf_attach_client(bufnr,client_id)
end

-- 初始化 LSP 配置
function M.setup(opts)
	opts = opts or {}
	local lspconfig = require('lspconfig')
	local configs = require('lspconfig.configs')

	-- 获取 Python 解释器和项目根目录
	local python_path, plugin_root = get_python_path()
	if not python_path then
		vim.notify("No Python interpreter found", vim.log.levels.ERROR)
		return
	end

	-- 构建 Python 命令
	local python_cmd = {
		python_path,
		"-m",
		"annotation_ls"
	}

	-- 注册自定义 LSP
	if not configs.annotation_ls then
		configs.annotation_ls = {
			default_config = {
				cmd = python_cmd,
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
	vim.notify("Setting up annotation_ls")
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
