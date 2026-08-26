local config = require("ai-review.config")

local M = {}

local function session_path(root, branch)
  local key = vim.fn.sha256(root .. "\n" .. branch):sub(1, 20)
  return vim.fs.joinpath(config.options.storage_dir, key .. ".json")
end

function M.load(root, branch)
  local path = session_path(root, branch)
  local file = io.open(path, "r")
  if not file then
    return { version = 1, root = root, branch = branch, comments = {}, archives = {} }, path
  end
  local contents = file:read("*a")
  file:close()
  local ok, data = pcall(vim.json.decode, contents)
  if not ok or type(data) ~= "table" then
    return { version = 1, root = root, branch = branch, comments = {}, archives = {} }, path
  end
  data.comments = data.comments or {}
  data.archives = data.archives or {}
  return data, path
end

function M.save(session, path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local temp = path .. ".tmp"
  local file = assert(io.open(temp, "w"))
  file:write(vim.json.encode(session))
  file:close()
  assert(os.rename(temp, path))
end

return M
