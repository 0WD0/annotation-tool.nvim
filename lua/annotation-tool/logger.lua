-- logger.lua - 日志模块
local M = {}

-- 默认配置
local config = {
	debug = false,
	level = vim.log.levels.INFO,
	prefix = "[annotation-tool]"
}

-- 设置日志配置
function M.setup(opts)
	if opts then
		if opts.debug ~= nil then
			config.debug = opts.debug
			-- 如果开启调试模式，自动设置日志级别为 DEBUG
			if opts.debug and not opts.level then
				config.level = vim.log.levels.DEBUG
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
	-- 如果当前日志级别低于配置级别，则不记录日志
	if level < config.level then
		return
	end

	-- 格式化消息
	local formatted_msg = config.prefix .. " " .. msg
	if select('#', ...) > 0 then
		formatted_msg = string.format(formatted_msg, ...)
	end

	-- 使用 vim.schedule 延迟消息显示，避免多条消息堆积
	vim.schedule(function()
		vim.notify(formatted_msg, level)
	end)
end

-- 调试日志
function M.debug(msg, ...)
	log(vim.log.levels.DEBUG, msg, ...)
end

-- 信息日志
function M.info(msg, ...)
	log(vim.log.levels.INFO, msg, ...)
end

-- 警告日志
function M.warn(msg, ...)
	log(vim.log.levels.WARN, msg, ...)
end

-- 错误日志
function M.error(msg, ...)
	log(vim.log.levels.ERROR, msg, ...)
end

-- 调试对象（用于输出复杂数据结构）
function M.debug_obj(label, obj)
	if not config.debug then
		return
	end

	local formatted_obj = vim.inspect(obj)
	log(vim.log.levels.DEBUG, "%s: %s", label, formatted_obj)
end

return M
