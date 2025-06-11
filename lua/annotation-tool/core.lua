local M = {}
local logger = require('annotation-tool.logger')

-- 检查当前文件类型是否为 markdown
function M.is_markdown_file()
	return vim.api.nvim_get_option_value('filetype', { buf = 0 }) == "markdown"
end

function M.get_visual_selection()
	-- 获取当前选区
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= 'v' and mode ~= 'V' then
		logger.warn("Please select text in visual mode or visual line mode first")
		return nil
	end

	local start_pos = vim.fn.getpos('v')
	local end_pos = vim.fn.getpos('.')

	if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
		start_pos, end_pos = end_pos, start_pos
	end

	if mode == 'V' then
		start_pos[3] = 1
		end_pos[3] = vim.fn.col({ end_pos[2], '$' }) - 1
	end

	-- 转换为 LSP 位置格式
	local result = {
		start_pos = { start_pos[2], start_pos[3] - 1 },
		end_pos = { end_pos[2], end_pos[3] - 1 }
	}

	return result
end

function M.make_selection_params()
	local range = M.get_visual_selection()
	if (range == nil) then
		return nil
	end
	return vim.lsp.util.make_given_range_params(range.start_pos, range.end_pos, 0, 'utf-16')
end

-- 启用标注模式
function M.enable_annotation_mode(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- 如果已经启用，直接返回
	if vim.b[bufnr].annotation_mode then
		return
	end

	vim.b[bufnr].annotation_mode = true
	vim.api.nvim_set_option_value('conceallevel', 2, { win = 0 })
	vim.cmd([[
		syn conceal on
		syn match AnnotationBracket "｢\|｣"
		syn conceal off
	]])
	logger.info("Annotation mode enabled")
end

-- 禁用标注模式
function M.disable_annotation_mode(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- 如果已经禁用，直接返回
	if not vim.b[bufnr].annotation_mode then
		return
	end

	vim.b[bufnr].annotation_mode = false
	vim.api.nvim_set_option_value('conceallevel', 0, { win = 0 })
	vim.cmd([[syntax clear AnnotationBracket]])
	logger.info("Annotation mode disabled")
end

-- 切换标注模式
function M.toggle_annotation_mode(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if vim.b[bufnr].annotation_mode then
		M.disable_annotation_mode(bufnr)
	else
		M.enable_annotation_mode(bufnr)
	end
end

-- 将 UTF-8 字符位置转换为字节位置
-- @param bufnr number 缓冲区 ID
-- @param pos_or_range table 位置或范围信息
-- @return table 转换后的位置或范围信息
function M.convert_utf8_to_bytes(bufnr, pos_or_range)
	-- 确保 bufnr 是有效的
	if bufnr == nil then
		bufnr = 0
	elseif type(bufnr) == 'number' and not vim.api.nvim_buf_is_valid(bufnr) then
		logger.warn("Invalid buffer ID in convert_utf8_to_bytes: " .. tostring(bufnr))
		bufnr = 0 -- 如果无效，使用当前缓冲区
	end

	-- 检查 pos_or_range 是否有效
	if not pos_or_range then
		logger.warn("Nil position or range in convert_utf8_to_bytes")
		return nil
	end

	-- 定义位置转换函数
	local function convert_position(line, character)
		-- 获取指定行的内容
		local line_content = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
		-- 转换为字节索引
		return vim.str_byteindex(line_content, character)
	end

	-- 处理范围类型
	if pos_or_range.start then
		-- 转换 range 类型
		local start_line = pos_or_range.start.line
		local end_line = pos_or_range['end'].line

		local start_byte = convert_position(start_line, pos_or_range.start.character + 1)
		local end_byte = convert_position(end_line, pos_or_range['end'].character)

		return {
			start = { line = start_line, character = start_byte },
			['end'] = { line = end_line, character = end_byte }
		}
	else
		-- 转换 single position 类型
		local line = pos_or_range.line
		local byte_index = convert_position(line, pos_or_range.character)
		return { line + 1, byte_index }
	end
end

---安全地截断 UTF-8 字符串，避免在多字节字符中间截断
---@param str string 要截断的字符串
---@param max_chars number 最大字符数（不是字节数）
---@param suffix string 截断后的后缀，默认为 "..."
---@return string 截断后的字符串
function M.safe_truncate_utf8(str, max_chars, suffix)
	suffix = suffix or "..."

	-- 使用 vim.fn.strchars 计算实际字符数（支持多字节字符）
	local char_count = vim.fn.strchars(str)

	if char_count <= max_chars then
		return str
	end

	-- 使用 vim.fn.strcharpart 安全地截断字符串
	-- 这个函数会确保不在多字节字符中间截断
	local truncated = vim.fn.strcharpart(str, 0, max_chars - vim.fn.strchars(suffix))
	return truncated .. suffix
end

-- 项目大小检测模块
-- 项目大小缓存
local project_size_cache = {}

-- 异步检测项目大小
local function detect_project_size_async(cwd, callback)
	-- 检查缓存
	if project_size_cache[cwd] then
		local cache_entry = project_size_cache[cwd]
		local config = require('annotation-tool.config')
		local cache_ttl = config.get('performance.cache_ttl') or 300
		if os.time() - cache_entry.timestamp < cache_ttl then
			callback(cache_entry.file_count)
			return
		end
	end

	-- 使用 plenary.scandir 进行异步扫描
	local ok, scandir = pcall(require, 'plenary.scandir')
	if not ok then
		-- 如果 plenary 不可用，使用默认值
		callback(0)
		return
	end

	-- 异步扫描目录
	scandir.scan_dir_async(cwd, {
		hidden = false,      -- 不包含隐藏文件
		add_dirs = false,    -- 只计算文件，不包含目录
		respect_gitignore = true, -- 尊重 .gitignore
		on_exit = function(files)
			local file_count = #files
			-- 缓存结果
			project_size_cache[cwd] = {
				file_count = file_count,
				timestamp = os.time(),
				method = 'scandir'
			}
			callback(file_count)
		end
	})
end

-- 获取项目大小缓存信息
function M.get_project_cache_info(cwd)
	cwd = cwd or vim.fn.getcwd()
	local cache_entry = project_size_cache[cwd]
	if not cache_entry then
		return nil
	end

	local config = require('annotation-tool.config')
	local cache_ttl = config.get('performance.cache_ttl') or 300
	local age = os.time() - cache_entry.timestamp

	return {
		file_count = cache_entry.file_count,
		method = cache_entry.method,
		age_seconds = age,
		is_expired = age >= cache_ttl,
		cached_at = os.date('%Y-%m-%d %H:%M:%S', cache_entry.timestamp)
	}
end

-- 清理项目大小缓存
function M.clear_project_cache(cwd)
	if cwd then
		project_size_cache[cwd] = nil
	else
		project_size_cache = {}
	end
end

-- 强制刷新项目大小检测
function M.refresh_project_size(cwd, callback)
	cwd = cwd or vim.fn.getcwd()
	-- 清除缓存
	project_size_cache[cwd] = nil

	-- 重新检测
	detect_project_size_async(cwd, function(file_count)
		local cache_info = M.get_project_cache_info(cwd)
		logger.info(string.format("项目大小刷新完成: %d 文件 (使用 %s)",
			file_count, cache_info and cache_info.method or 'unknown'))

		if callback then
			callback(file_count, cache_info)
		end
	end)
end

-- 获取智能搜索范围（根据项目大小）
function M.get_smart_scope()
	local config = require('annotation-tool.config')
	local perf_config = config.get('performance')
	local default_scope = config.get('search.default_scope') or 'current_file'
	if type(default_scope) == 'table'  then
		logger.warn("default_scope is a table, using 'current_file' as fallback")
		return "current_file"
	end

	if not perf_config or not perf_config.enable_cache then
		return default_scope
	end

	local cwd = vim.fn.getcwd()
	local threshold = perf_config.large_project_threshold or 1000
	local large_scope = perf_config.large_project_scope or 'current_file'

	-- 检查缓存
	if project_size_cache[cwd] then
		local cache_entry = project_size_cache[cwd]
		local cache_ttl = perf_config.cache_ttl or 300
		if os.time() - cache_entry.timestamp < cache_ttl then
			-- 使用缓存的结果
			if cache_entry.file_count > threshold then
				return large_scope
			else
				return default_scope
			end
		end
	end

	-- 启动异步检测（不阻塞当前调用）
	detect_project_size_async(cwd, function(file_count)
		-- 异步完成后，缓存已更新，下次调用会使用新结果
		local method = project_size_cache[cwd] and project_size_cache[cwd].method or 'unknown'
		logger.debug(string.format("项目大小检测完成: %d 文件 (使用 %s)", file_count, method))
	end)

	-- 在异步检测完成前，返回默认范围
	return default_scope
end

-- 检查 plenary.scandir 是否可用
function M.is_plenary_available()
	return pcall(require, 'plenary.scandir')
end

return M
