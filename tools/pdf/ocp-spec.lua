-- Pandoc Lua filter that lays out the OSPA Markdown spec per the 2024 OCP
-- Base Specification Template (v1.6):
--   * Everything before the "Table of Contents" heading becomes the title
--     page, which carries no header, footer, or page number. As in the
--     template, it is centered, with a 26pt title and 12pt text.
--   * The hand-maintained Markdown ToC is dropped and replaced by a
--     LaTeX-generated ToC with page numbers.
--   * The document title and the "Effective <date>" date are exported as
--     \ospatitle and \ospadate for the running header/footer.

local function latex_escape(s)
  local map = {
    ["\\"] = "\\textbackslash{}", ["&"] = "\\&", ["%"] = "\\%",
    ["$"] = "\\$", ["#"] = "\\#", ["_"] = "\\_", ["{"] = "\\{",
    ["}"] = "\\}", ["~"] = "\\textasciitilde{}", ["^"] = "\\textasciicircum{}",
  }
  return (s:gsub("[\\&%%$#_{}~^]", map))
end

local function raw(s)
  return pandoc.RawBlock("latex", s)
end

local function is_toc_heading(b)
  return b.t == "Header" and pandoc.utils.stringify(b.content) == "Table of Contents"
end

-- LaTeX never breaks a line inside a word such as "/sys/class/hwmon/" or a
-- URL, so long paths can run past the margin (especially in narrow table
-- cells). Allow a break after each "/" or "." in such words.
function Str(el)
  if #el.text < 16 or not el.text:find("/", 1, true) then
    return nil
  end
  local out = {}
  for part, sep in el.text:gmatch("([^/.]*)([/.]?)") do
    if part ~= "" then table.insert(out, pandoc.Str(part)) end
    if sep ~= "" then
      table.insert(out, pandoc.Str(sep))
      table.insert(out, pandoc.RawInline("latex", "\\allowbreak{}"))
    end
  end
  return out
end

function Pandoc(doc)
  local blocks = doc.blocks
  local toc_idx
  for i, b in ipairs(blocks) do
    if is_toc_heading(b) then
      toc_idx = i
      break
    end
  end
  if not toc_idx then
    io.stderr:write("ocp-spec.lua: no 'Table of Contents' heading found; layout unchanged\n")
    return doc
  end

  -- The Markdown ToC runs until the next level-1 heading.
  local body_idx = #blocks + 1
  for i = toc_idx + 1, #blocks do
    if blocks[i].t == "Header" and blocks[i].level == 1 then
      body_idx = i
      break
    end
  end

  local title, date = "", ""
  local title_page = {}
  for i = 1, toc_idx - 1 do
    local b = blocks[i]
    if b.t == "Header" then
      -- Render the title as styled text so it does not become a ToC entry.
      title = pandoc.utils.stringify(b.content)
      table.insert(title_page, raw("\\vspace*{1em}{\\fontsize{26}{31}\\selectfont "
        .. latex_escape(title) .. "\\par}\\vspace{15pt}"))
    else
      local text = pandoc.utils.stringify(b)
      date = text:match("^Effective%s+(.+)$") or date
      table.insert(title_page, b)
    end
  end

  local out = {
    raw("\\renewcommand{\\ospatitle}{" .. latex_escape(title) .. "}"),
    raw("\\renewcommand{\\ospadate}{" .. latex_escape(date) .. "}"),
    raw("\\begin{titlepage}\\centering\\fontsize{12}{14.5}\\selectfont"),
  }
  for _, b in ipairs(title_page) do table.insert(out, b) end
  table.insert(out, raw("\\end{titlepage}"))
  table.insert(out, raw("\\tableofcontents\\clearpage"))
  for i = body_idx, #blocks do table.insert(out, blocks[i]) end

  doc.blocks = out
  return doc
end
