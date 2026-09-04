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
2. Press `<localleader>c` on a line, or select a range in Visual mode and press `<localleader>c`.
3. Press `<localleader>y` to copy all active comments as Markdown for an AI assistant.
4. After applying fixes, press `<localleader>r` to refresh the diff. Comments without a current location remain visible as `Outdated review` entries and through `<localleader>l`.

Use `<localleader>t` to switch between changed files and the full repository tree. Changed-file mode expands directories containing changes; all-files mode starts collapsed. Unchanged files open as regular source and accept the same comments.

Use `<localleader>b` to select the working tree or one commit, and `<localleader>B` to select a commit range.

## Search and ignored files

- `<localleader>f` searches files in the current tree mode.
- `<localleader>g` searches file contents across the selected repository target.
- `<localleader>l` searches active comments and jumps to the selected location.

Search input and result selection use `vim.ui.input` and `vim.ui.select`, so LazyVim's configured UI/picker is reused automatically. Selecting a text result opens that file in the plugin's center pane at the matching line. Lowercase queries are case-insensitive; a query containing uppercase letters is case-sensitive.

Git-ignored paths are hidden by default. Add exact paths or glob patterns with `include_ignored`. Included directories remain collapsed and are scanned only when expanded or searched with `<localleader>f` in all-files mode.

```lua
{
  "rkyurit/ai-review.nvim",
  opts = {
    include_ignored = { ".env", "generated/*.json", "sample-data/" },
  },
}
```

## Review history

Press `<localleader>a` to archive every active comment under a name and clear the active review. Archives are stored in Neovim's state directory, not in the repository.

Press `<localleader>h` from the file tree or review pane and select an archive. Its read-only Markdown opens on the right:

```text
[ file tree ] [ current file or diff ] [ archived review ]
```

Archived comments never mix into the active review. In the history pane, press `y` to copy or `q` to close it. Selecting another archive replaces the pane contents.

## Key bindings

| Key | Action |
| --- | --- |
| `<CR>` | Open the selected file |
| `h` / `l` | Collapse / expand a directory |
| `<localleader>s` | Hide / show the file-tree panel |
| `<localleader><` / `<localleader>>` | Narrow / widen the file-tree panel |
| `<localleader>t` | Toggle changed files / all files |
| `<localleader>f` / `<localleader>g` | Search file names / file contents |
| `<localleader>b` / `<localleader>B` | Select one target / a commit range |
| `<localleader>p` | Review a branch comparison like a pull request |
| `<localleader>v` | Toggle diff / source view |
| `<localleader>c` | Comment on the current line |
| Visual selection, then `<localleader>c` | Comment on a range |
| `<localleader>e` / `<localleader>d` | Edit / delete the comment under the cursor |
| `<localleader>D` | Clear comments for the current target |
| `<localleader>l` | Search comments and jump |
| `]r` / `[r` | Next / previous comment |
| `]h` / `[h` | Next / previous diff hunk |
| `<localleader>a` | Archive and clear active comments |
| `<localleader>h` | Open review history on the right |
| `<localleader>y` | Copy active comments as Markdown |
| `<localleader>r` | Refresh the Git diff |
| `q` | Close review; in history, close that pane |
| `<localleader>k` | Show the keyboard guide |

`<localleader>` defaults to `\` unless your Neovim configuration changes `maplocalleader`; press it as a sequence, not a simultaneous chord. Every key can be changed through `keymaps`.

Content-search results open in diff view when the selected file belongs to the current review diff, and in source view otherwise. `<localleader>v` switches a changed file between those same diff and source views.

## Optional LazyVim integration

No extra dependency is required. When [Snacks.nvim](https://github.com/folke/snacks.nvim) is available, all-files search in the working tree and working-tree text search use its native picker, including preview and the layout configured by LazyVim. `Alt-i` toggles ignored files, `Alt-h` toggles hidden files, and `Alt-m` maximizes the picker. Changed-only search, commit/range search, and selective `include_ignored` search keep the plugin's Git-aware fallback so their meaning stays exact.

Changed-file, commit, range, and pull-request file searches also use a custom Snacks file picker, with the filename shown first and an exact diff/source preview for the selected review target. Other lists continue through `vim.ui.select`, which LazyVim already renders with Snacks. Keyboard help opens which-key when available and falls back to the built-in guide otherwise. Clipboard copying uses Neovim's standard provider first outside WSL, with platform fallbacks where needed.

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
  -- export_instructions = "Your custom instructions for the AI.",
  changed_only = true,
  include_ignored = {},
  keymaps = {
    search_files = "<localleader>f",
    search_content = "<localleader>g",
    comments = "<localleader>l",
    -- See lua/ai-review/config.lua for all defaults.
  },
  highlights = {
    -- Override individual VS Code Dark-inspired colors here.
  },
})
```

The plugin uses its own highlight groups and does not replace the active colorscheme. They can be linked to colorscheme groups such as `DiffAdd`, `DiffDelete`, or `DiagnosticInfo` in your setup if you prefer fully theme-native colors.

## Storage and scope

Comments and archives are JSON files under `storage_dir`, scoped by repository and branch. Comments are also scoped to the selected working-tree, commit, range, or pull-request-style branch target.

Branch comparison uses Git's three-dot form (`base...head`), matching the usual pull-request view from the branches' merge base. Both local and already-fetched remote branches are available, and neither branch needs to be checked out.

The plugin does not modify project files unless you explicitly export to a path inside the repository.

## WSL clipboard

Copying always updates Neovim's unnamed register. Inside WezTerm, the plugin first uses OSC 52 to update the real system clipboard without starting another process. On other WSL terminals, it prefers `win32yank.exe`, then Windows PowerShell with UTF-8 input enabled. It avoids sending UTF-8 directly to `clip.exe`, which can corrupt Japanese and other non-ASCII text. Other supported providers include Neovim's clipboard provider, `wl-copy`, `xclip`, and macOS `pbcopy`.

External clipboard commands run asynchronously, so copying through `<localleader>y` does not block the editor while WSL PowerShell or another provider starts.

## License

MIT
