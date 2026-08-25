local M = {}

local function location(comment)
  local line = tostring(comment.start_line or "?")
  if comment.end_line and comment.end_line ~= comment.start_line then
    line = line .. "-" .. comment.end_line
  end
  return comment.path .. ":" .. line
end

function M.markdown(session, target)
  local lines = {
    "# AI code review feedback",
    "",
    "Review target: " .. (target and target.label or "Working tree"),
    "",
    "Apply only the requested changes below. Preserve unrelated code and report how each comment was addressed.",
    "",
  }
  local count = 0
  for _, comment in ipairs(session.comments or {}) do
    if
      not comment.resolved
      and (not target or comment.target_id == target.id or (not comment.target_id and target.id == "working"))
    then
      count = count + 1
      lines[#lines + 1] = ("## %d. `%s`"):format(count, location(comment))
      lines[#lines + 1] = ""
      lines[#lines + 1] = comment.body
      lines[#lines + 1] = ""
      lines[#lines + 1] = "View: " .. (comment.side == "source" and "source file" or (comment.side .. " side of diff"))
      lines[#lines + 1] = ""
      if comment.context and comment.context ~= "" then
        lines[#lines + 1] = "```diff"
        vim.list_extend(lines, vim.split(comment.context, "\n", { plain = true }))
        lines[#lines + 1] = "```"
        lines[#lines + 1] = ""
      end
    end
  end
  if count == 0 then
    return "# AI code review feedback\n\nNo unresolved comments.\n"
  end
  return table.concat(lines, "\n")
end

return M
