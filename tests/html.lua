-- HTML -> Markdown conversion, on markup shaped like learncpp.com's lesson
-- bodies (WordPress output) and its minified pages.
local source = debug.getinfo(1, "S").source:sub(2)
vim.opt.rtp:prepend(vim.fn.fnamemodify(source, ":p:h:h"))
local html = require("learncpp.html")

local checks = 0
local function eq(actual, expected, what)
  checks = checks + 1
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\n  actual: %s"):format(what, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function lines(src)
  return html.convert(src, "https://www.learncpp.com").lines
end

eq(lines('<p class="cpp-section cpp-topline" style="clear: both">Consteval <span class="cpp-section-pill cpp-section-standard">C++20</span></p>'), {
  "## Consteval (C++20)",
}, "section paragraphs become headings, with the standard pill inline")

eq(lines("<p><strong>Pure virtual functions</strong></p>\n<p><strong>This is a sentence.</strong></p>"), {
  "## Pure virtual functions",
  "",
  "**This is a sentence.**",
}, "an all-bold paragraph is an old-style heading unless it reads as a sentence")

eq(lines('<p>A <strong>pure virtual function</strong> is <em>not</em> <code>std::vector&lt;int&gt;</code>, see <a href="/cpp-tutorial/the-virtual-table/">this</a> or <a href="javascript:void(0)">that</a>.</p>'), {
  "A **pure virtual function** is *not* `std::vector<int>`, see [this](https://www.learncpp.com/cpp-tutorial/the-virtual-table/) or that.",
}, "inline formatting, relative links made absolute, script links dropped")

eq(lines("<p>It&#8217;s in the &lt;string&gt; header; the operator (*) &amp;&nbsp;more.</p>"), {
  "It’s in the \\<string> header; the operator (\\*) & more.",
}, "entities are decoded and prose that would parse as Markdown is escaped")

eq(lines('<pre class="language-cpp line-numbers"><code class="language-cpp match-braces">#include &lt;iostream&gt;\r\n\r\nint main() {}\n</code></pre>\n<pre>Betsy says Moo\n</pre>'), {
  "```cpp",
  "#include <iostream>",
  "",
  "int main() {}",
  "```",
  "",
  "```",
  "Betsy says Moo",
  "```",
}, "code blocks keep their language; program output is a plain fence")

eq(lines('<div class="cpp-note cpp-lightgreenbackground">\n<p class="cpp-note-title cpp-bottomline">Best practice</p>\n<p>Use <code>constexpr</code>.</p>\n<p>Really.\n</div>'), {
  "> [!SUCCESS] Best practice",
  "> Use `constexpr`.",
  ">",
  "> Really.",
}, "notes become callouts, tolerating the unclosed paragraph WordPress emits")

eq(lines("<ul>\n<li>First\n</li>\n<li>Second<br />\nline\n<pre>out</pre>\n<ol><li>inner</li></ol>\n</li>\n</ul>"), {
  "- First",
  "- Second",
  "  line",
  "",
  "  ```",
  "  out",
  "  ```",
  "  1. inner",
}, "lists indent the blocks inside an item")

eq(lines('<div class="cpp-table-wrapper"><table class="cpp-table">\n<tr><th> Behavior </th><th> <code>std::optional</code> </th></tr>\n<tr><td> Get value </td><td> a | b </td></tr>\n</table></div>'), {
  "| Behavior  | `std::optional` |",
  "| --------- | --------------- |",
  "| Get value | a \\| b          |",
}, "tables are padded and pipes escaped")

local quiz = html.convert([[
<p>What is branch coverage?</p>
<p><a class="solution_link_show" href="javascript:void(0)" onclick="cppSolutionToggle(document.getElementById('cpp_solution_id_0'), this, 'Show Solution', 'Hide Solution')">Show Solution</a></p>
<div class="wpsolution" id="cpp_solution_id_0" style="display:none">
The percentage of branches executed.</div>
</p>
<div class="prevnext"><a class="nav-link" href="/">Back to table of contents</a></div>
]], "https://www.learncpp.com")
eq(quiz.lines, {
  "What is branch coverage?",
  "",
  "**Solution**",
  "",
  "The percentage of branches executed.",
}, "the show/hide toggle and the navigation buttons are dropped")
eq(quiz.spoilers, { { 3, 5 } }, "a solution reports the lines to keep hidden, label included")

local tokens = html.tokenize('<ul><li id="A, B">A, <a class=index href=https://x.test/a/>1.1</a><li id=C>C</ul>')
eq(tokens[2], { open = "li", attrs = { id = "A, B" } }, "quoted attribute")
eq(tokens[4], { open = "a", attrs = { class = "index", href = "https://x.test/a/" } }, "unquoted attributes, as minified pages write them")
eq(lines("<ul><li>one<li>two</ul>"), { "- one", "- two" }, "an omitted </li> still ends the item")

print(("html: %d checks passed"):format(checks))
