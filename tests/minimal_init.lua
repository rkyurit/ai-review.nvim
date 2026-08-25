vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("ai-review").setup({
  storage_dir = vim.env.AI_REVIEW_TEST_STATE,
  export_to_clipboard = false,
})
