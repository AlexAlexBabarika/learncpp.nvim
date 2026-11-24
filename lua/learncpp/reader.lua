local config = require("learncpp.config")
local store = require("learncpp.store")
local style = require("learncpp.style")
local util = require("learncpp.util")

local M = {}

local bufs = {}
local link_ns = vim.api.nvim_create_namespace("learncpp_links")
local targets = {} -- buffer -> link extmark id -> url

vim.api.nvim_set_hl(0, "LearncppLink", { link = "Underlined", default = true })

-- Markdown links in `line`, skipping anything inside a code span (a lambda looks like a link).
local function links_in(line)
  local found, pos = {}, 1
  while true do
    local s, e, bang, text = line:find("(!?)%[([^%]]*)%]%(", pos)
    if not s then
      return found
    end
    local url, stop = line:match("^<([^>]+)>%)()", e + 1)
    if not url then
      url, stop = line:match("^([^)%s]+)%)()", e + 1)
    end
    local _, ticks = line:sub(1, s - 1):gsub("`", "")
    if url and ticks % 2 == 0 then
      found[#found + 1] = { s = s, e = stop - 1, text = text, url = url, image = bang == "!" }
    end
    pos = url and stop or e + 1
  end
end

--- Replace `[text](url)` with its text and report where each link went.
--- Neovim wraps a line by its raw text, so a URL that is merely concealed still
--- breaks the paragraph early, and lessons link to each other constantly.
--- Fenced code is left alone, as are table rows, whose cells were padded with
--- the link syntax in place.
function M.plain_links(lines)
  local links, fenced = {}, false
  for row, line in ipairs(lines) do
    if line:find("^[%s>]*```") then
      fenced = not fenced
    elseif not fenced and not line:find("^%s*|") then
      local out, len, pos = {}, 0, 1
      for _, link in ipairs(links_in(line)) do
        local before = line:sub(pos, link.s - 1)
        local label = link.image and ("(image: %s)"):format(link.text) or link.text ~= "" and link.text or link.url
        local col = len + #before
        links[#links + 1] = { row = row, col = col, end_col = col + #label, url = link.url }
        out[#out + 1], out[#out + 2], len, pos = before, label, col + #label, link.e + 1
      end
      if pos > 1 then
        lines[row] = table.concat(out) .. line:sub(pos)
      end
    end
  end
  return links
end

function M.foldtext()
  local pre, label = vim.fn.getline(vim.v.foldstart):match("^(.-)%*%*(.-)%*%*")
  local hidden = vim.v.foldend - vim.v.foldstart
  local key = config.options.keys.follow
  return {
    { (pre or "") .. "▸ " .. (label or "Hidden"), "LearncppSolutionTitle" },
    { ("   %d lines hidden%s"):format(hidden, key and ", " .. key .. " to reveal" or ""), "LearncppHint" },
  }
end

-- Solutions, hints and tasks start out folded, as the site keeps them collapsed.
local function setup_win(win, buf, slug)
  local lesson = store.index().by_slug[slug]
  local wo = vim.wo[win][0]
  for name, value in pairs(config.options.win) do
    wo[name] = value
  end
  wo.foldmethod, wo.foldenable = "manual", true
  wo.foldtext = "v:lua.require'learncpp.reader'.foldtext()"
  if config.options.style then
    style.highlights()
    wo.fillchars = (vim.o.fillchars ~= "" and vim.o.fillchars .. "," or "") .. "fold: "
    if not wo.winhighlight:find("Folded:", 1, true) then
      wo.winhighlight = (wo.winhighlight ~= "" and wo.winhighlight .. "," or "") .. "Folded:LearncppSolution"
    end
  end
  local last = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_call(win, function()
    vim.cmd("silent! normal! zE")
    for _, range in ipairs(lesson and lesson.spoilers or {}) do
      if range[2] <= last then
        vim.cmd(("silent %d,%dfold"):format(range[1], range[2]))
      end
    end
  end)
end

local function link_at(line, col)
  for _, link in ipairs(links_in(line)) do
    if col + 1 >= link.s and col + 1 <= link.e then
      return link.url
    end
  end
  local pos = 1
  while true do
    local s, e, url = line:find("<(https?://[^>]+)>", pos)
    if not s then
      return nil
    elseif col + 1 >= s and col + 1 <= e then
      return url
    end
    pos = e + 1
  end
end

local function current_slug()
  return vim.b.learncpp_slug
end

function M.follow()
  local lnum = vim.fn.line(".")
  if vim.fn.foldclosed(lnum) ~= -1 then
    return vim.cmd("normal! zo")
  end
  local index = store.index()
  local lesson = index.by_slug[current_slug()]
  for _, range in ipairs(lesson and lesson.spoilers or {}) do
    if range[1] == lnum then
      return vim.cmd("normal! zc")
    end
  end
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local pos = { lnum - 1, col }
  local mark = vim.api.nvim_buf_get_extmarks(0, link_ns, pos, pos, { overlap = true, limit = 1 })[1]
  local url = mark and (targets[vim.api.nvim_get_current_buf()] or {})[mark[1]]
    or link_at(vim.api.nvim_get_current_line(), col)
  local slug = url and store.slug_of(url)
  if slug and index.by_slug[slug] then
    M.open(slug)
  elseif url then
    vim.ui.open(url)
  end
end

function M.step(delta)
  local index = store.index()
  local lesson = index and index.by_slug[current_slug()]
  local target = lesson and index.lessons[lesson.order + delta]
  if not target then
    return util.notify(lesson and "No more lessons in that direction" or "Not in a lesson buffer")
  end
  M.open(target.slug)
end

-- The cached lesson plus links to its neighbours, which depend on the table of contents rather than the lesson.
local function content(slug)
  local lines = store.read(slug)
  local index = store.index()
  local lesson = index.by_slug[slug]
  if not (lines and lesson) then
    return nil
  end
  vim.list_extend(lines, { "", "---", "" })
  for _, nav in ipairs({ { "Previous", -1 }, { "Next", 1 } }) do
    local other = index.lessons[lesson.order + nav[2]]
    if other then
      lines[#lines + 1] = ("%s: [%s](%s)"):format(nav[1], store.label(other), store.url(other.slug))
    end
  end
  return lines
end

local function fill(buf, slug, lines)
  local links = M.plain_links(lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, link_ns, 0, -1)
  targets[buf] = {}
  for _, link in ipairs(links) do
    local mark = { end_col = link.end_col, hl_group = "LearncppLink", priority = 150 }
    targets[buf][vim.api.nvim_buf_set_extmark(buf, link_ns, link.row - 1, link.col, mark)] = link.url
  end
  if config.options.style then
    style.decorate(buf, lines, store.index().by_slug[slug].spoilers)
  end
end

local function create(slug)
  local lines = content(slug)
  if not lines then
    return nil
  end
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "learncpp://" .. slug)
  vim.b[buf].learncpp_slug = slug
  if config.options.style then
    style.attach(buf)
  end
  fill(buf, slug, lines)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      bufs[slug], targets[buf] = nil, nil
    end,
  })
  return buf
end

-- Runs once the buffer is in a window: filetype plugins and renderers set themselves up against the
-- window a buffer is shown in, and the lesson's own options have to come after theirs.
local function start(buf, slug)
  vim.bo[buf].filetype = "markdown"
  -- lets wrapped quote lines indent like list items, keeping the text clear of the quote bar
  vim.bo[buf].formatlistpat = [[^\s*\(\d\+[.)]\|[-*+>]\)\s\+]]

  local keys = config.options.keys
  local function map(lhs, rhs, desc)
    if lhs then
      vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
    end
  end
  map(keys.follow, M.follow, "Follow link or toggle solution")
  map(keys.next, function() M.step(1) end, "Next lesson")
  map(keys.prev, function() M.step(-1) end, "Previous lesson")

  setup_win(vim.api.nvim_get_current_win(), buf, slug)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_buf(win) == buf then
        setup_win(win, buf, slug)
      end
    end,
  })
end

--- Show a lesson in the current window (or a split, per `open`), optionally at `line`.
function M.open(slug, line)
  local buf = bufs[slug]
  local fresh = not (buf and vim.api.nvim_buf_is_valid(buf))
  if fresh then
    buf = create(slug)
    if not buf then
      return util.notify(("Lesson %s is not cached; run :LearnCpp sync"):format(slug), vim.log.levels.ERROR)
    end
    bufs[slug] = buf
  end
  if vim.api.nvim_get_current_buf() ~= buf then
    vim.cmd("normal! m'")
    local split = ({ split = "split", vsplit = "vsplit", tab = "tab split" })[config.options.open]
    if split and not current_slug() then
      vim.cmd(split)
    end
    vim.api.nvim_win_set_buf(0, buf)
  end
  if fresh then
    start(buf, slug)
  end
  if line then
    vim.api.nvim_win_set_cursor(0, { math.min(line, vim.api.nvim_buf_line_count(buf)), 0 })
    vim.cmd("normal! zvzt")
  end
  store.set_last(slug)
end

--- Refill open lesson buffers after a sync.
function M.reload()
  for slug, buf in pairs(bufs) do
    local lines = vim.api.nvim_buf_is_valid(buf) and content(slug)
    if lines then
      fill(buf, slug, lines)
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        setup_win(win, buf, slug)
      end
    end
  end
end

return M
