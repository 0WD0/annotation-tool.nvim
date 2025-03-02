local M = {}

M.nodes = {}
M.edges = {}
M.metadata = {}

function M.create_node(buf_id, win_id, parent_id, metadata)
	local node_id = buf_id .. "_" .. win_id

	-- 存储节点信息
	M.nodes[node_id] = {
		buffer = buf_id,
		window = win_id,
		parent = parent_id
	}

	-- 存储节点元数据
	M.metadata[node_id] = metadata or {}

	-- 如果有父节点，建立关系
	if parent_id then
		if not M.edges[parent_id] then
			M.edges[parent_id] = {}
		end
		table.insert(M.edges[parent_id], node_id)
	end

	return node_id
end

function M.find_node(note_file)
	for node_id, node in pairs(M.nodes) do
		-- 检查 buffer 是否有效
		if node.buffer and vim.api.nvim_buf_is_valid(node.buffer) then
			local buf_name = vim.api.nvim_buf_get_name(node.buffer)
			-- 检查 buffer 名称是否匹配
			if(buf_name:match("/.annotation/notes/" .. note_file .. "$")) then
				-- 检查窗口是否有效
				if node.window and vim.api.nvim_win_is_valid(node.window) then
					-- 检查窗口是否显示该 buffer
					local win_buf = vim.api.nvim_win_get_buf(node.window)
					if win_buf == node.buffer then
						return node_id
					end
				end
			end
		end
	end
	return nil
end

function M.get_children(node_id)
	return M.edges[node_id] or {}
end

function M.get_parent(node_id)
	return M.nodes[node_id] and M.nodes[node_id].parent
end

function M.get_ancestors(node_id)
	local ancestors = {}
	local current = M.get_parent(node_id)

	while current do
		table.insert(ancestors, current)
		current = M.get_parent(current)
	end

	return ancestors
end

function M.remove_node(node_id)
	local children = M.get_children(node_id)
	for _, child_id in ipairs(children) do
		M.remove_node(child_id)
	end

	local parent_id = M.get_parent(node_id)
	if parent_id and M.edges[parent_id] then
		for i, id in ipairs(M.edges[parent_id]) do
			if id == node_id then
				table.remove(M.edges[parent_id], i)
				break
			end
		end
	end

	-- 关闭窗口和buffer（如果存在）
	if M.nodes[node_id] then
		local node = M.nodes[node_id]

		-- 检查窗口是否存在，如果存在则关闭
		if node.window and vim.api.nvim_win_is_valid(node.window) then
			-- 保存当前窗口
			local current_win = vim.api.nvim_get_current_win()

			-- 关闭窗口
			pcall(vim.api.nvim_win_close, node.window, true)

			-- 如果当前窗口被关闭，尝试恢复到其他窗口
			if not vim.api.nvim_win_is_valid(current_win) then
				local wins = vim.api.nvim_list_wins()
				if #wins > 0 then
					vim.api.nvim_set_current_win(wins[1])
				end
			end
		end

		-- 检查buffer是否存在，如果存在且不再被任何窗口使用，则关闭
		if node.buffer and vim.api.nvim_buf_is_valid(node.buffer) then
			local is_buffer_in_window = false
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_buf(win) == node.buffer then
					is_buffer_in_window = true
					break
				end
			end

			if not is_buffer_in_window then
				pcall(vim.api.nvim_buf_delete, node.buffer, {force = true})
			end
		end
	end

	M.nodes[node_id] = nil
	M.edges[node_id] = nil
	M.metadata[node_id] = nil
end

function M.update_metadata(node_id, key, value)
	if M.metadata[node_id] then
		M.metadata[node_id][key] = value
	end
end

function M.is_node_valid(node_id)
	local node = M.nodes[node_id]
	if not node then
		return false
	end

	-- 检查 buffer 是否存在
	local buf_valid = vim.api.nvim_buf_is_valid(node.buffer)
	-- 检查 window 是否存在
	local win_valid = vim.api.nvim_win_is_valid(node.window)

	-- 如果窗口和buffer都有效，检查window是否显示该buffer
	if buf_valid and win_valid then
		local win_buf = vim.api.nvim_win_get_buf(node.window)
		return win_buf == node.buffer
	end

	return false
end

function M.cleanup()
	local to_remove = {}

	for node_id, _ in pairs(M.nodes) do
		if not M.is_node_valid(node_id) then
			table.insert(to_remove, node_id)
		end
	end

	for _, node_id in ipairs(to_remove) do
		M.remove_node(node_id)
	end
end

-- 遍历树
function M.traverse(callback, start_node_id)
	local function dfs(node_id, depth)
		if not M.nodes[node_id] then return end

		-- 调用回调函数，传入节点ID和深度
		callback(node_id, M.nodes[node_id], M.metadata[node_id], depth)

		-- 遍历子节点
		local children = M.get_children(node_id)
		for _, child_id in ipairs(children) do
			dfs(child_id, depth + 1)
		end
	end

	-- 如果没有指定起始节点，则遍历所有根节点
	if start_node_id then
		dfs(start_node_id, 0)
	else
		-- 找出所有根节点 (没有父节点的节点)
		for node_id, node in pairs(M.nodes) do
			if not node.parent then
				dfs(node_id, 0)
			end
		end
	end
end

-- 创建根批注 (例如原始文档)
function M.create_source(buf_id, win_id, metadata)
	return M.create_node(buf_id, win_id, nil, metadata)
end

-- 创建子批注
M.create_annotation = M.create_node

-- 显示批注树
function M.show_annotation_tree()
	-- 创建一个新的缓冲区
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
	vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
	vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
	vim.api.nvim_set_option_value('filetype', 'annotation-tree', { buf = buf })

	-- 计算浮动窗口的尺寸和位置
	local width = 60
	local height = 20
	local editor_width = vim.o.columns
	local editor_height = vim.o.lines
	local row = math.floor((editor_height - height) / 2) - 1
	local col = math.floor((editor_width - width) / 2)

	-- 创建浮动窗口
	local win_opts = {
		relative = 'editor',
		width = width,
		height = height,
		row = row,
		col = col,
		style = 'minimal',
		border = 'rounded', -- 使用圆角边框
		title = ' 批注树 ',
		title_pos = 'center'
	}

	local win = vim.api.nvim_open_win(buf, true, win_opts)
	vim.api.nvim_set_option_value('winhl', 'Normal:NormalFloat', { win = win })
	vim.api.nvim_set_option_value('cursorline', true, { win = win })

	-- 存储节点ID和行号的映射关系
	local node_lines = {}
	local result = {}

	-- 添加说明
	table.insert(result, "按 <Enter> 跳转到对应批注")
	table.insert(result, "按 q 或 <Esc> 关闭此窗口")
	table.insert(result, "")
	table.insert(result, "---")
	table.insert(result, "")

	-- 遍历树并构建结果
	local line_idx = #result + 1
	M.traverse(function(node_id, node, metadata, depth)
		local indent = string.rep("  ", depth)
		local buf_name = vim.api.nvim_buf_get_name(node.buffer)
		local file_name = buf_name:match("[^/]+$") or buf_name

		-- 添加树形图标
		local prefix = ""
		if depth > 0 then
			if depth == 1 then
				prefix = "├─ "
			else
				prefix = "│  "..(string.rep("  ", depth - 2)).."├─ "
			end
		end

		-- 添加节点类型图标
		local icon = ""
		if not node.parent then
			icon = "📄 "  -- 源文件图标
		else
			icon = "📝 "  -- 批注文件图标
		end

		-- 添加元数据信息
		local meta_info = ""
		if metadata and metadata.title then
			meta_info = " - " .. metadata.title
		end

		-- 构建显示行
		local display_line = indent .. prefix .. icon .. file_name .. meta_info
		table.insert(result, display_line)

		-- 记录节点ID对应的行号
		node_lines[line_idx] = node_id
		line_idx = line_idx + 1
	end)

	-- 如果没有节点，显示提示信息
	if line_idx == #result + 1 then
		table.insert(result, "  (没有批注节点)")
	end

	-- 设置缓冲区内容
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, result)

	-- 设置语法高亮
	vim.api.nvim_buf_add_highlight(buf, -1, 'Comment', 0, 0, -1)
	vim.api.nvim_buf_add_highlight(buf, -1, 'Comment', 1, 0, -1)
	vim.api.nvim_buf_add_highlight(buf, -1, 'NonText', 3, 0, -1)

	-- 为每个节点行添加高亮
	for line, node_id in pairs(node_lines) do
		local node = M.nodes[node_id]
		if node then
			if not node.parent then
				-- 源文件高亮
				vim.api.nvim_buf_add_highlight(buf, -1, 'Function', line - 1, 0, -1)
			else
				-- 批注文件高亮
				vim.api.nvim_buf_add_highlight(buf, -1, 'String', line - 1, 0, -1)
			end
		end
	end

	-- 设置键盘映射
	local opts = { noremap = true, silent = true, buffer = buf }

	-- 跳转到选中的批注
	vim.keymap.set('n', '<CR>', function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]
		local node_id = node_lines[line_num]

		if node_id and M.is_node_valid(node_id) then
			vim.api.nvim_win_close(win, true)
			M.jump_to_annotation(node_id)
		end
	end, opts)

	-- 关闭窗口的多种方式
	local close_keys = {'q', '<Esc>'}
	for _, key in ipairs(close_keys) do
		vim.keymap.set('n', key, function()
			vim.api.nvim_win_close(win, true)
		end, opts)
	end

	-- 添加自动命令，在窗口关闭时清理
	vim.api.nvim_create_autocmd('WinClosed', {
		pattern = tostring(win),
		callback = function()
			-- 清理相关资源
			vim.api.nvim_buf_delete(buf, { force = true })
		end,
		once = true
	})

	-- 自动调整窗口高度以适应内容
	local content_height = #result
	if content_height < height then
		vim.api.nvim_win_set_height(win, content_height)
		-- 重新居中窗口
		local new_row = math.floor((editor_height - content_height) / 2) - 1
		vim.api.nvim_win_set_config(win, {
			relative = 'editor',
			row = new_row,
			col = col,
			height = content_height
		})
	end

	return buf, win
end

-- 跳转到特定批注
function M.jump_to_annotation(node_id)
	if M.is_node_valid(node_id) then
		local node = M.nodes[node_id]
		if node then
			vim.api.nvim_set_current_win(node.window)
			return true
		end
	end
	return false
end

-- 注册自动命令以监听缓冲区/窗口关闭
function M.setup()
	-- 定期清理无效节点
	vim.api.nvim_create_autocmd({"BufDelete", "WinClosed", "BufWinLeave"}, {
		callback = function()
			M.cleanup()
		end
	})
end

-- 打开批注文件并创建新的buffer和window
function M.open_note_file(note_file, parent_node_id, metadata)
	-- 检查是否已经打开了这个批注文件
	local existing_node_id = M.find_node(note_file)
	if existing_node_id and M.is_node_valid(existing_node_id) then
		-- 如果已经打开，直接跳转到那个窗口
		return M.jump_to_annotation(existing_node_id)
	end

	-- 构建批注文件的完整路径
	local workspace_path = metadata and metadata.workspace_path or vim.fn.getcwd()
	local file_path = workspace_path .. '/.annotation/notes/' .. note_file

	-- 保存当前窗口作为父窗口
	local parent_win = vim.api.nvim_get_current_win()
	local parent_buf = vim.api.nvim_win_get_buf(parent_win)

	-- 在右侧打开文件
	vim.cmd('vsplit ' .. vim.fn.fnameescape(file_path))

	-- 获取新窗口和buffer的ID
	local note_win = vim.api.nvim_get_current_win()
	local note_buf = vim.api.nvim_get_current_buf()

	-- 设置窗口大小
	vim.cmd('vertical resize ' .. math.floor(vim.o.columns * 0.4))

	-- 设置窗口选项
	vim.api.nvim_set_option_value('number', true, { win = note_win })
	vim.api.nvim_set_option_value('relativenumber', false, { win = note_win })
	vim.api.nvim_set_option_value('wrap', true, { win = note_win })
	vim.api.nvim_set_option_value('winfixwidth', true, { win = note_win })

	-- 设置 buffer 选项
	vim.api.nvim_set_option_value('filetype', 'markdown', { buf = note_buf })

	-- 跳转到笔记部分
	vim.cmd([[
		normal! G
		?^## Notes
		normal! 2j
		]])

	-- 如果没有提供父节点ID，但我们知道当前窗口，则尝试查找对应的节点
	if not parent_node_id and parent_win then
		for node_id, node in pairs(M.nodes) do
			if node.window == parent_win and node.buffer == parent_buf then
				parent_node_id = node_id
				break
			end
		end
	end

	-- 创建新节点并建立关系
	local node_id = M.create_node(note_buf, note_win, parent_node_id, metadata or {})

	-- 当窗口关闭时自动清理节点
	vim.api.nvim_create_autocmd('WinClosed', {
		pattern = tostring(note_win),
		callback = function()
			M.cleanup()
		end,
		once = true
	})

	return node_id
end

-- 打开批注文件并创建子批注
function M.open_child_annotation(note_file, parent_node_id, metadata)
	return M.open_note_file(note_file, parent_node_id, metadata)
end

-- 打开源文件的批注
function M.open_source_annotation(note_file, metadata)
	-- 获取当前buffer和window
	local buf_id = vim.api.nvim_get_current_buf()
	local win_id = vim.api.nvim_get_current_win()

	-- 检查当前buffer/window是否已经是一个节点
	local current_node_id = nil
	for node_id, node in pairs(M.nodes) do
		if node.buffer == buf_id and node.window == win_id then
			current_node_id = node_id
			break
		end
	end

	-- 如果当前buffer/window不是节点，创建一个源节点
	if not current_node_id then
		current_node_id = M.create_source(buf_id, win_id, {
			type = "source",
			file = vim.api.nvim_buf_get_name(buf_id)
		})
	end

	-- 打开批注文件作为子节点
	return M.open_child_annotation(note_file, current_node_id, metadata)
end

-- 查找或创建源文件节点
function M.find_or_create_source_node(buf_id, win_id, metadata)
	-- 检查是否已经存在这个源文件节点
	for node_id, node in pairs(M.nodes) do
		if node.buffer == buf_id and node.window == win_id and not node.parent then
			return node_id
		end
	end

	-- 不存在则创建新的源文件节点
	return M.create_source(buf_id, win_id, metadata or {
		type = "source",
		file = vim.api.nvim_buf_get_name(buf_id)
	})
end

-- 调试函数：输出批注树的结构
function M.debug_print_tree()
	local logger = require('annotation-tool.logger')
	logger.debug("=== 批注树结构 ===")

	-- 打印节点总数
	local node_count = 0
	for _ in pairs(M.nodes) do
		node_count = node_count + 1
	end
	logger.debug(string.format("节点总数: %d", node_count))

	-- 查找根节点
	local root_nodes = {}
	for node_id, node in pairs(M.nodes) do
		if not M.get_parent(node_id) then
			table.insert(root_nodes, node_id)
		end
	end

	logger.debug(string.format("根节点数: %d", #root_nodes))

	-- 递归打印树结构
	local function print_node(node_id, depth)
		local indent = string.rep("  ", depth)
		local node = M.nodes[node_id]
		local metadata = M.metadata[node_id] or {}
		local buffer_valid = node.buffer and vim.api.nvim_buf_is_valid(node.buffer)
		local window_valid = node.window and vim.api.nvim_win_is_valid(node.window)
		local buffer_name = buffer_valid and vim.api.nvim_buf_get_name(node.buffer) or "无效"

		logger.debug(string.format("%s节点ID: %s", indent, node_id))
		logger.debug(string.format("%s├─ 类型: %s", indent, metadata.type or "未知"))
		logger.debug(string.format("%s├─ Buffer: %s (有效: %s)", indent, node.buffer or "无", buffer_valid))
		logger.debug(string.format("%s├─ Window: %s (有效: %s)", indent, node.window or "无", window_valid))
		logger.debug(string.format("%s├─ 文件: %s", indent, buffer_name))

		-- 打印子节点
		local children = M.get_children(node_id)
		if #children > 0 then
			logger.debug(string.format("%s└─ 子节点数: %d", indent, #children))
			for _, child_id in ipairs(children) do
				print_node(child_id, depth + 1)
			end
		end
	end

	-- 打印每个根节点及其子树
	for _, root_id in ipairs(root_nodes) do
		print_node(root_id, 0)
		logger.debug("---")
	end

	logger.debug("=== 批注树结构结束 ===")
end

-- 调试函数：检查批注树中的无效节点
function M.debug_check_invalid_nodes()
	local logger = require('annotation-tool.logger')
	logger.debug("=== 检查无效节点 ===")

	local invalid_nodes = {}
	for node_id, node in pairs(M.nodes) do
		if not M.is_node_valid(node_id) then
			table.insert(invalid_nodes, node_id)

			-- 详细输出无效原因
			local buffer_valid = node.buffer and vim.api.nvim_buf_is_valid(node.buffer)
			local window_valid = node.window and vim.api.nvim_win_is_valid(node.window)
			local window_shows_buffer = false

			if buffer_valid and window_valid then
				local win_buf = vim.api.nvim_win_get_buf(node.window)
				window_shows_buffer = (win_buf == node.buffer)
			end

			logger.debug(string.format("无效节点ID: %s", node_id))
			logger.debug(string.format("├─ Buffer有效: %s", buffer_valid))
			logger.debug(string.format("├─ Window有效: %s", window_valid))
			logger.debug(string.format("└─ Window显示Buffer: %s", window_shows_buffer))
		end
	end

	logger.debug(string.format("发现 %d 个无效节点", #invalid_nodes))
	logger.debug("=== 检查结束 ===")

	return invalid_nodes
end

-- 调试函数：输出节点的详细信息
function M.debug_node_info(node_id)
	local logger = require('annotation-tool.logger')

	if not node_id then
		logger.debug("请提供节点ID")
		return
	end

	local node = M.nodes[node_id]
	if not node then
		logger.debug(string.format("节点ID %s 不存在", node_id))
		return
	end

	logger.debug(string.format("=== 节点详情 (ID: %s) ===", node_id))

	-- 基本信息
	local metadata = M.metadata[node_id] or {}
	local buffer_valid = node.buffer and vim.api.nvim_buf_is_valid(node.buffer)
	local window_valid = node.window and vim.api.nvim_win_is_valid(node.window)
	local buffer_name = buffer_valid and vim.api.nvim_buf_get_name(node.buffer) or "无效"

	logger.debug("基本信息:")
	logger.debug(string.format("├─ 类型: %s", metadata.type or "未知"))
	logger.debug(string.format("├─ Buffer: %s (有效: %s)", node.buffer or "无", buffer_valid))
	logger.debug(string.format("├─ Window: %s (有效: %s)", node.window or "无", window_valid))
	logger.debug(string.format("└─ 文件: %s", buffer_name))

	-- 关系信息
	local parent_id = M.get_parent(node_id)
	local children = M.get_children(node_id)

	logger.debug("关系信息:")
	logger.debug(string.format("├─ 父节点: %s", parent_id or "无"))
	logger.debug(string.format("└─ 子节点数: %d", #children))

	if #children > 0 then
		logger.debug("子节点列表:")
		for i, child_id in ipairs(children) do
			local child_valid = M.is_node_valid(child_id)
			logger.debug(string.format("  %d. %s (有效: %s)", i, child_id, child_valid))
		end
	end

	-- 元数据
	if next(metadata) then
		logger.debug("元数据:")
		for k, v in pairs(metadata) do
			logger.debug(string.format("├─ %s: %s", k, vim.inspect(v)))
		end
	end

	logger.debug("=== 节点详情结束 ===")
end

-- 调试函数：显示所有节点的 ID 列表
function M.debug_list_nodes()
	local logger = require('annotation-tool.logger')
	logger.debug("=== 批注节点列表 ===")

	-- 统计节点总数
	local node_count = 0
	local valid_count = 0
	local invalid_count = 0

	-- 按类型分组节点
	local nodes_by_type = {}

	for node_id, node in pairs(M.nodes) do
		node_count = node_count + 1

		local is_valid = M.is_node_valid(node_id)
		if is_valid then
			valid_count = valid_count + 1
		else
			invalid_count = invalid_count + 1
		end

		local metadata = M.metadata[node_id] or {}
		local node_type = metadata.type or "未知"

		if not nodes_by_type[node_type] then
			nodes_by_type[node_type] = {}
		end

		table.insert(nodes_by_type[node_type], {
			id = node_id,
			valid = is_valid
		})
	end

	-- 输出统计信息
	logger.debug(string.format("节点总数: %d (有效: %d, 无效: %d)", 
		node_count, valid_count, invalid_count))

	-- 按类型输出节点
	for node_type, nodes in pairs(nodes_by_type) do
		logger.debug(string.format("\n类型: %s (%d个节点)", node_type, #nodes))

		-- 先输出有效节点
		local valid_nodes = {}
		local invalid_nodes = {}

		for _, node_info in ipairs(nodes) do
			if node_info.valid then
				table.insert(valid_nodes, node_info)
			else
				table.insert(invalid_nodes, node_info)
			end
		end

		if #valid_nodes > 0 then
			logger.debug("有效节点:")
			for i, node_info in ipairs(valid_nodes) do
				logger.debug(string.format("  %d. %s", i, node_info.id))
			end
		end

		if #invalid_nodes > 0 then
			logger.debug("无效节点:")
			for i, node_info in ipairs(invalid_nodes) do
				logger.debug(string.format("  %d. %s", i, node_info.id))
			end
		end
	end

	logger.debug("\n=== 批注节点列表结束 ===")
end

return M
