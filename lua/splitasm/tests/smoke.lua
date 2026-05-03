package.path = "/home/nick/.config/nvim/lua/?.lua;/home/nick/.config/nvim/lua/?/init.lua;" .. package.path

local splitasm = require("splitasm")
local splitasm_config = require("splitasm.config")
local splitasm_state = require("splitasm.state")

local M = {}

local ROOT = "/home/nick/.config/nvim"
local TMP_ROOT = vim.fn.stdpath("data") .. "/splitasm-tests"

local function assert_truthy(value, message)
    if not value then
        error(message or "assertion failed")
    end
    return value
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)))
    end
end

local function assert_match(value, pattern, message)
    if type(value) ~= "string" or not value:match(pattern) then
        error((message or "value did not match pattern") .. string.format(" (pattern=%s actual=%s)", pattern, tostring(value)))
    end
end

local function assert_nil(value, message)
    if value ~= nil then
        error((message or "expected nil") .. string.format(" (actual=%s)", tostring(value)))
    end
end

local function command_names()
    return vim.api.nvim_get_commands({ builtin = false })
end

local function count_keys(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function with_mock_runtime(mock_runtime, callback)
    local original_runtime = package.loaded["splitasm.runtime"]
    package.loaded["splitasm.runtime"] = mock_runtime

    local ok, err = xpcall(callback, debug.traceback)

    package.loaded["splitasm.runtime"] = original_runtime
    if original_runtime == nil then
        package.loaded["splitasm.runtime"] = nil
    end

    if not ok then
        error(err)
    end
end

local function with_captured_notify(callback)
    local original_notify = vim.notify
    local original_notify_once = vim.notify_once
    local messages = {}

    local function capture(message, level, opts)
        messages[#messages + 1] = { message = message, level = level, opts = opts }
    end

    vim.notify = capture
    vim.notify_once = capture

    local ok, result_or_err = xpcall(function()
        return callback(messages)
    end, debug.traceback)

    vim.notify = original_notify
    vim.notify_once = original_notify_once

    if not ok then
        error(result_or_err)
    end

    return result_or_err
end

local function cleanup_splitasm()
    local state = splitasm_state.get()

    if state.asm_win and vim.api.nvim_win_is_valid(state.asm_win) then
        pcall(vim.api.nvim_win_close, state.asm_win, true)
    end
    if state.asm_buf and vim.api.nvim_buf_is_valid(state.asm_buf) then
        pcall(vim.api.nvim_buf_delete, state.asm_buf, { force = true })
    end

    splitasm_state.cleanup(state.augroup)
    if #vim.api.nvim_list_wins() > 1 then
        vim.cmd("only")
    end
end

local function write_source_file(name, lines)
    vim.fn.mkdir(TMP_ROOT, "p")
    local path = string.format("%s/%s-%d.c", TMP_ROOT, name, vim.uv.hrtime())
    vim.fn.writefile(lines, path)
    return path
end

local function test_setup_registers_publishable_commands_and_aliases()
    cleanup_splitasm()

    -- Arrange
    local expected_commands = {
        "SplitAsm",
        "SplitAsmOpen",
        "SplitAsmSetup",
        "SplitAsmConfig",
        "SplitAsmToggleSync",
    }
    local spec = dofile(ROOT .. "/lua/plugins/splitasm.lua")
    local seen_args = {}
    local original_open = splitasm.open

    -- Act
    splitasm.setup({ auto_sync = true, clean_asm = true })
    splitasm.open = function(arg)
        seen_args[#seen_args + 1] = arg
    end
    vim.cmd("SplitAsm ./demo-a.out")
    vim.cmd("SplitAsmOpen ./demo-b.out")
    splitasm.open = original_open

    -- Assert
    local commands = command_names()
    for _, name in ipairs(expected_commands) do
        assert_truthy(commands[name], "missing command: " .. name)
    end
    assert_eq(#spec.cmd, #expected_commands, "lazy command surface mismatch")
    for index, name in ipairs(expected_commands) do
        assert_eq(spec.cmd[index], name, "lazy command ordering mismatch")
    end
    assert_eq(seen_args[1], "./demo-a.out", "SplitAsm alias should pass the provided path")
    assert_eq(seen_args[2], "./demo-b.out", "SplitAsmOpen should pass the provided path")
end

local function test_setup_is_idempotent_after_registration()
    cleanup_splitasm()

    -- Arrange
    splitasm.setup({ auto_sync = true, clean_asm = false })
    local command_count_before = count_keys(command_names())

    -- Act
    splitasm.setup({ auto_sync = false, clean_asm = true })

    -- Assert
    local commands = command_names()
    assert_eq(count_keys(commands), command_count_before, "setup should not register duplicate commands")
    assert_eq(splitasm_config.get().auto_sync, false, "setup should still refresh configuration on later calls")
    assert_eq(splitasm_config.get().clean_asm, true, "setup should update later configuration values")
end

local function test_config_command_shows_settings_before_prompting()
    cleanup_splitasm()

    -- Arrange
    splitasm.setup({ auto_sync = true, clean_asm = false })
    local calls = {}
    local original_show_config = splitasm.show_config
    local original_configure = splitasm.configure

    splitasm.show_config = function()
        calls[#calls + 1] = "config"
    end
    splitasm.configure = function()
        calls[#calls + 1] = "configure"
    end

    -- Act
    vim.cmd("SplitAsmConfig")

    -- Cleanup
    splitasm.show_config = original_show_config
    splitasm.configure = original_configure

    -- Assert
    assert_eq(calls[1], "config", "SplitAsmConfig should show saved settings first")
    assert_eq(calls[2], "configure", "SplitAsmConfig should still prompt for updates")
end

local function test_setup_command_runs_guided_wizard()
    cleanup_splitasm()

    -- Arrange
    splitasm.setup({ auto_sync = true, clean_asm = false })
    local calls = {}
    local original_setup_wizard = splitasm.setup_wizard

    splitasm.setup_wizard = function()
        calls[#calls + 1] = "setup_wizard"
    end

    -- Act
    vim.cmd("SplitAsmSetup")

    -- Cleanup
    splitasm.setup_wizard = original_setup_wizard

    -- Assert
    assert_eq(calls[1], "setup_wizard", "SplitAsmSetup should launch the guided setup flow")
end

local function test_toggle_sync_command_updates_config_and_notifies()
    cleanup_splitasm()

    -- Arrange
    splitasm.setup({ auto_sync = true, clean_asm = false })

    -- Act + Assert
    with_captured_notify(function(messages)
        vim.cmd("SplitAsmToggleSync")
        assert_eq(splitasm_config.get().auto_sync, false, "SplitAsmToggleSync should disable auto-sync on first toggle")
        assert_match(messages[1] and messages[1].message, "auto%-sync disabled", "toggle should explain the disabled state")

        vim.cmd("SplitAsmToggleSync")
        assert_eq(splitasm_config.get().auto_sync, true, "SplitAsmToggleSync should re-enable auto-sync on second toggle")
        assert_match(messages[2] and messages[2].message, "auto%-sync enabled", "toggle should explain the enabled state")
    end)
end

local function test_setup_validates_publishable_user_config()
    cleanup_splitasm()

    -- Arrange + Act + Assert
    local ok, err = pcall(splitasm.setup, "bad-config")
    assert_eq(ok, false, "setup should reject non-table config values")
    assert_match(err, "setup%(%) expects a table or nil", "setup should describe invalid config type")

    ok, err = pcall(splitasm.setup, { auto_sync = "yes" })
    assert_eq(ok, false, "setup should reject non-boolean auto_sync values")
    assert_match(err, "auto_sync must be a boolean", "setup should describe invalid auto_sync values")

    ok, err = pcall(splitasm.setup, { compiler_cmd = 42 })
    assert_eq(ok, false, "setup should reject non-string compiler commands")
    assert_match(err, "compiler_cmd must be a string or nil", "setup should describe invalid compiler_cmd values")
end

local function test_open_returns_early_when_runtime_has_no_output()
    cleanup_splitasm()

    -- Arrange
    local source_path = write_source_file("no-output", { "int main(void) {", "  return 0;", "}" })
    vim.cmd("edit " .. vim.fn.fnameescape(source_path))
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    -- Act
    with_mock_runtime({
        load_asm_session = function()
            return nil
        end,
    }, function()
        with_captured_notify(function()
            splitasm.setup({ auto_sync = true, clean_asm = true })
            splitasm.open("./missing-binary")
        end)
    end)

    -- Assert
    local state = splitasm_state.get()
    assert_eq(state.current_file, source_path, "open should still track the active source file")
    assert_eq(next(state.file_line_maps), nil, "open should not keep stale source mappings on failure")
    assert_eq(next(state.asm_to_source), nil, "open should not keep stale asm mappings on failure")
    assert_nil(state.augroup, "open should not install sync autocmds on failure")
    assert_nil(state.asm_buf, "open should not create an asm buffer when runtime returns no output")
end

local function test_open_renders_filtered_output_and_syncs_from_source_cursor()
    cleanup_splitasm()

    -- Arrange
    local source_path = write_source_file("open-flow", {
        "int helper(void) {",
        "  int x = 1;",
        "  x += 1;",
        "  return x;",
        "}",
    })
    local runtime_calls = {}
    local asm_output = table.concat({
        source_path .. ":2",
        "0000000000000000 <main()>:",
        "  0000: mov eax,ebx",
        source_path .. ":4",
        "  0008: ret",
    }, "\n")

    vim.cmd("edit " .. vim.fn.fnameescape(source_path))
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local state = splitasm_state.get()
    state.file_line_maps = { stale = { value = true } }
    state.asm_to_source = { [99] = 99 }
    state.asm_to_file = { [99] = "stale" }
    state.current_file = "stale"

    -- Act
    with_mock_runtime({
        load_asm_session = function(opts)
            runtime_calls[#runtime_calls + 1] = vim.deepcopy(opts)
            return {
                asm_output = asm_output,
                full_exec_path = "/tmp/demo-bin",
            }
        end,
    }, function()
        with_captured_notify(function()
            splitasm.setup({ auto_sync = true, clean_asm = true })
            splitasm.open("./demo-bin")
        end)
    end)

    -- Assert
    assert_eq(#runtime_calls, 1, "runtime should be invoked exactly once")
    assert_eq(runtime_calls[1].exec_path_override, "./demo-bin", "runtime should receive the executable override")
    assert_eq(runtime_calls[1].source_path, source_path, "runtime should receive the active source path")

    assert_truthy(state.asm_buf and vim.api.nvim_buf_is_valid(state.asm_buf), "open should create an asm buffer")
    assert_truthy(state.asm_win and vim.api.nvim_win_is_valid(state.asm_win), "open should create an asm split")
    assert_truthy(state.augroup ~= nil, "open should register sync autocmds")
    assert_eq(state.current_file, source_path, "open should store the active source file")
    assert_eq(vim.bo[state.asm_buf].filetype, "asm", "asm buffer should use asm filetype")
    assert_eq(vim.bo[state.asm_buf].modifiable, false, "asm buffer should be non-modifiable")
    assert_eq(vim.bo[state.asm_buf].readonly, true, "asm buffer should be readonly")

    local asm_lines = vim.api.nvim_buf_get_lines(state.asm_buf, 0, -1, false)
    assert_eq(#asm_lines, 3, "open should render the cleaned asm output")
    assert_eq(asm_lines[1], "main():", "open should normalize function labels")
    assert_eq(asm_lines[2], "  mov eax, ebx", "open should normalize instruction spacing")
    assert_eq(asm_lines[3], "  ret", "open should render later instructions")
    assert_eq(state.file_line_maps[source_path][2].start_line, 2, "line 2 should map to the first instruction")
    assert_eq(state.file_line_maps[source_path][4].start_line, 3, "line 4 should map to the return instruction")
    assert_eq(vim.api.nvim_win_get_cursor(state.asm_win)[1], 2, "open should jump to the current source mapping")

    vim.api.nvim_set_current_win(state.source_win)
    vim.api.nvim_win_set_cursor(state.source_win, { 4, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
    assert_eq(vim.api.nvim_win_get_cursor(state.asm_win)[1], 3, "source cursor movement should sync the asm cursor after open")
end

local function test_open_keeps_existing_view_when_refresh_validation_fails()
    cleanup_splitasm()

    -- Arrange
    local source_path = write_source_file("refresh-preserve", {
        "int main(void) {",
        "  return 0;",
        "}",
    })
    local asm_output = table.concat({
        source_path .. ":1",
        "0000000000000000 <main()>:",
        "  0000: ret",
    }, "\n")

    vim.cmd("edit " .. vim.fn.fnameescape(source_path))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    with_mock_runtime({
        load_asm_session = function()
            return {
                asm_output = asm_output,
                full_exec_path = "/tmp/demo-bin",
            }
        end,
        inspect = function(opts)
            return {
                config = opts.config,
                cwd = vim.uv.cwd(),
                source_path = opts.source_path,
                exec_path_override = opts.exec_path_override,
                configured_path = nil,
                detected_candidates = {},
                resolved_exec_path = "/tmp/demo-bin",
                full_exec_path = "/tmp/demo-bin",
                executable_exists = true,
                objdump_available = true,
            }
        end,
        status_lines = function(status)
            return { "Executable (override): " .. status.resolved_exec_path }
        end,
    }, function()
        splitasm.setup({ auto_sync = true, clean_asm = true })
        splitasm.open("./demo-bin")
    end)

    local state = splitasm_state.get()
    local original_asm_buf = state.asm_buf
    local original_asm_win = state.asm_win
    local original_augroup = state.augroup
    local original_file = state.current_file
    local original_lines = vim.api.nvim_buf_get_lines(original_asm_buf, 0, -1, false)

    vim.api.nvim_set_current_win(state.source_win)

    -- Act
    with_mock_runtime({
        load_asm_session = function()
            return nil
        end,
        inspect = function(opts)
            return {
                config = opts.config,
                cwd = vim.uv.cwd(),
                source_path = opts.source_path,
                exec_path_override = opts.exec_path_override,
                configured_path = nil,
                detected_candidates = {},
                resolved_exec_path = nil,
                full_exec_path = nil,
                executable_exists = false,
                objdump_available = false,
            }
        end,
        status_lines = function()
            return { "objdump: missing from PATH" }
        end,
    }, function()
        with_captured_notify(function()
            splitasm.open("./missing-bin")
        end)
    end)

    -- Assert
    assert_eq(state.asm_buf, original_asm_buf, "failed refresh should keep the current asm buffer")
    assert_eq(state.asm_win, original_asm_win, "failed refresh should keep the current asm window")
    assert_eq(state.augroup, original_augroup, "failed refresh should keep sync autocmds active")
    assert_eq(state.current_file, original_file, "failed refresh should keep the current source file")
    assert_eq(vim.api.nvim_buf_get_lines(original_asm_buf, 0, -1, false)[1], original_lines[1], "failed refresh should preserve asm contents")
end

function M.run()
    test_setup_registers_publishable_commands_and_aliases()
    test_setup_is_idempotent_after_registration()
    test_config_command_shows_settings_before_prompting()
    test_setup_command_runs_guided_wizard()
    test_toggle_sync_command_updates_config_and_notifies()
    test_setup_validates_publishable_user_config()
    test_open_returns_early_when_runtime_has_no_output()
    test_open_renders_filtered_output_and_syncs_from_source_cursor()
    test_open_keeps_existing_view_when_refresh_validation_fails()
    cleanup_splitasm()
end

local function run_as_script()
    local ok, err = xpcall(M.run, debug.traceback)

    if ok then
        io.stdout:write("splitasm smoke tests passed\n")
        vim.cmd("qa!")
    else
        io.stderr:write(err .. "\n")
        vim.cmd("cquit 1")
    end
end

if ... == nil then
    run_as_script()
end

return M
