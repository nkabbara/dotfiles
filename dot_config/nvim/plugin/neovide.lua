if vim.g.neovide then
  vim.g.neovide_cursor_animation_length = 0
  -- vim.o.guifont = "Monaspace Argon NF:h16"
  vim.o.guifont = "BlexMono Nerd Font Mono Light:h16"
  vim.o.guicursor = "n:block-blinkwait100-blinkon0-blinkoff0,i:ver25-blinkwait100-blinkon0-blinkoff0"
  vim.g.neovide_show_border = true
  vim.g.neovide_scroll_animation_length = 0.3
  vim.g.neovide_scroll_animation_far_lines = 0 --does this stop the annoying animation that shows up when we come back to a window?
  vim.g.neovide_hide_mouse_when_typing = true

  vim.keymap.set("n", "<D-s>", ":w<CR>") -- Save
  vim.keymap.set("v", "<D-c>", '"+y') -- Copy
  vim.keymap.set("n", "<D-v>", '"+P') -- Paste normal mode
  vim.keymap.set("v", "<D-v>", '"+P') -- Paste visual mode
  vim.keymap.set("c", "<D-v>", "<C-R>+") -- Paste command mode
  vim.keymap.set("i", "<D-v>", '<ESC>l"+Pli') -- Paste insert mode

  -- Allow clipboard copy paste in neovim
  vim.api.nvim_set_keymap("", "<D-v>", "+p<CR>", { noremap = true, silent = true })
  vim.api.nvim_set_keymap("!", "<D-v>", "<C-R>+", { noremap = true, silent = true })
  vim.api.nvim_set_keymap("t", "<D-v>", "<C-R>+", { noremap = true, silent = true })
  vim.api.nvim_set_keymap("v", "<D-v>", "<C-R>+", { noremap = true, silent = true })
end
