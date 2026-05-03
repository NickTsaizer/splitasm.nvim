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

    registered = true
end

return M
