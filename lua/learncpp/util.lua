local M = {}

function M.notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = "learncpp" })
  end)
end

function M.read(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local data = file:read("*a")
  file:close()
  return data
end

function M.write(path, data)
  local file = assert(io.open(path, "wb"))
  file:write(data)
  file:close()
end

return M
