local M = {}

M.defaults = {
  cache_dir = vim.fn.stdpath("cache") .. "/learncpp",
  open = "edit", -- where a lesson opens: "edit" | "split" | "vsplit" | "tab"
  style = true, -- boxed code, callouts and solutions; uses render-markdown.nvim when it is installed
  win = { -- window options while a lesson is shown
    wrap = true,
    linebreak = true,
    breakindent = true,
    breakindentopt = "list:-1",
    spell = false,
    list = false,
    number = false,
    relativenumber = false,
    cursorline = false,
    colorcolumn = "",
    signcolumn = "yes:1",
    statuscolumn = "",
    foldcolumn = "0",
  },
  keys = { -- buffer-local keys in lesson buffers; set one to false to leave it unmapped
    follow = "<CR>", -- follow the link under the cursor, or reveal/hide a solution
    next = "]l",
    prev = "[l",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
