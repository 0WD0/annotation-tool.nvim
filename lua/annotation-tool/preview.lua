local M = {}

-- 在右侧打开批注文件
function M.setup()
	if not vim.b.annotation_mode then
		vim.notify("Please enable annotation mode first", vim.log.levels.WARN)
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

	-- 使用 LSP 命令获取批注文件
	vim.lsp.buf.execute_command({
		command = "getAnnotationNote",
		arguments = { params }
	}, function(err, result)
		if err then
			vim.notify("Failed to get annotation: " .. vim.inspect(err), vim.log.levels.ERROR)
			return
		end

		if result and result.note_file then
			-- 在右侧分割窗口中打开笔记文件
			local width = math.floor(vim.o.columns * 0.4)
			vim.cmd('botright vsplit ' .. vim.fn.fnameescape(result.note_file))
			vim.cmd('vertical resize ' .. width)
			
			-- 设置窗口选项
			local win = vim.api.nvim_get_current_win()
			vim.wo[win].number = true
			vim.wo[win].relativenumber = false
			vim.wo[win].wrap = true
			vim.wo[win].winfixwidth = true
			
			-- 设置buffer选项
			local buf = vim.api.nvim_get_current_buf()
			vim.bo[buf].filetype = 'markdown'
			
			-- 跳转到笔记部分
			vim.cmd([[
				normal! G
				?^## Notes
				normal! 2j
			]])
			
			-- 返回到原始窗口
			vim.cmd('wincmd p')
		else
			vim.notify("No annotation found at cursor position", vim.log.levels.INFO)
		end
	end)
end

return M
