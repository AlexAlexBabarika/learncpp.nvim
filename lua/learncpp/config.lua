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
  hints = true, -- show the run and edit keys in the header of each C++ code block
  run = { -- running a lesson's code block
    compiler = nil, -- defaults to $CXX, then the first of clang++, g++, c++
    flags = { "-std=c++23" },
    sandbox = true, -- macOS: the program gets no network and cannot write outside its temporary directory
    height = 12, -- of the output window
  },
  keys = { -- buffer-local keys in lesson buffers; set one to false to leave it unmapped
    follow = "<CR>", -- follow the link under the cursor, or reveal/hide a solution
    next = "]l",
    prev = "[l",
    run = "r", -- compile and run the code block under the cursor
    edit = "o", -- open that block as a scratch file you can change
    scratch_run = "<CR>", -- in the scratch file: run it
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
