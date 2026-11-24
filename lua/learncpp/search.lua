local store = require("learncpp.store")

local M = {}

local OPS = {
  "<=>", "<<=", ">>=", "->*", "...",
  "::", "->", ".*", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "++", "--",
  "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
}
local OP_CHAR = "[%+%-%*/%%=<>!&|%^~%?:%.,]"

-- Meanings of an operator token that the site index files under a name instead of the symbol.
local TOPICS = {
  ["&"] = { "lvalue reference" },
  ["&&"] = { "rvalue reference", "r-value reference" },
  ["..."] = { "ellipsis" },
  ["<=>"] = { "spaceship operator" },
  ["?"] = { "?:" },
  [":"] = { "?:" },
}

local LIMIT = 40
local cache = {}

local function count(text, needle, is_plain)
  local n, pos = 0, 1
  while true do
    local s, e = text:find(needle, pos, is_plain)
    if not s then
      return n
    end
    n, pos = n + 1, math.max(e, s) + 1
  end
end

local function name_of(s)
  return vim.trim((s:gsub("%s*%b()%s*$", ""))):lower()
end

local function prepare(index)
  if cache.index == index then
    return cache
  end
  cache = { index = index, docs = {}, entries = {} }
  for i, lesson in ipairs(index.lessons) do
    local lines = store.read(lesson.slug) or {}
    local heads = {}
    for lnum, line in ipairs(lines) do
      if line:find("^#") then
        heads[#heads + 1] = line:lower()
      elseif line == "<" .. store.url(lesson.slug) .. ">" then
        lines[lnum] = ""
      end
    end
    cache.docs[i] = {
      lines = lines,
      lower = table.concat(lines, "\n"):lower(),
      title = lesson.title:lower(),
      heads = table.concat(heads, "\n"),
    }
  end
  for _, item in ipairs(index.terms or {}) do
    local head, tail = item.term:match("^(.-), (.*)$")
    local entry = { term = item.term, slugs = item.slugs, head = name_of(head or item.term), aliases = {} }
    entry.tail = tail and name_of(tail)
    local inner = item.term:match("(%b())%s*$")
    for alias in ((inner and inner:sub(2, -2) or "") .. ", "):gmatch("(.-), ") do
      entry.aliases[alias:lower()] = true
    end
    cache.entries[#cache.entries + 1] = entry
  end
  return cache
end

--- The C++ symbol at byte column `col` (0-based) of `line`: a possibly
--- qualified name, a preprocessor directive, `operator<<`, or an operator token.
function M.symbol_at(line, col)
  local at = col + 1
  local c = line:sub(at, at)
  if c:find("[%w_]") then
    local s, e = at, at
    while line:sub(s - 1, s - 1):find("[%w_]") do
      s = s - 1
    end
    while line:sub(e + 1, e + 1):find("[%w_]") do
      e = e + 1
    end
    while true do
      local qualifier = line:sub(1, s - 1):match("()[%a_][%w_]*::$")
      if not qualifier then
        break
      end
      s = qualifier
    end
    while true do
      local member_end = line:match("^::~?[%a_][%w_]*()", e + 1)
      if not member_end then
        break
      end
      e = member_end - 1
    end
    local word = line:sub(s, e)
    if word == "operator" then
      for _, pattern in ipairs({ "^%s*(" .. OP_CHAR .. "+)", "^%s*(%(%))", "^%s*(%[%])" }) do
        local op = line:match(pattern, e + 1)
        if op then
          return word .. op
        end
      end
    end
    return (line:sub(1, s - 1):find("#%s*$") and "#" or "") .. word
  elseif c == "[" or c == "]" then
    return "[]"
  elseif c == "(" or c == ")" then
    return "()"
  elseif not c:find(OP_CHAR) then
    return nil
  end
  local s, e = at, at
  while line:sub(s - 1, s - 1):find(OP_CHAR) do
    s = s - 1
  end
  while line:sub(e + 1, e + 1):find(OP_CHAR) do
    e = e + 1
  end
  local pos = s
  while pos <= e do
    local token = line:sub(pos, pos)
    for _, op in ipairs(OPS) do
      if line:sub(pos, pos + #op - 1) == op then
        token = op
        break
      end
    end
    if at < pos + #token then
      return token
    end
    pos = pos + #token
  end
end

local function variants(query)
  local q = vim.trim(query):lower()
  local op = q:match("^operator%s*(%A+)$") or (not q:find("[%w_]") and q)
  if op then
    return vim.list_extend({ op }, TOPICS[op] or {})
  end
  q = q:gsub("%(%)$", ""):gsub("^::", ""):gsub("^std::", "")
  local list = { q }
  for _, alt in ipairs({ q:match("::([^:]+)$") or false, q:match("^#(.+)$") or false }) do
    if alt then
      list[#list + 1] = alt
    end
  end
  return list
end

-- Whole-word match that also accepts a plural, since prose and titles say "references" for `reference`.
local function word_pattern(q)
  return (q:find("^[%w_]") and "%f[%w_]" or "") .. vim.pesc(q) .. (q:find("[%w_]$") and "s?%f[^%w_]" or "")
end

local function text_score(doc, q)
  if not q:find("[%w_]") then
    local n = count(doc.lower, "`" .. q .. "`", true) + count(doc.lower, "operator" .. q, true)
    return math.min(n, 10) * 2, n
  end
  local pattern = word_pattern(q)
  local n = count(doc.lower, pattern)
  if n == 0 then
    return 0, 0
  end
  local score = math.min(n, 20) + (doc.heads:find(pattern) and 25 or 0)
  if doc.title:find(pattern) then
    score = score + 60 + math.floor(40 * #q / #doc.title)
  end
  return score + (doc.lower:find("**" .. q .. "**", 1, true) and 30 or 0), n
end

local function index_score(entry, q)
  if not q:find("[%w_]") then
    return entry.aliases[q] and 100 or 0
  elseif entry.head == q then
    return entry.tail and 25 or 100
  end
  return (entry.tail == q or entry.aliases[q]) and 90 or 0
end

--- Lessons relevant to a C++ symbol, best first: `{ lesson, score, why }`.
--- The site's own index decides when it knows the symbol; mentions in the
--- lesson text fill in everything it has not indexed yet.
function M.lookup(index, query)
  local data, qs = prepare(index), variants(query)
  local from_index = {}
  for _, entry in ipairs(data.entries) do
    local best = 0
    for _, q in ipairs(qs) do
      best = math.max(best, index_score(entry, q))
    end
    -- An index entry lists the lesson that introduces a term first; keep that one ahead of its sequels.
    for position, slug in ipairs(best > 0 and entry.slugs or {}) do
      local score = best - math.min(position - 1, 2) * 20
      if score > (from_index[slug] and from_index[slug].score or 0) then
        from_index[slug] = { score = score, term = entry.term }
      end
    end
  end
  local results = {}
  for i, lesson in ipairs(index.lessons) do
    local score, mentions = 0, 0
    for _, q in ipairs(qs) do
      local s, n = text_score(data.docs[i], q)
      score, mentions = math.max(score, s), math.max(mentions, n)
    end
    local hit = from_index[lesson.slug]
    if hit or score > 0 then
      results[#results + 1] = {
        lesson = lesson,
        score = score + (hit and hit.score or 0),
        why = hit and "index: " .. hit.term or mentions .. (mentions == 1 and " mention" or " mentions"),
      }
    end
  end
  table.sort(results, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.lesson.order < b.lesson.order
  end)
  return vim.list_slice(results, 1, LIMIT)
end

--- Lessons containing every word of `query`, best first: `{ lesson, score, line, why }`.
--- The words appearing together as a phrase outranks them scattered over the lesson.
function M.search(index, query)
  local data, results = prepare(index), {}
  local phrase = vim.trim(query):lower():gsub("%s+", " ")
  local words = vim.split(phrase, " ", { plain = true })
  for i, lesson in ipairs(index.lessons) do
    local doc, score = data.docs[i], 0
    for _, word in ipairs(words) do
      local n = count(doc.lower, word, true)
      if n == 0 then
        score = nil
        break
      end
      score = score + math.min(n, 20)
      score = score + (doc.title:find(word, 1, true) and 50 or 0) + (doc.heads:find(word, 1, true) and 20 or 0)
    end
    if score then
      local together = #words > 1 and count(doc.lower, phrase, true) or 0
      if together > 0 then
        score = score + math.min(together, 20) * 5
        score = score + (doc.title:find(phrase, 1, true) and 100 or 0) + (doc.heads:find(phrase, 1, true) and 60 or 0)
      end
      local hit
      local needle = together > 0 and phrase or words[1]
      for lnum, line in ipairs(doc.lines) do
        if line:lower():find(needle, 1, true) then
          hit = lnum
          break
        end
      end
      results[#results + 1] = {
        lesson = lesson,
        score = score,
        line = hit,
        why = hit and vim.trim(doc.lines[hit]):sub(1, 100) or "",
      }
    end
  end
  table.sort(results, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.lesson.order < b.lesson.order
  end)
  return vim.list_slice(results, 1, LIMIT)
end

return M
