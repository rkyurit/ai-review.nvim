local M = {}

local function line_for_side(entry, side)
  if side == "source" and entry.kind == "source" then
    return entry.new_line
  elseif side == "old" then
    return entry.old_line
  elseif side == "new" then
    return entry.new_line
  end
end

local function normalize(text, source)
  if not source and text:match("^[ +%-]") then
    text = text:sub(2)
  end
  return vim.trim(text):gsub("%s+", " ")
end

local function find_sequence(entries, wanted, normalized, source)
  if #wanted == 0 or #wanted > #entries then
    return nil
  end
  for start_row = 1, #entries - #wanted + 1 do
    local matches = true
    for offset, text in ipairs(wanted) do
      local actual = entries[start_row + offset - 1].text
      if normalized then
        actual = normalize(actual, source)
        text = normalize(text, source)
      end
      if actual ~= text then
        matches = false
        break
      end
    end
    if matches then
      return start_row, start_row + #wanted - 1
    end
  end
end

local function result_for_rows(comment, entries, start_row, end_row, confidence)
  local lines = {}
  for row = start_row, end_row do
    local line = line_for_side(entries[row], comment.side)
    if line then
      lines[#lines + 1] = line
    end
  end
  if #lines == 0 then
    return nil
  end
  local start_line = lines[1]
  local end_line = lines[1]
  local context = {}
  for row = start_row, end_row do
    start_line = math.min(start_line, line_for_side(entries[row], comment.side) or start_line)
    end_line = math.max(end_line, line_for_side(entries[row], comment.side) or end_line)
    context[#context + 1] = entries[row].text
  end
  return {
    side = comment.side,
    start_line = start_line,
    end_line = end_line,
    context = table.concat(context, "\n"),
    confidence = confidence,
  }
end

function M.anchor(comment, entries)
  local wanted = vim.split(comment.context or "", "\n", { plain = true })
  if #wanted == 1 and wanted[1] == "" then
    return nil
  end
  local source = comment.side == "source"
  local start_row, end_row = find_sequence(entries, wanted, false, source)
  if start_row then
    return result_for_rows(comment, entries, start_row, end_row, "exact")
  end
  start_row, end_row = find_sequence(entries, wanted, true, source)
  if start_row then
    return result_for_rows(comment, entries, start_row, end_row, "normalized")
  end

  local best_text = ""
  for _, text in ipairs(wanted) do
    local candidate = normalize(text, source)
    if #candidate > #best_text then
      best_text = candidate
    end
  end
  if #best_text < 4 then
    return nil
  end
  local best_row
  local best_distance
  for row, entry in ipairs(entries) do
    if normalize(entry.text, source) == best_text and line_for_side(entry, comment.side) then
      local distance = math.abs(line_for_side(entry, comment.side) - (comment.start_line or 1))
      if not best_distance or distance < best_distance then
        best_row = row
        best_distance = distance
      end
    end
  end
  if best_row then
    return result_for_rows(comment, entries, best_row, best_row, "partial")
  end
  return nil
end

return M
