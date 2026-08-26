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

function M.copy(text)
  vim.fn.setreg('"', text)
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

M._is_wsl = is_wsl
M._command_providers = command_providers

return M
