-- Lua
local settings = {
  window = {
    backdrop = 1,
    width = 0.30,
  },
  plugins = {
    options = {
      enabled = true,
      laststatus = 3,
    },
  },
}

return {
  "folke/zen-mode.nvim",
  opts = settings,
  config = function()
    vim.keymap.set("n", "<leader>z", function()
      require("zen-mode").toggle(settings)
    end)
  end,
}
