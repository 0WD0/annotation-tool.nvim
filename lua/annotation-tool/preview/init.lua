local core = require('annotation-tool.core')
local logger = require('annotation-tool.logger')
local M = {}

-- 保存预览窗口的信息
M.preview_state = {
	win = nil,  -- 窗口 ID
	buf = nil,  -- Buffer ID
}

-- 关闭预览窗口
function M.close_preview(force)
	if M.preview_state.buf and vim.api.nvim_buf_is_valid(M.preview_state.buf) then
		-- 如果不是强制关闭且 buffer 被修改了，保存它
		if not force and vim.bo[M.preview_state.buf].modified then
			vim.api.nvim_buf_call(M.preview_state.buf, function()
				vim.cmd('write')
			end)
		end
		-- 关闭 buffer，force 为 true 时强制关闭
		vim.api.nvim_buf_delete(M.preview_state.buf, { force = force })
	end
	if M.preview_state.win and vim.api.nvim_win_is_valid(M.preview_state.win) then
		vim.api.nvim_win_close(M.preview_state.win, true)
	end
	M.preview_state.win = nil
	M.preview_state.buf = nil
end

-- 检查当前预览的是否是指定的文件
function M.is_previewing(note_file)
	if not M.preview_state.buf or not vim.api.nvim_buf_is_valid(M.preview_state.buf) then
		return false
	end
	local buf_name = vim.api.nvim_buf_get_name(M.preview_state.buf)
	return buf_name:match("/.annotation/notes/" .. note_file .. "$") ~= nil
end

-- 设置预览窗口
function M.setup_preview_window(file_path)
	-- 在右侧打开文件
	vim.cmd('vsplit ' .. vim.fn.fnameescape(file_path))

	-- 保存新的预览窗口信息
	M.preview_state.win = vim.api.nvim_get_current_win()
	M.preview_state.buf = vim.api.nvim_get_current_buf()

	-- 设置窗口大小
	vim.cmd('vertical resize ' .. math.floor(vim.o.columns * 0.4))

	-- 设置窗口选项
	vim.wo[M.preview_state.win].number = true
	vim.wo[M.preview_state.win].relativenumber = false
	vim.wo[M.preview_state.win].wrap = true
	vim.wo[M.preview_state.win].winfixwidth = true

	-- 设置 buffer 选项
	vim.bo[M.preview_state.buf].filetype = 'markdown'

	-- 跳转到笔记部分
	vim.cmd([[
		normal! G
		?^## Notes
		normal! 2j
	]])

	-- 当预览窗口关闭时，清除状态
	vim.api.nvim_create_autocmd('WinClosed', {
		pattern = tostring(M.preview_state.win),
		callback = function()
			M.preview_state.win = nil
			M.preview_state.buf = nil
		end,
		once = true
	})


	return M.preview_state.buf
end

function M.goto_annotation_note(result)
	-- 如果预览窗口已存在，先关闭它
	-- TODO: 如果在 nodes 中发现已经打开了这个 note_file ，直接跳转到那个 buffer
	M.close_preview(false)
	-- 设置新的预览窗口
	local file_path = result.workspace_path .. '/.annotation/notes/' .. result.note_file
	local buf = M.setup_preview_window(file_path)
	if not buf then
		logger.error("Failed to open preview window")
		return
	end
end

function M.goto_current_annotation_note()
	local params = core.make_position_params()
	logger.info("Getting annotation note...")

	-- 延迟加载 lsp 模块，避免循环依赖
	local lsp = require('annotation-tool.lsp')
	local client = lsp.get_client()
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
		M.goto_annotation_note(result)
	end)
end

return M
