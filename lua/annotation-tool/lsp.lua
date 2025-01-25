local M = {}
local core = require('annotation-tool.core')

-- 获取 Python 解释器路径
local function get_python_path()
	-- 获取当前文件所在目录
	local current_file = debug.getinfo(1, "S").source:sub(2)
	local plugin_root = vim.fn.fnamemodify(current_file, ":h:h:h")
	
	-- 首先检查项目虚拟环境
	local venv_python = plugin_root .. "/.venv/bin/python"
	if vim.fn.executable(venv_python) == 1 then
		return venv_python, plugin_root
	end
	
	-- 如果没有虚拟环境，尝试系统 Python
	local system_python = vim.fn.exepath('python3') or vim.fn.exepath('python')
	if system_python then
		return system_python, plugin_root
	end
	
	return nil, nil
end

-- 获取 LSP 客户端
function M.get_client()
	local clients = vim.lsp.get_active_clients({
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
	vim.b.annotation_mode = true
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
	
	client.request('workspace/executeCommand', {
		command = "listAnnotations",
		arguments = { {
			textDocument = { uri = vim.uri_from_bufnr(0) }
		} }
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
function M.delete_annotation(annotation_id)
	local client = M.get_client()
	if not client then
		return
	end
	
	if not annotation_id then
		vim.notify("No annotation ID provided", vim.log.levels.ERROR)
		return
	end
	
	client.request('workspace/executeCommand', {
		command = "deleteAnnotation",
		arguments = { annotation_id }
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
	
	local clients = vim.lsp.get_active_clients({
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
		"-c",
		string.format([[import sys; sys.path.insert(0, '%s'); from annotation_lsp.__main__ import main; main()]], plugin_root)
	}
	
	-- 启动 LSP 服务器
	local client_id = vim.lsp.start_client({
		name = "annotation_ls",
		cmd = python_cmd,
		root_dir = vim.fn.getcwd(),
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
		"-c",
		string.format([[import sys; sys.path.insert(0, '%s'); from annotation_lsp.__main__ import main; main()]], plugin_root)
	}
	
	-- 注册自定义 LSP
	if not configs.annotation_ls then
		configs.annotation_ls = {
			default_config = {
				cmd = python_cmd,
				filetypes = { 'markdown', 'text', 'annot' },
				root_dir = function(fname)
					return lspconfig.util.find_git_ancestor(fname) or vim.fn.getcwd()
				end,
				settings = {},
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
