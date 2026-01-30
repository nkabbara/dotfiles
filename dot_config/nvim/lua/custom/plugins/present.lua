return {
  dir = "~/dev/present.nvim",
  config = function()
    require("present").setup({
      executors = {
        js = require("present").set_executor("node"),
      },
    })
  end,
}
