if vim.g.loaded_ai_review then
  return
end
vim.g.loaded_ai_review = true

vim.api.nvim_create_user_command("AIReview", function(command)
  require("ai-review").open({ cwd = command.args ~= "" and command.args or nil })
end, { nargs = "?", complete = "dir", desc = "Review local Git changes" })

vim.api.nvim_create_user_command("AIReviewClose", function()
  require("ai-review").close()
end, { desc = "Close the active AI review" })

vim.api.nvim_create_user_command("AIReviewExport", function(command)
  require("ai-review").export(command.args)
end, { nargs = "?", complete = "file", desc = "Export review comments as Markdown" })
