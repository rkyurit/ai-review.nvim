local config = require("ai-review.config")
local clipboard = require("ai-review.clipboard")
local export = require("ai-review.export")
local git = require("ai-review.git")
local reanchor = require("ai-review.reanchor")
local state = require("ai-review.state")
local tree = require("ai-review.tree")

local M = {}
local ui_ns = vim.api.nvim_create_namespace("ai-review-ui")
local comment_ns = vim.api.nvim_create_namespace("ai-review-comments")
local active

local function working_target()
  return { kind = "working", id = "working", label = "Working tree" }
end

local function current_node()
  return active and active.visible_nodes and active.visible_nodes[active.file_index] or nil
end

local function current_path()
  local node = current_node()
  return node and node.type == "file" and node.path or active and active.selected_path or nil
end

local function comment_belongs(comment)
  return comment.target_id == active.target.id or (not comment.target_id and active.target.id == "working")
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "AI Review" })
end

local function valid_window(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function current_diff_entry()
  if not active or vim.api.nvim_get_current_buf() ~= active.diff_buf then
    return nil
  end
  return active.parsed and active.parsed.lines[vim.api.nvim_win_get_cursor(active.diff_win)[1]] or nil
end

local function comment_line(entry)
  if entry and entry.kind == "source" then
    return "source", entry.new_line
  end
  if entry.new_line then
    return "new", entry.new_line
  end
  if entry.old_line then
    return "old", entry.old_line
  end
  return nil, nil
end

local function context_for_range(start_row, end_row)
  local lines = {}
  for row = start_row, end_row do
    local entry = active.parsed.lines[row]
    if entry then
      lines[#lines + 1] = entry.text
    end
  end
  return table.concat(lines, "\n")
end

local function persist()
  state.save(active.session, active.session_path)
end

local function comments_for_file(path)
  local comments = {}
  for _, comment in ipairs(active.session.comments) do
    if comment.path == path and not comment.resolved and comment_belongs(comment) then
      comments[#comments + 1] = comment
    end
  end
  return comments
end

local function render_comments()
  vim.api.nvim_buf_clear_namespace(active.diff_buf, comment_ns, 0, -1)
  local path = active.selected_path
  for _, comment in ipairs(comments_for_file(path)) do
    if not comment.orphaned then
      local target_row
      for row, entry in ipairs(active.parsed.lines) do
        local side, line = comment_line(entry)
        if side == comment.side and line == comment.start_line then
          target_row = row
          break
        end
      end
      if target_row then
        local virtual = {}
        for index, line in ipairs(vim.split(comment.body, "\n", { plain = true })) do
          local prefix = index == 1 and "  ● " or "    "
          virtual[#virtual + 1] = { { prefix .. line, "AIReviewComment" } }
        end
        vim.api.nvim_buf_set_extmark(active.diff_buf, comment_ns, target_row - 1, 0, {
          virt_lines = virtual,
          virt_lines_above = false,
        })
      end
    end
  end
  local orphaned = {}
  for _, comment in ipairs(comments_for_file(path)) do
    if comment.orphaned then
      orphaned[#orphaned + 1] = {
        {
          ("  ⚠ Unplaced review from %s:%d — %s"):format(comment.path, comment.start_line or 0, comment.body),
          "DiagnosticWarn",
        },
      }
    end
  end
  if #orphaned > 0 and vim.api.nvim_buf_line_count(active.diff_buf) > 0 then
    vim.api.nvim_buf_set_extmark(active.diff_buf, comment_ns, 0, 0, {
      virt_lines = orphaned,
      virt_lines_above = true,
    })
  end
end

local function render_files()
  local lines = {}
  if valid_window(active.file_win) then
    vim.wo[active.file_win].winbar = (" AI Review │ %s │ %s "):format(
      active.target.label,
      (active.changed_only and "Changed files" or "All files") .. " │ f:Files b:Commit ?:Help"
    )
  end
  active.visible_nodes = tree.build(active.all_files, active.files, active.expanded, active.changed_only)
  if active.selected_path then
    for index, node in ipairs(active.visible_nodes) do
      if node.type == "file" and node.path == active.selected_path then
        active.file_index = index
        break
      end
    end
  end
  active.file_index = math.min(active.file_index, math.max(1, #active.visible_nodes))
  for index, file in ipairs(active.visible_nodes) do
    local marker = index == active.file_index and "▸" or " "
    local count = file.type == "file" and #comments_for_file(file.path) or 0
    local suffix = count > 0 and ("  [%d]"):format(count) or ""
    local indent = string.rep("  ", file.depth)
    if file.type == "directory" then
      local icon = active.expanded[file.path] == true and "▾" or "▸"
      lines[#lines + 1] = ("%s %s%s %s/"):format(marker, indent, icon, file.name)
    else
      lines[#lines + 1] = ("%s %s%-1s %s%s"):format(marker, indent, file.status or " ", file.name, suffix)
    end
  end
  if #lines == 0 then
    lines = { "  No changes" }
  end
  set_lines(active.file_buf, lines)
  vim.api.nvim_buf_clear_namespace(active.file_buf, ui_ns, 0, -1)
  for index, node in ipairs(active.visible_nodes) do
    local group
    if index == active.file_index then
      group = "AIReviewSelection"
    elseif node.type == "directory" then
      group = "AIReviewDirectory"
    elseif node.status == "M" then
      group = "AIReviewModified"
    elseif node.status == "A" then
      group = "AIReviewAdded"
    elseif node.status == "D" then
      group = "AIReviewDeleted"
    elseif node.status == "?" then
      group = "AIReviewUntracked"
    else
      group = "AIReviewMuted"
    end
    vim.api.nvim_buf_set_extmark(active.file_buf, ui_ns, index - 1, 0, { line_hl_group = group })
  end
end

local function source_entries(contents)
  local entries = {}
  local lines = vim.split(contents, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  for row, line in ipairs(lines) do
    entries[#entries + 1] = { text = line, kind = "source", new_line = row }
  end
  return entries
end

local function render_diff(keep_cursor)
  local path = active.selected_path
  if not path then
    set_lines(active.diff_buf, { "No changes to review." })
    active.parsed = nil
    return
  end
  local old_cursor = valid_window(active.diff_win) and vim.api.nvim_win_get_cursor(active.diff_win) or { 1, 0 }
  local changed = active.changed_by_path[path]
  local view_mode = active.view_mode
  if not changed then
    view_mode = "source"
  end
  local ok, parsed
  if view_mode == "source" then
    local source_ok, contents = pcall(git.read_file, active.root, path, active.target)
    ok = source_ok
    parsed = source_ok and { file = { path = path }, lines = source_entries(contents), hunks = {} } or contents
  else
    ok, parsed = pcall(git.diff, active.root, changed, config.options.context_lines, active.target)
  end
  if not ok then
    set_lines(active.diff_buf, { "Failed to load diff:", tostring(parsed) })
    active.parsed = nil
    return
  end
  active.parsed = parsed
  local lines = {}
  for _, entry in ipairs(parsed.lines) do
    lines[#lines + 1] = entry.text
  end
  set_lines(active.diff_buf, #lines > 0 and lines or { "No diff for " .. path })
  vim.api.nvim_buf_clear_namespace(active.diff_buf, ui_ns, 0, -1)
  for row, entry in ipairs(parsed.lines) do
    local group
    if entry.kind == "add" then
      group = "AIReviewDiffAdd"
    elseif entry.kind == "delete" then
      group = "AIReviewDiffDelete"
    elseif entry.kind == "hunk" then
      group = "AIReviewHunk"
    elseif entry.kind == "meta" then
      group = "AIReviewMuted"
    elseif entry.kind == "context" then
      group = "AIReviewDiffContext"
    end
    if group then
      vim.api.nvim_buf_set_extmark(active.diff_buf, ui_ns, row - 1, 0, { line_hl_group = group })
    end
  end
  if view_mode == "source" then
    vim.bo[active.diff_buf].filetype = vim.filetype.match({ filename = path }) or ""
  else
    vim.bo[active.diff_buf].filetype = "diff"
  end
  vim.api.nvim_buf_set_name(active.diff_buf, ("ai-review://%s/%s"):format(view_mode, path))
  active.rendered_mode = view_mode
  vim.wo[active.diff_win].winbar = (" AI Review │ %s │ %s │ %s │ c:Comment V…c:Range y:Copy A:Archive H:History ?:Help "):format(
    active.target.label,
    view_mode,
    path
  )
  render_comments()
  if keep_cursor and valid_window(active.diff_win) then
    old_cursor[1] = math.min(old_cursor[1], math.max(1, #lines))
    vim.api.nvim_win_set_cursor(active.diff_win, old_cursor)
  end
end

local function select_file(index)
  local node = active.visible_nodes[index]
  if not node then
    return
  end
  if node.type == "directory" then
    active.expanded[node.path] = active.expanded[node.path] ~= true
    render_files()
    return
  end
  active.file_index = index
  active.selected_path = node.path
  active.view_mode = active.changed_by_path[node.path] and "diff" or "source"
  render_files()
  render_diff(false)
  vim.api.nvim_set_current_win(active.diff_win)
end

local function add_comment(start_row, end_row)
  if not active.parsed then
    return
  end
  local new_lines = {}
  local old_lines = {}
  local has_addition = false
  local has_deletion = false
  for row = start_row, end_row do
    local entry = active.parsed.lines[row]
    if entry then
      if entry.new_line then
        new_lines[#new_lines + 1] = entry.new_line
      end
      if entry.old_line then
        old_lines[#old_lines + 1] = entry.old_line
      end
      has_addition = has_addition or entry.kind == "add"
      has_deletion = has_deletion or entry.kind == "delete"
    end
  end

  local side
  local selected_lines
  if active.rendered_mode == "source" and #new_lines > 0 then
    side = "source"
    selected_lines = new_lines
  elseif has_addition and #new_lines > 0 then
    side = "new"
    selected_lines = new_lines
  elseif has_deletion and #old_lines > 0 then
    side = "old"
    selected_lines = old_lines
  elseif #new_lines > 0 then
    side = "new"
    selected_lines = new_lines
  else
    side = "old"
    selected_lines = old_lines
  end

  if not selected_lines or #selected_lines == 0 then
    notify("Place the cursor on a changed or context line", vim.log.levels.WARN)
    return
  end
  local start_line = selected_lines[1]
  local end_line = selected_lines[1]
  for _, line in ipairs(selected_lines) do
    start_line = math.min(start_line, line)
    end_line = math.max(end_line, line)
  end
  vim.ui.input({ prompt = ("Comment on %s:%d: "):format(active.selected_path, start_line) }, function(body)
    if not body or vim.trim(body) == "" or not active then
      return
    end
    active.session.comments[#active.session.comments + 1] = {
      id = tostring(vim.uv.hrtime()),
      path = active.selected_path,
      target_id = active.target.id,
      target_label = active.target.label,
      side = side,
      start_line = start_line,
      end_line = end_line,
      body = body,
      context = context_for_range(start_row, end_row),
      created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      resolved = false,
    }
    persist()
    render_files()
    render_comments()
  end)
end

local function comment_at_cursor()
  local row = vim.api.nvim_win_get_cursor(active.diff_win)[1]
  add_comment(row, row)
end

local function comment_visual()
  local start_row = vim.fn.line("v")
  local end_row = vim.fn.line(".")
  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  add_comment(start_row, end_row)
end

local function comment_at_cursor_position()
  local entry = current_diff_entry()
  if not entry then
    return nil
  end
  local side, line = comment_line(entry)
  if not line then
    return nil
  end
  for _, comment in ipairs(active.session.comments) do
    if
      comment.path == active.selected_path
      and comment_belongs(comment)
      and comment.side == side
      and line >= comment.start_line
      and line <= (comment.end_line or comment.start_line)
      and not comment.resolved
    then
      return comment
    end
  end
end

local function edit_comment()
  local comment = comment_at_cursor_position()
  if not comment then
    notify("No comment on this line", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "Edit comment: ", default = comment.body }, function(body)
    if body and vim.trim(body) ~= "" and active then
      comment.body = body
      persist()
      render_comments()
    end
  end)
end

local function delete_comment()
  local comment = comment_at_cursor_position()
  if not comment then
    notify("No comment on this line", vim.log.levels.WARN)
    return
  end
  for index, candidate in ipairs(active.session.comments) do
    if candidate.id == comment.id then
      table.remove(active.session.comments, index)
      break
    end
  end
  persist()
  render_files()
  render_comments()
end

local function clear_comments()
  local count = 0
  for _, comment in ipairs(active.session.comments) do
    if not comment.resolved and comment_belongs(comment) then
      count = count + 1
    end
  end
  if count == 0 then
    notify("No review comments to clear")
    return
  end
  vim.ui.select(
    { "Cancel", ("Clear %d comments"):format(count) },
    { prompt = "Clear comments for this review target?" },
    function(choice)
      if not choice or choice == "Cancel" or not active then
        return
      end
      local kept = {}
      for _, comment in ipairs(active.session.comments) do
        if not comment_belongs(comment) then
          kept[#kept + 1] = comment
        end
      end
      active.session.comments = kept
      persist()
      render_files()
      render_comments()
      notify(("Cleared %d review comments"):format(count))
    end
  )
end

local function target_comments()
  local comments = {}
  for _, comment in ipairs(active.session.comments) do
    if not comment.resolved and comment_belongs(comment) then
      comments[#comments + 1] = comment
    end
  end
  return comments
end

local function remove_target_comments()
  local kept = {}
  for _, comment in ipairs(active.session.comments) do
    if not comment_belongs(comment) then
      kept[#kept + 1] = comment
    end
  end
  active.session.comments = kept
end

local function archive_comments()
  local comments = target_comments()
  if #comments == 0 then
    notify("No review comments to archive")
    return
  end
  local default_title = active.target.label .. " — " .. os.date("%Y-%m-%d %H:%M")
  vim.ui.input({ prompt = "Review title: ", default = default_title }, function(title)
    if not title or vim.trim(title) == "" or not active then
      return
    end
    local archived_session = { comments = vim.deepcopy(comments) }
    active.session.archives = active.session.archives or {}
    active.session.archives[#active.session.archives + 1] = {
      id = tostring(vim.uv.hrtime()),
      title = title,
      target = vim.deepcopy(active.target),
      created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      comments = vim.deepcopy(comments),
      markdown = export.markdown(archived_session, active.target),
    }
    remove_target_comments()
    persist()
    render_files()
    render_comments()
    notify(("Archived %d comments as %s"):format(#comments, title))
  end)
end

local function source_context(comment)
  local lines = {}
  for _, text in ipairs(vim.split(comment.context or "", "\n", { plain = true })) do
    local prefix = text:sub(1, 1)
    local include = prefix == " "
      or (comment.side == "new" and prefix == "+")
      or (comment.side == "old" and prefix == "-")
    if include and not text:match("^%+%+%+ ") and not text:match("^%-%-%- ") then
      lines[#lines + 1] = text:sub(2)
    end
  end
  return table.concat(lines, "\n")
end

local function entries_for_restore(comment)
  local changed = active.changed_by_path[comment.path]
  if comment.side ~= "source" and changed then
    local ok, parsed = pcall(git.diff, active.root, changed, config.options.context_lines, active.target)
    if ok then
      return parsed.lines, comment.side
    end
  end
  local ok, contents = pcall(git.read_file, active.root, comment.path, active.target)
  if not ok then
    return nil
  end
  return source_entries(contents), "source"
end

local function restore_archive(archive)
  local restored = 0
  local unplaced = 0
  for _, archived in ipairs(archive.comments or {}) do
    local duplicate = vim.iter(active.session.comments):any(function(comment)
      return comment.archive_id == archive.id and comment.archive_comment_id == archived.id and comment_belongs(comment)
    end)
    if not duplicate then
      local comment = vim.deepcopy(archived)
      comment.id = tostring(vim.uv.hrtime()) .. ":" .. tostring(restored + unplaced + 1)
      comment.archive_id = archive.id
      comment.archive_comment_id = archived.id
      comment.target_id = active.target.id
      comment.target_label = active.target.label
      comment.resolved = false
      comment.orphaned = false

      local entries, side = entries_for_restore(comment)
      local anchored
      if entries then
        if side == "source" and comment.side ~= "source" then
          comment.side = "source"
          comment.context = source_context(archived)
        end
        anchored = reanchor.anchor(comment, entries)
      end
      if not anchored and side ~= "source" then
        local source_ok, contents = pcall(git.read_file, active.root, comment.path, active.target)
        if source_ok then
          comment.side = "source"
          comment.context = source_context(archived)
          anchored = reanchor.anchor(comment, source_entries(contents))
        end
      end
      if anchored then
        comment.side = anchored.side
        comment.start_line = anchored.start_line
        comment.end_line = anchored.end_line
        comment.context = anchored.context
        comment.anchor_confidence = anchored.confidence
        restored = restored + 1
      else
        comment.orphaned = true
        unplaced = unplaced + 1
      end
      active.session.comments[#active.session.comments + 1] = comment
    end
  end
  persist()
  render_files()
  render_diff(true)
  notify(("Restored %d comments%s"):format(restored, unplaced > 0 and (", " .. unplaced .. " unplaced") or ""))
end

local function open_history_entry(archive)
  local lines = vim.split(archive.markdown or "", "\n", { plain = true })
  local width = math.min(100, vim.o.columns - 4)
  local height = math.min(math.max(10, #lines), vim.o.lines - 4)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. archive.title .. " ",
    title_pos = "center",
  })
  local function close_history()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close_history, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close_history, { buffer = buf, silent = true })
  vim.keymap.set("n", "y", function()
    local copied, provider = clipboard.copy(archive.markdown or "")
    notify(copied and ("Archived review copied with " .. provider) or "Archived review copied to unnamed register")
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "r", function()
    close_history()
    restore_archive(archive)
  end, { buffer = buf, silent = true, desc = "Restore archived review" })
end

local function show_history()
  local archives = active.session.archives or {}
  if #archives == 0 then
    notify("No archived reviews")
    return
  end
  local items = {}
  for index = #archives, 1, -1 do
    items[#items + 1] = archives[index]
  end
  vim.ui.select(items, {
    prompt = "Review history",
    format_item = function(item)
      return ("%s  [%d comments]"):format(item.title, #(item.comments or {}))
    end,
  }, function(choice)
    if choice and active then
      open_history_entry(choice)
    end
  end)
end

local function jump_rows(rows, direction)
  if #rows == 0 then
    return
  end
  local current = vim.api.nvim_win_get_cursor(active.diff_win)[1]
  if direction > 0 then
    for _, row in ipairs(rows) do
      if row > current then
        vim.api.nvim_win_set_cursor(active.diff_win, { row, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(active.diff_win, { rows[1], 0 })
  else
    for index = #rows, 1, -1 do
      if rows[index] < current then
        vim.api.nvim_win_set_cursor(active.diff_win, { rows[index], 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(active.diff_win, { rows[#rows], 0 })
  end
end

local function jump_hunk(direction)
  jump_rows(active.parsed and active.parsed.hunks or {}, direction)
end

local function comment_rows()
  local rows = {}
  local path = active.selected_path
  for row, entry in ipairs(active.parsed.lines) do
    local side, line = comment_line(entry)
    for _, comment in ipairs(active.session.comments) do
      if
        comment.path == path
        and not comment.resolved
        and comment_belongs(comment)
        and comment.side == side
        and comment.start_line == line
      then
        rows[#rows + 1] = row
        break
      end
    end
  end
  return rows
end

local function show_comments()
  local items = {}
  for _, comment in ipairs(active.session.comments) do
    if not comment.resolved and comment_belongs(comment) then
      items[#items + 1] = comment
    end
  end
  if #items == 0 then
    notify("No review comments")
    return
  end
  vim.ui.select(items, {
    prompt = "Review comments",
    format_item = function(item)
      return ("%s:%d  %s"):format(item.path, item.start_line, item.body)
    end,
  }, function(choice)
    if not choice or not active then
      return
    end
    active.changed_only = false
    active.expanded = tree.expand_for_paths({ choice.path })
    render_files()
    for index, file in ipairs(active.visible_nodes) do
      if file.type == "file" and file.path == choice.path then
        select_file(index)
        for row, entry in ipairs(active.parsed.lines) do
          local side, line = comment_line(entry)
          if side == choice.side and line == choice.start_line then
            vim.api.nvim_win_set_cursor(active.diff_win, { row, 0 })
            break
          end
        end
        break
      end
    end
  end)
end

local function export_comments()
  local markdown = export.markdown(active.session, active.target)
  local copied = false
  local provider
  if config.options.export_to_clipboard then
    copied, provider = clipboard.copy(markdown)
  else
    vim.fn.setreg('"', markdown)
  end
  notify(copied and ("Review copied with " .. provider) or "Review copied to unnamed register")
end

local function refresh()
  local selected_path = active.selected_path
  active.files = git.changed_files(active.root, active.target)
  active.all_files = git.repo_files(active.root, active.target)
  active.changed_by_path = {}
  for _, file in ipairs(active.files) do
    active.changed_by_path[file.path] = file
  end
  for _, file in ipairs(active.files) do
    if not vim.tbl_contains(active.all_files, file.path) then
      active.all_files[#active.all_files + 1] = file.path
    end
  end
  table.sort(active.all_files)
  active.file_index = 1
  active.visible_nodes = tree.build(active.all_files, active.files, active.expanded, active.changed_only)
  for index, file in ipairs(active.visible_nodes) do
    if file.type == "file" and file.path == selected_path then
      active.file_index = index
      break
    end
  end
  local node = active.visible_nodes[active.file_index]
  active.selected_path = node and node.type == "file" and node.path or nil
  render_files()
  render_diff(true)
end

local function apply_target(target)
  active.target = target
  active.selected_path = nil
  active.file_index = 1
  active.view_mode = "diff"
  refresh()
  for index, node in ipairs(active.visible_nodes) do
    if node.type == "file" then
      select_file(index)
      return
    end
  end
end

local function commit_label(commit)
  return ("%s  %s  (%s)"):format(commit.short, commit.subject, commit.relative)
end

local function select_target()
  local items = { { kind = "working", id = "working", label = "Working tree" } }
  for _, commit in ipairs(git.commits(active.root, 100)) do
    items[#items + 1] = {
      kind = "commit",
      id = "commit:" .. commit.hash,
      label = commit_label(commit),
      commit = commit.hash,
    }
  end
  vim.ui.select(items, {
    prompt = "Review target",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice and active then
      apply_target(choice)
    end
  end)
end

local function select_range()
  local commits = git.commits(active.root, 100)
  vim.ui.select(commits, {
    prompt = "Range base (older commit)",
    format_item = commit_label,
  }, function(base)
    if not base or not active then
      return
    end
    vim.ui.select(commits, {
      prompt = "Range target (newer commit)",
      format_item = commit_label,
    }, function(target)
      if target and active then
        apply_target({
          kind = "range",
          id = "range:" .. base.hash .. ".." .. target.hash,
          label = base.short .. ".." .. target.short,
          base = base.hash,
          target = target.hash,
        })
      end
    end)
  end)
end

local function toggle_files()
  active.changed_only = not active.changed_only
  if active.changed_only then
    active.expanded = tree.expand_for_paths(vim.tbl_map(function(file)
      return file.path
    end, active.files))
  else
    active.expanded = {}
  end
  render_files()
  local node = current_node()
  if not node or node.type ~= "file" then
    for index, candidate in ipairs(active.visible_nodes) do
      if candidate.type == "file" then
        select_file(index)
        break
      end
    end
  end
  notify(active.changed_only and "Showing changed files" or "Showing all repository files")
end

local function toggle_view()
  local path = active.selected_path
  if not path then
    return
  end
  if not active.changed_by_path[path] then
    notify("This file has no diff in the selected target", vim.log.levels.WARN)
    return
  end
  active.view_mode = active.rendered_mode == "diff" and "source" or "diff"
  render_diff(true)
end

local function collapse_node()
  local node = current_node()
  if node and node.type == "directory" then
    active.expanded[node.path] = false
    render_files()
  end
end

local function expand_node()
  local node = current_node()
  if node and node.type == "directory" then
    active.expanded[node.path] = true
    render_files()
  elseif node and node.type == "file" then
    select_file(active.file_index)
  end
end

local function show_help()
  local lines = {
    " AI Review — keyboard guide",
    "",
    " Navigation",
    "   Ctrl-h / Ctrl-l   Move between tree and review",
    "   j / k             Move cursor",
    "   Enter or l        Open file / expand directory",
    "   h                 Collapse directory",
    "   ]h / [h           Next / previous diff hunk",
    "",
    " Review targets and files",
    "   f                 Changed files / all files",
    "   b                 Working tree / single commit",
    "   B                 Select a commit range",
    "   v                 Diff / regular source view",
    "   r                 Refresh",
    "",
    " Comments",
    "   c                 Comment on current line",
    "   V, j/k, c         Comment on selected lines",
    "   e / d             Edit / delete comment",
    "   D                 Clear comments for this target",
    "   A                 Archive this review and clear it",
    "   H                 Open archived review history",
    "   History: r/y/q     Restore / copy / close",
    "   ]c / [c           Next / previous comment",
    "   C                 List all comments",
    "   y                 Copy AI-ready review",
    "",
    "   q                 Close review or this help",
  }
  local width = math.min(70, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 4)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " AI Review Help ",
    title_pos = "center",
  })
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:AIReviewTitle,FloatTitle:AIReviewTitle"
  local function close_help()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close_help, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close_help, { buffer = buf, silent = true })
  vim.keymap.set("n", "?", close_help, { buffer = buf, silent = true })
end

local function close()
  if not active then
    return
  end
  persist()
  local tab = active.tab
  active = nil
  if vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd("tabclose")
  end
end

local function map(buf, modes, lhs, rhs, desc)
  vim.keymap.set(modes, lhs, rhs, { buffer = buf, silent = true, desc = desc })
end

local function install_keymaps()
  local keys = config.options.keymaps
  map(active.file_buf, "n", keys.open_file, function()
    select_file(vim.api.nvim_win_get_cursor(active.file_win)[1])
  end, "Open file diff")
  map(active.file_buf, "n", keys.collapse, collapse_node, "Collapse directory")
  map(active.file_buf, "n", keys.expand, expand_node, "Expand directory or open file")
  map(active.file_buf, "n", keys.toggle_files, toggle_files, "Toggle changed/all files")
  map(active.file_buf, "n", keys.select_target, select_target, "Select review target")
  map(active.file_buf, "n", keys.select_range, select_range, "Select commit range")
  map(active.file_buf, "n", keys.help, show_help, "Show keyboard help")
  map(active.file_buf, "n", keys.refresh, refresh, "Refresh review")
  map(active.file_buf, "n", keys.close, close, "Close review")

  map(active.diff_buf, "n", keys.comment, comment_at_cursor, "Add review comment")
  map(active.diff_buf, "x", keys.comment, comment_visual, "Comment selected lines")
  map(active.diff_buf, "n", keys.edit_comment, edit_comment, "Edit review comment")
  map(active.diff_buf, "n", keys.delete_comment, delete_comment, "Delete review comment")
  map(active.diff_buf, "n", keys.clear_comments, clear_comments, "Clear comments for review target")
  map(active.diff_buf, "n", keys.archive_comments, archive_comments, "Archive review comments")
  map(active.diff_buf, "n", keys.history, show_history, "Open review history")
  map(active.diff_buf, "n", keys.comments, show_comments, "List review comments")
  map(active.diff_buf, "n", keys.toggle_view, toggle_view, "Toggle diff/source view")
  map(active.diff_buf, "n", keys.toggle_files, toggle_files, "Toggle changed/all files")
  map(active.diff_buf, "n", keys.select_target, select_target, "Select review target")
  map(active.diff_buf, "n", keys.select_range, select_range, "Select commit range")
  map(active.diff_buf, "n", keys.help, show_help, "Show keyboard help")
  map(active.diff_buf, "n", keys.next_hunk, function()
    jump_hunk(1)
  end, "Next hunk")
  map(active.diff_buf, "n", keys.prev_hunk, function()
    jump_hunk(-1)
  end, "Previous hunk")
  map(active.diff_buf, "n", keys.next_comment, function()
    jump_rows(comment_rows(), 1)
  end, "Next review comment")
  map(active.diff_buf, "n", keys.prev_comment, function()
    jump_rows(comment_rows(), -1)
  end, "Previous review comment")
  map(active.diff_buf, "n", keys.export, export_comments, "Copy review for AI")
  map(active.diff_buf, "n", keys.refresh, refresh, "Refresh review")
  map(active.diff_buf, "n", keys.close, close, "Close review")
end

function M.open(opts)
  opts = opts or {}
  require("ai-review.highlights").setup()
  if active then
    notify("A review is already open", vim.log.levels.WARN)
    return
  end
  local ok, root = pcall(git.root, opts.cwd or vim.uv.cwd())
  if not ok then
    notify("Not inside a Git repository", vim.log.levels.ERROR)
    return
  end
  local target = working_target()
  local files = git.changed_files(root, target)
  local all_files = git.repo_files(root, target)
  local changed_by_path = {}
  for _, file in ipairs(files) do
    changed_by_path[file.path] = file
    if not vim.tbl_contains(all_files, file.path) then
      all_files[#all_files + 1] = file.path
    end
  end
  table.sort(all_files)
  local branch = git.branch(root)
  local session, session_path = state.load(root, branch)

  vim.cmd("tabnew")
  local diff_win = vim.api.nvim_get_current_win()
  local diff_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(diff_win, diff_buf)
  vim.cmd("topleft vsplit")
  local file_win = vim.api.nvim_get_current_win()
  local file_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(file_win, file_buf)
  vim.api.nvim_win_set_width(file_win, config.options.file_panel_width)

  active = {
    root = root,
    branch = branch,
    target = target,
    files = files,
    all_files = all_files,
    changed_by_path = changed_by_path,
    expanded = config.options.changed_only and tree.expand_for_paths(vim.tbl_map(function(file)
      return file.path
    end, files)) or {},
    changed_only = config.options.changed_only,
    visible_nodes = {},
    file_index = 1,
    selected_path = files[1] and files[1].path or all_files[1],
    view_mode = files[1] and "diff" or "source",
    session = session,
    session_path = session_path,
    tab = vim.api.nvim_get_current_tabpage(),
    file_win = file_win,
    file_buf = file_buf,
    diff_win = diff_win,
    diff_buf = diff_buf,
  }

  vim.bo[file_buf].buftype = "nofile"
  vim.bo[file_buf].bufhidden = "wipe"
  vim.bo[file_buf].swapfile = false
  vim.bo[file_buf].filetype = "ai-review-files"
  vim.bo[diff_buf].buftype = "nofile"
  vim.bo[diff_buf].bufhidden = "wipe"
  vim.bo[diff_buf].swapfile = false
  vim.wo[file_win].number = false
  vim.wo[file_win].relativenumber = false
  vim.wo[file_win].signcolumn = "no"
  vim.wo[file_win].cursorline = true
  vim.wo[file_win].winbar = " AI Review │ Changed files "
  vim.wo[file_win].statusline = " ? Help   f All files   b Commit   B Range   Enter Open "
  vim.wo[diff_win].wrap = false
  vim.wo[diff_win].cursorline = true
  vim.wo[diff_win].statusline = " ? Help   c Comment   V…c Range   y Copy   A Archive   H History   q Close "

  install_keymaps()
  render_files()
  if active.selected_path then
    for index, node in ipairs(active.visible_nodes) do
      if node.type == "file" and node.path == active.selected_path then
        active.file_index = index
        break
      end
    end
    render_files()
  end
  render_diff(false)
  vim.api.nvim_set_current_win(diff_win)
end

function M.export_to_file(path)
  if not active then
    notify("No active review", vim.log.levels.ERROR)
    return
  end
  path = path ~= "" and path or vim.fs.joinpath(active.root, "review.md")
  vim.fn.writefile(vim.split(export.markdown(active.session, active.target), "\n", { plain = true }), path)
  notify("Review written to " .. path)
end

function M.close()
  close()
end

return M
