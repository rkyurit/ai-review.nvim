local M = {}

M.defaults = {
  storage_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "ai-review"),
  file_panel_width = 34,
  context_lines = 3,
  export_to_clipboard = true,
  changed_only = true,
  highlights = {
    selection = { bg = "#37373d", bold = true },
    directory = { fg = "#c5c5c5", bold = true },
    modified = { fg = "#e2c08d" },
    added = { fg = "#89d185" },
    deleted = { fg = "#f14c4c" },
    untracked = { fg = "#73c991" },
    muted = { fg = "#858585" },
    hunk = { fg = "#75beff", bg = "#252526", bold = true },
    diff_add = { fg = "#b5cea8", bg = "#1e3a2a" },
    diff_delete = { fg = "#f48771", bg = "#3f2020" },
    diff_context = { fg = "#d4d4d4" },
    comment = { fg = "#ffffff", bg = "#264f78" },
    title = { fg = "#ffffff", bg = "#007acc", bold = true },
  },
  keymaps = {
    open_file = "<CR>",
    comment = "c",
    edit_comment = "e",
    delete_comment = "d",
    clear_comments = "D",
    archive_comments = "A",
    history = "H",
    comments = "C",
    help = "?",
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
