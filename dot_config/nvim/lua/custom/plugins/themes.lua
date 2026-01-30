return {
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        config = function()
            require("catppuccin").setup({
                color_overrides = {
                    all = {
                        text = "#C5C9C7",
                    },
                },
            })
            vim.cmd.colorscheme("dracula")
        end,
    },
    { "ellisonleao/gruvbox.nvim", priority = 1000, config = true, opts = {} },
    {
        "webhooked/kanso.nvim",
        lazy = false,
        priority = 1000, -- Make sure to load this before all the other start plugins.
        config = function()
            ---@diagnostic disable-next-line: missing-fields
            require("kanso").setup({
                commentStyle = { italic = true },
            })
        end,
    },
    {
        { "Mofiqul/dracula.nvim" },
        {
            "LazyVim/LazyVim",
            opts = {
                colorscheme = "dracula",
            },
            config = function() end,
        },
    },
    {
        "folke/tokyonight.nvim",
        lazy = false,
        priority = 1000,
        opts = {},
    },
}
