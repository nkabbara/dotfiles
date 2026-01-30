return {
  "NickvanDyke/opencode.nvim",
  dependencies = {
    -- Recommended for `ask()` and `select()`.
    -- Required for `toggle()`.
    { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
  },
  config = function()
    vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>")

    vim.g.opencode_opts = {
      provider = {
        enabled = "snacks",
        snacks = {},
      },
    }

    -- Required for `vim.g.opencode_opts.auto_reload`
    vim.opt.autoread = true

    -- Recommended/example keymaps
    vim.keymap.set({ "n", "x" }, "<leader>oa", function()
      require("opencode").ask("@this: ", { submit = true })
    end, { desc = "Ask about this" })
    vim.keymap.set({ "n", "x" }, "<leader>o+", function()
      require("opencode").prompt("@this")
    end, { desc = "Add this" })
    vim.keymap.set({ "n", "x" }, "<leader>os", function()
      require("opencode").select()
    end, { desc = "Select prompt" })
    vim.keymap.set("n", "<leader>ot", function()
      require("opencode").toggle()
    end, { desc = "Toggle embedded" })
    vim.keymap.set("n", "<leader>ol", function()
      require("opencode").command("session.list")
    end, { desc = "Select command" })
    vim.keymap.set("n", "<leader>on", function()
      require("opencode").command("session.new")
    end, { desc = "New session" })
    vim.keymap.set("n", "<leader>oi", function()
      require("opencode").command("session.interrupt")
    end, { desc = "Interrupt session" })
    vim.keymap.set("n", "<leader>oA", function()
      require("opencode").command("agent.cycle")
    end, { desc = "Cycle selected agent" })
    vim.keymap.set("n", "<M-a>", function()
      require("opencode").command("session.half.page.up")
    end, { desc = "Messages half page up" })
    vim.keymap.set("n", "<M-h>", function()
      require("opencode").command("session.half.page.down")
    end, { desc = "Messages half page down" })
  end,
}
