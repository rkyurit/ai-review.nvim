# ai-review.nvim

Keyboard-first review of local Git changes, with inline comments that can be exported as an AI-ready prompt.

The plugin is local-only. It does not require GitHub, an account, a network connection, or another Neovim plugin. It supports macOS, Linux, and Windows through WSL.

## Requirements

- Neovim 0.11 or newer
- Git

## Installation

With `lazy.nvim`:

```lua
{
  dir = vim.fn.expand("~/workspace/ai-review.nvim"),
  cmd = { "AIReview", "AIReviewClose", "AIReviewExport" },
  opts = {},
}
```

## Usage

Open Neovim in a Git repository containing local changes and run:

```vim
:AIReview
```

By default, the left pane shows only uncommitted files changed against `HEAD`. Changed files have `M`, `A`, `D`, or `?` markers. The right pane shows the selected diff.

Press `f` when you need the full repository tree, including unchanged and Git-ignored files. An unchanged file opens as regular source and supports the same line and range comments. Full-tree mode starts with directories collapsed; changed-files mode automatically expands only the directories containing changes.

Press `b` to choose between the working tree and a single commit. Press `B` to choose two commits and review the range between them.

### Keys

| Key | Action |
| --- | --- |
| `<CR>` | Open the selected file from the file pane |
| `h` / `l` | Collapse / expand a directory in the file pane |
| `f` | Toggle changed files / all repository files |
| `b` | Select the working tree or a single commit |
| `B` | Select a commit range |
| `v` | Toggle diff / regular source view for a changed file |
| `c` | Comment on the current diff line |
| Visual selection, then `c` | Comment on a range |
| `e` | Edit the comment under the cursor |
| `d` | Delete the comment under the cursor |
| `D` | Clear all comments for the current review target |
| `A` | Archive the current comment set as a named review |
| `H` | Browse archived review history |
| `C` | List all comments |
| `]h` / `[h` | Next / previous diff hunk |
| `]c` / `[c` | Next / previous comment |
| `y` | Copy AI-ready Markdown to the clipboard |
| `r` | Refresh the Git diff |
| `q` | Close the review |
| `?` | Open the complete keyboard guide |

Comments are stored outside the repository under Neovim's state directory and are scoped by repository and branch.

Inside an archived review, press `r` to restore its comments onto the current review target, `y` to copy the archived Markdown, or `q` to close it. Restore searches the saved code context, so comments follow line-number shifts when the selected code still exists. Comments whose context no longer exists are retained as unplaced warnings instead of being silently dropped.

Unchanged files can be opened directly from the tree and commented on in the same way. Comments are additionally scoped to the selected review target, so working-tree and commit reviews do not mix.

To write the review to a file instead of copying it:

```vim
:AIReviewExport review.md
```

## Configuration

```lua
require("ai-review").setup({
  file_panel_width = 34,
  context_lines = 3,
  export_to_clipboard = true,
})
```

Every key can be changed through the `keymaps` option. See `lua/ai-review/config.lua` for defaults.

The review UI uses its own VS Code Dark-inspired highlight groups and does not replace the active Neovim colorscheme. Every color can be overridden through the `highlights` option.

## WSL clipboard

Export always writes to Neovim's unnamed register. On WSL, the plugin prefers `win32yank.exe`, then uses Windows PowerShell with UTF-8 input explicitly enabled. It intentionally avoids sending UTF-8 text directly to `clip.exe`, which can corrupt Japanese and other non-ASCII text. On other systems it supports Neovim's clipboard provider, `wl-copy`, `xclip`, and macOS `pbcopy`.

## Current scope

- Reviews staged and unstaged changes against `HEAD` together.
- Reviews an individual commit or a selected commit range.
- Browses the full repository tree and comments on unchanged source files.
- Includes untracked files.
- Supports added, modified, deleted, copied, and renamed files.
- Stores review comments locally and exports unresolved comments as Markdown.
