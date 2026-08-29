local M = {}

local function snacks_picker()
  local snacks = rawget(_G, "Snacks")
  return snacks and snacks.picker or nil
end

function M.available()
  return snacks_picker() ~= nil
end

local function selected_path(item)
  if not item or not item.file then
    return nil
  end
  return item.file
end

local function confirm(callback)
  return function(picker, item)
    local path = selected_path(item)
    local pos = item and item.pos or nil
    picker:close()
    if path then
      vim.schedule(function()
        callback(path, pos)
      end)
    end
  end
end

function M.files(opts)
  local picker = snacks_picker()
  if not picker or type(picker.files) ~= "function" then
    return false
  end
  picker.files({
    cwd = opts.cwd,
    hidden = false,
    ignored = false,
    confirm = confirm(opts.on_select),
  })
  return true
end

function M.grep(opts)
  local picker = snacks_picker()
  if not picker or type(picker.grep) ~= "function" then
    return false
  end
  picker.grep({
    cwd = opts.cwd,
    hidden = false,
    ignored = false,
    confirm = confirm(opts.on_select),
  })
  return true
end

return M
