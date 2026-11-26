local picker = require("learncpp.picker")
local reader = require("learncpp.reader")
local search = require("learncpp.search")
local store = require("learncpp.store")
local util = require("learncpp.util")

local M = {}

function M.setup(opts)
  require("learncpp.config").setup(opts)
end

local function open(entry)
  reader.open(entry.lesson.slug, entry.line)
end

local function show(title, entries, empty)
  if #entries == 0 then
    return util.notify(empty, vim.log.levels.WARN)
  end
  picker.pick(title, entries, open)
end

--- Browse every lesson in table-of-contents order.
function M.toc()
  store.ensure(function(index)
    local entries = {}
    for i, lesson in ipairs(index.lessons) do
      entries[i] = { lesson = lesson }
    end
    show("learncpp.com", entries, "No lessons cached")
  end)
end

--- Open a lesson by number ("25.7"), slug, URL or part of its title.
function M.open(ref)
  if not ref or ref == "" then
    return M.toc()
  end
  store.ensure(function(index)
    local exact = index.by_slug[store.slug_of(ref) or ref]
    local entries, needle = {}, ref:lower()
    for _, lesson in ipairs(index.lessons) do
      exact = exact or (lesson.number:lower() == needle and lesson)
      if lesson.title:lower():find(needle, 1, true) then
        entries[#entries + 1] = { lesson = lesson }
      end
    end
    if exact or #entries == 1 then
      return reader.open((exact or entries[1].lesson).slug)
    end
    show("learncpp.com: " .. ref, entries, "No lesson matches " .. ref)
  end)
end

--- Lessons about a C++ name or operator: `query`, the visual selection, or the symbol under the cursor.
function M.lookup(query)
  if not query or query == "" then
    local mode = vim.fn.mode()
    if mode:find("^[vV\22]") then
      query = vim.trim(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })[1] or "")
      vim.cmd.normal({ "\27", bang = true })
    else
      query = search.symbol_at(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2])
    end
  end
  if not query or query == "" then
    return util.notify("No symbol under the cursor", vim.log.levels.WARN)
  end
  store.ensure(function(index)
    show("learncpp.com: " .. query, search.lookup(index, query), "No lesson covers " .. query)
  end)
end

--- Full-text search over all lessons; prompts when `query` is omitted.
function M.search(query)
  if not query or query == "" then
    return vim.ui.input({ prompt = "Search learncpp.com: " }, function(input)
      if input and vim.trim(input) ~= "" then
        M.search(input)
      end
    end)
  end
  store.ensure(function(index)
    show("learncpp.com: " .. query, search.search(index, query), "No lesson contains " .. query)
  end)
end

--- Reopen the lesson that was read last.
function M.resume()
  store.ensure(function(index)
    local last = store.last()
    if last and index.by_slug[last] then
      return reader.open(last)
    end
    M.toc()
  end)
end

function M.next()
  reader.step(1)
end

function M.prev()
  reader.step(-1)
end

--- Compile and run the code block under the cursor (or the scratch file being edited).
function M.run()
  require("learncpp.run").run()
end

--- Open the code block under the cursor as a scratch file.
function M.edit()
  require("learncpp.run").edit()
end

--- Download all lessons again and refresh the cache.
function M.sync()
  util.notify("Downloading lessons from learncpp.com...")
  store.sync(function(err, index)
    if err then
      return util.notify("sync failed: " .. err, vim.log.levels.ERROR)
    end
    reader.reload()
    util.notify(("Cached %d lessons"):format(#index.lessons))
  end)
end

return M
