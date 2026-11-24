local store = require("learncpp.store")

local M = {}

--- Let the user choose among `entries` (`{ lesson, line?, why? }`), previewing
--- the cached lesson. Uses snacks.nvim's picker when present, else `vim.ui.select`.
function M.pick(title, entries, on_choice)
  local chapters = store.index().chapters
  local function detail(entry)
    local chapter = chapters[entry.lesson.chapter]
    return entry.why or (chapter and vim.trim(chapter.label .. ": " .. chapter.title)) or ""
  end

  local snacks = rawget(_G, "Snacks")
  if not (snacks and snacks.picker) then
    return vim.ui.select(entries, {
      prompt = title,
      format_item = function(entry)
        return ("%-6s %s  [%s]"):format(entry.lesson.number, entry.lesson.title, detail(entry))
      end,
    }, function(entry)
      if entry then
        on_choice(entry)
      end
    end)
  end

  local items = {}
  for i, entry in ipairs(entries) do
    items[i] = {
      text = table.concat({ entry.lesson.number, entry.lesson.title, detail(entry) }, " "),
      file = store.lesson_path(entry.lesson.slug),
      pos = { entry.line or 1, 0 },
      entry = entry,
    }
  end
  snacks.picker.pick({
    title = title,
    items = items,
    preview = "file",
    format = function(item)
      local entry = item.entry
      return {
        { ("%-6s "):format(entry.lesson.number), "Number" },
        { entry.lesson.title },
        { "  " .. detail(entry), "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          on_choice(item.entry)
        end)
      end
    end,
  })
end

return M
