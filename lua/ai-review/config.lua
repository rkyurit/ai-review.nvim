local M = {}

M.defaults = {
  storage_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "ai-review"),
  file_panel_width = 34,
  history_panel_width = 60,
  context_lines = 3,
  export_to_clipboard = true,
  changed_only = true,
  include_ignored = {},
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
    comment = "<localleader>c",
    edit_comment = "<localleader>e",
    delete_comment = "<localleader>d",
    clear_comments = "<localleader>D",
    archive_comments = "<localleader>a",
    history = "<localleader>h",
    comments = "<localleader>l",
    search_files = "<localleader>f",
    search_content = "<localleader>g",
    help = "<localleader>k",
    toggle_files = "<localleader>t",
    toggle_view = "<localleader>v",
    select_target = "<localleader>b",
    select_range = "<localleader>B",
    select_pull_request = "<localleader>p",
    collapse = "h",
    expand = "l",
    next_hunk = "]h",
    prev_hunk = "[h",
    next_comment = "]r",
    prev_comment = "[r",
    export = "<localleader>y",
    refresh = "<localleader>r",
    close = "q",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
