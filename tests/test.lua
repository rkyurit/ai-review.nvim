local git = require("ai-review.git")
local state = require("ai-review.state")
local export = require("ai-review.export")

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

local diff_buf = vim.api.nvim_get_current_buf()
local diff_lines = vim.api.nvim_buf_get_lines(diff_buf, 0, -1, false)
local added_row
for row, line in ipairs(diff_lines) do
  if line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
    added_row = row
    break
  end
end
assert(added_row, "no added line in review buffer")
vim.api.nvim_win_set_cursor(0, { added_row, 0 })
vim.ui.input = function(_, callback)
  callback("Visual range comment")
end
vim.cmd("normal! V")
vim.api.nvim_feedkeys("c", "x", false)
vim.wait(50)

local visual_export = vim.fs.joinpath(vim.env.AI_REVIEW_TEST_STATE, "visual-review.md")
vim.cmd("AIReviewExport " .. vim.fn.fnameescape(visual_export))
local exported = table.concat(vim.fn.readfile(visual_export), "\n")
assert(exported:find("Visual range comment", 1, true), "visual comment was not exported")

require("ai-review").close()
assert(#vim.api.nvim_list_tabpages() == 1, "review tab was not closed")

print("all tests passed")
