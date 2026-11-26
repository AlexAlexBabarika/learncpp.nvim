if vim.g.loaded_learncpp then
  return
end
vim.g.loaded_learncpp = true

local SUBCOMMANDS = {
  toc = function() require("learncpp").toc() end,
  open = function(arg) require("learncpp").open(arg) end,
  lookup = function(arg) require("learncpp").lookup(arg) end,
  search = function(arg) require("learncpp").search(arg) end,
  resume = function() require("learncpp").resume() end,
  next = function() require("learncpp").next() end,
  prev = function() require("learncpp").prev() end,
  run = function() require("learncpp").run() end,
  edit = function() require("learncpp").edit() end,
  sync = function() require("learncpp").sync() end,
}

vim.api.nvim_create_user_command("LearnCpp", function(cmd)
  local sub, arg = cmd.args:match("^(%S*)%s*(.-)$")
  local fn = SUBCOMMANDS[sub ~= "" and sub or "toc"]
  if not fn then
    return vim.notify("unknown subcommand: " .. sub, vim.log.levels.ERROR, { title = "learncpp" })
  end
  fn(arg)
end, {
  nargs = "*",
  desc = "learncpp.com lessons",
  complete = function(lead, line)
    if line:find("^%S+%s+%S*$") then
      local names = vim.tbl_filter(function(name)
        return name:find(lead, 1, true) == 1
      end, vim.tbl_keys(SUBCOMMANDS))
      table.sort(names)
      return names
    end
    return {}
  end,
})
