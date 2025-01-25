local M = {}

-- 使用telescope进行标注搜索
function M.find()
	if not vim.b.annotation_mode then
		vim.notify("Please enable annotation mode first", vim.log.levels.WARN)
		return
	end
	
	local pickers = require('telescope.pickers')
	local finders = require('telescope.finders')
	local conf = require('telescope.config').values
	local actions = require('telescope.actions')
	local action_state = require('telescope.actions.state')
	
	-- 从LSP服务器获取所有标注
	vim.lsp.buf_request(0, 'workspace/annotations', {}, function(err, result, ctx, config)
		if err then
			vim.notify("Failed to get annotations: " .. err.message, vim.log.levels.ERROR)
			return
		end
		
		if not result or #result == 0 then
			vim.notify("No annotations found", vim.log.levels.INFO)
			return
		end
		
		pickers.new({}, {
			prompt_title = 'Find Annotations',
			finder = finders.new_table({
				results = result,
				entry_maker = function(entry)
					return {
						value = entry,
						display = string.format("%s: %s", entry.file, entry.content),
						ordinal = string.format("%s %s %s", entry.file, entry.content, entry.note or ""),
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					
					-- 打开文件并跳转到标注位置
					vim.cmd('edit ' .. selection.value.file)
					vim.api.nvim_win_set_cursor(0, {
						selection.value.range.start.line + 1,
						selection.value.range.start.character
					})
					
					-- 如果有预览窗口，更新预览内容
					if vim.g.annotation_preview_win and vim.api.nvim_win_is_valid(vim.g.annotation_preview_win) then
						require('annotation-tool.preview').update()
					end
				end)
				return true
			end,
		}):find()
	end)
end

return M
