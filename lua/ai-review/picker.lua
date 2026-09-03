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

function M.file_list(opts)
  local picker = snacks_picker()
  if not picker or type(picker.pick) ~= "function" then
    return false
  end
  local items = vim.tbl_map(function(path)
    return { text = path, file = path, cwd = opts.cwd }
  end, opts.paths)
  picker.pick({
    title = opts.title or "Files",
    cwd = opts.cwd,
    items = items,
    format = "file",
    formatters = { file = { filename_first = true } },
    preview = function(ctx)
      if not opts.preview then
        picker.preview.file(ctx)
        return
      end
      local ok, contents, filetype = pcall(opts.preview, ctx.item.file)
      if not ok then
        ctx.preview:notify(tostring(contents), "error")
        return
      end
      ctx.preview:reset()
      ctx.preview:set_title(vim.fn.fnamemodify(ctx.item.file, ":t"))
      vim.bo[ctx.buf].buftype = "nofile"
      vim.bo[ctx.buf].filetype = filetype or vim.filetype.match({ filename = ctx.item.file }) or ""
      ctx.preview:set_lines(vim.split(contents, "\n", { plain = true }))
    end,
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
