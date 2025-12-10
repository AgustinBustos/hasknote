vim.api.nvim_set_keymap('i', 'jk', '<Esc>', { noremap = true, silent = true })

--vim.keymap.set('n', '<F9>', ':bprevious<CR>', { noremap = true, silent = true })
--vim.keymap.set('n', '<F10>', ':bnext<CR>', { noremap = true, silent = true })
--vim.keymap.set('n', '<F9>', vim.cmd.bprevious, { silent = true })

vim.wo.relativenumber = true
vim.wo.number = true
vim.g.mapleader = ' '
vim.g.maplocalleader = ' ' -- Optional: also set the local leader to space

vim.keymap.set('t', 'jk', [[<C-\><C-n>]], {noremap = true, silent = true})

local function send_yank_to_term()
  local save_win = vim.api.nvim_get_current_win()
  local save_buf = vim.api.nvim_get_current_buf()

  -- Find a terminal buffer
  local term_buf = nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "terminal" then
      term_buf = buf
      break
    end
  end

  if not term_buf then
    print("No terminal buffer found")
    return
  end

  -- Switch current window to the terminal buffer
  vim.api.nvim_set_current_buf(term_buf)

  -- Send yank to the terminal job
  local job_id = vim.b.terminal_job_id
  if job_id then
    local yank = vim.fn.getreg('"')
    vim.fn.chansend(job_id, yank)
  else
    print("Not a terminal buffer")
  end

  -- Restore the original buffer in the original window
  vim.api.nvim_set_current_win(save_win)
  vim.api.nvim_set_current_buf(save_buf)
end
--vim.keymap.set("n","<C-J>", function()
--  send_yank_to_term()
--end, { noremap = true, silent = true })
---------------------------------------------------------------------------------------
-- Set these to your manually opened GHCI buffer/job
-- Send lines to terminal buffer and capture output into a register
_G.sent_lines_count = 0
function SendToTermAndCapture(bufnr, lines, register)
  local term_job_id = vim.b[bufnr].terminal_job_id
  if not term_job_id then
    print("Not a terminal buffer")
    return
  end

  local output = {}

  -- Attach to terminal buffer to capture new lines
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, _, _, _, new_lines, _)
      if type(new_lines) == "table" then
        for _, line in ipairs(new_lines) do
          table.insert(output, line)
        end
      end
      return false
    end,
  })

  -- Send each line to the terminal
  for _, line in ipairs(lines) do
    vim.fn.chansend(term_job_id, line .. "\n")
  end
  _G.sent_lines_count = _G.sent_lines_count + #lines

  -- Wait a bit to collect output, then save to register
--  vim.defer_fn(function()
--    vim.fn.setreg(register, table.concat(output, "\n"))
--    print("Captured output to register " .. register)
--  end, 700) -- increase delay if your commands take longer
end

-- Example usage:
-- :lua SendToTermAndCapture(2, {"1+1", "2+2"}, "a")
-- Get the last n lines from a buffer
-- Get the first n lines from a buffer
function SendYankToTerm()
  local bufnr = 3
  local register = '"'
  -- Get yanked lines from the unnamed register
  local prelines = vim.fn.getreg('"', 1, true)  -- 1 = get as list of lines
  lines={}
  last_insertion=""
  for idx,line in ipairs(prelines) do
    tostartwith=line:gsub("^%s*where", "where")
    tostartwith=tostartwith:gsub("^%s*|>", "|>")
    if string.sub(tostartwith,1,string.len("where"))=="where" then
      last_insertion = string.sub(last_insertion, 1, -2) .. tostartwith
    elseif string.sub(tostartwith,1,string.len("|>"))=="|>" then
      last_insertion = string.sub(last_insertion, 1, -2) .. tostartwith
    else
      last_insertion = last_insertion .. line
    end
    local lastChar = string.sub(line, -1)
    if lastChar~=';' then 
      table.insert(lines,last_insertion)
      last_insertion=""

    end
  end
  
  

  if #lines == 0 then
    print("No yanked text found")
    return
  end

  -- Call your existing function
  SendToTermAndCapture(bufnr, lines, register)
end

function GetFirstLines(bufnr, n, register)
  -- Get total number of lines in the buffer
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Calculate end line (0-indexed, exclusive)
  local end_line = math.min(n, line_count)

  -- Get the first n lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, end_line, false)

  -- If register is given, save to it
  if register then
    vim.fn.setreg(register, table.concat(lines, "\n"))
    print("Saved first " .. n .. " lines to register " .. register)
  end

  return lines
end
-- Yank all lines from a buffer into a register
_G.ghci_prompt_count = 0
function YankTerminalOutput(bufnr)
  -- Get total number of lines in the buffer
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  
  -- Get all lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, line_count, false)
  
  -- Store in register

  --count it
  local last_count=_G.ghci_prompt_count
  local count = 0
  for _, line in ipairs(lines) do
    for _ in line:gmatch("ghci>") do
      count = count + 1
    end
  end
  _G.ghci_prompt_count = count
  
  return lines,last_count
end

function GetNewTerminalOutput(lines, last_count, register)
  local ghci_seen = 0
  local start_line = 0

  for i, line in ipairs(lines) do
    for _ in line:gmatch("ghci>") do
      ghci_seen = ghci_seen + 1
    end
    if ghci_seen == last_count then
      start_line = i
      break
    end
  end

  local new_lines = {}
  for i = start_line + 1, #lines do
    table.insert(new_lines, lines[i])
  end

  return new_lines
end
function DropGHCiPromptLines(lines)
  local result = {}
  for _, line in ipairs(lines) do
    if not line:match("ghci>") then
      table.insert(result, line)
    end
  end
  return result
end

function TrimTrailingEmptyLines(lines)
  local last_nonempty = #lines
  for i = #lines, 1, -1 do
    if lines[i]:match("%S") then  -- contains a non-space character
      last_nonempty = i
      break
    end
  end

  local trimmed = {}
  for i = 1, last_nonempty do
    table.insert(trimmed, lines[i])
  end

  return trimmed
end
function YankNewTerminalOutputDefault()
  local bufnr = 3       -- terminal buffer number
  local register = '"'  -- unnamed register

  local lines, count = YankTerminalOutput(bufnr)
  local mid_lines = GetNewTerminalOutput(lines, count)
  local new_lines = DropGHCiPromptLines(mid_lines)
  local new_lines = TrimTrailingEmptyLines(new_lines)

  if register then
    vim.fn.setreg(register, table.concat(new_lines, "\n"))
    print("Yanked " .. #new_lines .. " new lines into register " .. register)
  end

  -- Call the combined function
  return new_lines
end


function SendYankAndCapture(callback)
  SendYankToTerm()
  vim.defer_fn(function()
    local new_lines = YankNewTerminalOutputDefault()
    if callback then
      callback(new_lines)
    end
  end, 500) -- wait 200ms
  -- end, 200) -- wait 200ms
end
--function SendYankAndCapture()
--  -- 1. Send yanked lines
--  SendYankToTerm()
--
--  -- 2. Wait a bit (adjust delay if needed) and then capture output
--  vim.defer_fn(function()
--    local new_lines = YankNewTerminalOutputDefault()  -- gets new output, cleans ghci> lines
--    print("Captured " .. #new_lines .. " lines from terminal")
--    -- Optionally, inspect lines:
--    -- print(vim.inspect(new_lines))
--  end, 200)  -- 200ms delay; increase if terminal commands take longer
--end

-- Yank lines between ---HS (upwards) and ---HF (downwards) relative to cursor

function YankBlockBetweenMarkers()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1  -- 0-indexed

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start_line, end_line

  -- Search upwards for ---HS
  for i = row, 0, -1 do
    if lines[i + 1]:match("%-%-*HS") then
      start_line = i + 1  -- line after marker
      break
    end
  end
  if not start_line then
    print("No ---HS marker found above")
    return
  end

  -- Search downwards for ---HF
  for i = row + 1, #lines do
    if lines[i]:match("%-%-*HF") then
      end_line = i - 1  -- line before marker
      break
    end
  end
  if not end_line then
    print("No ---HF marker found below")
    return
  end

  -- Get the block
  local block = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line , false)

  -- Store in unnamed register
  vim.fn.setreg('"', table.concat(block, "\n"))
  --print("Yanked " .. #block .. " lines between ---HS and ---HF")
  return block
end

function PrintSections()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = 1, #lines do
    if lines[i]:match("%-%-*HS%#") then
       local extracted = string.match(lines[i], "#(.*)")
       print(extracted)
    end
  end
end

function ReplaceHFtoNextHS(replacement_text)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local start_row = cursor[1] - 1  -- 0-indexed
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local hf_line, hs_line

  -- Find the next ---HF from cursor
  for i = start_row + 1, #lines do
    if lines[i]:match("%-%-*HF") then
      hf_line = i
      break
    end
  end
  if not hf_line then
    print("No ---HF found below cursor")
    return
  end

  -- Find the next ---HS after the ---HF
  for i = hf_line + 1, #lines do
    if lines[i]:match("%-%-*HS") then
      hs_line = i
      break
    end
  end
  if not hs_line then
    print("No ---HS found after ---HF")
    return
  end

  -- Delete everything **between ---HF and ---HS** (exclusive of markers)
  local delete_start = hf_line + 1
  local delete_end = hs_line - 1
  if delete_end >= delete_start then
    vim.api.nvim_buf_set_lines(bufnr, delete_start-1, delete_end , false, {})
  end

  -- Insert replacement text at delete_start
  local replacement_lines = {}
  for line in replacement_text:gmatch("[^\n]+") do
    table.insert(replacement_lines, line)
  end
  vim.api.nvim_buf_set_lines(bufnr, delete_start-1, delete_start-1, false, replacement_lines)

  print("Replaced block between ---HF and next ---HS with replacement text")
end

function NoteBook()
  -- 1. Yank the block between ---HS and ---HF
  YankBlockBetweenMarkers()

  -- 2. Send to terminal and capture output asynchronously
  SendYankAndCapture(function(lines)
    -- lines is now the captured output after the terminal processed the input
    print("Captured " .. #lines .. " lines from terminal")

    -- Convert lines table to a string for ReplaceHFtoNextHS
    local replacement_text = table.concat(lines, "\n")

    -- 3. Replace the next ---HF → ---HS block with the captured output
    ReplaceHFtoNextHS(replacement_text)
  end)
end
vim.api.nvim_set_keymap(
  'n',               -- normal mode
  '<leader>j',
  --'<C-J>',           -- key combination
  [[:lua NoteBook()<CR>]], -- command to run
  { noremap = true, silent = true }  -- options
)


function CreateEmptyBlockBeforeNextHS()
  local bufnr = vim.api.nvim_get_current_buf()

  local cursor = vim.api.nvim_win_get_cursor(0)
  local start_row = cursor[1] 
  --print(start_row)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local insert_line=#lines

  for i = start_row, #lines do
    if lines[i]:match("%-%-*HS") then
      insert_line = i-1
      break
    end
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local block = { "-------------------------------------------------------------------------------------------------------------------------------------------------HS", "", "--------------------------------------------------------------------HF" }

  vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, block)
  vim.api.nvim_win_set_cursor(0,{insert_line+2,0})
end



vim.api.nvim_set_keymap(
  'n',               -- normal mode
  '<leader>n',
  -- '<C-N>',           -- key combination
  [[:lua CreateEmptyBlockBeforeNextHS()<CR>]], -- command to run
  { noremap = true, silent = true }  -- options
)
vim.keymap.set('n', '<leader>-', '/-------------------------------------------------------------------------------------------------------------------------------------------------HS<CR>', { noremap = true, silent = true })
-- vim.keymap.set('n', '<leader>o', '/--------------------------------------------------------------------HF<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>/', ':lua PrintSections()<CR>/-------------------------------------------------------------------------------------------------------------------------------------------------HS# ', { noremap = true, silent = true })
-- vim.keymap.set('n', '<leader>s', ':lua PrintSections()<CR>', { noremap = true, silent = true })

vim.keymap.set('n', '<leader>y', '"+y', { noremap = true, silent = true })
vim.keymap.set('v', '<leader>y', '"+y', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>l', '<C-^>', { noremap = true, silent = true })
-- keep track of runs to return good output in ghci
-- accept multiline input
-- it starts using a lot of ram with time, so i need to sometimes clear all history 
-- i can create a tab autocomplete super stupid using the ghci tab

-- vim.lsp.config["hls"] = {
--   settings = {
--     haskell = {
--       formattingProvider = "ormolu",
--     },
--   },
-- }
-- 
-- vim.lsp.start(vim.lsp.config["hls"])

require("nvim-treesitter.configs").setup {
  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false
  }
}

vim.opt.termguicolors = true
vim.cmd [[hi Normal guibg=NONE ctermbg=NONE]]
vim.cmd [[hi NormalFloat guibg=NONE]]

vim.cmd("source ~/.cache/wal/colors-wal.vim")

-- convert pywal colors (color0..color15) into Lua-accessible vim.g.colorN
for i = 0, 15 do
  local name = "color" .. i
  if pcall(vim.api.nvim_get_var, name) then
    vim.g[name] = vim.api.nvim_get_var(name)
  end
end
-- vim.api.nvim_set_hl(0, "Normal", { bg = "#000000" })  -- your preferred bg

local color2 = vim.g.color2
local color3 = vim.g.color3
local color4 = vim.g.color4
local color6 = vim.g.color6
local color8 = vim.g.color8
vim.api.nvim_set_hl(0, "@keyword",  { fg = color2 })
vim.api.nvim_set_hl(0, "@type",     { fg = color4 })
vim.api.nvim_set_hl(0, "@function", { fg = color6 })
vim.api.nvim_set_hl(0, "@string",   { fg = color3 })
vim.api.nvim_set_hl(0, "@comment",  { fg = color8 })



-- vim.api.nvim_set_hl(0, "Comment",  { fg = color8 })
-- vim.api.nvim_set_hl(0, "Keyword",  { fg = color2 })
-- vim.api.nvim_set_hl(0, "String",   { fg = color3 })
-- vim.api.nvim_set_hl(0, "Function", { fg = color6 })
-- vim.api.nvim_set_hl(0, "Type",     { fg = color4 })

-- local lspconfig = require("lspconfig")
-- 
-- lspconfig.hls.setup {
--   settings = {
--     haskell = {
--       formattingProvider = "ormolu",
--     },
--   },
-- }

-- local lspconfig = require("lspconfig")
-- vim.api.nvim_create_autocmd("FileType", {
--   pattern = "haskell",
--   callback = function()
--     lspconfig.hls.setup{
--       settings = {
--         haskell = {
--           formattingProvider = "ormolu",
--         },
--       },
--     }
--   end,
-- })
-- -- Modern LSP API (Neovim 0.10+)
-- vim.lsp.config["hls"] = {
--   -- This auto-detects haskell-language-server on PATH
--   cmd = { "haskell-language-server-wrapper", "--lsp" },
-- 
--   root_dir = vim.fs.root(0, { "hie.yaml", "stack.yaml", "cabal.project", "*.cabal" }),
-- 
--   settings = {
--     haskell = {
--       formattingProvider = "ormolu",
--     },
--   },
-- }
-- 
-- -- Auto-start only for Haskell files
-- vim.api.nvim_create_autocmd("FileType", {
--   pattern = "haskell",
--   callback = function()
--     vim.lsp.start(vim.lsp.config["hls"])
--   end,
-- })
