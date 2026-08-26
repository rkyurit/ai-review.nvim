# ai-review.nvim

[日本語](README.ja.md)

A keyboard-first Neovim interface for reviewing local Git changes, writing inline comments, and exporting them as an AI-ready Markdown prompt.

Everything stays local. No GitHub account, network connection, or external Neovim plugin is required. It works on macOS, Linux, and Windows through WSL.

## Features

- Review staged and unstaged changes against `HEAD`, a single commit, or a commit range.
- Browse and comment on unchanged files as well as diffs.
- Comment on one line or a Visual selection.
- Search files and comments without typing paths or line numbers.
- Archive named review snapshots outside the repository.
- Read archived Markdown in a separate right-hand pane.
- Export active comments as an AI-ready Markdown prompt.
- Copy Japanese text safely from WSL.

## Requirements

- Neovim 0.11 or newer
- Git

## Installation

With `lazy.nvim`:

```lua
{
  "rkyurit/ai-review.nvim",
  cmd = { "AIReview", "AIReviewClose", "AIReviewExport" },
  opts = {},
}
```

Run `:Lazy sync`, then restart Neovim.

## Quick start

Open Neovim inside a Git repository and run:

```vim
:AIReview
```

The initial layout shows changed files on the left and the selected diff in the center. The working-tree target includes staged, unstaged, and non-ignored untracked files.

1. Select a file with `j` / `k` and `<CR>`.
2. Press `c` on a line, or select a range in Visual mode and press `c`.
3. Press `y` to copy all active comments as Markdown for an AI assistant.
4. After applying fixes, press `r` to refresh the diff. Comments without a current location remain visible as `Outdated review` entries and through `C`.

Use `f` to switch between changed files and the full repository tree. Changed-file mode expands directories containing changes; all-files mode starts collapsed. Unchanged files open as regular source and accept the same comments.

Use `b` to select the working tree or one commit, and `B` to select a commit range.

## Search and ignored files

- `F` searches files in the current tree mode.
- `C` searches active comments and jumps to the selected location.

Git-ignored paths are hidden by default. Add exact paths or glob patterns with `include_ignored`. Included directories remain collapsed and are scanned only when expanded or searched with `F` in all-files mode.

```lua
{
  "rkyurit/ai-review.nvim",
  opts = {
    include_ignored = { ".env", "generated/*.json", "sample-data/" },
  },
}
```

## Review history

Press `A` to archive every active comment under a name and clear the active review. Archives are stored in Neovim's state directory, not in the repository.

Press `H` from the file tree or review pane and select an archive. Its read-only Markdown opens on the right:

```text
[ file tree ] [ current file or diff ] [ archived review ]
```

Archived comments never mix into the active review. In the history pane, press `y` to copy or `q` to close it. Selecting another archive replaces the pane contents.

## Key bindings

| Key | Action |
| --- | --- |
| `<CR>` | Open the selected file |
| `h` / `l` | Collapse / expand a directory |
| `f` | Toggle changed files / all files |
| `F` | Search files in the current mode |
| `b` / `B` | Select one target / a commit range |
| `v` | Toggle diff / source view |
| `c` | Comment on the current line |
| Visual selection, then `c` | Comment on a range |
| `e` / `d` | Edit / delete the comment under the cursor |
| `D` | Clear comments for the current target |
| `C` | Search comments and jump |
| `]c` / `[c` | Next / previous comment |
| `]h` / `[h` | Next / previous diff hunk |
| `A` | Archive and clear active comments |
| `H` | Open review history on the right |
| `y` | Copy active comments as Markdown |
| `r` | Refresh the Git diff |
| `q` | Close review; in history, close that pane |
| `?` | Show the keyboard guide |

Every key can be changed through `keymaps`.

## Commands

```vim
:AIReview [directory]
:AIReviewClose
:AIReviewExport [path]
```

`:AIReviewExport` defaults to `review.md` in the repository root.

## Configuration

```lua
require("ai-review").setup({
  storage_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "ai-review"),
  file_panel_width = 34,
  history_panel_width = 60,
  context_lines = 3,
  export_to_clipboard = true,
  changed_only = true,
  include_ignored = {},
  keymaps = {
    search_files = "F",
    comments = "C",
    -- See lua/ai-review/config.lua for all defaults.
  },
  highlights = {
    -- Override individual VS Code Dark-inspired colors here.
  },
})
```

The plugin uses its own highlight groups and does not replace the active colorscheme.

## Storage and scope

Comments and archives are JSON files under `storage_dir`, scoped by repository and branch. Comments are also scoped to the selected working-tree, commit, or range target.

The plugin does not modify project files unless you explicitly export to a path inside the repository.

## WSL clipboard

Copying always updates Neovim's unnamed register. On WSL, the plugin prefers `win32yank.exe`, then Windows PowerShell with UTF-8 input enabled. It avoids sending UTF-8 directly to `clip.exe`, which can corrupt Japanese and other non-ASCII text. Other supported providers include Neovim's clipboard provider, `wl-copy`, `xclip`, and macOS `pbcopy`.

## License

MIT
