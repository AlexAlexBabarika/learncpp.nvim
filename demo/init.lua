-- Minimal config the showcase GIF is recorded with; run `vhs demo/demo.tape` from the repository root.
-- It borrows the plugins it shows from an existing lazy.nvim install instead of downloading them.
local lazy = vim.fn.stdpath("data") .. "/lazy/"
local plugins = { "catppuccin", "mini.icons", "snacks.nvim", "render-markdown.nvim", "nvim-treesitter/runtime" }
for _, plugin in ipairs(plugins) do
  vim.opt.rtp:prepend(lazy .. plugin)
end
vim.opt.rtp:prepend(vim.fn.getcwd())

vim.g.mapleader = " "
vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.laststatus = 0
vim.o.showmode = false
vim.o.ruler = false
vim.o.shortmess = vim.o.shortmess .. "I"
vim.o.fillchars = "eob: "
vim.o.scrolloff = 4

vim.cmd.colorscheme("catppuccin-mocha")
require("mini.icons").setup()
require("snacks").setup({ picker = { enabled = true } })
require("render-markdown").setup({})
require("learncpp").setup({})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function()
    pcall(vim.treesitter.start)
  end,
})
