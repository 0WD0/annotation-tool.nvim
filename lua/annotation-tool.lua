local M = {}

-- 获取 Python 解释器路径
local function get_python_path()
	-- 获取当前文件所在目录
	local current_file = debug.getinfo(1, "S").source:sub(2)  -- 移除开头的 '@'
	local plugin_root = vim.fn.fnamemodify(current_file, ":h:h")  -- 上级目录就是插件根目录
	
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

-- 初始化插件
M.setup = function(opts)
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
		on_attach = function(client, bufnr)
			-- 设置 buffer 的按键映射
			vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>a', '<cmd>lua require("annotation-tool").create_annotation()<CR>', { noremap = true, silent = true })
			vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>f', '<cmd>lua require("annotation-tool").find_annotations()<CR>', { noremap = true, silent = true })
			vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Leader>p', '<cmd>lua require("annotation-tool").setup_annotation_preview()<CR>', { noremap = true, silent = true })
			vim.api.nvim_buf_set_keymap(bufnr, 'n', 'K', '<cmd>lua vim.lsp.buf.hover()<CR>', { noremap = true, silent = true })

			-- 启用标注模式
			vim.b.annotation_mode = true

			-- 设置其他 LSP 相关的配置
			vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

			-- 启用文档高亮
			if client.server_capabilities.documentHighlightProvider then
				vim.cmd [[
					augroup lsp_document_highlight
					autocmd! * <buffer>
					autocmd CursorHold <buffer> lua vim.lsp.buf.document_highlight()
					autocmd CursorMoved <buffer> lua vim.lsp.buf.clear_references()
					augroup END
				]]
			end

			vim.notify("LSP attached successfully", vim.log.levels.INFO)
		end,

		capabilities = vim.lsp.protocol.make_client_capabilities(),

		settings = vim.tbl_deep_extend("force", {
			annotation = {
				saveDir = vim.fn.expand('~/.local/share/nvim/annotation-notes'),
			}
		}, opts.settings or {})
	})

	-- 设置命令
	M.setup_commands()

	-- 设置自动命令：当打开支持的文件类型时自动启用 LSP
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "markdown", "text", "annot" },
		callback = function(args)
			local clients = vim.lsp.get_active_clients({
				bufnr = args.buf,
				name = "annotation_ls"
			})
			
			if #clients == 0 then
				vim.notify("Auto-attaching LSP to buffer...", vim.log.levels.INFO)
				lspconfig.annotation_ls.setup({})  -- 使用 lspconfig 的 setup 方法
			end
		end,
	})
end

-- 启用标注模式
M.enable_annotation_mode = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')

	if filetype ~= 'markdown' and filetype ~= 'text' and filetype ~= 'annot' then
		vim.notify("Annotation mode only works with markdown, text and annot files", vim.log.levels.WARN)
		return
	end

	-- 如果 LSP 客户端还没有启动，启动它
	local clients = vim.lsp.get_active_clients({
		bufnr = bufnr,
		name = "annotation_ls"
	})

	if #clients == 0 then
		-- 确保 LSP 配置已经设置
		require('annotation-tool').setup()
		-- LSP 会自动 attach 到合适的 buffer
	end

	vim.b.annotation_mode = true
	vim.notify("Annotation mode enabled", vim.log.levels.INFO)
end

-- 切换annotation mode
M.toggle_annotation_mode = function()
	local buf = vim.api.nvim_get_current_buf()
	local enabled = vim.b[buf].annotation_mode

	if enabled then
		-- 禁用annotation mode
		vim.b[buf].annotation_mode = false
		-- 禁用concealment
		vim.wo.conceallevel = 0
	else
		-- 启用annotation mode
		vim.b[buf].annotation_mode = true
		-- 启用concealment来隐藏特殊括号
		vim.wo.conceallevel = 2
		-- 设置conceal规则
		vim.cmd([[syntax match AnnotationBracket "｢\|｣" conceal]])
	end
end

-- 创建新标注
function M.create_annotation()
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_active_clients({
        bufnr = bufnr,
        name = "annotation_ls"
    })

    if #clients == 0 then
        vim.notify("LSP not attached", vim.log.levels.ERROR)
        return
    end

    -- 获取当前选中的范围
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    
    -- 创建请求参数
    local params = {
        textDocument = {
            uri = vim.uri_from_bufnr(bufnr)
        },
        range = {
            start = {
                line = start_pos[2] - 1,
                character = start_pos[3] - 1
            },
            ['end'] = {
                line = end_pos[2] - 1,
                character = end_pos[3] - 1
            }
        }
    }

    -- 发送请求到 LSP 服务器
    clients[1].request('textDocument/createAnnotation', params, function(err, result)
        if err then
            vim.notify("Failed to create annotation: " .. vim.inspect(err), vim.log.levels.ERROR)
            return
        end
        if result and result.success then
            vim.notify("Annotation created successfully", vim.log.levels.INFO)
        end
    end, bufnr)
end

-- 使用telescope进行标注搜索
M.find_annotations = function()
	if not vim.b.annotation_mode then
		vim.notify("Please enable annotation mode first", vim.log.levels.WARN)
		return
	end

	local pickers = require('telescope.pickers')
	local finders = require('telescope.finders')
	local conf = require('telescope.config').values
	local actions = require('telescope.actions')
	local action_state = require('telescope.actions.state')

	-- 从LSP服务器获取所有标注
	vim.lsp.buf_request(0, 'workspace/annotations', {}, function(err, result, ctx, config)
		if err then
			vim.notify("Failed to get annotations: " .. err.message, vim.log.levels.ERROR)
			return
		end

		if not result or #result == 0 then
			vim.notify("No annotations found", vim.log.levels.INFO)
			return
		end

		pickers.new({}, {
			prompt_title = 'Find Annotations',
			finder = finders.new_table({
				results = result,
				entry_maker = function(entry)
					return {
						value = entry,
						display = string.format("%s: %s", entry.file, entry.content),
						ordinal = string.format("%s %s %s", entry.file, entry.content, entry.note or ""),
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()

					-- 打开文件并跳转到标注位置
					vim.cmd('edit ' .. selection.value.file)
					vim.api.nvim_win_set_cursor(0, {
						selection.value.range.start.line + 1,
						selection.value.range.start.character
					})

					-- 如果有预览窗口，更新预览内容
					if vim.g.annotation_preview_win and vim.api.nvim_win_is_valid(vim.g.annotation_preview_win) then
						M.update_annotation_preview()
					end
				end)
				return true
			end,
		}):find()
	end)
end

-- 在右侧打开标注预览窗口
M.setup_annotation_preview = function()
	if not vim.b.annotation_mode then
		vim.notify("Please enable annotation mode first", vim.log.levels.WARN)
		return
	end

	-- 如果预览窗口已经存在，关闭它
	if vim.g.annotation_preview_win and vim.api.nvim_win_is_valid(vim.g.annotation_preview_win) then
		vim.api.nvim_win_close(vim.g.annotation_preview_win, true)
		vim.g.annotation_preview_win = nil
		vim.g.annotation_preview_buf = nil
		return
	end

	-- 创建新窗口
	local width = math.floor(vim.o.columns * 0.3)
	vim.cmd('botright vsplit')
	vim.cmd('vertical resize ' .. width)

	-- 设置窗口选项
	local win = vim.api.nvim_get_current_win()
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].wrap = true
	vim.wo[win].signcolumn = 'no'
	vim.wo[win].foldcolumn = '0'
	vim.wo[win].winfixwidth = true

	-- 创建新buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, buf)

	-- 设置buffer选项
	vim.bo[buf].filetype = 'markdown'
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = 'wipe'

	-- 保存窗口和buffer的ID
	vim.g.annotation_preview_win = win
	vim.g.annotation_preview_buf = buf

	-- 返回到原始窗口
	vim.cmd('wincmd p')

	-- 设置自动命令以更新预览内容
	vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
		buffer = vim.api.nvim_get_current_buf(),
		callback = function()
			M.update_annotation_preview()
		end,
	})

	-- 立即更新预览内容
	M.update_annotation_preview()
end

-- 更新标注预览窗口的内容
M.update_annotation_preview = function()
	local win = vim.g.annotation_preview_win
	local buf = vim.g.annotation_preview_buf

	if not win or not buf or not vim.api.nvim_win_is_valid(win) then
		return
	end

	-- 获取当前光标位置
	local cursor = vim.api.nvim_win_get_cursor(0)
	local params = {
		textDocument = {
			uri = vim.uri_from_bufnr(0)
		},
		position = {
			line = cursor[1] - 1,
			character = cursor[2]
		}
	}

	-- 从LSP服务器获取当前位置的标注
	vim.lsp.buf_request(0, 'textDocument/annotation', params, function(err, result, ctx, config)
		if err then
			return
		end

		if result then
			-- 更新预览窗口内容
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
				"# Annotation",
				"",
				"> " .. result.content,
				"",
				result.note or ""
			})
			vim.bo[buf].modifiable = false
		else
			-- 清空预览窗口
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
				"No annotation at cursor"
			})
			vim.bo[buf].modifiable = false
		end
	end)
end

-- 手动 attach LSP 到当前 buffer
M.attach_lsp = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')

	if filetype ~= 'markdown' and filetype ~= 'text' and filetype ~= 'annot' then
		vim.notify("Annotation LSP only works with markdown, text and annot files", vim.log.levels.WARN)
		return
	end

	-- 检查 LSP 是否已经 attach
	local clients = vim.lsp.get_active_clients({
		bufnr = bufnr,
		name = "annotation_ls"
	})

	if #clients > 0 then
		vim.notify("LSP already attached to this buffer", vim.log.levels.INFO)
		return
	end

	-- 确保 LSP 配置已经设置
	if not require('lspconfig.configs').annotation_ls then
		require('annotation-tool').setup()
	end

	-- 手动启动 LSP 客户端并 attach 到当前 buffer
	lspconfig.annotation_ls.setup({})  -- 使用 lspconfig 的 setup 方法
end

-- 创建用户命令
M.setup_commands = function()
	vim.api.nvim_create_user_command('AnnotationLspAttach', function()
		require('annotation-tool').attach_lsp()
	end, {})

	vim.api.nvim_create_user_command('AnnotationModeEnable', function()
		require('annotation-tool').enable_annotation_mode()
	end, {})

	vim.api.nvim_create_user_command('AnnotationModeDisable', function()
		local bufnr = vim.api.nvim_get_current_buf()
		vim.b[bufnr].annotation_mode = false
		vim.wo.conceallevel = 0
		vim.cmd([[syntax clear AnnotationBracket]])
		vim.notify("Annotation mode disabled", vim.log.levels.INFO)
	end, {})

	vim.api.nvim_create_user_command('AnnotationModeToggle', function()
		require('annotation-tool').toggle_annotation_mode()
	end, {})
end

return M
