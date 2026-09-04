local git = require("ai-review.git")
local state = require("ai-review.state")
local export = require("ai-review.export")
local clipboard = require("ai-review.clipboard")
local tree = require("ai-review.tree")
local picker = require("ai-review.picker")

local root = assert(vim.env.AI_REVIEW_TEST_REPO)
local unborn_root = assert(vim.env.AI_REVIEW_TEST_UNBORN_REPO)

local function equal(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(
      (message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
    )
  end
end

local picked_file
local picked_position
local picked_filtered_file
local picked_comment
local closed_picker = false
_G.Snacks = {
  picker = {
    files = function(opts)
      opts.confirm({
        close = function()
          closed_picker = true
        end,
      }, { file = "src/plain.lua" })
    end,
    grep = function(opts)
      opts.confirm({
        close = function() end,
      }, { file = "tracked.txt", pos = { 3, 4 } })
    end,
    pick = function(opts)
      equal("file", opts.format, "filtered files should use Snacks file formatting")
      assert(type(opts.preview) == "function", "filtered files should provide a preview")
      opts.confirm({ close = function() end }, opts.items[1])
    end,
  },
}
assert(picker.available(), "Snacks picker should be detected")
assert(
  picker.files({
    cwd = root,
    on_select = function(path)
      picked_file = path
    end,
  }),
  "Snacks file picker was not used"
)
assert(
  picker.grep({
    cwd = root,
    on_select = function(path, pos)
      picked_position = { path, pos }
    end,
  }),
  "Snacks grep picker was not used"
)
assert(
  picker.file_list({
    cwd = root,
    paths = { "tracked.txt" },
    preview = function()
      return "preview", "text"
    end,
    on_select = function(path)
      picked_filtered_file = path
    end,
  }),
  "Snacks filtered file picker was not used"
)
local picker_comment = { path = "tracked.txt", start_line = 1, body = "Review this line" }
assert(
  picker.comment_list({
    cwd = root,
    comments = { picker_comment },
    preview = function()
      return "preview", "diff"
    end,
    on_select = function(comment)
      picked_comment = comment
    end,
  }),
  "Snacks comment picker was not used"
)
vim.wait(100, function()
  return picked_file ~= nil and picked_position ~= nil and picked_filtered_file ~= nil and picked_comment ~= nil
end)
equal("src/plain.lua", picked_file, "Snacks file selection")
equal({ "tracked.txt", { 3, 4 } }, picked_position, "Snacks grep selection")
equal("tracked.txt", picked_filtered_file, "Snacks filtered file selection")
equal(picker_comment, picked_comment, "Snacks comment selection")
assert(closed_picker, "Snacks picker should close before selection")
_G.Snacks = nil
assert(not picker.available(), "missing Snacks picker should be detected")

local unborn_files = git.changed_files(unborn_root)
equal(1, #unborn_files, "unborn repository changed file count")
equal("first.txt", unborn_files[1].path, "unborn repository file path")
equal("?", unborn_files[1].status, "unborn repository file status")
local unborn_diff = git.diff(unborn_root, unborn_files[1], 3)
assert(vim.iter(unborn_diff.lines):any(function(line)
  return line.text == "+first file"
end), "unborn repository diff is missing new content")

local wsl_providers = clipboard._command_providers(true)
equal("clip.exe", wsl_providers[1].executable, "preferred WSL clipboard provider")
equal("utf-16le", wsl_providers[1].encoding, "clip.exe input encoding")
local encoded_japanese = clipboard._provider_input(wsl_providers[1], "日本語")
local encoded_bytes = encoded_japanese:gsub(".", function(byte)
  return ("%02x"):format(byte:byte())
end)
equal("e5652c679e8a", encoded_bytes, "UTF-16LE clipboard input")
equal("win32yank.exe", wsl_providers[2].executable, "WSL clipboard fallback")
equal("powershell.exe", wsl_providers[3].executable, "UTF-8 WSL clipboard fallback")
assert(table.concat(wsl_providers[3].command, " "):find("UTF8Encoding", 1, true), "PowerShell input is not UTF-8")

equal(vim.uv.fs_realpath(root), vim.uv.fs_realpath(git.root(root)), "repository root")
local repo_root = git.root(root)

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
local github_pr = assert(git._parse_github_pull_request(vim.json.encode({
  number = 42,
  title = "Review this change",
  url = "https://github.com/example/repo/pull/42",
  baseRefName = "main",
  baseRefOid = "base-oid",
  headRefName = "feature",
  headRefOid = "head-oid",
})))
equal(42, github_pr.number, "GitHub PR number")
equal("base-oid", github_pr.baseRefOid, "GitHub PR base OID")
local invalid_pr, invalid_pr_error = git._parse_github_pull_request("{}")
assert(not invalid_pr and invalid_pr_error:find("number", 1, true), "invalid GitHub PR data was accepted")
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
local commit_search = git.search(root, "one", base)
equal("history.txt", commit_search[1].path, "commit text search path")
equal(1, commit_search[1].line, "commit text search line")

local branches = git.branches(root)
assert(vim.iter(branches):any(function(branch)
  return branch.name == "review-base"
end), "base branch is missing")
assert(vim.iter(branches):any(function(branch)
  return branch.name == "review-head"
end), "head branch is missing")
local pull_request = {
  kind = "pull_request",
  base = "review-base",
  head = "review-head",
}
local pull_request_files = git.changed_files(root, pull_request)
equal("history.txt", pull_request_files[1].path, "PR changed path")
local pull_request_diff = git.diff(root, pull_request_files[1], 3, pull_request)
assert(vim.iter(pull_request_diff.lines):any(function(line)
  return line.text == "+two"
end), "PR diff is missing new content")
equal("two\n", git.read_file(root, "history.txt", pull_request), "PR head source content")
local pull_request_search = git.search(root, "two", pull_request)
equal("history.txt", pull_request_search[1].path, "PR text search path")

local repo_files = git.repo_files(root)
assert(not vim.tbl_contains(repo_files, "ignored/"), "ignored directory should be hidden by default")
repo_files = git.repo_files(root, nil, { "ignored/" })
assert(vim.tbl_contains(repo_files, "ignored/"), "configured ignored directory is missing from repository tree")
assert(not vim.tbl_contains(repo_files, "ignored/generated.txt"), "ignored directory contents should be loaded lazily")
local ignored_entries = git.directory_entries(root, "ignored")
assert(vim.tbl_contains(ignored_entries, "ignored/generated.txt"), "ignored directory could not be expanded lazily")
local ignored_files = git.directory_files(root, "ignored")
assert(vim.tbl_contains(ignored_files, "ignored/generated.txt"), "ignored directory file is missing from search")
local text_results = git.search(root, "local value")
equal("src/plain.lua", text_results[1].path, "repository text search path")
equal(1, text_results[1].line, "repository text search line")
equal(1, text_results[1].column, "repository text search column")
equal(0, #git.search(root, "still visible in the full tree"), "ignored text should be excluded by default")
local ignored_text_results = git.search(root, "still visible in the full tree", nil, { "ignored/" })
equal("ignored/generated.txt", ignored_text_results[1].path, "included ignored text search path")
assert(not by_path["ignored/generated.txt"], "ignored file must not appear in changed files")

local visible_tree = tree.build(repo_files, files, tree.expand_for_paths(repo_files), false)
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
local collapsed_tree = tree.build(repo_files, files, {}, false)
assert(
  vim.iter(collapsed_tree):any(function(node)
    return node.type == "directory" and node.path == "ignored"
  end),
  "ignored directory should remain visible in the full tree"
)
assert(not vim.iter(collapsed_tree):any(function(node)
  return node.path == "src/plain.lua"
end), "full repository tree should start collapsed")
local nested_change = { { path = "src/plain.lua", status = "M" } }
local changed_tree = tree.build(repo_files, nested_change, tree.expand_for_paths({ "src/plain.lua" }), true)
assert(
  vim.iter(changed_tree):any(function(node)
    return node.path == "src/plain.lua"
  end),
  "changed-file parents should be expanded"
)
assert(not vim.iter(changed_tree):any(function(node)
  return node.path == "ignored"
end), "ignored directories must not appear in changed-files mode")

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

local session, path = state.load(repo_root, "main")
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
  {
    id = "ignored-comment",
    path = "ignored/generated.txt",
    side = "source",
    start_line = 1,
    end_line = 1,
    body = "Ignored source comment",
    context = "still visible in the full tree",
    resolved = false,
  },
}
state.save(session, path)
local restored = state.load(repo_root, "main")
equal("Keep the original wording.", restored.comments[1].body, "saved comment")

local markdown = export.markdown(restored)
assert(markdown:find("tracked.txt:1", 1, true), "export is missing location")
assert(markdown:find("Keep the original wording.", 1, true), "export is missing comment")
assert(markdown:find("If a comment asks a question", 1, true), "export is missing question guidance")
assert(not markdown:find("# AI code review feedback", 1, true), "export still contains the redundant title")

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
local diff_mappings = vim.api.nvim_buf_get_keymap(diff_buf, "n")
for _, lhs in ipairs({ "b", "B", "c", "e", "d", "D", "A", "H", "C", "f", "F", "?", "v", "y", "r", "]c", "[c" }) do
  assert(not vim.iter(diff_mappings):any(function(mapping)
    return mapping.lhs == lhs
  end), "standard Vim key is shadowed in review buffer: " .. lhs)
end
assert(
  vim.iter(vim.api.nvim_buf_get_keymap(file_buf, "n")):any(function(mapping)
    return mapping.lhs == ",l" and mapping.desc == "List review comments"
  end),
  "file tree is missing the comment search mapping"
)
assert(
  vim.iter(vim.api.nvim_buf_get_keymap(file_buf, "n")):any(function(mapping)
    return mapping.lhs == ",g" and mapping.desc == "Search repository text"
  end),
  "file tree is missing repository text search"
)
for _, mapping in ipairs({
  { lhs = ",s", desc = "Toggle file tree" },
  { lhs = ",<lt>", desc = "Narrow file tree" },
  { lhs = ",>", desc = "Widen file tree" },
  { lhs = ",P", desc = "Open GitHub PR" },
}) do
  assert(vim.iter(diff_mappings):any(function(item)
    return item.lhs == mapping.lhs and item.desc == mapping.desc
  end), "diff view is missing file-tree mapping: " .. mapping.lhs)
end
local original_file_width = vim.api.nvim_win_get_width(file_win)
vim.api.nvim_feedkeys(",>", "x", false)
equal(original_file_width + 4, vim.api.nvim_win_get_width(file_win), "file tree did not widen")
vim.api.nvim_feedkeys(",<", "x", false)
equal(original_file_width, vim.api.nvim_win_get_width(file_win), "file tree did not narrow")
vim.api.nvim_feedkeys(",s", "x", false)
assert(vim.fn.bufwinid(file_buf) == -1, "file tree did not close")
vim.api.nvim_feedkeys(",s", "x", false)
file_win = vim.fn.bufwinid(file_buf)
assert(file_win ~= -1, "file tree did not reopen")
equal(original_file_width, vim.api.nvim_win_get_width(file_win), "file tree width was not restored")
vim.api.nvim_set_current_win(vim.fn.bufwinid(diff_buf))
local initial_tree = vim.api.nvim_buf_get_lines(file_buf, 0, -1, false)
assert(not table.concat(initial_tree, "\n"):find("plain.lua", 1, true), "unchanged file should be hidden by default")

vim.api.nvim_set_current_win(vim.fn.bufwinid(diff_buf))
vim.api.nvim_feedkeys(",t", "x", false)
assert(vim.wo[file_win].winbar:find("All files", 1, true), "test did not enter all-files mode")
vim.ui.select = function(items, opts, callback)
  local wanted = opts.prompt == "PR base branch" and "review-base" or "review-head"
  callback(vim.iter(items):find(function(item)
    return item.name == wanted
  end))
end
vim.api.nvim_feedkeys(",p", "x", false)
assert(vim.wo[file_win].winbar:find("Changed files", 1, true), "PR selection did not reset to changed files")
assert(
  vim.wo[vim.fn.bufwinid(diff_buf)].winbar:find("review-base...review-head │ diff │ history.txt", 1, true),
  "PR selection did not open its first diff"
)
vim.ui.select = function(items, _, callback)
  callback(items[1])
end
vim.api.nvim_feedkeys(",b", "x", false)
local working_tree_rows = vim.api.nvim_buf_get_lines(file_buf, 0, -1, false)
for row, line in ipairs(working_tree_rows) do
  if line:find("tracked.txt", 1, true) then
    vim.api.nvim_set_current_win(file_win)
    vim.api.nvim_win_set_cursor(file_win, { row, 0 })
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
    break
  end
end
local selection_hl = vim.api.nvim_get_hl(0, { name = "AIReviewSelection" })
assert(selection_hl.bg, "review highlight was not configured")
assert(vim.wo[file_win].winbar:find(",k:Help", 1, true), "file tree is missing persistent help hint")
assert(
  vim.wo[vim.fn.bufwinid(diff_buf)].winbar:find(",c:Comment", 1, true),
  "diff view is missing persistent key hints"
)
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
vim.ui.input = function(_, callback)
  callback("after")
end
vim.ui.select = function(items, _, callback)
  callback(items[1])
end
vim.api.nvim_feedkeys(",g", "x", false)
assert(
  vim.wo[vim.fn.bufwinid(diff_buf)].winbar:find("│ diff │ tracked.txt", 1, true),
  "changed grep result did not open as a diff"
)
equal(added_row, vim.api.nvim_win_get_cursor(vim.fn.bufwinid(diff_buf))[1], "grep result did not reach its diff line")
local selection_start = math.min(added_row, deleted_row)
local selection_end = math.max(added_row, deleted_row)
vim.api.nvim_win_set_cursor(0, { selection_start, 0 })
vim.ui.input = function(_, callback)
  callback("Visual range comment")
end
vim.cmd("normal! V")
vim.api.nvim_win_set_cursor(0, { selection_end, 0 })
vim.api.nvim_feedkeys(",c", "x", false)
vim.wait(50)

local visual_export = vim.fs.joinpath(vim.env.AI_REVIEW_TEST_STATE, "visual-review.md")
vim.cmd("AIReviewExport " .. vim.fn.fnameescape(visual_export))
local exported = table.concat(vim.fn.readfile(visual_export), "\n")
assert(exported:find("Visual range comment", 1, true), "visual comment was not exported")
assert(exported:find("-before", 1, true), "visual comment context is missing deleted line")
assert(exported:find("+after", 1, true), "visual comment context is missing added line")

vim.ui.select = function(items, _, callback)
  callback(items[1])
end
vim.api.nvim_feedkeys(",l", "x", false)
assert(vim.wo[file_win].winbar:find("Changed files", 1, true), "comment jump changed the file-tree mode")
assert(vim.wo[vim.fn.bufwinid(diff_buf)].winbar:find("tracked.txt", 1, true), "comment jump did not open its file")
equal(added_row, vim.api.nvim_win_get_cursor(vim.fn.bufwinid(diff_buf))[1], "comment jump did not reach its line")

local windows_before_help = #vim.api.nvim_tabpage_list_wins(0)
vim.api.nvim_feedkeys(",k", "x", false)
equal(windows_before_help + 1, #vim.api.nvim_tabpage_list_wins(0), "help window did not open")
vim.api.nvim_feedkeys("q", "x", false)
equal(windows_before_help, #vim.api.nvim_tabpage_list_wins(0), "help window did not close")

vim.api.nvim_set_current_win(vim.fn.bufwinid(diff_buf))
vim.api.nvim_feedkeys(",t", "x", false)

local file_lines = vim.api.nvim_buf_get_lines(file_buf, 0, -1, false)
local src_row
for row, line in ipairs(file_lines) do
  if line:find("src", 1, true) then
    src_row = row
    break
  end
end
assert(src_row, "collapsed source directory is missing from file tree")
vim.api.nvim_set_current_win(file_win)
vim.api.nvim_win_set_cursor(file_win, { src_row, 0 })
vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
file_lines = vim.api.nvim_buf_get_lines(file_buf, 0, -1, false)
local source_row
for row, line in ipairs(file_lines) do
  if line:find("plain.lua", 1, true) then
    source_row = row
    break
  end
end
assert(source_row, "source file is missing from file tree")
local diff_win = vim.fn.bufwinid(diff_buf)
vim.api.nvim_win_set_cursor(diff_win, { vim.api.nvim_buf_line_count(diff_buf), 0 })
vim.api.nvim_set_current_win(file_win)
vim.api.nvim_win_set_cursor(file_win, { source_row, 0 })
vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
equal("lua", vim.bo[vim.api.nvim_get_current_buf()].filetype, "source filetype")
equal(1, vim.api.nvim_win_get_cursor(0)[1], "newly opened file should start at the first line")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.ui.input = function(_, callback)
  callback("Source file comment")
end
vim.cmd("normal! Vj")
vim.api.nvim_feedkeys(",c", "x", false)
vim.wait(50)
vim.cmd("AIReviewExport " .. vim.fn.fnameescape(visual_export))
exported = table.concat(vim.fn.readfile(visual_export), "\n")
assert(exported:find("Source file comment", 1, true), "source comment was not exported")
assert(exported:find("View: source file", 1, true), "source comment type was not exported")

vim.api.nvim_feedkeys(",t", "x", false)
assert(vim.wo[file_win].winbar:find("Changed files", 1, true), "test did not return to changed-files mode")
vim.ui.select = function(items, _, callback)
  local source_comment
  for _, item in ipairs(items) do
    if item.body == "Ignored source comment" then
      source_comment = item
      break
    end
  end
  callback(source_comment)
end
vim.api.nvim_feedkeys(",l", "x", false)
assert(vim.wo[file_win].winbar:find("All files", 1, true), "source comment did not switch to the full tree")
assert(
  vim.wo[vim.fn.bufwinid(diff_buf)].winbar:find("ignored/generated.txt", 1, true),
  "lazily loaded comment file did not open"
)
equal(1, vim.api.nvim_win_get_cursor(vim.fn.bufwinid(diff_buf))[1], "source comment did not jump to its line")
vim.api.nvim_feedkeys(",d", "x", false)

vim.ui.input = function(_, callback)
  callback("First AI review")
end
vim.api.nvim_feedkeys(",a", "x", false)
vim.wait(50)
vim.cmd("AIReviewExport " .. vim.fn.fnameescape(visual_export))
exported = table.concat(vim.fn.readfile(visual_export), "\n")
assert(exported:find("No unresolved comments", 1, true), "archiving did not clear active target comments")
local after_archive = state.load(repo_root, "main")
equal(1, #after_archive.archives, "review archive count")
equal("First AI review", after_archive.archives[1].title, "review archive title")
assert(after_archive.archives[1].markdown:find("Source file comment", 1, true), "archive is missing comments")

local windows_before_history = #vim.api.nvim_tabpage_list_wins(0)
vim.ui.select = function(items, _, callback)
  callback(items[1])
end
vim.api.nvim_feedkeys(",h", "x", false)
equal(windows_before_history + 1, #vim.api.nvim_tabpage_list_wins(0), "history window did not open")
assert(
  vim.wo[vim.api.nvim_get_current_win()].winbar:find("AI Review History │ First AI review", 1, true),
  "history pane is missing its title"
)
local history_lines = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(history_lines:find("Source file comment", 1, true), "history pane is missing archived comments")
local history_state = state.load(repo_root, "main")
equal(0, #history_state.comments, "opening history changed active comments")
equal(1, #history_state.archives, "opening history changed archives")
vim.api.nvim_feedkeys("q", "x", false)
equal(windows_before_history, #vim.api.nvim_tabpage_list_wins(0), "history pane did not close")

require("ai-review").close()
assert(#vim.api.nvim_list_tabpages() == 1, "review tab was not closed")

print("all tests passed")
