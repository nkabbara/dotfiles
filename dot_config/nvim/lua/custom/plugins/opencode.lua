return {
  "nkabbara/opencode.nvim",
  branch = "feature/support-tab-context-upstream",
  name = "opencode.nvim",
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
    local workflow = require("custom.workflow")
    local opencode_workflow = workflow.win_manager
    local opencode_resize_group = vim.api.nvim_create_augroup("custom-opencode-resize", { clear = true })

    workflow.new_worktree.setup()

    vim.api.nvim_create_autocmd("VimResized", {
      group = opencode_resize_group,
      callback = function()
        vim.schedule(function()
          opencode_workflow.resize_layout(opencode_cmd)
        end)
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
      opencode_workflow.focus_workspace_win(opencode_cmd)
    end, { desc = "Focus workspace in AI workflow" })
    vim.keymap.set("n", "<leader>a", function()
      opencode_workflow.focus_opencode_win(opencode_cmd)
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
