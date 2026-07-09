return {
  name = "custom-workflow",
  dir = vim.fn.stdpath("config"),
  lazy = false,
  config = function()
    require("custom.workflow").workspace.setup({
      ui = {
        keep_tabline_visible = true,
      },
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
