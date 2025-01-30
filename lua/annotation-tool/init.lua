local M = {}

local lsp = require('annotation-tool.lsp')
local core = require('annotation-tool.core')
local commands = require('annotation-tool.commands')
local telescope = require('annotation-tool.telescope')
local preview = require('annotation-tool.preview')

-- 暴露主要函数
M.enable = lsp.attach
M.create_annotation = lsp.create_annotation
M.list_annotations = lsp.list_annotations
M.delete_annotation = lsp.delete_annotation
M.find_annotations = telescope.find
M.setup_preview = preview.goto_annotation_note
M.enable_annotation_mode = core.enable_annotation_mode
M.disable_annotation_mode = core.disable_annotation_mode
M.toggle_annotation_mode = core.toggle_annotation_mode
M.show_conceal_rules = core.show_conceal_rules

-- 初始化插件
function M.setup(opts)
	opts = opts or {}

	-- 设置 LSP
	lsp.setup(opts)

	-- 设置命令
	commands.setup()

	-- 设置自动命令：当打开支持的文件类型时自动启用 LSP
	if opts.auto_attach == true then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "markdown", "text", "annot" },
			callback = function(args)
				local clients = vim.lsp.get_clients({
					bufnr = args.buf,
					name = "annotation_ls"
				})

				if #clients == 0 then
						vim.notify("Auto-attaching LSP to buffer...", vim.log.levels.INFO)
					lsp.attach()
				end
			end,
		})
	end

	-- 设置预览窗口
	if opts.preview == true then
		preview.goto_annotation_note()
	end
end

return M
