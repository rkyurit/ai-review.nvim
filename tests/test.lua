local git = require("ai-review.git")
local state = require("ai-review.state")
local export = require("ai-review.export")
local tree = require("ai-review.tree")

local root = assert(vim.env.AI_REVIEW_TEST_REPO)

local function equal(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(
      (message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
    )
  end
end

equal(vim.uv.fs_realpath(root), vim.uv.fs_realpath(git.root(root)), "repository root")

local files = git.changed_files(root)
equal(3, #files, "changed file count")

local by_path = {}
for _, file in ipairs(files) do
  by_path[file.path] = file
end
assert(by_path["added.txt"], "untracked file missing")
assert(by_path["deleted.txt"], "deleted file missing")
assert(by_path["tracked.txt"], "modified file missing")

local commits = git.commits(root, 10)
equal(2, #commits, "commit count")
local latest = { kind = "commit", commit = commits[1].hash }
local base = { kind = "commit", commit = commits[2].hash }
local commit_files = git.changed_files(root, latest)
equal("history.txt", commit_files[1].path, "single commit changed path")
local commit_diff = git.diff(root, commit_files[1], 3, latest)
assert(
  vim.iter(commit_diff.lines):any(function(line)
    return line.text == "+two"
  end),
  "single commit diff is missing new content"
)

local range = { kind = "range", base = commits[2].hash, target = commits[1].hash }
local range_files = git.changed_files(root, range)
equal("history.txt", range_files[1].path, "range changed path")
equal("one\n", git.read_file(root, "history.txt", base), "base source content")
equal("two\n", git.read_file(root, "history.txt", latest), "commit source content")

local repo_files = git.repo_files(root)
local visible_tree = tree.build(repo_files, files, {}, false)
assert(
  vim.iter(visible_tree):any(function(node)
    return node.type == "directory" and node.path == "src"
  end),
  "repository tree is missing directory"
)
assert(
  vim.iter(visible_tree):any(function(node)
    return node.type == "file" and node.path == "src/plain.lua"
  end),
  "repository tree is missing source file"
)

local modified = git.diff(root, by_path["tracked.txt"], 3)
assert(#modified.hunks > 0, "modified file has no hunks")
local saw_add, saw_delete = false, false
for _, line in ipairs(modified.lines) do
  saw_add = saw_add or line.kind == "add"
  saw_delete = saw_delete or line.kind == "delete"
end
assert(saw_add and saw_delete, "modified diff should contain additions and deletions")

local added = git.diff(root, by_path["added.txt"], 3)
assert(#added.hunks > 0, "untracked file has no diff")
assert(
  vim.iter(added.lines):any(function(line)
    return line.kind == "add"
  end),
  "untracked diff has no additions"
)

local session, path = state.load(root, "main")
session.comments = {
  {
    id = "1",
    path = "tracked.txt",
    side = "new",
    start_line = 1,
    end_line = 1,
    body = "Keep the original wording.",
    context = "-before\n+after",
    resolved = false,
  },
}
state.save(session, path)
local restored = state.load(root, "main")
equal("Keep the original wording.", restored.comments[1].body, "saved comment")

local markdown = export.markdown(restored)
assert(markdown:find("tracked.txt:1", 1, true), "export is missing location")
assert(markdown:find("Keep the original wording.", 1, true), "export is missing comment")

require("ai-review").open({ cwd = root })
assert(#vim.api.nvim_list_tabpages() == 2, "review tab was not created")

local file_win
local file_buf
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype == "ai-review-files" then
    file_win = win
    file_buf = buf
    vim.api.nvim_set_current_win(win)
    local rows = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local tracked_row
    for row, line in ipairs(rows) do
      if line:find("tracked.txt", 1, true) then
        tracked_row = row
        break
      end
    end
    assert(tracked_row, "tracked file is missing from file tree")
    vim.api.nvim_win_set_cursor(win, { tracked_row, 0 })
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
    break
  end
end

local diff_buf = vim.api.nvim_get_current_buf()
local initial_tree = vim.api.nvim_buf_get_lines(file_buf, 0, -1, false)
assert(not table.concat(initial_tree, "\n"):find("plain.lua", 1, true), "unchanged file should be hidden by default")
local selection_hl = vim.api.nvim_get_hl(0, { name = "AIReviewSelection" })
assert(selection_hl.bg, "review highlight was not configured")
assert(vim.wo[file_win].winbar:find("?:Help", 1, true), "file tree is missing persistent help hint")
assert(vim.wo[vim.fn.bufwinid(diff_buf)].winbar:find("c:Comment", 1, true), "diff view is missing persistent key hints")
local diff_lines = vim.api.nvim_buf_get_lines(diff_buf, 0, -1, false)
local added_row
local deleted_row
for row, line in ipairs(diff_lines) do
  if line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
    added_row = row
  elseif line:sub(1, 1) == "-" and line:sub(1, 3) ~= "---" then
    deleted_row = row
  end
end
assert(added_row, "no added line in review buffer")
assert(deleted_row, "no deleted line in review buffer")
local selection_start = math.min(added_row, deleted_row)
local selection_end = math.max(added_row, deleted_row)
vim.api.nvim_win_set_cursor(0, { selection_start, 0 })
vim.ui.input = function(_, callback)
  callback("Visual range comment")
end
vim.cmd("normal! V")
vim.api.nvim_win_set_cursor(0, { selection_end, 0 })
vim.api.nvim_feedkeys("c", "x", false)
vim.wait(50)

local visual_export = vim.fs.joinpath(vim.env.AI_REVIEW_TEST_STATE, "visual-review.md")
vim.cmd("AIReviewExport " .. vim.fn.fnameescape(visual_export))
local exported = table.concat(vim.fn.readfile(visual_export), "\n")
assert(exported:find("Visual range comment", 1, true), "visual comment was not exported")
assert(exported:find("-before", 1, true), "visual comment context is missing deleted line")
assert(exported:find("+after", 1, true), "visual comment context is missing added line")

local windows_before_help = #vim.api.nvim_tabpage_list_wins(0)
vim.api.nvim_feedkeys("?", "x", false)
equal(windows_before_help + 1, #vim.api.nvim_tabpage_list_wins(0), "help window did not open")
vim.api.nvim_feedkeys("q", "x", false)
equal(windows_before_help, #vim.api.nvim_tabpage_list_wins(0), "help window did not close")

vim.api.nvim_set_current_win(vim.fn.bufwinid(diff_buf))
vim.api.nvim_feedkeys("f", "x", false)

local file_lines = vim.api.nvim_buf_get_lines(file_buf, 0, -1, false)
local source_row
for row, line in ipairs(file_lines) do
  if line:find("plain.lua", 1, true) then
    source_row = row
    break
  end
end
assert(source_row, "source file is missing from file tree")
vim.api.nvim_set_current_win(file_win)
vim.api.nvim_win_set_cursor(file_win, { source_row, 0 })
vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
equal("lua", vim.bo[vim.api.nvim_get_current_buf()].filetype, "source filetype")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.ui.input = function(_, callback)
  callback("Source file comment")
end
vim.cmd("normal! Vj")
vim.api.nvim_feedkeys("c", "x", false)
vim.wait(50)
vim.cmd("AIReviewExport " .. vim.fn.fnameescape(visual_export))
exported = table.concat(vim.fn.readfile(visual_export), "\n")
assert(exported:find("Source file comment", 1, true), "source comment was not exported")
assert(exported:find("View: source file", 1, true), "source comment type was not exported")

require("ai-review").close()
assert(#vim.api.nvim_list_tabpages() == 1, "review tab was not closed")

print("all tests passed")
