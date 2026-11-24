-- Lesson links are shown as their text alone; the function reports where each
-- one went so the reader can keep the target on an extmark.
local source = debug.getinfo(1, "S").source:sub(2)
vim.opt.rtp:prepend(vim.fn.fnamemodify(source, ":p:h:h"))
local reader = require("learncpp.reader")

local checks = 0
local function eq(actual, expected, what)
  checks = checks + 1
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\n  actual: %s"):format(what, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local lines = {
  "See [10.6 -- Casting](https://www.learncpp.com/cpp-tutorial/casting/), then [this](<https://x.test/a (b)>).",
  "A lambda `[=](int x) { return x; }` is not a link, but [this](https://x.test/c) is.",
  "```cpp",
  "auto f{ [](int x) { return x; } };",
  "```",
  "| [cell](https://x.test/d) | padded |",
  "![string search](https://x.test/e.png)",
  "> Related: [`std::move`](https://x.test/f)",
}
local links = reader.plain_links(lines)

eq(lines, {
  "See 10.6 -- Casting, then this.",
  "A lambda `[=](int x) { return x; }` is not a link, but this is.",
  "```cpp",
  "auto f{ [](int x) { return x; } };",
  "```",
  "| [cell](https://x.test/d) | padded |",
  "(image: string search)",
  "> Related: `std::move`",
}, "links collapse to their text; code and table rows are untouched")

eq(links, {
  { row = 1, col = 4, end_col = 19, url = "https://www.learncpp.com/cpp-tutorial/casting/" },
  { row = 1, col = 26, end_col = 30, url = "https://x.test/a (b)" },
  { row = 2, col = 55, end_col = 59, url = "https://x.test/c" },
  { row = 7, col = 0, end_col = 22, url = "https://x.test/e.png" },
  { row = 8, col = 11, end_col = 22, url = "https://x.test/f" },
}, "each link reports its position in the rewritten line")

print(("reader: %d checks passed"):format(checks))
