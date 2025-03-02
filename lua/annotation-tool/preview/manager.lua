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
	vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
	vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
	vim.api.nvim_buf_set_option(buf, 'swapfile', false)
	vim.api.nvim_buf_set_option(buf, 'filetype', 'annotation-tree')

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
	vim.api.nvim_win_set_option(win, 'winhl', 'Normal:NormalFloat')
	vim.api.nvim_win_set_option(win, 'cursorline', true)

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
	end, { buffer = buf, noremap = true, silent = true })

	-- 关闭窗口的多种方式
	local close_keys = {'q', '<Esc>'}
	for _, key in ipairs(close_keys) do
		vim.keymap.set('n', key, function()
			vim.api.nvim_win_close(win, true)
		end, { buffer = buf, noremap = true, silent = true })
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
	vim.wo[note_win].number = true
	vim.wo[note_win].relativenumber = false
	vim.wo[note_win].wrap = true
	vim.wo[note_win].winfixwidth = true

	-- 设置 buffer 选项
	vim.bo[note_buf].filetype = 'markdown'

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

return M
