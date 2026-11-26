local M = {}

local ns = vim.api.nvim_create_namespace("learncpp")

-- One box colour per callout kind, taken from a highlight group the colorscheme is likely to give that hue.
local KINDS = {
  NOTE = { name = "Note", accent = false },
  TIP = { name = "Tip", accent = "Function" },
  SUCCESS = { name = "Success", accent = "String" },
  IMPORTANT = { name = "Important", accent = "Keyword" },
  WARNING = { name = "Warning", accent = "DiagnosticError" },
  INFO = { name = "Info", accent = "DiagnosticWarn" },
}
local TINT = 0.10

--- Options for render-markdown.nvim that apply to lesson buffers only.
M.render_markdown = {
  render_modes = true,
  anti_conceal = { enabled = false },
  sign = { enabled = false },
  heading = {
    sign = false,
    icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
    position = "inline",
    width = { "full", "full", "block" },
    border = false,
    left_pad = 1,
    right_pad = 2,
  },
  code = {
    sign = false,
    style = "full",
    width = "block",
    min_width = 72,
    left_pad = 2,
    right_pad = 4,
    language_pad = 2,
    border = "thick",
    highlight = "LearncppCode",
    highlight_border = "LearncppCode",
  },
  -- stylua: ignore
  pipe_table = { border = { "╭", "┬", "╮", "├", "┼", "┤", "╰", "┴", "╯", "│", "─" } },
  quote = { repeat_linebreak = true },
  callout = {},
  -- nothing is edited here, so the line under the cursor stays rendered as well
  win_options = { concealcursor = { rendered = "nvic" } },
}
for raw, kind in pairs(KINDS) do
  M.render_markdown.callout[raw:lower()] = { highlight = "Learncpp" .. kind.name .. "Title" }
end

local function channel(color, shift)
  return math.floor(color / shift) % 256
end

local function blend(fg, bg, amount)
  local out = 0
  for _, shift in ipairs({ 65536, 256, 1 }) do
    out = out + math.floor(channel(fg, shift) * amount + channel(bg, shift) * (1 - amount) + 0.5) * shift
  end
  return out
end

local function color(group, attr)
  return vim.api.nvim_get_hl(0, { name = group, link = false })[attr]
end

-- The editor background. A transparent colorscheme has none, so take the nearest thing it still paints.
local function background()
  for _, group in ipairs({ "Normal", "ColorColumn", "CursorLine", "Visual" }) do
    local bg = color(group, "bg")
    if bg then
      return bg
    end
  end
  return vim.o.background == "light" and 0xf0f0f0 or 0x1e1e1e
end

--- (Re)derive the box highlights from the current colorscheme.
function M.highlights()
  local bg = background()
  local fg = color("Normal", "fg") or (vim.o.background == "light" and 0x303030 or 0xc8c8c8)
  local muted = blend(fg, bg, 0.55)
  -- The title carries the box background too: rendered titles and quote bars replace the cells they cover.
  local function box(name, accent)
    local tint = blend(accent, bg, TINT)
    vim.api.nvim_set_hl(0, "Learncpp" .. name, { bg = tint })
    vim.api.nvim_set_hl(0, "Learncpp" .. name .. "Title", { fg = accent, bg = tint, bold = true })
  end
  for _, kind in pairs(KINDS) do
    box(kind.name, kind.accent and color(kind.accent, "fg") or muted)
  end
  box("Quote", muted)
  box("Solution", color("Special", "fg") or fg)
  local code = blend(fg, bg, 0.08)
  vim.api.nvim_set_hl(0, "LearncppCode", { bg = code })
  vim.api.nvim_set_hl(0, "LearncppKey", { fg = color("Special", "fg") or fg, bg = code, bold = true })
  vim.api.nvim_set_hl(0, "LearncppKeyLabel", { fg = muted, bg = code })
  vim.api.nvim_set_hl(0, "LearncppHint", { fg = muted, italic = true })
  vim.api.nvim_set_hl(0, "LearncppLink", { fg = color("Function", "fg"), underline = true })
end

--- Hand the buffer to render-markdown.nvim with the lesson style. Must run
--- before the filetype is set: the first configuration a buffer gets is kept.
function M.attach(buf)
  local ok, render_markdown = pcall(require, "render-markdown")
  if ok and render_markdown.render then
    pcall(render_markdown.render, { buf = buf, config = M.render_markdown })
  end
end

--- Give callouts, quotes and solutions a tinted background so each reads as one box.
function M.decorate(buf, lines, spoilers)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, range in ipairs(spoilers or {}) do
    for row = range[1], math.min(range[2], #lines) do
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { line_hl_group = "LearncppSolution", priority = 90 })
    end
  end
  local group
  for row, line in ipairs(lines) do
    local raw = line:match("^%s*> %[!(%u+)%]")
    if raw then
      group = "Learncpp" .. (KINDS[raw] or KINDS.NOTE).name
    elseif not line:find("^%s*>") then
      group = nil
    end
    if line:find("^%s*>") then
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { line_hl_group = group or "LearncppQuote", priority = 100 })
    end
  end
end

return M
