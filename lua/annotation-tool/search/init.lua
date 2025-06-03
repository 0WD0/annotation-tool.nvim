local M = {}

-- 延迟加载依赖，避免循环依赖
local function load_deps()
	local lsp = require('annotation-tool.lsp')
	local core = require('annotation-tool.core')
	local preview = require('annotation-tool.preview')
	local logger = require('annotation-tool.logger')

	return {
		lsp = lsp,
		core = core,
		preview = preview,
		logger = logger
	}
end

-- 搜索范围枚举
M.SCOPE = {
	CURRENT_FILE = 'current_file',
	CURRENT_PROJECT = 'current_project',
	ALL_PROJECTS = 'all_projects'
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
---@param scope string 搜索范围 (current_file | current_project | all_projects)
---@param callback function 回调函数，接收 (err, annotations) 参数
local function fetch_annotations_by_scope(scope, callback)
	if scope == M.SCOPE.CURRENT_FILE then
		-- 当前文件搜索 - 使用现有的 listAnnotations 命令
		vim.lsp.buf_request(0, 'workspace/executeCommand', {
			command = "listAnnotations",
			arguments = { {
				textDocument = vim.lsp.util.make_text_document_params()
			} }
		}, callback)
	elseif scope == M.SCOPE.CURRENT_PROJECT then
		-- 当前项目搜索 - 需要新的 LSP 命令
		vim.lsp.buf_request(0, 'workspace/executeCommand', {
			command = "listProjectAnnotations",
			arguments = { {
				textDocument = vim.lsp.util.make_text_document_params()
			} }
		}, callback)
	elseif scope == M.SCOPE.ALL_PROJECTS then
		-- 所有项目搜索 - 需要新的 LSP 命令
		vim.lsp.buf_request(0, 'workspace/executeCommand', {
			command = "listAllAnnotations",
			arguments = {}
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
		[M.SCOPE.CURRENT_PROJECT] = "当前项目",
		[M.SCOPE.ALL_PROJECTS] = "所有项目"
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
---@param options table 搜索选项 {scope: string, backend: string}
---  - scope: 搜索范围 (current_file | current_project | all_projects)
---  - backend: 使用的后端 (telescope | fzf-lua)，默认为 telescope
function M.find_annotations(options)
	options = options or {}
	local scope = options.scope or M.SCOPE.CURRENT_FILE
	local backend_name = options.backend or M.BACKEND.TELESCOPE

	-- 检查前置条件
	if not check_annotation_mode() then return end
	if not get_lsp_client() then return end

	-- 获取后端
	local backend = get_backend(backend_name)
	if not backend then
		return
	end

	-- 获取标注数据
	fetch_annotations_by_scope(scope, function(err, result)
		if err then
			local deps = load_deps()
			deps.logger.error("获取标注列表失败: " .. vim.inspect(err))
			return
		end

		-- 调用后端进行搜索
		local search_options = {
			scope = scope,
			scope_display_name = get_scope_display_name(scope),
			annotations_result = result
		}

		backend.search_annotations(search_options)
	end)
end

-- 便捷方法
function M.find_current_file()
	M.find_annotations({ scope = M.SCOPE.CURRENT_FILE })
end

function M.find_current_project()
	M.find_annotations({ scope = M.SCOPE.CURRENT_PROJECT })
end

function M.find_all_projects()
	M.find_annotations({ scope = M.SCOPE.ALL_PROJECTS })
end

return M
