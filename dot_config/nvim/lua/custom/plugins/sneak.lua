return {
  {
    "justinmk/vim-sneak",
    event = "VeryLazy",
    config = function()
      vim.api.nvim_create_autocmd({ "User", "ColorScheme" }, {
        callback = function()
          vim.api.nvim_set_hl(0, "Sneak", { link = "None", force = true })
          vim.api.nvim_set_hl(0, "SneakCurrent", { link = "None", force = true })
        end,
      })
    end,
  },
}
