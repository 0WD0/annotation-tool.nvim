local M = {}

local lsp = require('annotation-tool.lsp')
local core = require('annotation-tool.core')
local commands = require('annotation-tool.commands')
local pvw_manager = require('annotation-tool.preview.manager')
local search = require('annotation-tool.search')
local config = require('annotation-tool.config')
local logger = require('annotation-tool.logger')

-- 暴露主要函数
M.enable = lsp.attach
M.create_annotation = lsp.create_annotation
M.list_annotations = lsp.list_annotations
M.delete_annotation = lsp.delete_annotation
M.setup_preview = lsp.goto_current_annotation_note
M.enable_annotation_mode = core.enable_annotation_mode
M.disable_annotation_mode = core.disable_annotation_mode
M.toggle_annotation_mode = core.toggle_annotation_mode

-- 搜索相关函数
M.find_annotations = search.find_current_project
M.find_current_file = search.find_current_file
M.find_current_project = search.find_current_workspace
M.find_all_projects = search.find_current_project
M.smart_find = search.smart_find
M.find_with_telescope = search.find_with_telescope
M.find_with_fzf_lua = search.find_with_fzf_lua

-- 搜索常量
M.SCOPE = search.SCOPE
M.BACKEND = search.BACKEND

-- 配置相关函数
M.get_config = config.get
M.set_config = config.set
M.get_config_stats = config.get_stats
M.get_best_backend = config.get_best_backend
M.get_smart_scope = config.get_smart_scope
M.get_lsp_opts = config.get_lsp_opts

-- 初始化插件
function M.setup(opts)

	-- 设置配置系统
	config.setup(opts)

	-- 设置日志系统（从配置中获取设置）
	logger.setup({
		debug = config.get('debug.enabled'),
		level = config.get('debug.log_level'),
		prefix = config.get('debug.log_prefix')
	})

	if logger.is_debug() then
		logger.debug("插件初始化，调试模式已启用")
		logger.debug_obj("最终配置", config.get())
	end

	-- 初始化各模块
	lsp.setup()
	pvw_manager.setup()
	commands.setup()

	-- 显示配置统计信息
	if logger.is_debug() then
		local stats = config.get_stats()
		logger.debug_obj("配置统计", stats)
	end
end

return M
