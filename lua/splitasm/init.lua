local commands = require("splitasm.commands")
local splitasm_config = require("splitasm.config")
local parser = require("splitasm.parser")
local splitasm_state = require("splitasm.state")
local sync = require("splitasm.sync")
local view = require("splitasm.view")

local M = {}

local state = splitasm_state.get()
local function notify(message, level, opts)
    vim.notify(message, level or vim.log.levels.INFO, vim.tbl_extend("force", { title = "splitasm" }, opts or {}))
end

local function notify_once(message, level, opts)
    vim.notify_once(message, level or vim.log.levels.INFO, vim.tbl_extend("force", { title = "splitasm" }, opts or {}))
end

local function get_config()
    return splitasm_config.get()
end

local function config_summary_lines(config)
    return splitasm_config.describe(config)
end

local function notify_runtime_load_error(err)
    notify(
        "Failed to load SplitAsm runtime. Reinstall or update the plugin, then restart Neovim.\n\nDetails: " .. err,
        vim.log.levels.ERROR
    )
end

local function get_runtime_module()
    local ok, runtime = pcall(require, "splitasm.runtime")
    if ok then
        return runtime
    end

    notify_runtime_load_error(runtime)
end

local function toggle_auto_sync(should_notify)
    local enabled = splitasm_config.toggle_auto_sync()
    if should_notify then
        local message = enabled
                and "SplitAsm auto-sync enabled. Cursor moves now keep the source and assembly views aligned."
            or "SplitAsm auto-sync disabled. Run :SplitAsmToggleSync to re-enable it."
        notify(message, vim.log.levels.INFO)
    end
    return enabled
end

local function notify_config_updated(config)
    local lines = { "SplitAsm configuration updated." }
    vim.list_extend(lines, config_summary_lines(config))
    lines[#lines + 1] = "Next step: run :SplitAsmOpen to inspect the detected executable, or pass a path like :SplitAsmOpen ./build/app."

    notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

local function apply_config_update(partial_config)
    local updated_config = splitasm_config.update(partial_config)
    notify_config_updated(updated_config)
    return updated_config
end

local function prompt_for_executable_path(config, partial_config)
    vim.ui.input({
        prompt = "Executable path (optional; leave blank to auto-detect from cwd): ",
        default = config.executable_path or "",
    }, function(exec_path)
        if exec_path == nil then
            return
        end

        partial_config.executable_path = splitasm_config.normalize_path(exec_path)
        apply_config_update(partial_config)
    end)
end

local function prompt_for_compiler_command(config, opts)
    local prompt = opts.setup_mode
            and "Build command (optional; e.g. make, cargo build --release, cmake --build build): "
        or "Build command (optional; run before opening assembly): "

    vim.ui.input({
        prompt = prompt,
        default = config.compiler_cmd or "",
    }, function(compiler_cmd)
        if compiler_cmd == nil then
            return
        end

        prompt_for_executable_path(config, {
            compiler_cmd = splitasm_config.normalize_path(compiler_cmd),
        })
    end)
end

local function notify_open_hint_if_needed(config, exec_path_override)
    if exec_path_override or splitasm_config.has_user_configuration(config) then
        return
    end

    notify_once(
        "No SplitAsm executable is configured yet. Run :SplitAsmSetup for guided setup, or open a program directly with :SplitAsmOpen ./path/to/program.",
        vim.log.levels.INFO
    )
end

function M.setup(user_config)
    splitasm_config.setup(user_config)
    commands.setup(M)
end

function M.toggle_auto_sync(opts)
    opts = opts or {}
    return toggle_auto_sync(opts.notify)
end

function M.toggle_line_numbers()
    local enabled = splitasm_config.toggle_line_numbers()
    return enabled
end

function M.toggle_hide_address()
    local enabled = splitasm_config.toggle_hide_address()
    return enabled
end

function M.configure()
    local config = get_config()
    prompt_for_compiler_command(config, { setup_mode = false })
end

function M.setup_wizard()
    local config = get_config()
    prompt_for_compiler_command(config, { setup_mode = true })
end

function M.show_config()
    notify(table.concat(config_summary_lines(get_config()), "\n"), vim.log.levels.INFO)
end

function M.open(exec_path_override)
    local config = get_config()
    notify_open_hint_if_needed(config, exec_path_override)
    local runtime = get_runtime_module()
    if not runtime then
        return
    end

    local source_win, source_buf = view.get_source_context(state)
    local current_line = vim.api.nvim_win_get_cursor(source_win)[1]
    local current_file = vim.api.nvim_buf_get_name(source_buf)
    local has_active_view = state.asm_win and vim.api.nvim_win_is_valid(state.asm_win)

    if not has_active_view then
        state.source_win = source_win
        state.source_buf = source_buf
        state.current_file = current_file
    end

    local session = runtime.load_asm_session({
        config = config,
        exec_path_override = exec_path_override,
        source_path = current_file,
    })
    if not session then
        return
    end

    if state.augroup then
        pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    end

    splitasm_state.reset_open_state()
    state.source_win = source_win
    state.source_buf = source_buf
    state.current_file = current_file

    local asm_lines = vim.split(session.asm_output, "\n", { plain = true, trimempty = false })

    local parsed = parser.parse(asm_lines, {
        clean_asm = config.hide_address,
        source_path_mappings = config.source_path_mappings,
        current_source_path = current_file,
    })
    local filtered_lines = splitasm_state.apply_parsed_asm(parsed)

    view.ensure_asm_buffer(state)
    if not view.render_asm_buffer(state, filtered_lines, config) then
        return
    end

    view.jump_to_initial_position(state, current_line)
    sync.setup_autocmds(state, {
        get_config = get_config,
        focus_source_location = view.focus_source_location,
        toggle_auto_sync = toggle_auto_sync,
    })
    view.set_split_keymaps(state, {
        refresh = function()
            M.open(exec_path_override)
        end,
        toggle_sync = function()
            toggle_auto_sync(true)
        end,
    })

    notify(
        table.concat({
            "SplitAsm open.",
            "Loaded executable: " .. session.full_exec_path,
            "Press 'r' to refresh and 's' to toggle sync.",
        }, "\n"),
        vim.log.levels.INFO
    )
end

return M
