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

	logger.setup({
		debug = opts.debug or false,
		level = opts.log_level,
		prefix = opts.log_prefix or "[annotation-tool]"
	})

	if logger.is_debug() then
		logger.debug("插件初始化，调试模式已启用")
		logger.debug_obj("配置选项", opts)
	end

	lsp.setup(opts)
	commands.setup()
end

return M
