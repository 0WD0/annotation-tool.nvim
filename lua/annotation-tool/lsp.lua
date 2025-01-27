local M = {}
local core = require('annotation-tool.core')

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

	-- 检查依赖是否已安装
	if vim.fn.executable(venv_pip) == 1 then
		-- 安装依赖
		vim.notify("Installing dependencies...", vim.log.levels.INFO)
		local install_cmd = string.format("%s install -e %s", venv_pip, plugin_root)
		local install_result = vim.fn.system(install_cmd)

		if vim.v.shell_error ~= 0 then
			vim.notify("Failed to install dependencies: " .. install_result, vim.log.levels.ERROR)
			return nil
		end

		vim.notify("Dependencies installed successfully", vim.log.levels.INFO)
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

-- 查找包含 .annotation 目录的项目根目录
local function find_project_root()
	local current_file = vim.fn.expand('%:p')
	local current_dir = vim.fn.fnamemodify(current_file, ':h')

	-- 从当前目录向上查找 .annotation 目录
	local root_dir = current_dir
	local prev_dir = nil
	while root_dir ~= prev_dir do
		if vim.fn.isdirectory(root_dir .. '/.annotation') == 1 then
			print('found: ' .. root_dir)
			return root_dir
		end
		prev_dir = root_dir
		root_dir = vim.fn.fnamemodify(root_dir, ':h')
	end

	-- 如果没找到，就使用当前目录
	return current_dir
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

	-- 显示标注内容
	vim.keymap.set('n', 'K', vim.lsp.buf.hover, {
		buffer = bufnr,
		desc = "Show hover information",
		noremap = true,
		silent = true
	})

	-- 启用标注模式
	core.enable_annotation_mode()
	vim.notify("Annotation LSP attached", vim.log.levels.INFO)
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

	local params = vim.lsp.util.make_position_params()

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

-- 手动 attach LSP 到当前 buffer
function M.attach()
	local bufnr = vim.api.nvim_get_current_buf()
	local filetype = vim.bo[bufnr].filetype

	if not vim.tbl_contains({ "markdown", "text", "annot" }, filetype) then
		vim.notify("LSP only supports markdown, text and annot files", vim.log.levels.WARN)
		return
	end

	local clients = vim.lsp.get_clients({
		bufnr = bufnr,
		name = "annotation_ls"
	})

	if #clients > 0 then
		vim.notify("LSP already attached", vim.log.levels.INFO)
		return
	end

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
		"annotation_lsp"
	}

	-- 启动 LSP 客户端
	local client_id = vim.lsp.start_client({
		name = "annotation_ls",
		cmd = python_cmd,
		root_dir = find_project_root(),
		on_attach = on_attach
	})

	if not client_id then
		vim.notify("Failed to start LSP client", vim.log.levels.ERROR)
		return
	end

	-- 将 LSP 客户端附加到当前 buffer
	vim.lsp.buf_attach_client(bufnr, client_id)
	vim.notify("LSP attached successfully", vim.log.levels.INFO)
end

-- 初始化 LSP
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
		"annotation_lsp"
	}

	-- 注册自定义 LSP
	if not configs.annotation_ls then
		configs.annotation_ls = {
			default_config = {
				cmd = python_cmd,
				filetypes = { 'markdown', 'text', 'annot' },
				root_dir = function(fname)
					return find_project_root()
				end,
				settings = {}
			},
		}
	end

	-- 设置 LSP
	lspconfig.annotation_ls.setup({
		cmd = python_cmd,
		on_attach = on_attach,
		capabilities = vim.lsp.protocol.make_client_capabilities(),
		settings = vim.tbl_deep_extend("force", {
			annotation = {
				saveDir = vim.fn.expand('~/.local/share/nvim/annotation-notes'),
			}
		}, opts.settings or {})
	})
end

return M
