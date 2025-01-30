local core = require('annotation-tool.core')
local M = {}

-- 在右侧打开批注文件
function M.setup()
	if not vim.b.annotation_mode then
		vim.notify("Please enable annotation mode first", vim.log.levels.WARN)
		return
	end

	local params = core.make_position_params()

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
			local Split = require("nui.split")
			local split = Split({
				relative = "editor",
				position = "right",
				size = width,
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

			-- 读取文件内容
			local lines = vim.fn.readfile(result.note_file)
			vim.api.nvim_buf_set_lines(split.bufnr, 0, -1, false, lines)

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
		else
			vim.notify("No annotation found at cursor position", vim.log.levels.INFO)
		end
	end)
end


--[[
local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event

--- 创建一个可编辑的预览窗口
---@param opts table 窗口选项
---   - filename: string 文件名，用于设置 filetype
---   - content: string 初始内容
---   - on_submit: function 保存时的回调函数，参数为修改后的内容
---   - on_close: function 关闭时的回调函数
function M.create_preview_window(opts)
	local popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = " " .. opts.filename .. " ",
				top_align = "center",
			},
		},
		position = "50%",
		size = {
			width = "80%",
			height = "60%",
		},
		buf_options = {
			modifiable = true,
			readonly = false,
		},
		win_options = {
			wrap = true,
			cursorline = true,
			winblend = 10,
			winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
		},
	})

	-- 挂载窗口
	popup:mount()

	-- 设置内容
	vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, vim.split(opts.content, "\n"))

	-- 如果有文件类型，设置文件类型
	if opts.filename:match("%.(%w+)$") then
		vim.api.nvim_buf_set_option(popup.bufnr, "filetype", opts.filename:match("%.(%w+)$"))
	end

	-- 设置按键映射
	popup:map("n", "<ESC>", function()
		if opts.on_close then
			opts.on_close()
		end
		popup:unmount()
	end, { noremap = true })

	popup:map("n", "q", function()
		if opts.on_close then
			opts.on_close()
		end
		popup:unmount()
	end, { noremap = true })

	popup:map("n", "<C-s>", function()
		local content = table.concat(vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false), "\n")
		if opts.on_submit then
			opts.on_submit(content)
		end
	end, { noremap = true })

	-- 设置自动命令
	popup:on(event.BufLeave, function()
		if opts.on_close then
			opts.on_close()
		end
		popup:unmount()
	end)

	return popup
end
--]]

return M
