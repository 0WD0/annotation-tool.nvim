-- 搜索模块使用示例
local search = require('annotation-tool.search')

-- 基本用法 - 当前文件搜索
search.find_current_file()

-- 或者使用通用接口
search.find_current_project({
    scope = search.SCOPE.CURRENT_FILE,
    backend = search.BACKEND.TELESCOPE
})

-- 当前项目搜索
search.find_current_project()

-- 或者
search.find_current_project({
    scope = search.SCOPE.CURRENT_WORKSPACE,
    backend = search.BACKEND.TELESCOPE
})

-- 所有项目搜索
search.find_current_project()

-- 或者
search.find_current_project({
    scope = search.SCOPE.CURRENT_PROJECT,
    backend = search.BACKEND.TELESCOPE
})

-- 未来的 fzf-lua 支持（当后端可用时）
search.find_current_project({
    scope = search.SCOPE.CURRENT_FILE,
    backend = search.BACKEND.FZF_LUA
})

-- 键盘映射示例
vim.keymap.set('n', '<leader>af', search.find_current_file, { desc = '查找当前文件标注' })
vim.keymap.set('n', '<leader>ap', search.find_current_project, { desc = '查找当前项目标注' })
vim.keymap.set('n', '<leader>aa', search.find_current_project, { desc = '查找所有项目标注' })
