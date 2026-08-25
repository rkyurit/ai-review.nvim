local M = {}

function M.setup(opts)
  require("ai-review.config").setup(opts)
end

function M.open(opts)
  require("ai-review.ui").open(opts)
end

function M.close()
  require("ai-review.ui").close()
end

function M.export(path)
  require("ai-review.ui").export_to_file(path or "")
end

return M
