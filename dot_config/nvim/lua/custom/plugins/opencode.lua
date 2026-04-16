return {
  "NickvanDyke/opencode.nvim",
  -- dir = "/Users/nkabbara/dev/opencode.nvim",
  -- name = "opencode.nvim",
  dependencies = {
    {
      -- `snacks.nvim` integration is recommended, but optional
      ---@module "snacks" <- Loads `snacks.nvim` types for configuration intellisense
      "folke/snacks.nvim",
      opts = {
        input = {}, -- Enhances `ask()`
        picker = { -- Enhances `select()`
          actions = {
            opencode_send = function(...)
              return require("opencode").snacks_picker_send(...)
            end,
          },
          win = {
            input = {
              keys = {
                ["<a-a>"] = { "opencode_send", mode = { "n", "i" } },
              },
            },
          },
        },
      },
    },
  },
  config = function()
    vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>")

    local opencode_cmd = "opencode --port"
    local opencode_workflow = require("custom.opencode.workflow")
    local opencode_resize_group = vim.api.nvim_create_augroup("custom-opencode-resize", { clear = true })

    local function resize_opencode_win()
      local win = opencode_workflow.find_opencode_win(opencode_cmd)
      if win and vim.api.nvim_win_is_valid(win) then
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= "" then
          return
        end
        vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * 0.5))
      end
    end

    vim.api.nvim_create_autocmd("VimResized", {
      group = opencode_resize_group,
      callback = function()
        vim.schedule(resize_opencode_win)
      end,
    })

    vim.g.opencode_opts = {
      server = {
        start = function()
          require("opencode.terminal").open(opencode_cmd, {
            split = "right",
            width = math.floor(vim.o.columns * 0.5),
          })
        end,
        toggle = function()
          require("opencode.terminal").toggle(opencode_cmd, {
            split = "right",
            width = math.floor(vim.o.columns * 0.5),
          })
        end,
        stop = function()
          require("opencode.terminal").close()
        end,
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
    end, { desc = "Select from all functionality" })
    vim.keymap.set("n", "<leader>ot", function()
      require("opencode").toggle()
    end, { desc = "Toggle embedded" })
    vim.keymap.set("n", "<leader>c", function()
      opencode_workflow.focus_code_in_zen(opencode_cmd)
    end, { desc = "Focus code in AI workflow" })
    vim.keymap.set("n", "<leader>a", function()
      opencode_workflow.focus_opencode_in_zen(opencode_cmd)
    end, { desc = "Focus opencode in AI workflow" })
    vim.keymap.set("n", "<leader>ol", function()
      require("opencode").command("session.select")
    end, { desc = "List sessions" })
    vim.keymap.set("n", "<leader>on", function()
      require("opencode").command("session.new")
    end, { desc = "New session" })
    vim.keymap.set("n", "<leader>oi", function()
      require("opencode").command("session.interrupt")
    end, { desc = "Interrupt session" })
    vim.keymap.set("n", "<leader>oA", function()
      require("opencode").command("agent.cycle")
    end, { desc = "Cycle selected agent" })
    vim.keymap.set("n", "<C-M-u>", function()
      require("opencode").command("session.half.page.up")
    end, { desc = "Messages half page up" })
    vim.keymap.set("n", "<C-M-d>", function()
      require("opencode").command("session.half.page.down")
    end, { desc = "Messages half page down" })
  end,
}
