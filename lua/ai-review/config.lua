local M = {}

M.defaults = {
  storage_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "ai-review"),
  file_panel_width = 34,
  context_lines = 3,
  export_to_clipboard = true,
  keymaps = {
    open_file = "<CR>",
    comment = "c",
    edit_comment = "e",
    delete_comment = "d",
    comments = "C",
    toggle_files = "f",
    toggle_view = "v",
    select_target = "b",
    select_range = "B",
    collapse = "h",
    expand = "l",
    next_hunk = "]h",
    prev_hunk = "[h",
    next_comment = "]c",
    prev_comment = "[c",
    export = "y",
    refresh = "r",
    close = "q",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
