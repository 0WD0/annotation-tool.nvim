local core = require('annotation-tool.core')
local M = {}

-- 保存预览窗口的信息
local preview_state = {
	win = nil,  -- 窗口 ID
	buf = nil,  -- Buffer ID
}

-- 关闭预览窗口
function M.close_preview(force)
	if preview_state.buf and vim.api.nvim_buf_is_valid(preview_state.buf) then
		-- 如果不是强制关闭且 buffer 被修改了，保存它
		if not force and vim.bo[preview_state.buf].modified then
			vim.api.nvim_buf_call(preview_state.buf, function()
				vim.cmd('write')
			end)
		end
		-- 关闭 buffer，force 为 true 时强制关闭
		vim.api.nvim_buf_delete(preview_state.buf, { force = force })
	end
	if preview_state.win and vim.api.nvim_win_is_valid(preview_state.win) then
		vim.api.nvim_win_close(preview_state.win, true)
	end
	preview_state.win = nil
	preview_state.buf = nil
end

-- 检查当前预览的是否是指定的文件
function M.is_previewing(note_file)
	if not preview_state.buf or not vim.api.nvim_buf_is_valid(preview_state.buf) then
		return false
	end
	local buf_name = vim.api.nvim_buf_get_name(preview_state.buf)
	return buf_name:match("/.annotation/notes/" .. note_file .. "$") ~= nil
end

-- 设置预览窗口
function M.setup_preview_window(file_path, client)
	-- 在右侧打开文件
	vim.cmd('vsplit ' .. vim.fn.fnameescape(file_path))

	-- 保存新的预览窗口信息
	preview_state.win = vim.api.nvim_get_current_win()
	preview_state.buf = vim.api.nvim_get_current_buf()

	-- 设置窗口大小
	vim.cmd('vertical resize ' .. math.floor(vim.o.columns * 0.4))

	-- 设置窗口选项
	vim.wo[preview_state.win].number = true
	vim.wo[preview_state.win].relativenumber = false
	vim.wo[preview_state.win].wrap = true
	vim.wo[preview_state.win].winfixwidth = true

	-- 设置 buffer 选项
	vim.bo[preview_state.buf].filetype = 'markdown'

	-- 跳转到笔记部分
	vim.cmd([[
		normal! G
		?^## Notes
		normal! 2j
	]])

	-- 当预览窗口关闭时，清除状态
	vim.api.nvim_create_autocmd('WinClosed', {
		pattern = tostring(preview_state.win),
		callback = function()
			preview_state.win = nil
			preview_state.buf = nil
		end,
		once = true
	})

	-- 设置快捷键
	vim.api.nvim_buf_set_keymap(preview_state.buf, 'n', '[a', '', {
		callback = function() M.goto_annotation_source(client, -1) end,
		noremap = true,
		silent = true,
		desc = "Go to previous annotation"
	})
	vim.api.nvim_buf_set_keymap(preview_state.buf, 'n', ']a', '', {
		callback = function() M.goto_annotation_source(client, 1) end,
		noremap = true,
		silent = true,
		desc = "Go to next annotation"
	})

	return preview_state.buf
end

function M.goto_annotation_source(client, offset)
	if not preview_state.buf or not vim.api.nvim_buf_is_valid(preview_state.buf) then
		vim.notify("No preview window open", vim.log.levels.WARN)
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
			vim.notify("Error getting annotation source: " .. err.message, vim.log.levels.ERROR)
			return
		end

		if not result then
			vim.notify("No annotation source found", vim.log.levels.WARN)
			return
		end

		-- 如果预览窗口已存在，先关闭它
		M.close_preview(false)

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
		vim.cmd('edit ' .. result.source_path)
		vim.api.nvim_win_set_cursor(source_win, {result.position.line + 1, result.position.character})

		-- 设置预览窗口
		local file_path = result.workspace_path .. '/.annotation/notes/' .. result.note_file
		M.setup_preview_window(file_path, client)
	end)
end

function M.goto_annotation_note(client,result)
	-- 如果预览窗口已存在，先关闭它
	M.close_preview(false)
	-- 设置新的预览窗口
	local file_path = result.workspace_path .. '/.annotation/notes/' .. result.note_file
	local buf = M.setup_preview_window(file_path, client)
	if not buf then
		vim.notify("Failed to open preview window", vim.log.levels.ERROR)
		return
	end
end

function M.goto_current_annotation_note(client)
	local params = core.make_position_params()
	vim.notify("Getting annotation note...", vim.log.levels.INFO)

	-- 使用 LSP 命令获取批注文件
	client.request('workspace/executeCommand', {
		command = "getAnnotationNote",
		arguments = { params }
	}, function(err, result)
		if err then
			vim.notify("Error getting annotation note: " .. err.message, vim.log.levels.ERROR)
			return
		end

		if not result then
			vim.notify("No annotation note found", vim.log.levels.WARN)
			return
		end
		M.goto_annotation_note(client,result)
	end)
end

return M
