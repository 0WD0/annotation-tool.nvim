local M = {}

local AnnotationManager = {}
AnnotationManager.__index = AnnotationManager

function AnnotationManager.new()
	local self = setmetatable({}, AnnotationManager)
	-- 存储所有批注节点
	self.nodes = {}
	-- 存储节点间的关系 (邻接表)
	self.edges = {}
	-- 存储节点的元数据
	self.metadata = {}
	return self
end

-- 创建一个新的批注节点
function AnnotationManager:create_node(buf_id, win_id, parent_id, metadata)
	local node_id = buf_id .. "_" .. win_id

	-- 存储节点信息
	self.nodes[node_id] = {
		buffer = buf_id,
		window = win_id,
		parent = parent_id
	}

	-- 存储节点元数据
	self.metadata[node_id] = metadata or {}

	-- 如果有父节点，建立关系
	if parent_id then
		if not self.edges[parent_id] then
			self.edges[parent_id] = {}
		end
		table.insert(self.edges[parent_id], node_id)
	end

	return node_id
end

-- 获取节点的所有子节点
function AnnotationManager:get_children(node_id)
	return self.edges[node_id] or {}
end

-- 获取节点的父节点
function AnnotationManager:get_parent(node_id)
	return self.nodes[node_id] and self.nodes[node_id].parent
end

-- 获取节点的所有祖先节点 (从父节点到根节点的路径)
function AnnotationManager:get_ancestors(node_id)
	local ancestors = {}
	local current = self:get_parent(node_id)

	while current do
		table.insert(ancestors, current)
		current = self:get_parent(current)
	end

	return ancestors
end

-- 删除节点及其所有子节点
function AnnotationManager:remove_node(node_id)
	-- 递归删除所有子节点
	local children = self:get_children(node_id)
	for _, child_id in ipairs(children) do
		self:remove_node(child_id)
	end

	-- 从父节点的子列表中移除
	local parent_id = self:get_parent(node_id)
	if parent_id and self.edges[parent_id] then
		for i, id in ipairs(self.edges[parent_id]) do
			if id == node_id then
				table.remove(self.edges[parent_id], i)
				break
			end
		end
	end

	-- 删除节点数据
	self.nodes[node_id] = nil
	self.edges[node_id] = nil
	self.metadata[node_id] = nil
end

-- 更新节点元数据
function AnnotationManager:update_metadata(node_id, key, value)
	if self.metadata[node_id] then
		self.metadata[node_id][key] = value
	end
end

-- 检查节点是否有效 (buffer 和 window 是否仍然存在)
function AnnotationManager:is_node_valid(node_id)
	local node = self.nodes[node_id]
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

-- 清理无效节点
function AnnotationManager:cleanup()
	local to_remove = {}

	for node_id, _ in pairs(self.nodes) do
		if not self:is_node_valid(node_id) then
			table.insert(to_remove, node_id)
		end
	end

	for _, node_id in ipairs(to_remove) do
		self:remove_node(node_id)
	end
end

-- 遍历树
function AnnotationManager:traverse(callback, start_node_id)
	local function dfs(node_id, depth)
		if not self.nodes[node_id] then return end

		-- 调用回调函数，传入节点ID和深度
		callback(node_id, self.nodes[node_id], self.metadata[node_id], depth)

		-- 遍历子节点
		local children = self:get_children(node_id)
		for _, child_id in ipairs(children) do
			dfs(child_id, depth + 1)
		end
	end

	-- 如果没有指定起始节点，则遍历所有根节点
	if start_node_id then
		dfs(start_node_id, 0)
	else
		-- 找出所有根节点 (没有父节点的节点)
		for node_id, node in pairs(self.nodes) do
			if not node.parent then
				dfs(node_id, 0)
			end
		end
	end
end

M.annotation_manager = AnnotationManager.new()

-- 创建根批注 (例如原始文档)
function M.create_root_annotation(buf_id, win_id, metadata)
	return M.annotation_manager:create_node(buf_id, win_id, nil, metadata)
end

-- 创建子批注
function M.create_annotation(buf_id, win_id, parent_id, metadata)
	return M.annotation_manager:create_node(buf_id, win_id, parent_id, metadata)
end

-- 显示批注树
function M.show_annotation_tree()
	local result = {}

	M.annotation_manager:traverse(function(node_id, node, metadata, depth)
		local indent = string.rep("  ", depth)
		local buf_name = vim.api.nvim_buf_get_name(node.buffer)
		table.insert(result, indent .. node_id .. ": " .. buf_name)
	end)

	-- 在新缓冲区中显示结果
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, result)
	vim.api.nvim_command('vsplit')
	vim.api.nvim_win_set_buf(0, buf)
end

-- 跳转到特定批注
function M.jump_to_annotation(node_id)
	local node = M.annotation_manager.nodes[node_id]
	if node and M.annotation_manager:is_node_valid(node_id) then
		vim.api.nvim_set_current_win(node.window)
		return true
	end
	return false
end

-- 在批注间导航
function M.next_annotation(current_buf_id, current_win_id)
	-- 找到当前节点
	local current_id = current_buf_id .. "_" .. current_win_id

	-- 获取其子节点
	local children = M.annotation_manager:get_children(current_id)
	if #children > 0 then
		return M.jump_to_annotation(children[1])
	end

	-- 或者跳转到父节点
	local parent_id = M.annotation_manager:get_parent(current_id)
	if parent_id then
		return M.jump_to_annotation(parent_id)
	end

	return false
end

-- 注册自动命令以监听缓冲区/窗口关闭
function M.setup()
	-- 定期清理无效节点
	vim.api.nvim_create_autocmd({"BufDelete", "WinClosed"}, {
		callback = function()
			M.annotation_manager:cleanup()
		end
	})
end

return M
