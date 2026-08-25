local config = require("ai-review.config")

local M = {}

local names = {
  selection = "AIReviewSelection",
  directory = "AIReviewDirectory",
  modified = "AIReviewModified",
  added = "AIReviewAdded",
  deleted = "AIReviewDeleted",
  untracked = "AIReviewUntracked",
  muted = "AIReviewMuted",
  hunk = "AIReviewHunk",
  diff_add = "AIReviewDiffAdd",
  diff_delete = "AIReviewDiffDelete",
  diff_context = "AIReviewDiffContext",
  comment = "AIReviewComment",
  title = "AIReviewTitle",
}

function M.setup()
  for option, group in pairs(names) do
    vim.api.nvim_set_hl(0, group, config.options.highlights[option] or {})
  end
end

return M
