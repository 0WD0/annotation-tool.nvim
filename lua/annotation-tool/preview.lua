local core = require('annotation-tool.core')
local Split = require("nui.split")
local M = {}

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

		-- 使用 nui.split 创建分割窗口
		local split = Split({
			relative = "editor",
			position = "right",
			size = math.floor(vim.o.columns * 0.4),
			buf_options = {
				filetype = "markdown",
				modifiable = true,
			},
			win_options = {
				number = true,
				relativenumber = false,
				wrap = true,
				winfixwidth = true,
			},
		})

		-- 挂载窗口
		split:mount()

		-- 读取并设置文件内容
		local lines = vim.fn.readfile(full_path)
		if not lines then
			vim.notify("Failed to read note file: " .. full_path, vim.log.levels.ERROR)
			split:unmount()
			return
		end
		vim.api.nvim_buf_set_lines(split.bufnr, 0, -1, false, lines)

		-- 设置保存时的行为
		vim.api.nvim_buf_set_option(split.bufnr, 'buftype', 'acwrite')
		vim.api.nvim_create_autocmd('BufWriteCmd', {
			buffer = split.bufnr,
			callback = function()
				-- 获取内容
				local content = vim.api.nvim_buf_get_lines(split.bufnr, 0, -1, false)
				-- 写入文件
				local success = vim.fn.writefile(content, full_path) == 0
				if success then
					vim.notify("Note saved", vim.log.levels.INFO)
					vim.api.nvim_buf_set_option(split.bufnr, 'modified', false)
				else
					vim.notify("Failed to save note", vim.log.levels.ERROR)
				end
				return success
			end
		})

		-- 跳转到笔记部分
		vim.api.nvim_buf_call(split.bufnr, function()
			vim.cmd([[
				normal! G
				?^## Notes
				normal! 2j
			]])
		end)

		-- 返回到原始窗口
		vim.cmd('wincmd p')
	end)
end

return M
