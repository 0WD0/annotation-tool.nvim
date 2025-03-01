local M = {}

-- 延迟加载依赖，避免循环依赖
local function load_deps()
    local lsp = require('annotation-tool.lsp')
    local core = require('annotation-tool.core')
    local preview = require('annotation-tool.preview')
    
    return {
        lsp = lsp,
        core = core,
        preview = preview
    }
end

-- 检查标注模式是否启用
local function check_annotation_mode()
    if not vim.b.annotation_mode then
        vim.notify("请先启用标注模式（:AnnotationEnable）", vim.log.levels.WARN)
        return false
    end
    return true
end

-- 获取当前工作区的所有标注
function M.find_annotations()
    if not check_annotation_mode() then return end
    
    local deps = load_deps()
    local client = deps.lsp.get_client()
    if not client then
        vim.notify("LSP 客户端未连接", vim.log.levels.ERROR)
        return
    end
    
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local conf = require('telescope.config').values
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local previewers = require('telescope.previewers')
    
    -- 从 LSP 服务器获取所有标注
    vim.lsp.buf_request(0, 'workspace/executeCommand', {
        command = "listAnnotations",
        arguments = { {
            textDocument = vim.lsp.util.make_text_document_params()
        } }
    }, function(err, result, ctx, config)
        if err then
            vim.notify("获取标注列表失败: " .. vim.inspect(err), vim.log.levels.ERROR)
            return
        end
        
        if not result or not result.note_files or #result.note_files == 0 then
            vim.notify("未找到标注", vim.log.levels.INFO)
            return
        end
        
        -- 从每个标注文件中提取信息
        local annotations = {}
        for _, note_file in ipairs(result.note_files) do
            -- 获取标注内容
            local file_path = note_file.workspace_path .. "/.annotation/notes/" .. note_file.note_file
            local file_content = vim.fn.readfile(file_path)
            
            -- 提取标注内容和笔记
            local content = ""
            local note = ""
            local in_notes_section = false
            
            for _, line in ipairs(file_content) do
                if line:match("^## Content") then
                    in_notes_section = false
                elseif line:match("^## Notes") then
                    in_notes_section = true
                elseif in_notes_section then
                    if note ~= "" then
                        note = note .. "\n"
                    end
                    note = note .. line
                elseif not in_notes_section and not line:match("^#") then
                    if content ~= "" then
                        content = content .. " "
                    end
                    content = content .. line:gsub("^%s*(.-)%s*$", "%1")
                end
            end
            
            table.insert(annotations, {
                file = note_file.source_path,
                content = content,
                note = note,
                position = note_file.position,
                range = note_file.range,
                note_file = note_file.note_file,
                workspace_path = note_file.workspace_path
            })
        end
        
        -- 创建预览器
        local annotation_previewer = previewers.new_buffer_previewer({
            title = "标注预览",
            define_preview = function(self, entry, status)
                local lines = {}
                
                -- 添加标注内容
                table.insert(lines, "# 标注内容")
                table.insert(lines, "")
                table.insert(lines, entry.value.content)
                table.insert(lines, "")
                
                -- 添加笔记内容
                table.insert(lines, "# 笔记")
                table.insert(lines, "")
                if entry.value.note and entry.value.note ~= "" then
                    for note_line in entry.value.note:gmatch("[^\r\n]+") do
                        table.insert(lines, note_line)
                    end
                else
                    table.insert(lines, "（无笔记）")
                end
                
                -- 添加文件信息
                table.insert(lines, "")
                table.insert(lines, "# 文件信息")
                table.insert(lines, "")
                table.insert(lines, "文件: " .. entry.value.file)
                table.insert(lines, string.format("位置: 第 %d 行, 第 %d 列", 
                    entry.value.position.line + 1, 
                    entry.value.position.character + 1))
                
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
                vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
            end
        })
        
        -- 创建 Telescope 选择器
        pickers.new({}, {
            prompt_title = '查找标注',
            finder = finders.new_table({
                results = annotations,
                entry_maker = function(entry)
                    local display_text = entry.content
                    if #display_text > 50 then
                        display_text = display_text:sub(1, 47) .. "..."
                    end
                    
                    local filename = vim.fn.fnamemodify(entry.file, ":t")
                    
                    return {
                        value = entry,
                        display = string.format("%s: %s", filename, display_text),
                        ordinal = string.format("%s %s %s", 
                            entry.file, 
                            entry.content, 
                            entry.note or ""),
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = annotation_previewer,
            attach_mappings = function(prompt_bufnr, map)
                -- 定义打开标注的动作
                local open_annotation = function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    
                    -- 打开文件并跳转到标注位置
                    vim.cmd('edit ' .. selection.value.file)
                    vim.api.nvim_win_set_cursor(0, {
                        selection.value.position.line + 1,
                        selection.value.position.character
                    })
                    
                    -- 打开预览窗口
                    local deps = load_deps()
                    deps.preview.goto_annotation_note({
                        workspace_path = selection.value.workspace_path,
                        note_file = selection.value.note_file
                    })
                end
                
                -- 定义删除标注的动作
                local delete_annotation = function()
                    local selection = action_state.get_selected_entry()
                    
                    -- 确认删除
                    vim.ui.select(
                        {"是", "否"}, 
                        {prompt = "确定要删除这个标注吗？"}, 
                        function(choice)
                            if choice == "是" then
                                actions.close(prompt_bufnr)
                                
                                -- 打开文件并跳转到标注位置
                                vim.cmd('edit ' .. selection.value.file)
                                vim.api.nvim_win_set_cursor(0, {
                                    selection.value.position.line + 1,
                                    selection.value.position.character
                                })
                                
                                -- 删除标注
                                local deps = load_deps()
                                deps.lsp.delete_annotation()
                            end
                        end
                    )
                end
                
                -- 映射按键
                actions.select_default:replace(open_annotation)
                map("i", "<C-d>", delete_annotation)
                map("n", "d", delete_annotation)
                map("i", "<C-o>", open_annotation)
                map("n", "o", open_annotation)
                
                return true
            end,
        }):find()
    end)
end

-- 搜索标注内容
function M.search_annotations()
    if not check_annotation_mode() then return end
    
    local deps = load_deps()
    local client = deps.lsp.get_client()
    if not client then
        vim.notify("LSP 客户端未连接", vim.log.levels.ERROR)
        return
    end
    
    -- 弹出输入框让用户输入搜索关键词
    vim.ui.input(
        {prompt = "输入搜索关键词: "}, 
        function(query)
            if not query or query == "" then
                return
            end
            
            -- 实现搜索功能
            vim.notify("正在搜索: " .. query, vim.log.levels.INFO)
            
            -- 这里可以实现搜索逻辑，类似于 server.py 中的 queryAnnotations 函数
            -- 由于当前 LSP 服务器没有实现 queryAnnotations 命令，这里使用 listAnnotations 然后在客户端过滤
            
            M.find_annotations()  -- 临时使用 find_annotations 代替
        end
    )
end

-- 跳转到当前标注的笔记
function M.goto_current_note()
    if not check_annotation_mode() then return end
    
    local deps = load_deps()
    deps.preview.goto_current_annotation_note()
end

return M
