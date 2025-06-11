local M = {}

-- 延迟加载依赖，避免循环依赖
local function load_deps()
	local lsp = require('annotation-tool.lsp')
	local core = require('annotation-tool.core')
	local preview = require('annotation-tool.preview')
	local logger = require('annotation-tool.logger')
	local config = require('annotation-tool.config')

	return {
		lsp = lsp,
		core = core,
		preview = preview,
		logger = logger,
		config = config
	}
end

-- 搜索范围枚举
M.SCOPE = {
	CURRENT_FILE = 'currnt_file',
	CURRENT_WORKSPACE = 'current_workspace',
	CURRENT_PROJECT = 'current_project'
}

-- 后端枚举
M.BACKEND = {
	TELESCOPE = 'telescope',
	FZF_LUA = 'fzf-lua'
}

---检查当前缓冲区是否已启用标注模式。
---@return boolean 若已启用标注模式则返回 true，否则返回 false。未启用时会记录警告日志。
local function check_annotation_mode()
	local deps = load_deps()
	if not vim.b.annotation_mode then
		deps.logger.warn("请先启用标注模式（:AnnotationEnable）")
		return false
	end
	return true
end

---获取 LSP 客户端并检查连接状态
---@return table|nil LSP 客户端对象，失败时返回 nil
local function get_lsp_client()
	local deps = load_deps()
	local client = deps.lsp.get_client()
	if not client then
		deps.logger.error("LSP 客户端未连接")
		return nil
	end
	return client
end

---根据搜索范围获取标注数据
---@param scope string 搜索范围 (current_file | current_workspace | current_project)
---@param callback function 回调函数，接收 (err, annotations) 参数
local function fetch_annotations_by_scope(scope, callback)
	if vim.tbl_contains(M.SCOPE, scope) then
		-- 当前文件搜索 - 使用现有的 listAnnotations 命令
		vim.lsp.buf_request(0, 'workspace/executeCommand', {
			command = "queryAnnotations",
			arguments = { {
				textDocument = vim.lsp.util.make_text_document_params(),
				scope = scope
			} }
		}, callback)
	else
		callback({ message = "不支持的搜索范围: " .. scope }, nil)
	end
end

---获取搜索范围的显示名称
---@param scope string 搜索范围
---@return string 显示名称
local function get_scope_display_name(scope)
	local scope_names = {
		[M.SCOPE.CURRENT_FILE] = "当前文件",
		[M.SCOPE.CURRENT_WORKSPACE] = "当前工作区",
		[M.SCOPE.CURRENT_PROJECT] = "当前项目"
	}
	return scope_names[scope] or "未知范围"
end

-- 加载后端模块
local backends = {}

---获取或加载后端模块
---@param backend_name string 后端名称
---@return table|nil 后端模块，失败时返回 nil
local function get_backend(backend_name)
	if backends[backend_name] then
		return backends[backend_name]
	end

	local deps = load_deps()

	if backend_name == M.BACKEND.TELESCOPE then
		local ok, telescope_backend = pcall(require, 'annotation-tool.search.telescope')
		if ok then
			backends[backend_name] = telescope_backend
			return telescope_backend
		else
			deps.logger.error("无法加载 telescope 后端: " .. telescope_backend)
			return nil
		end
	elseif backend_name == M.BACKEND.FZF_LUA then
		local ok, fzf_backend = pcall(require, 'annotation-tool.search.fzf_lua')
		if ok then
			backends[backend_name] = fzf_backend
			return fzf_backend
		else
			deps.logger.error("无法加载 fzf-lua 后端: " .. fzf_backend)
			return nil
		end
	else
		deps.logger.error("不支持的后端: " .. backend_name)
		return nil
	end
end



---统一的标注搜索接口
---@param options? table 搜索选项 {scope: string, backend: string}
---  - scope: 搜索范围 (current_file | current_workspace | current_project)，默认使用配置中的智能范围
---  - backend: 使用的后端 (telescope | fzf-lua)，默认使用配置中的最佳后端
function M.find_annotations(options)
	options = options or {}
	local deps = load_deps()
	local config = deps.config

	-- 直接使用配置系统获取默认值
	local scope = options.scope or config.get_smart_scope()
	local backend_name = options.backend

	-- 如果没有指定后端，使用配置系统的最佳后端
	if not backend_name then
		backend_name = config.get_best_backend()
	elseif not config.is_backend_available(backend_name) then
		deps.logger.warn("指定的后端 " .. backend_name .. " 不可用，使用最佳可用后端")
		backend_name = config.get_best_backend()
	end

	-- 检查前置条件
	if not check_annotation_mode() then return end
	if not get_lsp_client() then return end

	-- 检查后端是否可用
	if not backend_name then
		deps.logger.error("没有可用的搜索后端，请安装 telescope.nvim 或 fzf-lua")
		return
	end

	-- 获取后端
	local backend = get_backend(backend_name)
	if not backend then
		return
	end

	-- 获取标注数据
	fetch_annotations_by_scope(scope, function(err, result)
		if err then
			deps.logger.error("获取标注列表失败: " .. vim.inspect(err))
			return
		end

		deps.logger.debug_obj("获取到的标注数据", result)
		-- 调用后端进行搜索
		local search_options = {
			scope = scope,
			scope_display_name = get_scope_display_name(scope),
			annotations_result = result,
			backend_name = backend_name
		}

		backend.search_annotations(search_options)
	end)
end

-- 便捷方法
function M.find_current_file(backend)
	M.find_annotations({ scope = M.SCOPE.CURRENT_FILE, backend = backend })
end

function M.find_current_workspace(backend)
	M.find_annotations({ scope = M.SCOPE.CURRENT_WORKSPACE, backend = backend })
end

function M.find_current_project(backend)
	M.find_annotations({ scope = M.SCOPE.CURRENT_PROJECT, backend = backend })
end

-- 智能搜索 - 使用配置中的智能后端和范围选择
function M.smart_find()
	M.find_annotations() -- 使用默认的智能选择
end

-- 强制使用特定后端的搜索方法
function M.find_with_telescope(scope)
	M.find_annotations({ scope = scope, backend = M.BACKEND.TELESCOPE })
end

function M.find_with_fzf_lua(scope)
	M.find_annotations({ scope = scope, backend = M.BACKEND.FZF_LUA })
end

return M
