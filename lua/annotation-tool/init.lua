local M = {}

-- 导入所有模块
local core = require('annotation-tool.core')
local lsp = require('annotation-tool.lsp')
local preview = require('annotation-tool.preview')
local telescope = require('annotation-tool.telescope')
local commands = require('annotation-tool.commands')

-- 暴露主要函数
-- M.setup = lsp.setup
M.enable = lsp.attach
M.create_annotation = lsp.create_annotation
M.list_annotations = lsp.list_annotations
M.delete_annotation = lsp.delete_annotation
M.find_annotations = telescope.find
M.setup_preview = preview.setup
M.toggle_mode = core.toggle_mode

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
				local clients = vim.lsp.get_active_clients({
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
end

return M
