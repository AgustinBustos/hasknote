vim.api.nvim_set_keymap('i', 'jk', '<Esc>', { noremap = true, silent = true })

vim.wo.relativenumber = true
vim.wo.number = true

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

vim.keymap.set("n","<C-J>", function()
  send_yank_to_term()
end, { noremap = true, silent = true })

