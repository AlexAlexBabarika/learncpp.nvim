local config = require("learncpp.config")
local util = require("learncpp.util")

local M = {}

-- macOS Seatbelt profile for a lesson program: no network, and no writes outside its run directory.
local PROFILE =
  '(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath "%s") (regex #"^/dev/"))'

local output = {} -- window and job of the latest run
local workdir

-- Lives inside Neovim's own temporary directory, so it is gone when the session ends.
local function dir()
  if not workdir then
    workdir = vim.fn.tempname()
    vim.fn.mkdir(workdir .. "/run", "p")
  end
  return workdir
end

local function quote(text)
  return "'" .. text:gsub("'", [['\'']]) .. "'"
end

--- Every fenced code block in `lines`: `{ lang, first, last, code }`, with the
--- quote or list prefix of a nested block removed from its code.
function M.blocks(lines)
  local blocks, open = {}, nil
  for row, line in ipairs(lines) do
    local prefix, ticks, lang = line:match("^([%s>]*)(```+)(%S*)%s*$")
    if ticks and not open then
      open = { first = row, prefix = prefix, ticks = ticks, lang = lang }
    elseif ticks and lang == "" and #ticks >= #open.ticks then
      local code = {}
      for i = open.first + 1, row - 1 do
        local text = lines[i]
        local nested = text:sub(1, #open.prefix) == open.prefix
        code[#code + 1] = nested and text:sub(#open.prefix + 1) or (text:gsub("^[%s>]+", ""))
      end
      blocks[#blocks + 1] = { lang = open.lang, first = open.first, last = row, code = code }
      open = nil
    end
  end
  return blocks
end

--- The fenced code block that contains line `lnum`, fences included.
function M.block_at(lines, lnum)
  for _, block in ipairs(M.blocks(lines)) do
    if lnum >= block.first and lnum <= block.last then
      return block
    end
  end
end

--- Whether `code` is a whole program; anything else can only be checked for errors.
function M.has_main(code)
  return code:find("%f[%w_]main%s*%(") ~= nil
end

function M.compiler()
  local wanted = config.options.run.compiler or vim.env.CXX
  for _, name in ipairs(wanted and wanted ~= "" and { wanted } or { "clang++", "g++", "c++" }) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
end

--- The `sh` script for one run, started in the run directory: compile `source`, then
--- become the program. Code without a main() is only checked for errors.
function M.script(compiler, source, code, cwd)
  local opts = config.options.run
  local compile = { quote(compiler) }
  for _, flag in ipairs(opts.flags) do
    compile[#compile + 1] = quote(flag)
  end
  compile = table.concat(compile, " ")
  if not M.has_main(code) then
    local note = "Compiles. There is no main() here, so nothing was run."
    return ("%s -fsyntax-only %s && echo %s"):format(compile, quote(source), quote(note))
  end
  local program = "./prog"
  if opts.sandbox and vim.fn.executable("sandbox-exec") == 1 then
    program = "sandbox-exec -p " .. quote(PROFILE:format(vim.uv.fs_realpath(cwd) or cwd)) .. " ./prog"
  end
  return ("%s -o prog %s && exec %s"):format(compile, quote(source), program)
end

local function launch(source, code)
  local compiler = M.compiler()
  if not compiler then
    return util.notify("No C++ compiler found; set run.compiler or $CXX", vim.log.levels.ERROR)
  end
  local cwd = dir() .. "/run"
  local cmd = { "sh", "-c", M.script(compiler, source, code, cwd) }
  if output.job then
    pcall(vim.fn.jobstop, output.job)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  if output.win and vim.api.nvim_win_is_valid(output.win) then
    vim.api.nvim_win_set_buf(output.win, buf)
  else
    output.win = vim.api.nvim_open_win(buf, false, { split = "below", win = -1, height = config.options.run.height })
  end
  local wo = vim.wo[output.win][0]
  wo.number, wo.relativenumber, wo.signcolumn = false, false, "no"
  vim.api.nvim_win_call(output.win, function()
    if vim.fn.has("nvim-0.11") == 1 then
      output.job = vim.fn.jobstart(cmd, { term = true, cwd = cwd })
    else
      output.job = vim.fn.termopen(cmd, { cwd = cwd })
    end
  end)
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close program output" })
  -- a program that reads input needs the keyboard; otherwise stay where the code is
  if code:find("cin%f[%W]") or code:find("getline%f[%W]") or code:find("getchar%f[%W]") then
    vim.api.nvim_set_current_win(output.win)
    vim.cmd("startinsert")
  end
end

local function current_block()
  local block = M.block_at(vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.fn.line("."))
  if not block or (block.lang ~= "cpp" and block.lang ~= "c++") then
    util.notify("Put the cursor on a C++ code block", vim.log.levels.WARN)
    return nil
  end
  return block
end

--- Compile and run the code block under the cursor, or the scratch file being edited, in a terminal split.
function M.run()
  if vim.b.learncpp_scratch then
    vim.cmd("silent update")
    local code = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    return launch(vim.api.nvim_buf_get_name(0), code)
  end
  local block = current_block()
  if block then
    local source, code = dir() .. "/run/main.cpp", table.concat(block.code, "\n")
    util.write(source, code .. "\n")
    launch(source, code)
  end
end

--- Open the code block under the cursor as a scratch file that can be changed and run.
function M.edit()
  local block = current_block()
  if not block then
    return
  end
  local path = ("%s/%s-%d.cpp"):format(dir(), vim.b.learncpp_slug or "block", block.first)
  if not vim.uv.fs_stat(path) then
    util.write(path, table.concat(block.code, "\n") .. "\n")
  end
  vim.cmd("split " .. vim.fn.fnameescape(path))
  vim.b.learncpp_scratch = true
  local key = config.options.keys.scratch_run
  if key then
    vim.keymap.set("n", key, M.run, { buffer = true, desc = "Run this scratch file" })
  end
  util.notify(("Scratch copy, deleted when Neovim exits%s"):format(key and "; " .. key .. " runs it" or ""))
end

return M
