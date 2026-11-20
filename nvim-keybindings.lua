-- Keycheat: print the mappings Neovim has once the user's config and plugins
-- have loaded. One line per mapping, tab separated:
--
--   n<TAB><Leader>ff<TAB>Find files
--
-- Only mappings with a description are printed: an unnamed mapping says nothing
-- useful in a cheat sheet, and plugins create many of those.
local modes = { "n", "v", "i", "t", "c", "o" }
local leader = vim.g.mapleader or "\\"
local seen = {}

local function printable(value)
  return (tostring(value):gsub("[\t\r\n]", " "))
end

for _, mode in ipairs(modes) do
  for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
    local lhs = mapping.lhs or ""
    local description = mapping.desc or ""

    if description ~= "" and lhs ~= ""
      and not lhs:find("<Plug>", 1, true)
      and not lhs:find("<SNR>", 1, true)
    then
      -- LazyVim sets the leader to a space. Writing that space out would make
      -- the listing look like it starts with an empty key, so it becomes
      -- `<Leader>`, which the panel renders as LEADER.
      if leader ~= "" and lhs:sub(1, #leader) == leader then
        lhs = "<Leader>" .. lhs:sub(#leader + 1)
      end

      local id = mode .. "\t" .. lhs
      if not seen[id] then
        seen[id] = true
        io.write(mode, "\t", lhs, "\t", printable(description), "\n")
      end
    end
  end
end
