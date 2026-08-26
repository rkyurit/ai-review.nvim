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

local function target_kind(target)
  return target and target.kind or "working"
end

local function name_status(root, target)
  if target_kind(target) == "commit" then
    return run(
      { "git", "diff-tree", "--root", "--no-commit-id", "-r", "--name-status", "-z", "--find-renames", target.commit },
      root
    )
  elseif target_kind(target) == "range" then
    return run({ "git", "diff", "--name-status", "-z", "--find-renames", target.base, target.target }, root)
  end
  return run({ "git", "diff", "--name-status", "-z", "--find-renames", "HEAD" }, root)
end

function M.changed_files(root, target)
  local out = name_status(root, target)
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

  if target_kind(target) == "working" then
    local untracked = split_nul(run({ "git", "ls-files", "--others", "--exclude-standard", "-z" }, root))
    for _, path in ipairs(untracked) do
      files[#files + 1] = { status = "?", path = path }
    end
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

function M.diff(root, file, context_lines, target)
  local args
  local allow_failure = false
  if target_kind(target) == "commit" then
    args = {
      "git",
      "show",
      "--format=",
      "--no-ext-diff",
      "--no-color",
      "--find-renames",
      "--unified=" .. context_lines,
      target.commit,
      "--",
      file.path,
    }
  elseif target_kind(target) == "range" then
    args = {
      "git",
      "diff",
      "--no-ext-diff",
      "--no-color",
      "--find-renames",
      "--unified=" .. context_lines,
      target.base,
      target.target,
      "--",
      file.path,
    }
  elseif file.status == "?" then
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

function M.commits(root, limit)
  local format = "%H%x1f%h%x1f%s%x1f%an%x1f%ar%x1e"
  local out = run({ "git", "log", "--all", "--date-order", "-n", tostring(limit or 100), "--format=" .. format }, root)
  local commits = {}
  for record in out:gmatch("([^\30]+)") do
    local hash, short, subject, author, relative =
      record:gsub("^%s+", ""):match("([^\31]*)\31([^\31]*)\31([^\31]*)\31([^\31]*)\31([^\31]*)")
    if hash then
      commits[#commits + 1] = {
        hash = hash,
        short = short,
        subject = subject,
        author = author,
        relative = relative,
      }
    end
  end
  return commits
end

local function included_ignored_paths(root, patterns)
  local paths = {}
  local seen = {}
  local root_prefix = vim.fs.normalize(root) .. "/"
  for _, pattern in ipairs(patterns or {}) do
    for _, absolute in ipairs(vim.fn.globpath(root, pattern, false, true)) do
      local normalized = vim.fs.normalize(absolute)
      if normalized:sub(1, #root_prefix) == root_prefix then
        local relative = normalized:sub(#root_prefix + 1)
        if vim.fn.isdirectory(normalized) == 1 then
          relative = relative .. "/"
        end
        if relative ~= "" and not seen[relative] then
          seen[relative] = true
          paths[#paths + 1] = relative
        end
      end
    end
  end
  return paths
end

function M.repo_files(root, target, include_ignored)
  local out
  local extras = {}
  if target_kind(target) == "commit" then
    out = run({ "git", "ls-tree", "-r", "--name-only", "-z", target.commit }, root)
  elseif target_kind(target) == "range" then
    out = run({ "git", "ls-tree", "-r", "--name-only", "-z", target.target }, root)
  else
    out = run({ "git", "ls-files", "--cached", "--others", "--exclude-standard", "-z" }, root)
    extras = included_ignored_paths(root, include_ignored)
  end
  local files = split_nul(out)
  vim.list_extend(files, extras)
  table.sort(files)
  return files
end

function M.directory_entries(root, path)
  local entries = {}
  local handle = vim.fs.dir(vim.fs.joinpath(root, path))
  if not handle then
    return entries
  end
  for name, kind in handle do
    if name ~= ".git" then
      local child = path == "" and name or (path .. "/" .. name)
      entries[#entries + 1] = kind == "directory" and (child .. "/") or child
    end
  end
  table.sort(entries)
  return entries
end

function M.directory_files(root, path)
  local files = {}
  local pending = { path }
  while #pending > 0 do
    local directory = table.remove(pending)
    local handle = vim.fs.dir(vim.fs.joinpath(root, directory))
    if handle then
      for name, kind in handle do
        if name ~= ".git" then
          local child = directory == "" and name or (directory .. "/" .. name)
          if kind == "directory" then
            pending[#pending + 1] = child
          elseif kind == "file" or kind == "link" then
            files[#files + 1] = child
          end
        end
      end
    end
  end
  table.sort(files)
  return files
end

function M.read_file(root, path, target)
  if target_kind(target) == "commit" then
    return run({ "git", "show", target.commit .. ":" .. path }, root)
  elseif target_kind(target) == "range" then
    return run({ "git", "show", target.target .. ":" .. path }, root)
  end
  local file = assert(io.open(vim.fs.joinpath(root, path), "rb"))
  local contents = file:read("*a")
  file:close()
  return contents
end

return M
