-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Select all text in Normal mode using Ctrl + a
vim.keymap.set("n", "<C-a>", "ggVG", { desc = "Select All" })

-- Select all text in Visual mode using Ctrl + a
vim.keymap.set("v", "<C-a>", "<Esc>ggVG", { desc = "Select All" })
