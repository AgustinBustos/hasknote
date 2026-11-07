-- Tab key inserts spaces: a literal Tab sent to ghci triggers completion
vim.opt.expandtab = true

-- bootstrap lazy.nvim, LazyVim and your plugins
-- windowrequire("config.lazy")


vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = true, silent = true })

--vim.keymap.set('n', '<F9>', ':bprevious<CR>', { noremap = true, silent = true })
--vim.keymap.set('n', '<F10>', ':bnext<CR>', { noremap = true, silent = true })
--vim.keymap.set('n', '<F9>', vim.cmd.bprevious, { silent = true })

vim.wo.relativenumber = true
vim.wo.number = true
vim.g.mapleader = " "
vim.g.maplocalleader = " " -- Optional: also set the local leader to space

vim.keymap.set("t", "jk", [[<C-\><C-n>]], { noremap = true, silent = true })

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
		-- a Tab reaching ghci is a completion request ("Display all N
		-- possibilities?") that swallows the rest of the cell
		vim.fn.chansend(term_job_id, (line:gsub("\t", "    ")) .. "\n")
	end
	_G.sent_lines_count = _G.sent_lines_count + #lines
	-- remembered so the wrapped tail of ghci's echo can be told apart from output
	_G.hasknote_sent = (table.concat(lines, "\n"):gsub("\t", "    "))

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
	local prelines = vim.fn.getreg('"', 1, true) -- 1 = get as list of lines
	local lines = BuildTermLines(prelines, getIndicator())
	if #lines == 0 then
		print("No yanked text found")
		return
	end
	-- Call your existing function
	SendToTermAndCapture(bufnr, lines, register)
end

-- Turn a cell's source lines into the lines to send to the REPL
-- (";"/where/|> joining, and :{ :} grouping for ghci).
function BuildTermLines(prelines, indicator)
	local lines = {}
	last_insertion = ""
	for idx, line in ipairs(prelines) do
		tostartwith = line:gsub("^%s*where", "where")
		tostartwith = tostartwith:gsub("^%s*|>", "|>")
		-- only glue where/|> onto a pending ";"-joined line; otherwise keep the
		-- line as-is (indented) so GroupGhciChunks sees it as a continuation
		if last_insertion ~= "" and string.sub(tostartwith, 1, string.len("where")) == "where" then
			last_insertion = string.sub(last_insertion, 1, -2) .. tostartwith
		elseif last_insertion ~= "" and string.sub(tostartwith, 1, string.len("|>")) == "|>" then
			last_insertion = string.sub(last_insertion, 1, -2) .. tostartwith
		else
			last_insertion = last_insertion .. line
		end
		local lastChar = string.sub(line, -1)
		if lastChar ~= ";" then
			table.insert(lines, last_insertion)
			last_insertion = ""
		end
	end

	if #lines > 0 and indicator == "ghci>" then
		lines = GroupGhciChunks(lines)
	end
	return lines
end

-- Name a top-level line defines ("f x = ..", "f :: ..", "data T = .."), or nil
local function decl_name(line)
	local name = line:match("^([%a_][%w_']*)")
	if not name or name == "let" or name == "import" then
		return nil
	end
	if line:find("::", 1, true) or line:find("[^=<>/!]=[^=>]") then
		return name
	end
	return nil
end

-- Group lines into ghci inputs so normal Haskell layout works:
-- indented lines continue the previous top-level line, and consecutive
-- equations/signature of the same name stay together. Multi-line groups
-- are wrapped in :{ :}, single lines are sent as-is (so :t, import work).
function GroupGhciChunks(lines)
	local chunks = {}
	for _, line in ipairs(lines) do
		if line:match("^%s*$") then
			-- blank lines carry no meaning inside :{ :}
		elseif line:match("^%s") and #chunks > 0 then
			table.insert(chunks[#chunks].lines, line)
		else
			local name = decl_name(line)
			local prev = chunks[#chunks]
			if name and prev and prev.name == name then
				table.insert(prev.lines, line)
			else
				table.insert(chunks, { name = name, lines = { line } })
			end
		end
	end

	local out = {}
	for _, chunk in ipairs(chunks) do
		if #chunk.lines == 1 then
			table.insert(out, chunk.lines[1])
		else
			table.insert(out, ":{")
			vim.list_extend(out, chunk.lines)
			table.insert(out, ":}")
		end
	end
	return out
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
	local last_count = _G.ghci_prompt_count
	local count = 0

	local runtime_indicator = getIndicator()
	for _, line in ipairs(lines) do
		for _ in line:gmatch(runtime_indicator) do
			count = count + 1
		end
	end
	_G.ghci_prompt_count = count

	return lines, last_count
end

function GetNewTerminalOutput(lines, last_count, register)
	local ghci_seen = 0
	local start_line = 0

	local runtime_indicator = getIndicator()
	for i, line in ipairs(lines) do
		for _ in line:gmatch(runtime_indicator) do
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

function getIndicator()
	filename = vim.api.nvim_buf_get_name(0)
	ext = filename:match("^.+%.(.+)$")

	if ext == "py" then
		runtime_indicator = ">>> "
	else
		runtime_indicator = "ghci>"
	end
	return runtime_indicator
end

-- Width the terminal wraps at: the widest line it holds (wrapped lines fill it).
local function term_width(bufnr)
	local w = 0
	for _, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		w = math.max(w, vim.fn.strdisplaywidth(l))
	end
	return w
end

function DropGHCiPromptLines(lines, indicator)
	local runtime_indicator = indicator or getIndicator()
	local width = term_width(3)
	local sent = _G.hasknote_sent or ""

	local result = {}
	local wrapping = false -- previous line was an echoed input that filled the width
	for _, line in ipairs(lines) do
		local text = line:gsub("%s+$", "")
		local full = vim.fn.strdisplaywidth(line) >= width - 1
		-- "ghci|" is the continuation prompt echoed for :{ :} blocks
		if line:match(runtime_indicator) or line:find("ghci|", 1, true) then
			wrapping = full
		elseif wrapping and text ~= "" and sent:find(text, 1, true) then
			-- the rest of a long input line the terminal wrapped: not output
			wrapping = full
		else
			wrapping = false
			table.insert(result, line)
		end
	end
	return result
end

function TrimTrailingEmptyLines(lines)
	local last_nonempty = #lines
	for i = #lines, 1, -1 do
		if lines[i]:match("%S") then -- contains a non-space character
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
	local bufnr = 3 -- terminal buffer number
	local register = '"' -- unnamed register

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
	local row = cursor[1] - 1 -- 0-indexed

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local start_line, end_line

	-- Search upwards for ---HS
	for i = row, 0, -1 do
		if lines[i + 1]:match("%-%-*HS") then
			start_line = i + 1 -- line after marker
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
			end_line = i - 1 -- line before marker
			break
		end
	end
	if not end_line then
		print("No ---HF marker found below")
		return
	end

	-- Get the block
	local block = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)

	-- Store in unnamed register
	vim.fn.setreg('"', table.concat(block, "\n"))
	--print("Yanked " .. #block .. " lines between ---HS and ---HF")
	return block
end

-- Sections: "-----HS# Title" / "-----HS## Sub" lines, and markdown headings
-- "# Title" / "## Sub" inside markdown cells (---MS … ---MF) mean the same thing.
function PrintSections()
	local bufnr = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local in_md, in_fence = false, false
	for i = 1, #lines do
		local l = lines[i]
		if l:match("^%-%-+MS") then
			in_md, in_fence = true, false
		elseif l:match("^%-%-+MF") or l:match("%-%-*HS") then
			in_md = false
		elseif in_md and l:match("^%s*```") then
			in_fence = not in_fence
		end
		if l:match("%-%-*HS%#") then
			local hashes, title = l:match("HS(#+)%s*(.*)$")
			print(string.rep("  ", #hashes - 1) .. title)
		elseif in_md and not in_fence then
			local hashes, title = l:match("^(#+)%s+(.*)$")
			if hashes then
				print(string.rep("  ", #hashes - 1) .. title)
			end
		end
	end
end

-- bufnr / start_row (0-indexed) default to the current buffer and cursor
function ReplaceHFtoNextHS(replacement_text, bufnr, start_row)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	start_row = start_row or (vim.api.nvim_win_get_cursor(0)[1] - 1) -- 0-indexed
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

	-- Find the next ---HS (or markdown ---MS) after the ---HF
	for i = hf_line + 1, #lines do
		if lines[i]:match("%-%-*HS") or lines[i]:match("%-%-*MS") then
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
		vim.api.nvim_buf_set_lines(bufnr, delete_start - 1, delete_end, false, {})
	end

	-- Insert replacement text at delete_start
	local replacement_lines = {}
	for line in replacement_text:gmatch("[^\n]+") do
		table.insert(replacement_lines, line)
	end
	vim.api.nvim_buf_set_lines(bufnr, delete_start - 1, delete_start - 1, false, replacement_lines)

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
		RenderNotebookPlots()
	end)
end
-- ---------------------------------------------------------------------------
-- Notebook queue (what <leader>j runs).
-- <leader>j adds the cell under the cursor to a queue, so you can press it on
-- several cells in a row without waiting. Cells are sent to the REPL one at a
-- time (the next one only once the previous one has finished, so inputs and
-- outputs never interleave), and each cell's output goes into ITS OWN HF block
-- (the cell is tracked with an extmark, so moving the cursor or editing is fine).
--
-- Each cell is sent wrapped in two sentinels that print a unique token, e.g.
--   putStrLn ("<<hasknote" ++ ":start:7>>")   <cell lines>   putStrLn ("<<hasknote" ++ ":done:7>>")
-- The cell's output is exactly what appears between the two printed tokens (the
-- echoed input shows the token split in two, so it never matches). This does not
-- depend on counting prompts, survives the terminal's scrollback trimming, and
-- works when GHCi is slow, errors, or is interrupted (the done token still prints).
--
-- When the output is written:
--   * the cell finished (done token printed)    -> right away, complete output;
--   * it started printing but is still running  -> NB_SETTLE_MS after the first
--     output, whatever is there (long outputs: look at the REPL terminal). If it
--     finishes within NB_RECAPTURE_MS of that, the full output replaces it.
-- A cell that prints nothing while computing just waits until it finishes.
-- The cell's HS line shows "queued" / "running" while it waits.
-- <leader>J empties the queue (e.g. if the REPL died).
local NB_TERM_BUF = 3
local NB_POLL_MS = 50
local NB_SETTLE_MS = 400
local NB_RECAPTURE_MS = 3000
local nb_ns = vim.api.nvim_create_namespace("hasknote_queue")
local nb_queue = {}
local nb_active = nil
local nb_timer = nil
local nb_seq = 0

-- set vim.g.nb_debug = "/path/to/log" to log every queue decision
local function nb_log(fmt, ...)
	if vim.g.nb_debug then
		local f = io.open(vim.g.nb_debug, "a")
		if f then
			f:write(string.format("%d " .. fmt .. "\n", vim.uv.now(), ...))
			f:close()
		end
	end
end

local function nb_mark_row(job)
	if not vim.api.nvim_buf_is_valid(job.buf) then
		return nil
	end
	local pos = vim.api.nvim_buf_get_extmark_by_id(job.buf, nb_ns, job.mark, {})
	return pos[1]
end

local function nb_status(job, text)
	local row = nb_mark_row(job)
	if not row then
		return
	end
	local opts = { id = job.mark }
	if text then
		opts.virt_text = { { "  " .. text, "Comment" } }
		opts.virt_text_pos = "eol"
	end
	vim.api.nvim_buf_set_extmark(job.buf, nb_ns, row, 0, opts)
end

local function nb_done(job)
	if vim.api.nvim_buf_is_valid(job.buf) then
		pcall(vim.api.nvim_buf_del_extmark, job.buf, nb_ns, job.mark)
	end
end

-- a REPL line that prints `token` without containing it literally
local function nb_sentinel(ind, token)
	local a, b = token:sub(1, 10), token:sub(11)
	if ind == "ghci>" then
		return 'putStrLn ("' .. a .. '" ++ "' .. b .. '")'
	end
	return 'print("' .. a .. '" + "' .. b .. '")'
end

local function nb_write(job, out)
	-- drop leading blank lines (e.g. the wrapped tail of a long echoed input)
	while #out > 0 and not out[1]:match("%S") do
		table.remove(out, 1)
	end
	local row = nb_mark_row(job)
	if not row then
		return
	end
	ReplaceHFtoNextHS(table.concat(out, "\n"), job.buf, row)
	RenderNotebookPlots(job.buf)
end

local function nb_stop_timer()
	if nb_timer then
		nb_timer:stop()
		nb_timer:close()
		nb_timer = nil
	end
end

local function nb_trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- (start index, done index or nil) of this job's printed tokens in the terminal
local function nb_find_tokens(term, job)
	local e
	for i = #term, 1, -1 do
		local l = nb_trim(term[i])
		if l == job.done_tok then
			e = i
		elseif l == job.start_tok then
			return i, e
		end
	end
	return nil, nil
end

local function nb_tick()
	local job = nb_active
	if not job then
		job = table.remove(nb_queue, 1)
		while job and not nb_mark_row(job) do -- its buffer/cell is gone
			job = table.remove(nb_queue, 1)
		end
		if not job then
			nb_stop_timer()
			return
		end
		local send = { nb_sentinel(job.ind, job.start_tok) }
		vim.list_extend(send, job.lines)
		table.insert(send, nb_sentinel(job.ind, job.done_tok))
		nb_log("send row=%s id=%d lines=%d", tostring(nb_mark_row(job)), job.id, #job.lines)
		SendToTermAndCapture(NB_TERM_BUF, send, '"')
		nb_active = job
		nb_status(job, "running…")
		return
	end

	local term = vim.api.nvim_buf_get_lines(NB_TERM_BUF, 0, -1, false)
	local s, e = nb_find_tokens(term, job)
	if not s then
		return -- the REPL hasn't reached this cell yet
	end
	local new = {}
	for i = s + 1, (e or (#term + 1)) - 1 do
		table.insert(new, term[i])
	end
	local finished = e ~= nil
	local now = vim.uv.now()

	if finished then
		local rewrite = not job.captured_at or now - job.captured_at < NB_RECAPTURE_MS
		nb_log("finished row=%s id=%d new=%d rewrite=%s", tostring(nb_mark_row(job)), job.id, #new, tostring(rewrite))
		if rewrite then
			nb_write(job, TrimTrailingEmptyLines(DropGHCiPromptLines(new, job.ind)))
		end
		nb_done(job)
		nb_active = nil
		return
	end

	if not job.captured_at then
		local out = TrimTrailingEmptyLines(DropGHCiPromptLines(new, job.ind))
		local has_output = #out > 0 and table.concat(out, ""):match("%S") ~= nil
		if has_output then
			job.started_at = job.started_at or now
			if now - job.started_at >= NB_SETTLE_MS then
				nb_log("partial row=%s id=%d lines=%d", tostring(nb_mark_row(job)), job.id, #out)
				nb_write(job, out)
				job.captured_at = now
				nb_status(job, "still running… (see the REPL)")
			end
		end
	end
end

function NoteBookEnqueue()
	local buf = vim.api.nvim_get_current_buf()
	local cur = vim.api.nvim_win_get_cursor(0)[1] -- 1-indexed
	local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	-- inside a markdown cell (---MS … ---MF)? render it instead of sending it
	for i = cur, 1, -1 do
		if all[i]:match("^%-%-+MS") then
			return NoteBookRenderMarkdown(buf, i - 1)
		elseif all[i]:match("%-%-*HS") then
			break
		end
	end
	local hs_row
	for i = cur, 1, -1 do
		if all[i]:match("%-%-*HS") then
			hs_row = i - 1 -- 0-indexed
			break
		end
	end
	local block = YankBlockBetweenMarkers()
	if not block or not hs_row then
		return
	end
	local ind = getIndicator()
	local lines = BuildTermLines(block, ind)
	if #lines == 0 then
		print("Empty cell")
		return
	end
	nb_seq = nb_seq + 1
	local id = nb_seq
	local job = {
		id = id,
		buf = buf,
		ind = ind,
		lines = lines,
		start_tok = "<<hasknote:start:" .. id .. ">>",
		done_tok = "<<hasknote:done:" .. id .. ">>",
		mark = vim.api.nvim_buf_set_extmark(buf, nb_ns, hs_row, 0, {}),
	}
	table.insert(nb_queue, job)
	nb_status(job, "queued (" .. (#nb_queue + (nb_active and 1 or 0)) .. ")")
	if not nb_timer then
		nb_timer = vim.uv.new_timer()
		nb_timer:start(0, NB_POLL_MS, vim.schedule_wrap(nb_tick))
	end
end

function NoteBookQueueClear()
	for _, job in ipairs(nb_queue) do
		nb_done(job)
	end
	if nb_active then
		nb_done(nb_active)
	end
	nb_queue, nb_active = {}, nil
	nb_stop_timer()
	print("Notebook queue cleared")
end

vim.keymap.set("n", "<leader>j", NoteBookEnqueue, { noremap = true, silent = true, desc = "Notebook: run cell (queued)" })
vim.keymap.set("n", "<leader>J", NoteBookQueueClear, { noremap = true, silent = true, desc = "Notebook: clear run queue" })

-- ---------------------------------------------------------------------------
-- Markdown cells:
--   -----…MS
--   # Heading, **text**, lists, math $\beta$ / $$ … $$
--   -----…MF
--   [img] charts/md/<id>.png      <- preview, (re)written by <leader>j
-- <leader>m inserts an empty markdown cell (like <leader>n for code cells).
-- <leader>j inside a markdown cell renders it with `hasknote-compile --md-snippet`
-- (same typography as the compiled document: Latin Modern + KaTeX) and shows the
-- PNG inline under the cell. It is not sent to GHCi.
local NB_MS = "-------------------------------------------------------------------------------------------------------------------------------------------------MS"
local NB_MF = "--------------------------------------------------------------------MF"

-- replace the lines between the cell's ---MF and the next cell (or end of buffer)
local function nb_replace_after_mf(buf, ms_row, new_lines)
	local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local mf
	for i = ms_row + 2, #all do
		if all[i]:match("^%-%-+MF") then
			mf = i
			break
		end
	end
	if not mf then
		return
	end
	local stop = #all + 1
	for i = mf + 1, #all do
		if all[i]:match("%-%-*HS") or all[i]:match("^%-%-+MS") then
			stop = i
			break
		end
	end
	vim.api.nvim_buf_set_lines(buf, mf, stop - 1, false, new_lines)
end

function NoteBookRenderMarkdown(buf, ms_row)
	local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local mf
	for i = ms_row + 2, #all do
		if all[i]:match("^%-%-+MF") then
			mf = i
			break
		elseif all[i]:match("%-%-*HS") or all[i]:match("^%-%-+MS") then
			break
		end
	end
	if not mf then
		print("No ---MF below this ---MS")
		return
	end
	local md = vim.list_slice(all, ms_row + 2, mf - 1)
	local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p:h")
	local id = tostring(vim.uv.hrtime())
	local rel = "charts/md/" .. id
	vim.fn.mkdir(dir .. "/charts/md", "p")
	vim.fn.writefile(md, dir .. "/" .. rel .. ".md")
	local mark = vim.api.nvim_buf_set_extmark(buf, nb_ns, ms_row, 0, {
		virt_text = { { "  rendering…", "Comment" } },
		virt_text_pos = "eol",
	})
	local exe = vim.fn.exepath("hasknote-compile")
	if exe == "" then
		exe = vim.fn.expand("~/.local/bin/hasknote-compile")
	end
	vim.system(
		{ exe, "--md-snippet", dir .. "/" .. rel .. ".md", "-o", dir .. "/" .. rel .. ".png" },
		{ text = true },
		function(res)
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end
				local pos = vim.api.nvim_buf_get_extmark_by_id(buf, nb_ns, mark, {})
				pcall(vim.api.nvim_buf_del_extmark, buf, nb_ns, mark)
				if res.code ~= 0 then
					print("markdown render failed: " .. (res.stderr or ""):sub(1, 300))
					return
				end
				if pos[1] then
					nb_replace_after_mf(buf, pos[1], { "[img] " .. rel .. ".png" })
					RenderNotebookPlots(buf)
				end
			end)
		end
	)
end

function CreateMarkdownBlockBeforeNextCell()
	local bufnr = vim.api.nvim_get_current_buf()
	local start_row = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local insert_line = #lines
	for i = start_row, #lines do
		if lines[i]:match("%-%-*HS") or lines[i]:match("^%-%-+MS") then
			insert_line = i - 1
			break
		end
	end
	vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, { NB_MS, "", NB_MF })
	vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
end

vim.keymap.set("n", "<leader>m", CreateMarkdownBlockBeforeNextCell, { noremap = true, silent = true, desc = "Notebook: new markdown cell" })

function CreateEmptyBlockBeforeNextHS()
	local bufnr = vim.api.nvim_get_current_buf()

	local cursor = vim.api.nvim_win_get_cursor(0)
	local start_row = cursor[1]
	--print(start_row)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local insert_line = #lines

	for i = start_row, #lines do
		if lines[i]:match("%-%-*HS") or lines[i]:match("%-%-*MS") then
			insert_line = i - 1
			break
		end
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local block = {
		"-------------------------------------------------------------------------------------------------------------------------------------------------HS",
		"",
		"--------------------------------------------------------------------HF",
	}

	vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, block)
	vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
end

vim.api.nvim_set_keymap(
	"n", -- normal mode
	"<leader>n",
	-- '<C-N>',           -- key combination
	[[:lua CreateEmptyBlockBeforeNextHS()<CR>]], -- command to run
	{ noremap = true, silent = true } -- options
)
vim.keymap.set(
	"n",
	"<leader>-",
	"/-------------------------------------------------------------------------------------------------------------------------------------------------HS<CR>",
	{ noremap = true, silent = true }
)
vim.keymap.set(
	"n",
	"<leader>o",
	"/--------------------------------------------------------------------HF<CR>",
	{ noremap = true, silent = true }
)
vim.keymap.set(
	"n",
	"<leader>/",
	":lua PrintSections()<CR>/\\(HS#* \\|^#\\+ \\).*",
	{ noremap = true, silent = true }
)
-- vim.keymap.set("i", "<C-n>", "<Tab>", { noremap = true })
-- vim.keymap.set('n', '<leader>s', ':lua PrintSections()<CR>', { noremap = true, silent = true })
vim.keymap.set(
	"n",
	"<leader>N",
	"i-------------------------------------------------------------------------------------------------------------------------------------------------HS<Esc>",
	{ noremap = true, silent = true }
)

vim.keymap.set("n", "<leader>y", '"+y', { noremap = true, silent = true })
vim.keymap.set("v", "<leader>y", '"+y', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>l", "<C-^>", { noremap = true, silent = true })

function MarkWithTimestamp()
	local l = vim.fn.line(".")
	local ts = os.date("%Y-%m-%d %H:%M")

	local line = vim.fn.getline(l)
	line = "* " .. line .. " -> " .. ts
	vim.fn.setline(l, line)
	vim.fn.deletebufline("", l)       
	vim.fn.append(0, line)           
end

function MarkWithTimestampFinish()
	local l = vim.fn.line(".")
	local ts = os.date("%Y-%m-%d %H:%M")

	local line = vim.fn.getline(l)
	line = string.sub(line, 3)
	line = "-- " .. line .. " -> " .. ts
	vim.fn.setline(l, line)
	vim.fn.deletebufline("", l)              
	vim.fn.append(vim.fn.line("$"), line)   
end

vim.api.nvim_set_keymap(
	"n", -- normal mode
	"<leader>z",
	-- '<C-N>',           -- key combination
	[[:lua MarkWithTimestamp()<CR>]], -- command to run
	{ noremap = true, silent = true } -- options
)
vim.api.nvim_set_keymap(
	"n", -- normal mode
	"<leader>x",
	-- '<C-N>',           -- key combination
	[[:lua MarkWithTimestampFinish()<CR>]], -- command to run
	{ noremap = true, silent = true } -- options
)
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

-- require("nvim-treesitter.configs").setup({ highlight = { enable = true, additional_vim_regex_highlighting = false, }, })

vim.opt.termguicolors = true
vim.cmd([[hi Normal guibg=NONE ctermbg=NONE]])
vim.cmd([[hi NormalFloat guibg=NONE]])

vim.cmd("source ~/.cache/wal/colors-wal.vim")

-- convert pywal colors (color0..color15) into Lua-accessible vim.g.colorN
for i = 0, 15 do
	local name = "color" .. i
	if pcall(vim.api.nvim_get_var, name) then
		vim.g[name] = vim.api.nvim_get_var(name)
	end
end
-- vim.api.nvim_set_hl(0, "Normal", { bg = "#000000" })  -- your preferred bg

-- Highlighting is Vim's built-in regex syntax, not treesitter.
--
-- Treesitter's colors are finer (it can tell a call from a definition, self.attr
-- from a local), but its error recovery is pathological on files that aren't
-- valid source -- and the ---HS/---HF notebook buffers are exactly that:
-- captured REPL output pasted straight into a .py. On get_revenue.py (238KB,
-- 3274 ERROR nodes) the tree can't be reused, so every keystroke pays a full
-- reparse. Measured keystroke-to-redraw latency:
--
--   get_revenue.py    treesitter 146ms   regex syntax 2.3ms
--   valid .py, 250KB  treesitter  11ms   regex syntax 1.5ms
--
-- Regex syntax is line-oriented, so garbage in the buffer costs it nothing.
-- The palette below covers both the legacy groups (what's actually in use) and
-- the treesitter @captures, so re-enabling treesitter is a one-liner:
--
--   vim.api.nvim_create_autocmd("FileType", function(a) pcall(vim.treesitter.start, a.buf) end)

-- True/False/None as Boolean/Constant rather than Function, to match the
-- palette below. (Deliberately *not* python_highlight_all -- that also switches
-- on space-error highlighting, which paints the pasted REPL output in the
-- notebook files bright red.)
vim.g.python_constant_highlight = 1

-- Syntax palette from the pywal slots. The active theme is near-monochrome,
-- so we lean on the few distinct slots (brown color3, bright greys color6/7)
-- and bold/italic to create contrast the palette alone can't.
local wal = {}
for i = 0, 15 do
	wal[i] = vim.g["color" .. i]
end
local syn = {
	-- comments recede: darkest slot, italic
	{ "@comment", { fg = wal[1], italic = true } },
	-- keywords: grey-blue, bold
	{ "@keyword", { fg = wal[2], bold = true } },
	{ "@keyword.function", { fg = wal[2], bold = true } }, -- def, lambda
	{ "@keyword.import", { fg = wal[2], bold = true } }, -- import, from
	{ "@keyword.return", { fg = wal[2], bold = true } },
	{ "@keyword.operator", { fg = wal[2] } }, -- and, or, not, in, is
	{ "@keyword.conditional", { fg = wal[2], bold = true } }, -- if, elif, else
	{ "@keyword.repeat", { fg = wal[2], bold = true } }, -- for, while
	{ "@keyword.exception", { fg = wal[2], bold = true } }, -- try, except, raise
	-- types
	{ "@type", { fg = wal[4] } },
	{ "@type.builtin", { fg = wal[4], bold = true } }, -- int, str, list, dict
	{ "@constructor", { fg = wal[4] } },
	-- functions: brightest grey
	{ "@function", { fg = wal[6], bold = true } },
	{ "@function.call", { fg = wal[6] } },
	{ "@function.method", { fg = wal[6], bold = true } },
	{ "@function.method.call", { fg = wal[6] } },
	{ "@function.builtin", { fg = wal[6], italic = true } }, -- print, len, range
	-- strings + numbers share the one warm/brown slot; numbers bold to split them
	{ "@string", { fg = wal[3] } },
	{ "@string.documentation", { fg = wal[3], italic = true } }, -- docstrings
	{ "@string.escape", { fg = wal[3], bold = true } },
	{ "@number", { fg = wal[3], bold = true } },
	{ "@number.float", { fg = wal[3], bold = true } },
	{ "@boolean", { fg = wal[3], bold = true } }, -- True / False
	{ "@constant", { fg = wal[6] } },
	{ "@constant.builtin", { fg = wal[3], bold = true } }, -- None
	-- variables
	{ "@variable", { fg = wal[7] } }, -- base text tone
	{ "@variable.member", { fg = wal[5] } }, -- self.attr, obj.field
	{ "@variable.parameter", { fg = wal[5], italic = true } }, -- def args
	{ "@variable.builtin", { fg = wal[5], bold = true } }, -- self, cls
	{ "@attribute", { fg = wal[3], italic = true } }, -- @decorator
	-- punctuation/operators: mid grey, quiet
	{ "@operator", { fg = wal[8] } },
	{ "@punctuation.bracket", { fg = wal[8] } },
	{ "@punctuation.delimiter", { fg = wal[8] } },

	-- The same palette on the legacy syntax groups -- these are the ones actually
	-- doing the work now. Coarser than the @captures above (regex syntax can't
	-- tell a call from a definition, or self.attr from a local) but same colors.
	{ "Comment", { fg = wal[1], italic = true } },
	{ "Statement", { fg = wal[2], bold = true } }, -- def, return, pass, lambda
	{ "Keyword", { fg = wal[2], bold = true } },
	{ "Conditional", { fg = wal[2], bold = true } },
	{ "Repeat", { fg = wal[2], bold = true } },
	{ "Exception", { fg = wal[2], bold = true } },
	{ "Include", { fg = wal[2], bold = true } }, -- import, from
	{ "PreProc", { fg = wal[2], bold = true } },
	{ "Type", { fg = wal[4] } },
	{ "Structure", { fg = wal[4] } }, -- class names, exception names
	{ "StorageClass", { fg = wal[4] } },
	{ "Typedef", { fg = wal[4] } },
	{ "Function", { fg = wal[6], bold = true } }, -- def names + builtins
	{ "Identifier", { fg = wal[5] } }, -- self, cls
	{ "String", { fg = wal[3] } },
	{ "Character", { fg = wal[3] } },
	{ "Number", { fg = wal[3], bold = true } },
	{ "Float", { fg = wal[3], bold = true } },
	{ "Boolean", { fg = wal[3], bold = true } },
	{ "Constant", { fg = wal[3], bold = true } }, -- None
	{ "Define", { fg = wal[3], italic = true } }, -- @decorator
	{ "Macro", { fg = wal[3], italic = true } },
	{ "Special", { fg = wal[3], bold = true } }, -- \n escapes, f-string braces
	{ "SpecialChar", { fg = wal[3], bold = true } },
	{ "Operator", { fg = wal[8] } },
	{ "Delimiter", { fg = wal[8] } },
}
for _, h in ipairs(syn) do
	vim.api.nvim_set_hl(0, h[1], h[2])
end

-- local last_j = 0
-- local last_k = 0
-- local delay = 1000 -- ms
--
-- local function allow_motion(last_time)
-- 	-- Allow freely during macro recording or execution
-- 	if vim.fn.reg_recording() ~= "" or vim.fn.reg_executing() ~= "" then
-- 		return true
-- 	end
--
-- 	local now = vim.loop.now()
-- 	if now - last_time > delay then
-- 		return true
-- 	end
--
-- 	return false
-- end
--
-- vim.keymap.set("n", "j", function()
-- 	if allow_motion(last_j) then
-- 		last_j = vim.loop.now()
-- 		vim.cmd("normal! " .. vim.v.count1 .. "j")
-- 	end
-- end)
--
-- vim.keymap.set("n", "k", function()
-- 	if allow_motion(last_k) then
-- 		last_k = vim.loop.now()
-- 		vim.cmd("normal! " .. vim.v.count1 .. "k")
-- 	end
-- end)

-- Vertical "find": like f<char> but across lines.
-- Reads one char, then jumps to the next word (scanning in the given direction)
-- that starts *or* ends with that char, landing on that char.
-- <leader>d = downward, <leader>u = upward. n repeats, N repeats reversed.
local last_vf = nil -- { ch = <char>, dir = 1 or -1 }

-- All 0-indexed columns on `line` where `ch` begins *or* ends a word/token,
-- left to right.
local function vf_word_cols(line, ch)
	local cols = {}
	for p = 1, #line do
		if line:sub(p, p) == ch then
			local prev = p > 1 and line:sub(p - 1, p - 1) or ""
			local nxt = p < #line and line:sub(p + 1, p + 1) or ""
			local starts = not prev:match("[%w_]")
			local ends = not nxt:match("[%w_]")
			if starts or ends then
				cols[#cols + 1] = p - 1
			end
		end
	end
	return cols
end

-- Jump to the next word-start/word-end matching `ch` after the cursor (dir 1) or before
-- it (dir -1). Walks within a line too, so multiple matches per line are all
-- reachable (e.g. both p-words in "profile performance").
local function vf_exec(ch, dir)
	local cur = vim.api.nvim_win_get_cursor(0)
	local row, col = cur[1], cur[2]
	local last = vim.api.nvim_buf_line_count(0)
	for i = row, (dir > 0 and last or 1), dir do
		local cols = vf_word_cols(vim.fn.getline(i), ch)
		if dir > 0 then
			for _, c in ipairs(cols) do
				if i > row or c > col then
					vim.api.nvim_win_set_cursor(0, { i, c })
					return
				end
			end
		else
			for j = #cols, 1, -1 do
				local c = cols[j]
				if i < row or c < col then
					vim.api.nvim_win_set_cursor(0, { i, c })
					return
				end
			end
		end
	end
end

local function vertical_find(dir)
	local ch = vim.fn.getcharstr()
	if ch == "" or ch == "\27" then return end -- empty / <Esc> cancels
	last_vf = { ch = ch, dir = dir }
	vf_exec(ch, dir)
end

vim.keymap.set("n", "<leader>d", function() vertical_find(1) end)
vim.keymap.set("n", "<leader>u", function() vertical_find(-1) end)

-- Repeat the last vertical find with ; / , . These coexist with the native
-- ; / , (repeat f/t/F/T): they only take over while a vertical find is the
-- most recent motion; otherwise they fall through to normal f/t-repeat.
-- Using f/t/F/T clears last_vf so ; and , take back over for horizontal finds.
vim.keymap.set("n", ";", function()
	if last_vf then vf_exec(last_vf.ch, last_vf.dir)
	else vim.cmd("normal! ;") end
end)
vim.keymap.set("n", ",", function()
	if last_vf then vf_exec(last_vf.ch, -last_vf.dir)
	else vim.cmd("normal! ,") end
end)

for _, key in ipairs({ "f", "t", "F", "T" }) do
	vim.keymap.set("n", key, function()
		last_vf = nil
		return key
	end, { expr = true })
end

vim.filetype.add({
  extension = {
    todo = "mytodo",  -- or sg if you prefer
  },
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "mytodo",
  callback = function()
    vim.cmd("set syntax=mytodo")
  end,
})
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    vim.opt_local.number = true
    vim.opt_local.relativenumber = true
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = "netrw",
  callback = function()
    vim.opt_local.number = true
    vim.opt_local.relativenumber = true
  end,
})

-- Don't continue comment leaders (e.g. "--") when opening a line with o/O.
-- Done in a FileType autocmd because ftplugins reset formatoptions.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    vim.opt_local.formatoptions:remove("o")
  end,
})

-- Auto-commit + push the job todo file on every :w (that file only)
local todo_file = vim.fn.expand("~/Documents/job/do/todo")
local todo_dir = vim.fn.fnamemodify(todo_file, ":h")

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = todo_file,
  callback = function()
    vim.system(
      { "git", "-C", todo_dir, "add", "--", todo_file },
      { text = true },
      function(add)
        if add.code ~= 0 then
          vim.schedule(function()
            vim.notify("todo: git add failed\n" .. (add.stderr or ""), vim.log.levels.ERROR)
          end)
          return
        end
        local msg = "todo: " .. os.date("%Y-%m-%d %H:%M:%S")
        vim.system(
          { "git", "-C", todo_dir, "commit", "-q", "-m", msg },
          { text = true },
          function(commit)
            -- code 1 with no staged changes just means nothing to commit
            if commit.code ~= 0 then return end
            vim.system(
              { "git", "-C", todo_dir, "push", "-q", "origin", "main" },
              { text = true },
              function(push)
                vim.schedule(function()
                  if push.code == 0 then
                    vim.notify("todo: pushed", vim.log.levels.INFO)
                  else
                    vim.notify("todo: push failed\n" .. (push.stderr or ""), vim.log.levels.ERROR)
                  end
                end)
              end
            )
          end
        )
      end
    )
  end,
})

---------------------------------------------------------------------------------------
-- Inline plots for the notebooks (needs Ghostty/Kitty). The Hasknote helpers
-- (hasknote/hs, imported from ~/.ghci) print a marker line in the output:
--   showPlot   -> "[plot] <spec>.vl.json"       PNG via vl-convert
--   showHtml / showPlotly -> "[html] <file> <stamp>"  PNG via headless chromium
-- and here we turn it into a PNG drawn on that line. <leader>b opens it in the browser.
pcall(function()
	require("snacks").setup({ image = { enabled = true, doc = { enabled = false } } })
end)

local nb_python = vim.fn.expand("~/.venvs/main/bin/python")
local nb_vl2png = vim.fn.expand("~/Documents/dotfiles/hasknote/vl2png.py")
local nb_cache = vim.fn.expand("~/.cache/hasknote/plots")
local nb_plots = {} -- buf -> png -> { placement, row }
local nb_converting = {}

-- Screenshot size for [html] plots: exactly the pixels of the area the image
-- gets on screen (text width up to 100 columns x up to 30 rows / 70% of the
-- window height), so snacks
-- shows it 1:1 instead of rescaling it (which blurs text and thin lines).
-- Returns the window size in CSS pixels and the device scale factor.
local function nb_html_size()
	local ok, term = pcall(function()
		return Snacks.image.terminal.size()
	end)
	if not ok or not term.cell_width then
		return 900, 550, "2"
	end
	local dpr = math.max(1, math.min(3, term.scale or 1))
	local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
	local cols = math.min(100, info.width - info.textoff)
	local rows = math.min(30, math.floor(info.height * 0.7), math.floor(cols * term.cell_width * 0.6 / term.cell_height))
	local w_px, h_px = cols * term.cell_width, rows * term.cell_height
	return math.floor(w_px / dpr + 0.5), math.floor(h_px / dpr + 0.5), string.format("%.4f", dpr)
end

-- Parse a marker line: the PNG to show, the command that makes it,
-- and the file to open in the browser.
-- Relative marker paths (e.g. "[html] charts/by-id/<id>.html <stamp>") are
-- relative to the notebook's directory (= GHCi's working directory).
local function nb_abs(path, base)
	if path:sub(1, 1) == "/" or path:sub(1, 1) == "~" or not base or base == "" then
		return vim.fn.expand(path)
	end
	return base .. "/" .. path
end

local function nb_marker(line, base)
	local img = line:match("^%[img%] (.+%.png)%s*$")
	if img then
		img = nb_abs(img, base)
		return { png = img, src = img } -- already rendered: nothing to run
	end
	local json = line:match("^%[plot%] (.+%.vl%.json)%s*$")
	if json then
		json = nb_abs(json, base)
	end
	if json then
		local png = json:gsub("%.vl%.json$", ".png")
		return { png = png, src = json, cmd = { nb_python, nb_vl2png, json, png } }
	end
	local html, stamp = line:match("^%[html%] (.+%.html) (%d+)%s*$")
	if html then
		html = nb_abs(html, base)
		local png = nb_cache .. "/html-" .. stamp .. ".png"
		local w, h, dpr = nb_html_size()
		-- stylua: ignore
		return { png = png, src = html, cmd = {
			"chromium", "--headless=new", "--disable-gpu", "--hide-scrollbars",
			"--window-size=" .. w .. "," .. h, "--force-device-scale-factor=" .. dpr,
			"--virtual-time-budget=5000", "--screenshot=" .. png, "file://" .. html,
		} }
	end
end

function RenderNotebookPlots(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if vim.bo[buf].buftype ~= "" or not (_G.Snacks and Snacks.image.supports_terminal()) then
		return
	end
	nb_plots[buf] = nb_plots[buf] or {}
	local placed = nb_plots[buf]
	local seen = {}
	local base = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p:h")

	for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local m = nb_marker(line, base)
		if m then
			local png = m.png
			seen[png] = true
			local cur = placed[png]
			if cur and cur.row ~= i then
				cur.placement:close()
				placed[png], cur = nil, nil
			end
			if not cur then
				if vim.uv.fs_stat(png) then
					placed[png] = {
						row = i,
						placement = Snacks.image.placement.new(buf, png, {
							inline = true,
							pos = { i, 0 },
							range = { i, 0, i, #line },
							max_width = 100,
							max_height = 30,
						}),
					}
				elseif m.cmd and not nb_converting[png] and vim.uv.fs_stat(m.src) then
					nb_converting[png] = true
					vim.fn.mkdir(nb_cache, "p")
					vim.system(m.cmd, {}, function(res)
						vim.schedule(function()
							nb_converting[png] = nil
							if res.code ~= 0 or not vim.uv.fs_stat(png) then
								print("plot render failed: " .. (res.stderr or ""))
							elseif vim.api.nvim_buf_is_valid(buf) then
								RenderNotebookPlots(buf)
							end
						end)
					end)
				end
			end
		end
	end

	-- drop images whose marker line is gone (cell re-run or deleted)
	for png, cur in pairs(placed) do
		if not seen[png] then
			cur.placement:close()
			placed[png] = nil
		end
	end
end

-- Open the plot under the cursor in the browser (interactive: zoom, hover, ...)
function OpenNotebookPlot()
	local m = nb_marker(vim.api.nvim_get_current_line(), vim.fn.expand("%:p:h"))
	if not m then
		print("No [plot]/[html] line under the cursor")
		return
	end
	if m.src:match("%.html$") or m.src:match("%.png$") then
		vim.ui.open(m.src)
		return
	end
	local html = m.src:gsub("%.vl%.json$", ".html")
	vim.system({ nb_python, nb_vl2png, m.src, html }, {}, function(res)
		vim.schedule(function()
			if res.code == 0 then
				vim.ui.open(html)
			else
				print("vl2png failed: " .. (res.stderr or ""))
			end
		end)
	end)
end
vim.keymap.set("n", "<leader>b", OpenNotebookPlot, { noremap = true, silent = true })

vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "InsertLeave" }, {
	callback = function(ev)
		RenderNotebookPlots(ev.buf)
	end,
})

---------------------------------------------------------------------------------------
-- Git diffing: diffview.nvim (branch/commit diffs), gitsigns.nvim (hunks), vim-fugitive
require("diffview").setup({ use_icons = false })
require("gitsigns").setup({
	signcolumn = false, -- no gutter marks; toggle with <leader>gs
	on_attach = function(bufnr)
		local gs = require("gitsigns")
		local function map(lhs, rhs) vim.keymap.set("n", lhs, rhs, { buffer = bufnr, silent = true }) end
		map("]h", function() gs.nav_hunk("next") end)
		map("[h", function() gs.nav_hunk("prev") end)
		map("<leader>gp", gs.preview_hunk)
		map("<leader>gr", gs.reset_hunk)
		map("<leader>gb", gs.blame_line)
		map("<leader>gs", gs.toggle_signs)
	end,
})

-- Diff working tree against a branch (prompts, defaults to main)
local function diff_against_branch()
	vim.ui.input({ prompt = "Diff against: ", default = "main" }, function(ref)
		if ref and ref ~= "" then vim.cmd("DiffviewOpen " .. ref .. "...HEAD") end
	end)
end
vim.keymap.set("n", "<leader>gd", diff_against_branch, { silent = true })
vim.keymap.set("n", "<leader>gD", "<cmd>DiffviewOpen<CR>", { silent = true })
vim.keymap.set("n", "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", { silent = true })
vim.keymap.set("n", "<leader>gH", "<cmd>DiffviewFileHistory<CR>", { silent = true })
vim.keymap.set("n", "<leader>gq", "<cmd>DiffviewClose<CR>", { silent = true })

-- Markdown cells (---MS … ---MF) inside Haskell notebooks: highlight them as
-- markdown. Without this, Vim's Haskell syntax (which includes the C
-- preprocessor rules) paints "# heading" lines red as invalid CPP (cError).
-- (own augroup: `syntax on` runs `au! Syntax`, which clears ungrouped ones)
vim.api.nvim_create_autocmd("Syntax", {
	group = vim.api.nvim_create_augroup("HasknoteMdCells", { clear = true }),
	pattern = "haskell",
	callback = function(ev)
		-- scheduled: the Haskell syntax file itself is loaded by another Syntax
		-- autocmd that may run after this one and would clear our region
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(ev.buf) then
				return
			end
			vim.api.nvim_buf_call(ev.buf, function()
				vim.cmd([[
					unlet! b:current_syntax
					silent! syntax include @hasknoteMd syntax/markdown.vim
					let b:current_syntax = "haskell"
					syntax region hasknoteMdCell matchgroup=Comment start=/^-\+MS\s*$/ end=/^-\+MF\s*$/ keepend contains=@hasknoteMd
				]])
			end)
		end)
	end,
})
