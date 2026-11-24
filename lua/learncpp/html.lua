local M = {}

local VOID = { br = true, img = true, hr = true, input = true, meta = true, link = true }
local RAW = { script = true, style = true }
local SKIP = { script = true, style = true, form = true, input = true }
local BLOCK = {}
for tag in ("p div pre ul ol li table thead tbody tr td th blockquote h1 h2 h3 h4 h5 h6 hr footer"):gmatch("%S+") do
  BLOCK[tag] = true
end

local ENTITIES = {
  lt = "<", gt = ">", amp = "&", quot = '"', apos = "'", nbsp = " ",
  ndash = "–", mdash = "—", hellip = "…", lsquo = "‘", rsquo = "’", ldquo = "“", rdquo = "”",
}

-- The site colours its note boxes by purpose: gray asides, blue insights, green best practices,
-- red warnings, purple rules and yellow tool-specific notes.
local CALLOUTS = { blue = "TIP", green = "SUCCESS", red = "WARNING", purple = "IMPORTANT", yellow = "INFO" }
local SPOILERS = { wpsolution = "Solution", wphint = "Hint", wptasks = "Tasks" }
local START, END = "\1S", "\1E"

local function utf8(n)
  if n < 0x80 then
    return string.char(n)
  elseif n < 0x800 then
    return string.char(0xC0 + math.floor(n / 0x40), 0x80 + n % 0x40)
  elseif n < 0x10000 then
    return string.char(0xE0 + math.floor(n / 0x1000), 0x80 + math.floor(n / 0x40) % 0x40, 0x80 + n % 0x40)
  end
  return string.char(
    0xF0 + math.floor(n / 0x40000),
    0x80 + math.floor(n / 0x1000) % 0x40,
    0x80 + math.floor(n / 0x40) % 0x40,
    0x80 + n % 0x40
  )
end

function M.decode(s)
  return (s:gsub("&(#?)([%w]+);", function(hash, body)
    if hash == "" then
      return ENTITIES[body]
    end
    local n = body:match("^[xX]") and tonumber(body:sub(2), 16) or tonumber(body)
    if n == 160 then
      return " "
    end
    return n and n < 0x110000 and utf8(n) or nil
  end))
end

local function parse_attrs(src, pos)
  local attrs = {}
  while true do
    pos = src:find("%S", pos) or #src + 1
    local c = src:sub(pos, pos)
    if c == ">" or c == "" then
      return attrs, pos
    end
    local name, after = src:match("^([^%s=/>]+)()", pos)
    if not name then
      pos = pos + 1
    else
      pos = after
      local eq = src:match("^%s*=%s*()", pos)
      local q = eq and src:sub(eq, eq)
      if q == '"' or q == "'" then
        local e = src:find(q, eq + 1, true) or #src
        attrs[name:lower()] = src:sub(eq + 1, e - 1)
        pos = e + 1
      elseif eq then
        attrs[name:lower()], pos = src:match("^([^%s>]*)()", eq)
      else
        attrs[name:lower()] = ""
      end
    end
  end
end

--- Flat token stream: `{ text = s }`, `{ open = tag, attrs = {} }` or `{ close = tag }`.
--- Tolerates what minified pages do: unquoted attributes and omitted closing tags.
function M.tokenize(src)
  local tokens, pos, len = {}, 1, #src
  while pos <= len do
    local lt = src:find("<", pos, true)
    if not lt then
      tokens[#tokens + 1] = { text = src:sub(pos) }
      break
    end
    if lt > pos then
      tokens[#tokens + 1] = { text = src:sub(pos, lt - 1) }
    end
    if src:sub(lt, lt + 3) == "<!--" then
      local _, e = src:find("-->", lt + 4, true)
      pos = (e or len) + 1
    else
      local close, name, after = src:match("^<(/?)(%a[%w:-]*)()", lt)
      if not name then
        tokens[#tokens + 1] = { text = "<" }
        pos = lt + 1
      else
        name = name:lower()
        local attrs, gt = parse_attrs(src, after)
        pos = gt + 1
        if close == "/" then
          tokens[#tokens + 1] = { close = name }
        else
          tokens[#tokens + 1] = { open = name, attrs = attrs }
          if RAW[name] then
            local _, e = src:find("</" .. name .. "%s*>", pos)
            pos = (e or len) + 1
            tokens[#tokens + 1] = { close = name }
          end
        end
      end
    end
  end
  return tokens
end

local function has_class(node, class)
  local classes = node.attrs and node.attrs.class
  return classes ~= nil and (" " .. classes .. " "):find(" " .. class .. " ", 1, true) ~= nil
end

local function parse(src)
  local root = { tag = "#root", children = {} }
  local stack = { root }
  local function pop_through(tag, stop)
    for i = #stack, 2, -1 do
      local open = stack[i].tag
      if tag[open] then
        for _ = i, #stack do
          stack[#stack] = nil
        end
        return
      elseif stop[open] then
        return
      end
    end
  end
  local LIST, TABLE, NONE = { ul = true, ol = true }, { table = true }, {}
  for _, tok in ipairs(M.tokenize(src)) do
    if tok.text then
      table.insert(stack[#stack].children, { text = tok.text })
    elseif tok.open then
      local tag = tok.open
      if BLOCK[tag] then
        while stack[#stack].tag == "p" do
          stack[#stack] = nil
        end
      end
      if tag == "li" then
        pop_through({ li = true }, LIST)
      elseif tag == "tr" then
        pop_through({ tr = true }, TABLE)
      elseif tag == "td" or tag == "th" then
        pop_through({ td = true, th = true }, TABLE)
      end
      local node = { tag = tag, attrs = tok.attrs, children = {} }
      table.insert(stack[#stack].children, node)
      if not VOID[tag] then
        stack[#stack + 1] = node
      end
    else
      pop_through({ [tok.close] = true }, NONE)
    end
  end
  return root
end

local function text_of(node, buf)
  buf = buf or {}
  if node.text then
    buf[#buf + 1] = node.text
  elseif node.tag == "br" then
    buf[#buf + 1] = "\n"
  else
    for _, child in ipairs(node.children) do
      text_of(child, buf)
    end
  end
  return buf
end

local function plain(node)
  return M.decode(table.concat(text_of(node)))
end

local function escape(text)
  return (text:gsub("[*`]", "\\%0"):gsub("<([%a/!?])", "\\<%1"))
end

local function code_span(text)
  text = vim.trim(text:gsub("%s+", " "))
  if text == "" then
    return ""
  end
  return text:find("`", 1, true) and ("`` " .. text .. " ``") or ("`" .. text .. "`")
end

local function width(s)
  return select(2, s:gsub("[^\128-\191]", ""))
end

local inline

local function wrap(delim, nodes, ctx)
  local lead, core, trail = inline(nodes, ctx):match("^(%s*)(.-)(%s*)$")
  return core == "" and lead .. trail or lead .. delim .. core .. delim .. trail
end

local function link(node, ctx)
  local text = vim.trim(inline(node.children, ctx))
  local href = M.decode(node.attrs.href or "")
  if href == "" or href:find("^#") or href:find("^javascript:") then
    return text
  elseif href:find("^//") then
    href = "https:" .. href
  elseif href:find("^/") then
    href = ctx.base .. href
  end
  if text == "" or text == href then
    return "<" .. href .. ">"
  end
  return ("[%s](%s)"):format(text, href:find("[%s()]") and "<" .. href .. ">" or href)
end

function inline(nodes, ctx)
  local buf = {}
  for _, node in ipairs(nodes) do
    local tag = node.tag
    if node.text then
      buf[#buf + 1] = escape(M.decode(node.text):gsub("%s+", " "))
    elseif tag == "br" then
      buf[#buf + 1] = "\n"
    elseif tag == "code" or tag == "pre" then
      buf[#buf + 1] = code_span(plain(node))
    elseif tag == "strong" or tag == "b" then
      buf[#buf + 1] = wrap("**", node.children, ctx)
    elseif tag == "em" or (tag == "i" and not has_class(node, "fa")) then
      buf[#buf + 1] = wrap("*", node.children, ctx)
    elseif tag == "a" then
      buf[#buf + 1] = link(node, ctx)
    elseif tag == "img" then
      buf[#buf + 1] = ("![%s](%s)"):format(M.decode(node.attrs.alt or ""), node.attrs.src or "")
    elseif tag == "sup" then
      buf[#buf + 1] = "^" .. inline(node.children, ctx)
    elseif has_class(node, "cpp-section-pill") then
      buf[#buf + 1] = " (" .. vim.trim(inline(node.children, ctx)) .. ")"
    elseif not SKIP[tag] and tag ~= "i" then
      buf[#buf + 1] = inline(node.children, ctx)
    end
  end
  return (table.concat(buf):gsub(" +", " "):gsub(" ?\n ?", "\n"))
end

local function prefixed(lines, first, rest)
  local out = {}
  for i, line in ipairs(lines) do
    local pre = i == 1 and first or rest
    out[i] = line == "" and (pre:gsub("%s+$", "")) or pre .. line
  end
  return out
end

local function paragraph(nodes, ctx)
  local text = vim.trim(inline(nodes, ctx))
  if text == "" then
    return nil
  end
  local lines = vim.split(text, "\n", { plain = true })
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("^[#>]", "\\%0")
  end
  return lines
end

local function fence(node)
  local code
  for _, child in ipairs(node.children) do
    code = code or (child.tag == "code" and child)
  end
  local class = (code and code.attrs.class or "") .. " " .. (node.attrs.class or "")
  local text = plain(node):gsub("\r\n?", "\n"):gsub("^\n", ""):gsub("%s+$", "")
  local ticks = "```"
  for run in text:gmatch("`+") do
    if #run >= #ticks then
      ticks = ("`"):rep(#run + 1)
    end
  end
  local lines = vim.split(text, "\n", { plain = true })
  table.insert(lines, 1, ticks .. (class:match("language%-([%w+#]+)") or ""))
  lines[#lines + 1] = ticks
  return lines
end

local function rows_of(node, rows)
  for _, child in ipairs(node.children) do
    if child.tag == "tr" then
      rows[#rows + 1] = child
    elseif child.tag then
      rows_of(child, rows)
    end
  end
  return rows
end

local function table_block(node, ctx)
  local rows, widths = {}, {}
  for _, tr in ipairs(rows_of(node, {})) do
    local cells = {}
    for _, cell in ipairs(tr.children) do
      if cell.tag == "td" or cell.tag == "th" then
        local text = vim.trim(inline(cell.children, ctx)):gsub("%s*\n%s*", " "):gsub("|", "\\|")
        cells[#cells + 1] = text
        widths[#cells] = math.max(widths[#cells] or 3, width(text))
      end
    end
    if #cells > 0 then
      rows[#rows + 1] = cells
    end
  end
  local lines = {}
  for i, cells in ipairs(rows) do
    local padded = {}
    for col, w in ipairs(widths) do
      local text = cells[col] or ""
      padded[col] = text .. (" "):rep(w - width(text))
    end
    lines[#lines + 1] = "| " .. table.concat(padded, " | ") .. " |"
    if i == 1 then
      local rule = {}
      for col, w in ipairs(widths) do
        rule[col] = ("-"):rep(w)
      end
      lines[#lines + 1] = "| " .. table.concat(rule, " | ") .. " |"
    end
  end
  return #lines > 0 and lines or nil
end

local blocks

local function list(node, ctx)
  local lines, n = {}, 0
  for _, item in ipairs(node.children) do
    if item.tag == "li" then
      n = n + 1
      local marker = node.tag == "ol" and n .. ". " or "- "
      local body = blocks(item.children, ctx, true)
      vim.list_extend(lines, prefixed(#body > 0 and body or { "" }, marker, (" "):rep(#marker)))
    end
  end
  return #lines > 0 and lines or nil
end

local function callout(node, ctx)
  local title, rest = nil, {}
  for _, child in ipairs(node.children) do
    if not title and has_class(child, "cpp-note-title") then
      title = vim.trim(inline(child.children, ctx)):gsub("\n", " ")
    else
      rest[#rest + 1] = child
    end
  end
  local kind = CALLOUTS[(node.attrs.class or ""):match("cpp%-light(%a-)background")] or "NOTE"
  local lines = prefixed(blocks(rest, ctx), "> ", "> ")
  table.insert(lines, 1, "> [!" .. kind .. "]" .. (title and " " .. title or ""))
  return lines
end

local function spoiler(label, node, ctx)
  local body = blocks(node.children, ctx)
  if #body == 0 then
    return nil
  end
  local lines = { START .. label, "" }
  vim.list_extend(lines, body)
  lines[#lines + 1] = END
  return lines
end

local function is_toggle(node)
  local only
  for _, child in ipairs(node.children) do
    if child.tag then
      if only then
        return false
      end
      only = child
    elseif child.text:find("%S") then
      return false
    end
  end
  return only ~= nil and only.tag == "a" and (only.attrs.class or ""):find("_link_show", 1, true) ~= nil
end

local function is_title(node)
  local only
  for _, child in ipairs(node.children) do
    if child.tag then
      if only then
        return false
      end
      only = child
    elseif child.text:find("%S") then
      return false
    end
  end
  return only ~= nil and (only.tag == "strong" or only.tag == "b") and not plain(only):find("%.%s*$")
end

local function heading(level, nodes, ctx)
  local text = vim.trim(inline(nodes, ctx)):gsub("\n", " "):gsub("^%*%*(.*)%*%*$", "%1")
  return text ~= "" and { ("#"):rep(level) .. " " .. text } or nil
end

local function block(node, ctx)
  local tag = node.tag
  if SKIP[tag] or has_class(node, "prevnext") then
    return nil
  elseif tag == "p" then
    if is_toggle(node) then
      return nil
    elseif has_class(node, "cpp-section") or is_title(node) then
      return heading(2, node.children, ctx)
    elseif has_class(node, "quiz-header") or has_class(node, "cpp-quiz-question") then
      return heading(3, node.children, ctx)
    end
    return paragraph(node.children, ctx)
  elseif tag == "pre" then
    return fence(node)
  elseif tag == "ul" or tag == "ol" then
    return list(node, ctx)
  elseif tag == "table" then
    return table_block(node, ctx)
  elseif tag == "hr" then
    return { "---" }
  elseif tag == "blockquote" then
    return prefixed(blocks(node.children, ctx), "> ", "> ")
  elseif tag:find("^h%d$") then
    return heading(math.max(2, tonumber(tag:sub(2))), node.children, ctx)
  elseif has_class(node, "cpp-note") then
    return callout(node, ctx)
  end
  for class, label in pairs(SPOILERS) do
    if has_class(node, class) then
      return spoiler(label, node, ctx)
    end
  end
  local lines = blocks(node.children, ctx)
  return #lines > 0 and lines or nil
end

function blocks(nodes, ctx, tight)
  local out, run = {}, {}
  local function add(lines, is_list)
    if not lines then
      return
    end
    if #out > 0 and not (tight and is_list) then
      out[#out + 1] = ""
    end
    vim.list_extend(out, lines)
  end
  local function flush()
    if #run > 0 then
      add(paragraph(run, ctx))
      run = {}
    end
  end
  for _, node in ipairs(nodes) do
    if node.tag and BLOCK[node.tag] then
      flush()
      add(block(node, ctx), node.tag == "ul" or node.tag == "ol")
    else
      run[#run + 1] = node
    end
  end
  flush()
  return out
end

--- Convert lesson HTML to Markdown lines. `spoilers` are `{ first, last }` line
--- ranges (1-based, starting at the label line) of solutions, hints and tasks
--- the site keeps collapsed.
function M.convert(src, base)
  local lines, spoilers, open = {}, {}, {}
  for _, line in ipairs(blocks(parse(src).children, { base = base or "" })) do
    local pre, label = line:match("^(.-)" .. START .. "(.*)$")
    if label then
      lines[#lines + 1] = pre .. "**" .. label .. "**"
      open[#open + 1] = #lines
    elseif line:find(END, 1, true) then
      spoilers[#spoilers + 1] = { table.remove(open), #lines }
    else
      lines[#lines + 1] = line
    end
  end
  table.sort(spoilers, function(a, b)
    return a[1] < b[1]
  end)
  return { lines = lines, spoilers = spoilers }
end

return M
