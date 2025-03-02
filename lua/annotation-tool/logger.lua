-- logger.lua - 日志模块
local M = {}

-- 日志级别
M.levels = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
}

-- 默认配置
local config = {
	debug = false,
	level = M.levels.INFO,
	prefix = "[annotation-tool]"
}

-- 设置日志配置
function M.setup(opts)
	if opts then
		if opts.debug ~= nil then
			config.debug = opts.debug
			-- 如果开启调试模式，自动设置日志级别为 DEBUG
			if opts.debug and not opts.level then
				config.level = M.levels.DEBUG
			end
		end
		if opts.level then
			config.level = opts.level
		end
		if opts.prefix then
			config.prefix = opts.prefix
		end
	end
end

-- 获取当前配置
function M.get_config()
	return vim.deepcopy(config)
end

-- 判断是否开启调试模式
function M.is_debug()
	return config.debug
end

-- 内部日志函数
local function log(level, msg, ...)
	if level < config.level then
		return
	end

	-- 格式化消息
	local formatted_msg = config.prefix .. " " .. msg
	if select('#', ...) > 0 then
		formatted_msg = string.format(formatted_msg, ...)
	end

	-- 确定日志级别和颜色
	local hl_group
	if level == M.levels.DEBUG then
		hl_group = "Comment"
	elseif level == M.levels.INFO then
		hl_group = "None"
	elseif level == M.levels.WARN then
		hl_group = "WarningMsg"
	elseif level == M.levels.ERROR then
		hl_group = "ErrorMsg"
	else
		hl_group = "None"
	end

	-- 使用 vim.schedule 延迟消息显示，避免多条消息堆积
	vim.schedule(function()
		-- 使用 nvim_echo 显示带颜色的消息
		vim.api.nvim_echo({{formatted_msg, hl_group}}, false, {})
		-- 同时使用 nvim_out_write 将消息写入 :messages 历史
		-- 添加换行符确保消息正确显示
		-- vim.api.nvim_out_write(formatted_msg .. "\n")
	end)
end

-- 调试日志
function M.debug(msg, ...)
	log(M.levels.DEBUG, msg, ...)
end

-- 信息日志
function M.info(msg, ...)
	log(M.levels.INFO, msg, ...)
end

-- 警告日志
function M.warn(msg, ...)
	log(M.levels.WARN, msg, ...)
end

-- 错误日志
function M.error(msg, ...)
	log(M.levels.ERROR, msg, ...)
end

-- 调试对象（用于输出复杂数据结构）
function M.debug_obj(label, obj)
	if not config.debug then
		return
	end

	local formatted_obj = vim.inspect(obj)
	log(M.levels.DEBUG, "%s: %s", label, formatted_obj)
end

return M
