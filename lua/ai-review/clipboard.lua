local M = {}

local function is_wsl()
  if vim.env.WSL_DISTRO_NAME or vim.env.WSL_INTEROP then
    return true
  end
  local file = io.open("/proc/version", "r")
  if not file then
    return false
  end
  local version = file:read("*a"):lower()
  file:close()
  return version:find("microsoft", 1, true) ~= nil
end

local function command_providers(wsl)
  local providers = {}
  if wsl then
    providers = {
      { executable = "win32yank.exe", command = { "win32yank.exe", "-i", "--crlf" } },
      {
        executable = "powershell.exe",
        command = {
          "powershell.exe",
          "-NoLogo",
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "[Console]::InputEncoding=[Text.UTF8Encoding]::new($false);$text=[Console]::In.ReadToEnd();Set-Clipboard -Value $text",
        },
      },
      {
        executable = "pwsh.exe",
        command = {
          "pwsh.exe",
          "-NoLogo",
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "[Console]::InputEncoding=[Text.UTF8Encoding]::new($false);$text=[Console]::In.ReadToEnd();Set-Clipboard -Value $text",
        },
      },
    }
  else
    providers = {
      { executable = "wl-copy", command = { "wl-copy" } },
      { executable = "xclip", command = { "xclip", "-selection", "clipboard" } },
      { executable = "pbcopy", command = { "pbcopy" } },
    }
  end
  return providers
end

local function copy_with_osc52(text)
  local wezterm = vim.env.WEZTERM_PANE or (vim.env.TERM_PROGRAM or ""):lower() == "wezterm"
  if not wezterm or vim.env.TMUX then
    return false
  end
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if not ok or type(osc52.copy) ~= "function" then
    return false
  end
  return pcall(osc52.copy("+"), vim.split(text, "\n", { plain = true }))
end

function M.copy(text)
  vim.fn.setreg('"', text)
  if copy_with_osc52(text) then
    return true, "osc52"
  end
  local wsl = is_wsl()

  -- WSL clipboard providers must be chosen explicitly. Neovim can otherwise
  -- fall back to clip.exe, which corrupts UTF-8 text such as Japanese.
  if not wsl and vim.fn.has("clipboard") == 1 and pcall(vim.fn.setreg, "+", text) then
    return true, "neovim"
  end

  for _, provider in ipairs(command_providers(wsl)) do
    if vim.fn.executable(provider.executable) == 1 then
      local result = vim.system(provider.command, { stdin = text }):wait()
      if result.code == 0 then
        return true, provider.executable
      end
    end
  end

  if wsl and vim.fn.has("clipboard") == 1 and pcall(vim.fn.setreg, "+", text) then
    return true, "neovim"
  end
  return false, "unnamed-register"
end

function M.copy_async(text, callback)
  callback = callback or function() end
  vim.fn.setreg('"', text)
  if copy_with_osc52(text) then
    callback(true, "osc52")
    return
  end
  local wsl = is_wsl()
  local has_clipboard = vim.fn.has("clipboard") == 1

  if not wsl and has_clipboard and pcall(vim.fn.setreg, "+", text) then
    callback(true, "neovim")
    return
  end

  local providers = vim.tbl_filter(function(provider)
    return vim.fn.executable(provider.executable) == 1
  end, command_providers(wsl))
  local index = 0
  local function finish(copied, provider)
    vim.schedule(function()
      callback(copied, provider)
    end)
  end
  local function try_next()
    index = index + 1
    local provider = providers[index]
    if not provider then
      vim.schedule(function()
        if wsl and has_clipboard and pcall(vim.fn.setreg, "+", text) then
          callback(true, "neovim")
        else
          callback(false, "unnamed-register")
        end
      end)
      return
    end
    vim.system(provider.command, { stdin = text }, function(result)
      if result.code == 0 then
        finish(true, provider.executable)
      else
        vim.schedule(try_next)
      end
    end)
  end
  try_next()
end

M._is_wsl = is_wsl
M._command_providers = command_providers
M._copy_with_osc52 = copy_with_osc52

return M
