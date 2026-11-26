-- Finding the code block under the cursor, building the run script, and one
-- real compile-and-run through the terminal (skipped without a C++ compiler).
local source = debug.getinfo(1, "S").source:sub(2)
vim.opt.rtp:prepend(vim.fn.fnamemodify(source, ":p:h:h"))
local run = require("learncpp.run")

local checks = 0
local function eq(actual, expected, what)
  checks = checks + 1
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\n  actual: %s"):format(what, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local lines = {
  "Some prose.", -- 1
  "```cpp", -- 2
  "int main()", -- 3
  "{", -- 4
  "}", -- 5
  "```", -- 6
  "", -- 7
  "```", -- 8
  "Hello", -- 9
  "```", -- 10
  "> [!NOTE] Aside", -- 11
  "> ```cpp", -- 12
  "> int x{};", -- 13
  ">", -- 14
  "> int y{};", -- 15
  "> ```", -- 16
  "- item", -- 17
  "  ```cpp", -- 18
  "  void f()", -- 19
  "      ;", -- 20
  "  ```", -- 21
}

eq(run.block_at(lines, 1), nil, "prose is not a block")
eq(run.block_at(lines, 4), { lang = "cpp", first = 2, last = 6, code = { "int main()", "{", "}" } }, "inside a block")
eq(run.block_at(lines, 2).first, 2, "the opening fence belongs to its block")
eq(run.block_at(lines, 6).first, 2, "so does the closing fence")
eq(run.block_at(lines, 7), nil, "between blocks")
eq(run.block_at(lines, 9).lang, "", "program output is a block without a language")
eq(run.block_at(lines, 14).code, { "int x{};", "", "int y{};" }, "the quote prefix of a callout is removed")
eq(run.block_at(lines, 19).code, { "void f()", "    ;" }, "list indentation is removed, the code's own is kept")
eq(
  vim.tbl_map(function(block)
    return { block.lang, block.first, block.last }
  end, run.blocks(lines)),
  { { "cpp", 2, 6 }, { "", 8, 10 }, { "cpp", 12, 16 }, { "cpp", 18, 21 } },
  "all blocks of a lesson, in order"
)
eq({ run.has_main("int main()\n{}"), run.has_main("struct Domain {};") }, { true, false }, "only a whole program has main()")

require("learncpp.config").setup({ run = { flags = { "-std=c++23", "-DNAME='x y'" }, sandbox = false } })
eq(
  run.script("clang++", "/tmp/a b/main.cpp", "int main() {}", "/tmp"),
  [['clang++' '-std=c++23' '-DNAME='\''x y'\''' -o prog '/tmp/a b/main.cpp' && exec ./prog]],
  "arguments are quoted for sh"
)
eq(
  run.script("g++", "/tmp/main.cpp", "struct Domain {};", "/tmp"):match("%-fsyntax%-only") ~= nil,
  true,
  "code without main() is only checked ('Domain' does not count as main)"
)

if run.compiler() then
  require("learncpp.config").setup({})
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "```cpp",
    "#include <fstream>",
    "#include <iostream>",
    "int main()",
    "{",
    '    std::ofstream{ "here.txt" } << "x";',
    '    std::ofstream outside{ "' .. vim.env.HOME .. '/learncpp-sandbox-probe.txt" };',
    '    std::cout << "sum=" << 2 + 3 << " local=" << std::ifstream{ "here.txt" }.good()',
    '              << " outside=" << outside.good() << std::endl;',
    "    return 7;",
    "}",
    "```",
  })
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  local code
  vim.api.nvim_create_autocmd("TermClose", {
    callback = function()
      code = vim.v.event.status
    end,
  })
  run.run()
  vim.wait(60000, function()
    return code ~= nil
  end, 50)
  local term = vim.tbl_filter(function(buf)
    return vim.bo[buf].buftype == "terminal"
  end, vim.api.nvim_list_bufs())[1]
  local text = table.concat(vim.api.nvim_buf_get_lines(term, 0, -1, false), "\n")
  local sandboxed = vim.fn.executable("sandbox-exec") == 1
  eq(code, 7, "the program's exit status is the job's\n" .. text)
  eq(text:match("sum=5 local=1 outside=%d"), "sum=5 local=1 outside=" .. (sandboxed and 0 or 1), "output; writes stay inside")
  eq(vim.api.nvim_get_current_buf() ~= term, true, "focus stays on the code when the program reads no input")
  os.remove(vim.env.HOME .. "/learncpp-sandbox-probe.txt")
else
  print("run: no C++ compiler, skipping the real run")
end

print(("run: %d checks passed"):format(checks))
