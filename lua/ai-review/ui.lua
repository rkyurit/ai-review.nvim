local config = require("ai-review.config")
local export = require("ai-review.export")
local git = require("ai-review.git")
local state = require("ai-review.state")

local M = {}
local ns = vim.api.nvim_create_namespace("ai-review")
local active

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
    if comment.path == path and not comment.resolved then
      comments[#comments + 1] = comment
    end
  end
  return comments
end

local function render_comments()
  vim.api.nvim_buf_clear_namespace(active.diff_buf, ns, 0, -1)
  local path = active.files[active.file_index].path
  for _, comment in ipairs(comments_for_file(path)) do
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
        virtual[#virtual + 1] = { { prefix .. line, "DiagnosticInfo" } }
      end
      vim.api.nvim_buf_set_extmark(active.diff_buf, ns, target_row - 1, 0, {
        virt_lines = virtual,
        virt_lines_above = false,
      })
    end
  end
end

local function render_files()
  local lines = {}
  for index, file in ipairs(active.files) do
    local marker = index == active.file_index and "▸" or " "
    local count = #comments_for_file(file.path)
    local suffix = count > 0 and ("  [%d]"):format(count) or ""
    lines[#lines + 1] = ("%s %s %s%s"):format(marker, file.status, file.path, suffix)
  end
  if #lines == 0 then
    lines = { "  No changes" }
  end
  set_lines(active.file_buf, lines)
end

local function render_diff(keep_cursor)
  local file = active.files[active.file_index]
  if not file then
    set_lines(active.diff_buf, { "No changes to review." })
    active.parsed = nil
    return
  end
  local old_cursor = valid_window(active.diff_win) and vim.api.nvim_win_get_cursor(active.diff_win) or { 1, 0 }
  local ok, parsed = pcall(git.diff, active.root, file, config.options.context_lines)
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
  set_lines(active.diff_buf, #lines > 0 and lines or { "No diff for " .. file.path })
  vim.bo[active.diff_buf].filetype = "diff"
  vim.api.nvim_buf_set_name(active.diff_buf, "ai-review://" .. file.path)
  render_comments()
  if keep_cursor and valid_window(active.diff_win) then
    old_cursor[1] = math.min(old_cursor[1], math.max(1, #lines))
    vim.api.nvim_win_set_cursor(active.diff_win, old_cursor)
  end
end

local function select_file(index)
  if not active.files[index] then
    return
  end
  active.file_index = index
  render_files()
  render_diff(false)
  vim.api.nvim_set_current_win(active.diff_win)
end

local function add_comment(start_row, end_row)
  if not active.parsed then
    return
  end
  local first = active.parsed.lines[start_row]
  local last = active.parsed.lines[end_row]
  local side, start_line = comment_line(first)
  local last_side, end_line = comment_line(last)
  if not side or not start_line then
    notify("Place the cursor on a changed or context line", vim.log.levels.WARN)
    return
  end
  if last_side ~= side or not end_line then
    end_line = start_line
    end_row = start_row
  end
  vim.ui.input(
    { prompt = ("Comment on %s:%d: "):format(active.files[active.file_index].path, start_line) },
    function(body)
      if not body or vim.trim(body) == "" or not active then
        return
      end
      active.session.comments[#active.session.comments + 1] = {
        id = tostring(vim.uv.hrtime()),
        path = active.files[active.file_index].path,
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
    end
  )
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
      comment.path == active.files[active.file_index].path
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
  local path = active.files[active.file_index].path
  for row, entry in ipairs(active.parsed.lines) do
    local side, line = comment_line(entry)
    for _, comment in ipairs(active.session.comments) do
      if comment.path == path and not comment.resolved and comment.side == side and comment.start_line == line then
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
    if not comment.resolved then
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
    for index, file in ipairs(active.files) do
      if file.path == choice.path then
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
  local markdown = export.markdown(active.session)
  vim.fn.setreg('"', markdown)
  if config.options.export_to_clipboard and vim.fn.has("clipboard") == 1 then
    vim.fn.setreg("+", markdown)
  end
  notify("Review copied to clipboard")
end

local function refresh()
  local selected_path = active.files[active.file_index] and active.files[active.file_index].path
  active.files = git.changed_files(active.root)
  active.file_index = 1
  for index, file in ipairs(active.files) do
    if file.path == selected_path then
      active.file_index = index
      break
    end
  end
  render_files()
  render_diff(true)
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
  map(active.file_buf, "n", keys.refresh, refresh, "Refresh review")
  map(active.file_buf, "n", keys.close, close, "Close review")

  map(active.diff_buf, "n", keys.comment, comment_at_cursor, "Add review comment")
  map(active.diff_buf, "x", keys.comment, comment_visual, "Comment selected lines")
  map(active.diff_buf, "n", keys.edit_comment, edit_comment, "Edit review comment")
  map(active.diff_buf, "n", keys.delete_comment, delete_comment, "Delete review comment")
  map(active.diff_buf, "n", keys.comments, show_comments, "List review comments")
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
  if active then
    notify("A review is already open", vim.log.levels.WARN)
    return
  end
  local ok, root = pcall(git.root, opts.cwd or vim.uv.cwd())
  if not ok then
    notify("Not inside a Git repository", vim.log.levels.ERROR)
    return
  end
  local files = git.changed_files(root)
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
    files = files,
    file_index = 1,
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
  vim.wo[diff_win].wrap = false

  install_keymaps()
  render_files()
  render_diff(false)
  vim.api.nvim_set_current_win(diff_win)
end

function M.export_to_file(path)
  if not active then
    notify("No active review", vim.log.levels.ERROR)
    return
  end
  path = path ~= "" and path or vim.fs.joinpath(active.root, "review.md")
  vim.fn.writefile(vim.split(export.markdown(active.session), "\n", { plain = true }), path)
  notify("Review written to " .. path)
end

function M.close()
  close()
end

return M
