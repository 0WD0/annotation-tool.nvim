-- Custom Markdown LSP configuration
local lsp = vim.lsp

-- Configuration for the Markdown LSP
local server_config = {
	cmd = { 'python', '/home/_WD_/.config/nvim/lua/dev/lsp/server.py' },  -- Adjust this path to your server.py location
	filetypes = { 'markdown' },
	root_dir = function(fname)
		return vim.fs.dirname(vim.fs.find('.git',{path= fname, upward = true})[1]) or vim.fn.getcwd()
		-- return util.find_git_ancestor(fname) or vim.fn.getcwd()
	end,
	settings = {},
}

-- Setup the LSP client
local client_id = nil

local function start_markdown_lsp()
	if client_id then
		-- Client already running
		return
	end

	local client = lsp.start_client({
		name = 'markdown_lsp',
		cmd = server_config.cmd,
		root_dir = server_config.root_dir(vim.fn.expand('%:p')),
		filetypes = server_config.filetypes,
		on_attach = function(client, bufnr)
			-- Key mappings
			local opts = { noremap = true, silent = true, buffer = bufnr }
			vim.keymap.set('n', 'K', lsp.buf.hover, opts)
			-- vim.keymap.set('n', 'gd', lsp.buf.definition, opts)
			-- vim.keymap.set('n', '<leader>ca', lsp.buf.code_action, opts)
			-- vim.keymap.set('n', '<leader>f', function() lsp.buf.format({ async = true }) end, opts)

			-- Enable completion
			vim.bo[bufnr].omnifunc = 'v:lua.vim.lsp.omnifunc'

			-- Enable formatting on save
			if client.server_capabilities.documentFormattingProvider then
				vim.api.nvim_create_autocmd("BufWritePre", {
					buffer = bufnr,
					callback = function()
						lsp.buf.format({ async = false })
					end,
				})
			end

			-- Attach buffer to client
			lsp.buf_attach_client(bufnr, client.id)
		end,
	})

	if client then
		client_id = client
	end
end

-- Attach
local function attach_markdown_lsp()
	if client_id then
		lsp.buf_attach_client(0,client_id)
	end
end
vim.api.nvim_create_user_command("AttachMarkdownLSP",function()
	attach_markdown_lsp()
end,{})

-- Optional: command to manually start/restart the LSP
vim.api.nvim_create_user_command("MarkdownLSPStart", function()
	if client_id then
		lsp.stop_client(client_id)
		client_id = nil
	end
	start_markdown_lsp()
end, {})


-- Autocommand to start LSP when opening markdown files
vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function(args)
		start_markdown_lsp()
		attach_markdown_lsp()
	end,
})
