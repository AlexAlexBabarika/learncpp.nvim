-- Table of contents and site index parsing, on markup shaped like the
-- minified learncpp.com home page and site index page.
local source = debug.getinfo(1, "S").source:sub(2)
vim.opt.rtp:prepend(vim.fn.fnamemodify(source, ":p:h:h"))
local store = require("learncpp.store")

local checks = 0
local function eq(actual, expected, what)
  checks = checks + 1
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\n  actual: %s"):format(what, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local chapters, rows = store.parse_toc(table.concat({
  "<div class=lessontable><div class=lessontable-header><a name=Chapter0></a>",
  "<div class=lessontable-header-chapter>Chapter 0</div><div class=lessontable-header-title>Introduction / Getting Started</div></div>",
  "<div class=lessontable-list><div class=lessontable-row><div class=lessontable-row-number>0.1</div>",
  "<div class=lessontable-row-title><a href=https://www.learncpp.com/cpp-tutorial/introduction-to-these-tutorials/>Introduction to these tutorials</a></div></div>",
  "<div class=lessontable-row><div class=lessontable-row-number>0.2</div>",
  '<div class=lessontable-row-title><a href=https://www.learncpp.com/cpp-tutorial/compilers/>Compilers &amp; linkers</a></div><div class="lessontable-row-tag lessontable-split">Split</div></div>',
  "</div></div><div class=lessontable><div class=lessontable-header>",
  "<div class=lessontable-header-chapter>Chapter 1</div><div class=lessontable-header-title>C++ Basics</div></div>",
  "<div class=lessontable-list><div class=lessontable-row><div class=lessontable-row-number>1.1</div>",
  "<div class=lessontable-row-title><a href=https://www.learncpp.com/cpp-tutorial/statements/>Statements</a></div></div></div></div>",
}))
eq(chapters, {
  { label = "Chapter 0", title = "Introduction / Getting Started" },
  { label = "Chapter 1", title = "C++ Basics" },
}, "chapters")
eq(rows, {
  { slug = "introduction-to-these-tutorials", number = "0.1", title = "Introduction to these tutorials", chapter = 1 },
  { slug = "compilers", number = "0.2", title = "Compilers & linkers", chapter = 1 },
  { slug = "statements", number = "1.1", title = "Statements", chapter = 2 },
}, "lesson rows keep their chapter and ignore the update tag")

eq(store.parse_terms(table.concat({
  "<li id=menu-item-1 class=menu-item><a href=https://www.learncpp.com/>Home</a>",
  '<div id=wid><ul><li id=Abort>Abort, <a class=index href=https://www.learncpp.com/cpp-tutorial/halts/>8.12</a>',
  '<li id="Access function">Access function, see <a class=index href="#Function, Access">Function, Access</a>',
  '<li id="Function, Access">Access, <a class=index href=https://www.learncpp.com/cpp-tutorial/access-functions/>14.6</a>',
  '<li id="Operators, Member selection from pointer (-&gt;)">Member selection from pointer (-&gt;), ',
  "<a class=index href=https://www.learncpp.com/cpp-tutorial/member-selection/>13.12</a>, <a class=index href=https://www.learncpp.com/cpp-tutorial/member-selection/>13.12</a>",
  "<li id=Empty>Empty</ul></div>",
})), {
  { term = "Abort", slugs = { "halts" } },
  { term = "Access function", slugs = { "access-functions" } },
  { term = "Function, Access", slugs = { "access-functions" } },
  { term = "Operators, Member selection from pointer (->)", slugs = { "member-selection" } },
}, "index terms resolve 'see' references and drop entries without lessons")

eq(store.slug_of("https://www.learncpp.com/cpp-tutorial/the-virtual-table/#vptr"), "the-virtual-table", "slug from a lesson URL")
eq(store.slug_of("https://en.cppreference.com/w/cpp"), nil, "other sites have no slug")

print(("store: %d checks passed"):format(checks))
