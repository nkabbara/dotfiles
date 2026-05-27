return {
  name = "custom-workflow",
  dir = vim.fn.stdpath("config"),
  lazy = false,
  config = function()
    require("custom.workflow").workspace.setup({
      copy_files = {
        source_branch = "main",
        paths = {
          "config/master.key",
        },
      },
      delete_workspace = {
        merged_into = "origin/main",
        fetch_remote = "origin",
      },
    })
  end,
}
