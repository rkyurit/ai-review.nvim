# ai-review.nvim

[English](README.md)

ローカルのGit差分をキーボード中心で確認し、行や範囲へコメントを書き、AIへ渡せるMarkdownとして出力するNeovimプラグインです。

処理はすべてローカルで完結します。GitHubアカウント、ネットワーク接続、外部のNeovimプラグインは不要です。macOS、Linux、WSL上のWindowsに対応しています。

## 主な機能

- `HEAD` に対するステージ済み・未ステージの変更、単一コミット、コミット範囲をレビュー
- 差分だけでなく、未変更ファイルも閲覧してコメント
- 1行またはVisual選択した範囲へコメント
- パスや行番号を手入力せず、ファイルとコメントを検索
- コメント一式を名前付き履歴としてリポジトリ外へ保存
- 履歴のMarkdownを右ペインで閲覧
- 現在のコメントをAI向けMarkdownとして出力
- WSLでも日本語を壊さずコピー

## 必要なもの

- Neovim 0.11以降
- Git

## インストール

`lazy.nvim`の場合：

```lua
{
  "rkyurit/ai-review.nvim",
  cmd = { "AIReview", "AIReviewClose", "AIReviewExport" },
  opts = {},
}
```

追加後に `:Lazy sync` を実行し、Neovimを再起動してください。

## 基本的な使い方

Gitリポジトリ内でNeovimを開き、次を実行します。

```vim
:AIReview
```

初期画面では、左側に変更ファイル、中央に選択中の差分が表示されます。最初の対象は作業ツリーで、ステージ済み・未ステージ・ignoreされていない未追跡ファイルを含みます。

1. `j` / `k` と `<CR>` でファイルを選びます。
2. 行上で `<localleader>c` を押すか、Visualモードで範囲を選んで `<localleader>c` を押します。
3. `<localleader>y` で現在の全コメントをAI向けMarkdownとしてコピーします。
4. 修正後は `<localleader>r` で差分を更新します。位置がなくなったコメントは `Outdated review` として残り、`<localleader>l` からも確認できます。

`<localleader>t` で「変更ファイルのみ」と「全ファイル」を切り替えます。変更ファイル表示では変更を含むフォルダが自動展開され、全ファイル表示ではフォルダが閉じた状態から始まります。未変更ファイルも通常のソースとして開き、コメントできます。

`<localleader>b` で作業ツリーまたは単一コミット、`<localleader>B` で2コミット間の範囲を選びます。

## 検索とignore対象

- `<localleader>f`：現在のツリーモードからファイルを検索
- `<localleader>g`：選択中のレビュー対象にあるファイルの内容を横断検索
- `<localleader>l`：現在のコメントを検索して該当箇所へジャンプ

検索入力と結果一覧には `vim.ui.input` と `vim.ui.select` を使うため、LazyVimで設定されたUI・pickerが自動的に利用されます。結果を選ぶと、プラグインの中央ペインで該当ファイルと行を開きます。検索語が小文字だけなら大文字小文字を区別せず、大文字を含む場合は区別します。

Gitでignoreされているパスは初期状態では表示しません。必要なものだけ、パスまたはglobを `include_ignored` で指定できます。指定したフォルダは閉じた状態で表示し、展開時または全ファイルモードで `<localleader>f` を押したときだけ中身を読み込みます。

```lua
{
  "rkyurit/ai-review.nvim",
  opts = {
    include_ignored = { ".env", "generated/*.json", "sample-data/" },
  },
}
```

## レビュー履歴

`<localleader>a` を押すと、現在の全コメントを名前付き履歴として保存し、現在のレビューから消します。履歴はリポジトリではなくNeovimのstateディレクトリへ保存されます。

ファイルツリーまたはレビュー画面で `<localleader>h` を押して履歴を選ぶと、閲覧専用のMarkdownが右ペインに表示されます。

```text
[ ファイルツリー ] [ 現在のファイル・差分 ] [ 履歴 ]
```

履歴コメントは現在のレビューへ混ざりません。履歴ペインでは `y` でコピー、`q` でペインを閉じます。別の履歴を選ぶと右ペインの内容が差し替わります。

## キーバインド

| キー | 操作 |
| --- | --- |
| `<CR>` | 選択中のファイルを開く |
| `h` / `l` | フォルダを閉じる／展開する |
| `<localleader>s` | ファイルツリーペインを隠す／再表示する |
| `<localleader><` / `<localleader>>` | ファイルツリーペインを狭く／広くする |
| `<localleader>t` | 変更ファイルのみ／全ファイルを切り替える |
| `<localleader>f` / `<localleader>g` | ファイル名／ファイル内容を検索する |
| `<localleader>b` / `<localleader>B` | 対象を1つ選ぶ／コミット範囲を選ぶ |
| `<localleader>p` | PR相当のブランチ比較を開く |
| `<localleader>v` | 差分表示／通常表示を切り替える |
| `<localleader>c` | 現在行へコメントする |
| Visual選択して `<localleader>c` | 選択範囲へコメントする |
| `<localleader>e` / `<localleader>d` | カーソル位置のコメントを編集／削除する |
| `<localleader>D` | 現在のレビュー対象の全コメントを消す |
| `<localleader>l` | コメントを検索してジャンプする |
| `]r` / `[r` | 次／前のコメントへ移動する |
| `]h` / `[h` | 次／前の差分hunkへ移動する |
| `<localleader>a` | 現在の全コメントを履歴へ保存して消す |
| `<localleader>h` | 履歴を右ペインへ表示する |
| `<localleader>y` | 現在のコメントをMarkdownとしてコピーする |
| `<localleader>r` | 現在のGit差分を更新する |
| `q` | レビューを閉じる。履歴内では右ペインだけ閉じる |
| `<localleader>k` | キーボード操作のヘルプを表示する |

`<localleader>` はNeovim側で `maplocalleader` を変更していなければ `\` です。同時押しではなく、順番に入力します。すべてのキーは `keymaps` で変更できます。

全文検索の結果は、現在のレビュー対象で変更されたファイルなら差分表示、変更されていなければ通常表示で開きます。変更ファイルでは `<localleader>v` により、同じ差分表示と通常表示を切り替えられます。

## LazyVimとの連携（任意）

追加の依存関係はありません。[Snacks.nvim](https://github.com/folke/snacks.nvim) が使える場合、作業ツリーの全ファイル検索と全文検索にはSnacks標準pickerを使い、プレビューやLazyVim側で設定したレイアウトもそのまま利用します。picker内では `Alt-i` でignore対象、`Alt-h` で隠しファイル、`Alt-m` で最大化を切り替えられます。変更ファイルのみの検索、コミット／範囲の検索、`include_ignored` の選択的な例外を含む検索は、意味を正確に保つためプラグイン側のGit検索を使います。

変更ファイル、コミット、範囲、PRのファイル検索にもSnacksのカスタムファイルpickerを使い、ファイル名を先頭に表示しつつ、選択中のレビュー対象に正確な差分／ソースをプレビューします。その他の一覧は引き続き `vim.ui.select` を通すため、LazyVimではSnacks表示になります。操作ヘルプはwhich-keyがあればそれを開き、なければ内蔵ガイドへ戻ります。クリップボードはWSL以外ではNeovim標準providerを優先し、必要に応じてOS別の代替手段を使います。

## コマンド

```vim
:AIReview [ディレクトリ]
:AIReviewClose
:AIReviewExport [出力先]
```

`:AIReviewExport` で出力先を省略すると、リポジトリ直下の `review.md` に保存します。

## 設定

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
    search_files = "<localleader>f",
    search_content = "<localleader>g",
    comments = "<localleader>l",
    -- 全デフォルト値は lua/ai-review/config.lua を参照してください。
  },
  highlights = {
    -- VS Code Dark風の各色を個別に上書きできます。
  },
})
```

独自のハイライトグループを使うため、現在のカラースキームは置き換えません。完全にテーマ準拠の色にしたい場合は、設定から `DiffAdd`、`DiffDelete`、`DiagnosticInfo` などへlinkできます。

## 保存場所とスコープ

コメントと履歴は `storage_dir` 配下のJSONへ保存し、リポジトリとブランチごとに分離します。コメントは作業ツリー・単一コミット・コミット範囲・PR相当のブランチ比較ごとにも分かれます。

ブランチ比較にはGitのthree-dot形式（`base...head`）を使い、通常のPRと同様にmerge baseから変更側ブランチまでを表示します。ローカルブランチと取得済みのリモートブランチを選択でき、どちらもcheckoutする必要はありません。

出力先をリポジトリ内に指定して `:AIReviewExport` を実行しない限り、プロジェクトのファイルを書き換えません。

## WSLのクリップボード

コピー時は常にNeovimの無名レジスタへ書き込みます。WSLでは `win32yank.exe` を優先し、次にUTF-8入力を明示したWindows PowerShellを使います。日本語などが文字化けするため、UTF-8テキストを `clip.exe` へ直接送りません。そのほか、Neovimのクリップボードプロバイダ、`wl-copy`、`xclip`、macOSの `pbcopy` に対応しています。

## ライセンス

MIT
