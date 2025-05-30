local M = {}
local core = require('annotation-tool.core')
local manager = require('annotation-tool.preview.manager')
local logger = require('annotation-tool.logger')

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
	vim.lsp.buf.document_highlight()
end

M.show_annotation_tree = manager.show_annotation_tree

-- LSP 回调函数
local function on_attach(client, bufnr)
	local base_options = { buffer = bufnr, noremap = true, silent = true }
	local keybindings = {
		{ mode = 'v', lhs = '<Leader>na', rhs = M.create_annotation,                       desc = "Create annotation at selection" },
		{ mode = 'n', lhs = '<Leader>nl', rhs = M.list_annotations,                        desc = "List annotations" },
		{ mode = 'n', lhs = '<Leader>nd', rhs = M.delete_annotation,                       desc = "Delete annotation at position" },
		{ mode = 'n', lhs = '<Leader>np', rhs = M.goto_current_annotation_note,            desc = "Preview current annotation" },
		{ mode = 'n', lhs = '<A-k>',      rhs = function() M.switch_annotation(-1) end,    desc = "Go to previous annotation" },
		{ mode = 'n', lhs = '<A-j>',      rhs = function() M.switch_annotation(1) end,     desc = "Go to next annotation" },
		{ mode = 'n', lhs = '<Leader>nh', rhs = function() M.goto_annotation_source() end, desc = "Go to annotation source" },
		{ mode = 'n', lhs = '<Leader>nt', rhs = M.show_annotation_tree,                  desc = "Show annotation tree" },
	}

	local ok, telescope_module = pcall(require, 'annotation-tool.telescope')
	if ok then
		table.insert(keybindings,
			{
				mode = 'n',
				lhs = '<Leader>nf',
				rhs = telescope_module.find_annotations,
				desc =
				"Find annotations with Telescope"
			})
		table.insert(keybindings,
			{
				mode = 'n',
				lhs = '<Leader>ns',
				rhs = telescope_module.search_annotations,
				desc =
				"Search annotation contents"
			})
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
	vim.api.nvim_set_hl(0, 'LspReferenceText', { underdouble = true, sp = '#85c1dc' }) -- 使用波浪线
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
			if result and result.note_files then
			  logger.info(('Found %d annotations'):format(#result.note_files))
			else
			  logger.warn('Server returned unexpected payload for listAnnotations: '
						  .. vim.inspect(result))
			end
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

	local params = vim.lsp.util.make_position_params(0,'utf-8')

	logger.debug('L' .. vim.inspect(params.position.line) .. 'C' .. vim.inspect(params.position.character))

	-- 直接显示确认对话框
	vim.ui.select({ "Yes", "No" }, {
		prompt = "Are you sure you want to delete this annotation?",
		kind = "confirmation"
	}, function(choice)
		if choice == "Yes" then
			-- 用户确认删除，执行删除操作
			client.request('workspace/executeCommand', {
				command = "deleteAnnotation",
				arguments = { params }
			}, function(err, result)
				if err then
					logger.error('Failed to delete annotation: ' .. vim.inspect(err))
				else
					local node_id = manager.find_node(result.note_file)
					if node_id then
						logger.info('Removing node ' .. node_id)
						manager.remove_node(node_id)
					end
					logger.info('Annotation deleted successfully')
				end
			end)
		else
			-- 用户取消删除
			logger.info('Annotation deletion cancelled by user')
		end
	end
	)
end

function M.goto_current_annotation_note()
	local client = M.get_client()
	if not client then
		logger.error("LSP client not available")
		return
	end

	logger.info("Getting annotation note...")
	local params = vim.lsp.util.make_position_params(0,'utf-8')
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

		local buf_id = vim.api.nvim_get_current_buf()
		local win_id = vim.api.nvim_get_current_win()
		local source_id = manager.create_source(buf_id, win_id, {
			workspace_path = result.workspace_path
		})
		manager.open_note_file(result.note_file, source_id, {
			workspace_path = result.workspace_path
		})
	end)
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
			logger.info("Annotation created successfully")
		end

		local buf_id = vim.api.nvim_get_current_buf()
		local win_id = vim.api.nvim_get_current_win()
		local source_id = manager.create_source(buf_id, win_id, {
			workspace_path = result.workspace_path
		})
		manager.open_note_file(result.note_file, source_id, {
			workspace_path = result.workspace_path
		})
	end)
end

function M.goto_annotation_source()
	-- 获取当前窗口和buffer
	local current_win = vim.api.nvim_get_current_win()
	local current_buf = vim.api.nvim_win_get_buf(current_win)

	-- 检查当前buffer是否是批注文件
	local buf_name = vim.api.nvim_buf_get_name(current_buf)
	if not buf_name:match("/.annotation/notes/") then
		logger.warn("Current buffer is not an annotation file")
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
				uri = vim.uri_from_bufnr(current_buf)
			},
			offset = 0
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

		-- 获取当前批注文件的节点ID
		local note_node_id = nil
		for node_id, node in pairs(manager.nodes) do
			if node.window == current_win and node.buffer == current_buf then
				note_node_id = node_id
				break
			end
		end

		-- 从注释跳转到源文件
		-- 在当前窗口打开源文件
		local source_buf = vim.fn.bufadd(result.source_path)
		vim.api.nvim_set_option_value('buflisted', true, { buf = source_buf })
		vim.api.nvim_win_set_buf(current_win, source_buf)

		-- 跳转到批注位置
		local cursor_pos = core.convert_utf8_to_bytes(0, result.position)
		vim.api.nvim_win_set_cursor(current_win, cursor_pos)

		-- 如果找到了批注文件的节点ID，更新节点关系
		if note_node_id then
			-- 获取当前源文件的window
			local source_win = vim.api.nvim_get_current_win()

			-- 创建源文件节点并与批注文件节点建立关系
			local source_node_id = manager.create_node(source_buf, source_win, nil, {
				type = "source",
				note_file = result.note_file,
				workspace_path = result.workspace_path
			})

			-- 将批注文件节点设为源文件节点的子节点
			if manager.nodes[note_node_id] then
				manager.nodes[note_node_id].parent = source_node_id
				if not manager.edges[source_node_id] then
					manager.edges[source_node_id] = {}
				end
				table.insert(manager.edges[source_node_id], note_node_id)
			end
		end
	end)
end

function M.switch_annotation(offset)
	-- 获取当前窗口和buffer
	local current_win = vim.api.nvim_get_current_win()
	local current_buf = vim.api.nvim_win_get_buf(current_win)

	-- 检查当前buffer是否是批注文件
	local buf_name = vim.api.nvim_buf_get_name(current_buf)
	if not buf_name:match("/.annotation/notes/") then
		logger.warn("Current buffer is not an annotation file")
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
				uri = vim.uri_from_bufnr(current_buf)
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

		-- 获取当前批注文件的节点ID
		local note_node_id = nil
		for node_id, node in pairs(manager.nodes) do
			if node.window == current_win and node.buffer == current_buf then
				note_node_id = node_id
				break
			end
		end

		-- 切换到上一个或下一个批注
		-- 复用当前窗口打开新的批注文件
		if result.note_file then
			-- 保存当前窗口和buffer，以便复用
			local note_win = current_win
			local annotation_buf = vim.api.nvim_get_current_buf()
			local annotation_win = vim.api.nvim_get_current_win()

			logger.debug("Switching to annotation " .. result.note_file)

			-- 使用 vim.api.nvim_win_set_buf 替代 vim.cmd('edit ...')
			local new_buf = vim.fn.bufadd(result.workspace_path .. '/.annotation/notes/' .. result.note_file)
			logger.debug("New buffer ID: " .. new_buf)
			vim.api.nvim_set_option_value('buflisted', true, { buf = new_buf })
			logger.debug("Set buflisted")
			vim.api.nvim_win_set_buf(annotation_win, new_buf)
			logger.debug("Set buffer")

			-- 跳转到笔记部分
			vim.cmd([[
				normal! G
				?^## Notes
				normal! 2j
			]])

			-- 更新节点关系
			if note_node_id then
				logger.debug("Switching to annotation " .. result.note_file)
				-- 获取新的批注文件buffer
				local new_note_buf = vim.api.nvim_get_current_buf()

				-- 创建新的批注文件节点
				local new_note_node_id = manager.create_node(new_note_buf, note_win, nil, {
					type = "annotation",
					workspace_path = result.workspace_path
				})
				logger.debug("New note node ID: " .. new_note_node_id)

				-- 如果原批注文件有父节点，将新节点也设为其子节点
				local parent_node_id = manager.get_parent(note_node_id)
				if parent_node_id then
					manager.nodes[new_note_node_id].parent = parent_node_id
					if not manager.edges[parent_node_id] then
						manager.edges[parent_node_id] = {}
					end
					table.insert(manager.edges[parent_node_id], new_note_node_id)
				end
			end

			logger.debug("Switched to annotation " .. result.note_file)
			manager.remove_node(annotation_buf .. '_' .. annotation_win, false)
			logger.debug("Removed node " .. annotation_buf .. '_' .. annotation_win)

			-- 如果有源文件信息，也更新源文件中的光标位置
			if result.source_path and result.position then
				-- 查找是否有源文件窗口
				local source_win = nil
				local source_buf = nil
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					local buf = vim.api.nvim_win_get_buf(win)
					local buf_name = vim.api.nvim_buf_get_name(buf)
					if buf_name == result.source_path then
						source_win = win
						source_buf = buf
						break
					end
				end

				-- 如果找到源文件窗口，更新光标位置
				if source_win then
					-- 保存当前窗口
					local current_win = vim.api.nvim_get_current_win()

					-- 切换到源文件窗口
					vim.api.nvim_set_current_win(source_win)

					-- 设置光标位置
					local cursor_pos = core.convert_utf8_to_bytes(source_buf, result.position)
					vim.api.nvim_win_set_cursor(source_win, cursor_pos)

					-- 更新高亮
					M.highlight()

					-- 切回原窗口
					vim.api.nvim_set_current_win(current_win)
				end
			end
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
		logger.error("LSP has not set up")
		return
	end
	logger.info("Attaching")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.lsp.buf_attach_client(bufnr, client_id)
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

	-- 设置 capabilities
	local capabilities = vim.lsp.protocol.make_client_capabilities()

	-- 如果有 cmp_nvim_lsp，使用它来增强 capabilities
	local has_cmp, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
	if has_cmp then
		capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
	end

	-- 增强文档高亮功能
	capabilities.textDocument.documentHighlight = {
		dynamicRegistration = false
	}

	-- 确保有完整的悬停功能支持
	capabilities.textDocument.hover = {
		dynamicRegistration = true,
		contentFormat = { 'markdown', 'plaintext' }
	}

	-- 注册自定义 LSP
	if not configs.annotation_ls then
		configs.annotation_ls = {
			default_config = {
				capabilities = capabilities,
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

				-- 获取目标缓冲区，默认为请求的缓冲区
				local target_bufnr = ctx.bufnr

				-- 检查是否有自定义的目标缓冲区
				if ctx.params and ctx.params._target_bufnr then
					target_bufnr = ctx.params._target_bufnr
				end

				-- 检查目标缓冲区是否有效
				if not vim.api.nvim_buf_is_valid(target_bufnr) then
					logger.warn("Invalid target buffer for highlight: " .. tostring(target_bufnr))
					return
				end

				local converted_result = {}
				for _, highlight in ipairs(result) do
					local byte_range = core.convert_utf8_to_bytes(target_bufnr, highlight.range)
					table.insert(converted_result, { range = byte_range })
				end

				vim.lsp.util.buf_highlight_references(
					target_bufnr,
					converted_result,
					'utf-8'
				)
			end
		}
	})
end

return M
