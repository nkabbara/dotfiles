return {
  "nkabbara/onmyterm.nvim",
  config = function(_, opts)
    require("onmyterm").setup(opts)

    local terminal_border_group = "OnMyTermTerminalModeBorder"
    local terminal_border_color = "#6c7086"

    local function hl_color(group, key)
      local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group })
      if ok and hl and hl[key] then
        return string.format("#%06x", hl[key])
      end
    end

    local function apply_terminal_border_color()
      vim.api.nvim_set_hl(0, terminal_border_group, {
        fg = terminal_border_color,
        bg = hl_color("Normal", "bg") or "#000000",
      })
    end

    local group = vim.api.nvim_create_augroup("custom-onmyterm-terminal-border", { clear = true })
    vim.api.nvim_create_autocmd({ "TermOpen", "TermEnter", "ColorScheme" }, {
      group = group,
      callback = function()
        vim.schedule(apply_terminal_border_color)
      end,
    })

    apply_terminal_border_color()
  end,
}
