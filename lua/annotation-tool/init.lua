local M = {}

-- LSP client configuration
M.setup = function(opts)
    opts = opts or {}
    
    -- 设置文件类型
    vim.filetype.add({
        extension = {
            annot = 'markdown'  -- 将.annot文件视为markdown
        }
    })
    
    -- 设置LSP
    local lspconfig = require('lspconfig')
    local configs = require('lspconfig.configs')
    
    -- 获取Python解释器路径
    local function get_python_path()
        local venv_python = vim.fn.expand('$VIRTUAL_ENV/bin/python')
        if vim.fn.filereadable(venv_python) == 1 then
            return venv_python
        end
        return vim.fn.exepath('python3') or vim.fn.exepath('python')
    end
    
    if not configs.annotation_lsp then
        configs.annotation_lsp = {
            default_config = {
                cmd = {get_python_path(), '-m', 'annotation_lsp'},
                filetypes = {'text', 'markdown', 'annot'},
                root_dir = function(fname)
                    return lspconfig.util.root_pattern('.annotation')(fname)
                end,
                settings = {},
            },
        }
    end
    
    -- 启动LSP服务器
    lspconfig.annotation_lsp.setup({
        on_attach = function(client, bufnr)
            -- 设置keymaps
            local opts = { noremap=true, silent=true, buffer=bufnr }
            vim.keymap.set('n', '<Leader>aa', M.toggle_annotation_mode, opts)
            vim.keymap.set('n', '<Leader>an', M.create_annotation, opts)
            vim.keymap.set('n', '<Leader>af', M.find_annotations, opts)
            
            -- 启用文档高亮
            if client.server_capabilities.documentHighlightProvider then
                vim.cmd [[
                    augroup lsp_document_highlight
                        autocmd! * <buffer>
                        autocmd CursorHold <buffer> lua vim.lsp.buf.document_highlight()
                        autocmd CursorMoved <buffer> lua vim.lsp.buf.clear_references()
                    augroup END
                ]]
            end
        end,
    })
end

-- 切换annotation mode
M.toggle_annotation_mode = function()
    local buf = vim.api.nvim_get_current_buf()
    local enabled = vim.b[buf].annotation_mode
    
    if enabled then
        -- 禁用annotation mode
        vim.b[buf].annotation_mode = false
        -- 禁用concealment
        vim.wo.conceallevel = 0
    else
        -- 启用annotation mode
        vim.b[buf].annotation_mode = true
        -- 启用concealment来隐藏特殊括号
        vim.wo.conceallevel = 2
        -- 设置conceal规则
        vim.cmd([[syntax match AnnotationBracket "｢\|｣" conceal]])
    end
end

-- 创建新标注
M.create_annotation = function()
    -- 获取当前选中的文本范围
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    
    -- 插入标注括号
    vim.cmd('normal! `>a｣')
    vim.cmd('normal! `<i｢')
end

-- 使用telescope进行标注搜索
M.find_annotations = function()
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local conf = require('telescope.config').values
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    
    -- 这里需要调用我们的Python后端来获取所有标注
    -- TODO: 实现与后端的通信
    
    pickers.new({}, {
        prompt_title = 'Find Annotations',
        finder = finders.new_table({
            results = {}, -- TODO: 从后端获取结果
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.file .. ': ' .. entry.content,
                    ordinal = entry.file .. ' ' .. entry.content,
                }
            end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                -- TODO: 跳转到选中的标注
            end)
            return true
        end,
    }):find()
end

-- 在右侧打开标注预览窗口
M.setup_annotation_preview = function()
    -- 创建新窗口
    local width = math.floor(vim.o.columns * 0.3)
    vim.cmd('vsplit')
    vim.cmd('vertical resize ' .. width)
    
    -- 设置窗口选项
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].wrap = true
    
    -- 创建新buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)
    
    -- 设置buffer选项
    vim.bo[buf].filetype = 'markdown'
    vim.bo[buf].modifiable = false
    
    -- 保存窗口和buffer的ID
    vim.g.annotation_preview_win = win
    vim.g.annotation_preview_buf = buf
end

-- 更新标注预览窗口的内容
M.update_annotation_preview = function()
    local win = vim.g.annotation_preview_win
    local buf = vim.g.annotation_preview_buf
    
    if not win or not buf or not vim.api.nvim_win_is_valid(win) then
        return
    end
    
    -- TODO: 获取当前光标下的标注内容并更新预览窗口
end

return M
