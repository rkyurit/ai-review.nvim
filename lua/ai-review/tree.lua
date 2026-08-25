local M = {}

local function status_map(changed_files)
  local statuses = {}
  for _, file in ipairs(changed_files) do
    statuses[file.path] = file.status
  end
  return statuses
end

function M.build(paths, changed_files, expanded, changed_only)
  local statuses = status_map(changed_files)
  local root = { type = "directory", name = "", path = "", children = {} }
  local directories = { [""] = root }

  for _, path in ipairs(paths) do
    if not changed_only or statuses[path] then
      local parts = vim.split(path, "/", { plain = true })
      local parent = root
      local current = ""
      for index, part in ipairs(parts) do
        current = current == "" and part or (current .. "/" .. part)
        if index == #parts then
          parent.children[#parent.children + 1] = {
            type = "file",
            name = part,
            path = path,
            status = statuses[path],
          }
        else
          local directory = directories[current]
          if not directory then
            directory = { type = "directory", name = part, path = current, children = {} }
            directories[current] = directory
            parent.children[#parent.children + 1] = directory
          end
          parent = directory
        end
      end
    end
  end

  local visible = {}
  local function flatten(node, depth)
    table.sort(node.children, function(a, b)
      if a.type ~= b.type then
        return a.type == "directory"
      end
      return a.name:lower() < b.name:lower()
    end)
    for _, child in ipairs(node.children) do
      child.depth = depth
      visible[#visible + 1] = child
      if child.type == "directory" and expanded[child.path] ~= false then
        flatten(child, depth + 1)
      end
    end
  end
  flatten(root, 0)
  return visible
end

return M
