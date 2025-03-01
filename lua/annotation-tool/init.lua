local M = {}

local lsp = require('annotation-tool.lsp')
local core = require('annotation-tool.core')
local commands = require('annotation-tool.commands')
local preview = require('annotation-tool.preview')
local logger = require('annotation-tool.logger')

-- 暴露主要函数
M.enable = lsp.attach
M.create_annotation = lsp.create_annotation
M.list_annotations = lsp.list_annotations
M.delete_annotation = lsp.delete_annotation
M.setup_preview = preview.goto_current_annotation_note
M.enable_annotation_mode = core.enable_annotation_mode
M.disable_annotation_mode = core.disable_annotation_mode
M.toggle_annotation_mode = core.toggle_annotation_mode
M.show_conceal_rules = core.show_conceal_rules

-- 初始化插件
function M.setup(opts)
	opts = opts or {}

	-- 设置日志
	logger.setup({
		debug = opts.debug or false,
		level = opts.log_level,
		prefix = opts.log_prefix or "[annotation-tool]"
	})

	if logger.is_debug() then
		logger.debug("插件初始化，调试模式已启用")
		logger.debug_obj("配置选项", opts)
	end

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
					logger.info("自动连接 LSP 到缓冲区...")
					lsp.attach()
				end
			end,
		})
	end

	-- 设置预览窗口
	if opts.preview == true then
		preview.goto_current_annotation_note()
	end
end

return M
