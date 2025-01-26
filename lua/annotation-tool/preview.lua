local M = {}

-- 在右侧打开标注预览窗口
function M.setup()
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
			M.update()
		end,
	})

	-- 立即更新预览内容
	M.update()
end

-- 更新标注预览窗口的内容
function M.update()
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

return M
