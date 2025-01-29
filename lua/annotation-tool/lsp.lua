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

	-- 检查是否已安装依赖
	if vim.fn.executable(venv_pip) == 1 then
		-- 检查 annotation-tool 是否已安装
		local check_cmd = string.format("%s -c 'import annotation_lsp' 2>/dev/null", venv_python)
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

	-- 显示标注内容
	vim.keymap.set('n', 'K', M.hover_annotation, {
		buffer = bufnr,
		desc = "Show hover information",
		noremap = true,
		silent = true
	})

	-- 启用标注模式
	core.enable_annotation_mode()
	vim.notify("Annotation LSP attached", vim.log.levels.INFO)
end

--- copy from nvim source code
local function request(method, params, handler)
	vim.validate({
		method = { method, 's' },
		handler = { handler, 'f', true },
	})
	return vim.lsp.buf_request(0, method, params, handler)
end
local ms= require('vim.lsp.protocol').Methods
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

-- 查找包含 .annotation 目录的项目根目录
local function find_project_root(start_path)
	local current_dir = start_path or vim.fn.expand('%:p:h')
	local root = vim.fs.find('.annotation', {
		path = current_dir,
		upward = true,
		type = 'directory'
	})[1]
	
	return root and vim.fs.dirname(root) or nil
end

-- 存储当前的工作区文件夹
local workspace_folders = {}

-- 添加工作区文件夹
local function add_workspace_folder(path)
	local uri = vim.uri_from_fname(path)
	if not workspace_folders[uri] then
		workspace_folders[uri] = {
			uri = uri,
			name = vim.fn.fnamemodify(path, ":t")
		}
		vim.notify("Added workspace: " .. path)
	end
end

-- 移除工作区文件夹
local function remove_workspace_folder(path)
	local uri = vim.uri_from_fname(path)
	if workspace_folders[uri] then
		workspace_folders[uri] = nil
		vim.notify("Removed workspace: " .. path)
	end
end

-- 清理不再使用的工作区文件夹
local function cleanup_workspace_folders()
	local used_folders = {}

	-- 收集所有当前使用的工作区
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local bufname = vim.api.nvim_buf_get_name(bufnr)
		local filetype = vim.bo[bufnr].filetype
		if bufname ~= "" and (filetype == 'markdown' or filetype == 'text' or filetype == 'annot') then
			local root = find_project_root(vim.fn.fnamemodify(bufname, ":p:h"))
			if root then
				used_folders[root] = true
			end
		end
	end

	-- 移除不再使用的工作区
	for folder, _ in pairs(workspace_folders) do
		if not used_folders[folder] then
			remove_workspace_folder(folder)
		end
	end
end

-- 扫描并添加工作区文件夹
local function scan_workspace_folders()
	-- 检查所有打开的 buffer
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local bufname = vim.api.nvim_buf_get_name(bufnr)
		local filetype = vim.bo[bufnr].filetype
		if bufname ~= "" and (filetype == 'markdown' or filetype == 'text' or filetype == 'annot') then
			local bufdir = vim.fn.fnamemodify(bufname, ":p:h")
			if find_project_root(bufdir) then
				add_workspace_folder(bufdir)
			end
		end
	end
end

-- 获取工作区文件夹
local function get_workspace_folders()
	local folders = {}
	for _, folder in pairs(workspace_folders) do
		table.insert(folders, folder)
	end
	vim.notify(vim.inspect(folders))
	return folders
end

-- 监听文件打开事件，自动扫描工作区
vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
	callback = function()
		scan_workspace_folders()
	end
})

-- 监听文件关闭事件，清理工作区
vim.api.nvim_create_autocmd({"BufDelete"}, {
	callback = function()
		cleanup_workspace_folders()
	end
})

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
		"annotation_lsp"
	}

	-- 注册自定义 LSP
	if not configs.annotation_ls then
		configs.annotation_ls = {
			default_config = {
				cmd = python_cmd,
				filetypes = { 'markdown', 'text', 'annot' },
				on_attach = on_attach,
				root_dir = function() return vim.uv.os_homedir() end,
				workspace_folders = get_workspace_folders,
				capabilities = vim.tbl_deep_extend("force",
					vim.lsp.protocol.make_client_capabilities(),
					{
						workspace = {
							workspaceFolders = {
								supported = true,
								changeNotifications = true
							}
						}
					}
				),
				single_file_support = false,
				settings = {}
			},
		}
	end

	-- setup LSP
	vim.notify("Setting up annotation_ls")
	scan_workspace_folders()  -- 启动前扫描工作区
	lspconfig.annotation_ls.setup({})
end

return M
