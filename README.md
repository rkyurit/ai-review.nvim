# ai-review.nvim

Keyboard-first review of local Git changes, with inline comments that can be exported as an AI-ready prompt.

The plugin is local-only. It does not require GitHub, an account, a network connection, or another Neovim plugin.

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

The left pane lists changed files. The right pane shows the selected unified diff.

### Keys

| Key | Action |
| --- | --- |
| `<CR>` | Open the selected file from the file pane |
| `c` | Comment on the current diff line |
| Visual selection, then `c` | Comment on a range |
| `e` | Edit the comment under the cursor |
| `d` | Delete the comment under the cursor |
| `C` | List all comments |
| `]h` / `[h` | Next / previous diff hunk |
| `]c` / `[c` | Next / previous comment |
| `y` | Copy AI-ready Markdown to the clipboard |
| `r` | Refresh the Git diff |
| `q` | Close the review |

Comments are stored outside the repository under Neovim's state directory and are scoped by repository and branch.

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

## Current scope

- Reviews staged and unstaged changes against `HEAD` together.
- Includes untracked files.
- Supports added, modified, deleted, copied, and renamed files.
- Stores review comments locally and exports unresolved comments as Markdown.
