-- Symbol extraction and lesson ranking, against a small cache written to a
-- temporary directory.
local source = debug.getinfo(1, "S").source:sub(2)
vim.opt.rtp:prepend(vim.fn.fnamemodify(source, ":p:h:h"))
local search = require("learncpp.search")
local store = require("learncpp.store")

local checks = 0
local function eq(actual, expected, what)
  checks = checks + 1
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\n  actual: %s"):format(what, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

-- `|` marks the cursor.
local function symbol(marked)
  local col = marked:find("|", 1, true) - 1
  return search.symbol_at(marked:sub(1, col) .. marked:sub(col + 2), col)
end

eq(symbol("    std::string_v|iew name{};"), "std::string_view", "qualified name from its last component")
eq(symbol("    s|td::ranges::sort(v);"), "std::ranges::sort", "qualified name from its first component")
eq(symbol("    auto* d{ dynamic|_cast<Derived*>(b) };"), "dynamic_cast", "keyword")
eq(symbol("    return ptr-|>value;"), "->", "two-character operator, from its second character")
eq(symbol("    std::cout |<< x;"), "<<", "operator next to a space")
eq(symbol("    a <|=> b"), "<=>", "longest operator wins")
eq(symbol("    x = cond |? a : b;"), "?", "conditional operator")
eq(symbol("    int& r|ef{ x };"), "ref", "identifier beside an operator")
eq(symbol("    int|& ref{ x };"), "&", "operator beside an identifier")
eq(symbol("    arr[|0] = 1;"), "0", "literal")
eq(symbol("    arr|[0] = 1;"), "[]", "subscript")
eq(symbol("#incl|ude <iostream>"), "#include", "preprocessor directive")
eq(symbol("    std::ostream& oper|ator<<(std::ostream& out, const Foo& f)"), "operator<<", "operator function name")
eq(symbol("    foo( |  );"), nil, "whitespace")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/lessons", "p")
require("learncpp.config").setup({ cache_dir = dir })

local index = { chapters = {}, lessons = {}, by_slug = {}, terms = {} }
local function lesson(number, slug, title, body)
  local entry = { slug = slug, number = number, title = title, chapter = 1, spoilers = {}, order = #index.lessons + 1 }
  index.lessons[entry.order], index.by_slug[slug] = entry, entry
  local lines = vim.list_extend({ "# " .. number .. " — " .. title, "", "<" .. store.url(slug) .. ">", "" }, body)
  vim.fn.writefile(lines, store.lesson_path(slug))
end

lesson("5.8", "introduction-to-stdstring_view", "Introduction to std::string_view", {
  "## std::string_view",
  "A `std::string_view` is a read-only view. Use `std::string_view` for parameters.",
})
lesson("5.9", "stdstring_view-part-2", "std::string_view (part 2)", {
  "More on `std::string_view`. A std::string_view does not own its string.",
})
lesson("12.3", "lvalue-references", "Lvalue references", {
  "An **lvalue reference** aliases an object. Many lvalue references are const.",
  "## Dangling references",
  "A dangling reference outlives its object.",
})
lesson("13.12", "member-selection", "Member selection with pointers and references", {
  "Use `->` on a pointer. The `operator->` can be overloaded. A dangling pointer is as bad as a reference that dangles.",
})
lesson("14.9", "constructors", "Introduction to constructors", {
  "Pass a std::string_view here. Prefer `ptr->value` over `(*ptr).value`.",
})
lesson("25.10", "dynamic-casting", "Dynamic casting", {
  "## dynamic_cast",
  "`dynamic_cast` converts base pointers to derived pointers. A failed dynamic_cast returns a null pointer.",
})
index.terms = {
  { term = "String_view", slugs = { "introduction-to-stdstring_view", "stdstring_view-part-2" } },
  { term = "Operators, Member selection from pointer (->)", slugs = { "member-selection" } },
  { term = "Operators, Arithmetic (+, -, *, /, %)", slugs = { "constructors" } },
  { term = "Reference", slugs = { "lvalue-references" } },
  { term = "Reference, Dangling", slugs = { "lvalue-references" } },
}

local function numbers(results)
  return vim.tbl_map(function(result)
    return result.lesson.number
  end, results)
end

eq(
  numbers(search.lookup(index, "std::string_view")),
  { "5.8", "5.9", "14.9" },
  "std:: is dropped; indexed lessons beat a mention, the introducing one first"
)
eq(search.lookup(index, "std::string_view")[1].why, "index: String_view", "the index term is given as the reason")
eq(numbers(search.lookup(index, "->")), { "13.12" }, "an operator resolves through the index, not through code that uses it")
eq(numbers(search.lookup(index, "operator->")), { "13.12" }, "operator-> is the same lookup")
eq(numbers(search.lookup(index, "*")), { "14.9" }, "one operator out of a group listed in the index")
eq(numbers(search.lookup(index, "dynamic_cast")), { "25.10" }, "an unindexed name is found in the lesson text")
eq(numbers(search.lookup(index, "&"))[1], "12.3", "& also means an lvalue reference, matched in a plural title")
eq(numbers(search.lookup(index, "dangling")), { "12.3", "13.12" }, "a subtopic of an index entry")
eq(numbers(search.lookup(index, "learncpp")), {}, "the lesson URL is not lesson text")

local hits = search.search(index, "dangling reference")
eq(numbers(hits), { "12.3", "13.12" }, "the phrase outranks the same words scattered")
eq({ hits[1].line, hits[1].why }, { 6, "## Dangling references" }, "a hit points at the first line with the phrase")
eq(numbers(search.search(index, "nothing here")), {}, "every word must occur")

print(("search: %d checks passed"):format(checks))
