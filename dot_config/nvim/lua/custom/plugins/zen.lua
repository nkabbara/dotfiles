-- Lua
return {
    "folke/zen-mode.nvim",
    opts = {
        window = {
            backdrop = 1,
            width = 0.50,
        },
    },
    config = function()
        vim.keymap.set("n", "<leader>z", function()
            require("zen-mode").toggle({
                window = {
                    backdrop = 1,
                    width = 0.40,
                },
            })
        end)
    end,
}
