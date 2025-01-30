local core = require('annotation-tool.core')
local M = {}

-- 保存预览窗口的信息
local preview_state = {
	win = nil,  -- 窗口 ID
	buf = nil,  -- Buffer ID
}

-- 关闭预览窗口
local function close_preview(force)
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

function M.setup(client)
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

		-- 构建完整的文件路径
		local full_path = result.workspace_path .. '/.annotation/notes/' .. result.note_file

		-- 保存当前窗口 ID
		local cur_win = vim.api.nvim_get_current_win()

		-- 如果预览窗口已存在，先关闭它
		close_preview(false)

		-- 在右侧打开文件
		vim.cmd('vsplit ' .. vim.fn.fnameescape(full_path))

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

		-- 返回到原始窗口
		vim.api.nvim_set_current_win(cur_win)

		-- 当预览窗口关闭时，清除状态
		vim.api.nvim_create_autocmd('WinClosed', {
			pattern = tostring(preview_state.win),
			callback = function()
				preview_state.win = nil
				preview_state.buf = nil
			end,
			once = true
		})
	end)
end

-- 导出关闭预览的函数
M.close_preview = close_preview

return M
