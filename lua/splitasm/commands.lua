local M = {}

local registered = false

local function create_command(name, callback, opts)
    if vim.fn.exists(":" .. name) == 2 then
        return
    end

    vim.api.nvim_create_user_command(name, callback, opts)
end

function M.setup(splitasm)
    if registered then
        return
    end

    create_command("SplitAsmOpen", function(opts)
        splitasm.open(opts.args)
    end, {
        desc = "Open the SplitAsm assembly view for the configured or provided executable",
        nargs = "?",
    })

    create_command("SplitAsm", function(opts)
        splitasm.open(opts.args)
    end, {
        desc = "Alias for :SplitAsmOpen",
        nargs = "?",
    })

    create_command("SplitAsmSetup", function()
        splitasm.setup_wizard()
    end, {
        desc = "Run guided SplitAsm setup for build and executable settings",
    })

    create_command("SplitAsmConfig", function()
        splitasm.show_config()
        splitasm.configure()
    end, {
        desc = "Show SplitAsm settings, then prompt for updates",
    })

    create_command("SplitAsmToggleSync", function()
        splitasm.toggle_auto_sync({ notify = true })
    end, {
        desc = "Toggle automatic synchronization between source and assembly",
    })

    create_command("SplitAsmToggleLineNumbers", function()
        local enabled = splitasm.toggle_line_numbers()
        vim.notify(
            enabled and "SplitAsm line numbers enabled" or "SplitAsm line numbers disabled",
            vim.log.levels.INFO,
            { title = "splitasm" }
        )
    end, {
        desc = "Toggle line number column in assembly view",
    })

    create_command("SplitAsmToggleHideAddress", function()
        local enabled = splitasm.toggle_hide_address()
        vim.notify(
            enabled and "SplitAsm addresses hidden" or "SplitAsm addresses shown",
            vim.log.levels.INFO,
            { title = "splitasm" }
        )
    end, {
        desc = "Toggle assembly address visibility",
    })

    registered = true
end

return M
