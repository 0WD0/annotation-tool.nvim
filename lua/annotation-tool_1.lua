local M = {}

-- 检查是否为 markdown 文件
local function is_markdown_file()
	return vim.bo.filetype == "markdown"
end

-- 获取 LSP 客户端
local function get_lsp_client()
	local clients = vim.lsp.get_active_clients({
		name = "annotation_ls"
	})
	
	if #clients == 0 then
		vim.notify("LSP not attached", vim.log.levels.ERROR)
		return nil
	end
	
	return clients[1]
end

-- 获取选中区域
local function get_visual_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	
	if start_pos[2] == 0 or end_pos[2] == 0 then
		vim.notify("No text selected", vim.log.levels.ERROR)
		return nil
	end
	
	return {
		start = {
			line = start_pos[2] - 1,
			character = start_pos[3] - 1
		},
		['end'] = {
			line = end_pos[2] - 1,
			character = end_pos[3] - 1
		}
	}
end

-- 启用标注模式
function M.enable()
	if not is_markdown_file() then
		vim.notify("Not a markdown file", vim.log.levels.ERROR)
		return
	end
	
	if vim.b.annotation_mode then
		vim.notify("Annotation mode already enabled", vim.log.levels.WARN)
		return
	end
	
	-- 设置标注模式标志
	vim.b.annotation_mode = true
	
	-- 启动 LSP 服务器
	local cmd = {"python", "-m", "annotation_lsp"}
	
	-- 配置 LSP 客户端
	local client_id = vim.lsp.start({
		name = "annotation_ls",
		cmd = cmd,
		root_dir = vim.fn.getcwd(),
		flags = {
			debounce_text_changes = 150,
		}
	})
	
	if not client_id then
		vim.notify("Failed to start LSP server", vim.log.levels.ERROR)
		return
	end
	
	vim.notify("Annotation mode enabled", vim.log.levels.INFO)
end

-- 创建标注
function M.create_annotation()
	local client = get_lsp_client()
	if not client then
		return
	end
	
	local range = get_visual_selection()
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
	local client = get_lsp_client()
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
	local client = get_lsp_client()
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

-- 设置快捷键
function M.setup()
	-- 检查是否为 markdown 文件
	if not is_markdown_file() then
		return
	end
	
	-- 设置快捷键
	vim.keymap.set('n', '<Leader>na', function()
		vim.cmd('normal! viw')  -- 选中当前单词
		M.create_annotation()
	end, { buffer = true, desc = "Create annotation" })
	
	vim.keymap.set('v', '<Leader>na', function()
		M.create_annotation()
	end, { buffer = true, desc = "Create annotation from selection" })
	
	vim.keymap.set('n', '<Leader>nl', function()
		M.list_annotations()
	end, { buffer = true, desc = "List annotations" })
	
	vim.keymap.set('n', 'K', vim.lsp.buf.hover, {
		buffer = true,
		desc = "Show annotation details"
	})
end

return M
