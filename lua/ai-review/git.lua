local M = {}

local function run(args, cwd, allow_failure)
  local result = vim.system(args, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 and not allow_failure then
    error((result.stderr or "git command failed"):gsub("%s+$", ""))
  end
  return result.stdout or "", result.code, result.stderr or ""
end

function M.root(cwd)
  local out = run({ "git", "rev-parse", "--show-toplevel" }, cwd)
  return vim.fs.normalize(vim.trim(out))
end

function M.branch(root)
  local out = run({ "git", "branch", "--show-current" }, root, true)
  local branch = vim.trim(out)
  if branch == "" then
    local head = run({ "git", "rev-parse", "--short", "HEAD" }, root, true)
    branch = "detached-" .. vim.trim(head)
  end
  return branch
end

local function split_nul(value)
  local items = {}
  for item in value:gmatch("([^%z]+)") do
    items[#items + 1] = item
  end
  return items
end

function M.changed_files(root)
  local out = run({ "git", "diff", "--name-status", "-z", "--find-renames", "HEAD" }, root)
  local tokens = split_nul(out)
  local files = {}
  local index = 1
  while index <= #tokens do
    local status = tokens[index]
    index = index + 1
    local old_path
    local path
    if status:match("^[RC]") then
      old_path = tokens[index]
      path = tokens[index + 1]
      index = index + 2
    else
      path = tokens[index]
      index = index + 1
    end
    if path then
      files[#files + 1] = { status = status:sub(1, 1), path = path, old_path = old_path }
    end
  end

  local untracked = split_nul(run({ "git", "ls-files", "--others", "--exclude-standard", "-z" }, root))
  for _, path in ipairs(untracked) do
    files[#files + 1] = { status = "?", path = path }
  end
  table.sort(files, function(a, b)
    return a.path < b.path
  end)
  return files
end

local function parse_hunk_header(line)
  local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not old_start then
    return nil
  end
  return {
    old_start = tonumber(old_start),
    old_count = tonumber(old_count ~= "" and old_count or "1"),
    new_start = tonumber(new_start),
    new_count = tonumber(new_count ~= "" and new_count or "1"),
  }
end

function M.parse_diff(text, file)
  local parsed = { file = file, lines = {}, hunks = {} }
  local old_line
  local new_line
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local entry = { text = line, kind = "meta" }
    local hunk = parse_hunk_header(line)
    if hunk then
      entry.kind = "hunk"
      entry.hunk = hunk
      old_line = hunk.old_start
      new_line = hunk.new_start
      parsed.hunks[#parsed.hunks + 1] = #parsed.lines + 1
    elseif old_line and line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
      entry.kind = "add"
      entry.new_line = new_line
      new_line = new_line + 1
    elseif old_line and line:sub(1, 1) == "-" and line:sub(1, 3) ~= "---" then
      entry.kind = "delete"
      entry.old_line = old_line
      old_line = old_line + 1
    elseif old_line and line:sub(1, 1) == " " then
      entry.kind = "context"
      entry.old_line = old_line
      entry.new_line = new_line
      old_line = old_line + 1
      new_line = new_line + 1
    end
    parsed.lines[#parsed.lines + 1] = entry
  end
  if #parsed.lines > 0 and parsed.lines[#parsed.lines].text == "" then
    table.remove(parsed.lines)
  end
  return parsed
end

function M.diff(root, file, context_lines)
  local args
  local allow_failure = false
  if file.status == "?" then
    args = {
      "git",
      "diff",
      "--no-index",
      "--no-ext-diff",
      "--no-color",
      "--unified=" .. context_lines,
      "--",
      "/dev/null",
      file.path,
    }
    allow_failure = true
  else
    args = { "git", "diff", "--no-ext-diff", "--no-color", "--unified=" .. context_lines, "HEAD", "--", file.path }
  end
  local out, code, err = run(args, root, allow_failure)
  if allow_failure and code > 1 then
    error(vim.trim(err))
  end
  return M.parse_diff(out, file)
end

return M
