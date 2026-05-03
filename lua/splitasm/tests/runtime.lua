local function current_script_path()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        return vim.fs.normalize(source:sub(2))
    end

    return vim.fs.normalize(source)
end

local function config_root_from_script()
    local script_dir = vim.fs.dirname(current_script_path())
    return vim.fs.normalize(vim.fs.joinpath(script_dir, "..", "..", ".."))
end

local function prepend_lua_path(root)
    package.path = table.concat({
        vim.fs.joinpath(root, "lua", "?.lua"),
        vim.fs.joinpath(root, "lua", "?", "init.lua"),
        package.path,
    }, ";")
end

prepend_lua_path(config_root_from_script())

local runtime = require("splitasm.runtime")

local M = {}

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)))
    end
end

local function assert_truthy(value, message)
    if not value then
        error(message or "assertion failed")
    end

    return value
end

local function assert_contains(list, expected, message)
    for _, item in ipairs(list) do
        if item == expected then
            return
        end
    end

    error((message or "missing expected item") .. string.format(" (expected=%s)", tostring(expected)))
end

local function assert_not_contains(list, unexpected, message)
    for _, item in ipairs(list) do
        if item == unexpected then
            error((message or "found unexpected item") .. string.format(" (unexpected=%s)", tostring(unexpected)))
        end
    end
end

local function with_mocked_runtime_env(mock, callback)
    local original_has = vim.fn.has
    local original_executable = vim.fn.executable
    local original_exepath = vim.fn.exepath
    local original_expand = vim.fn.expand
    local original_system = vim.fn.system
    local original_cwd = vim.uv.cwd
    local original_notify = vim.notify
    local original_notify_once = vim.notify_once

    vim.fn.has = mock.has or original_has
    vim.fn.executable = mock.executable or original_executable
    vim.fn.exepath = mock.exepath or original_exepath
    vim.fn.expand = mock.expand or original_expand
    vim.fn.system = mock.system or original_system
    vim.uv.cwd = mock.cwd or original_cwd
    vim.notify = mock.notify or original_notify
    vim.notify_once = mock.notify_once or original_notify_once

    local ok, result_or_err = xpcall(callback, debug.traceback)

    vim.fn.has = original_has
    vim.fn.executable = original_executable
    vim.fn.exepath = original_exepath
    vim.fn.expand = original_expand
    vim.fn.system = original_system
    vim.uv.cwd = original_cwd
    vim.notify = original_notify
    vim.notify_once = original_notify_once

    if not ok then
        error(result_or_err)
    end

    return result_or_err
end

local function test_inspect_prefers_windows_executable_candidates_and_tracks_gnu_backend()
    with_mocked_runtime_env({
        has = function(name)
            if name == "win32" or name == "win64" then
                return 1
            end

            return 0
        end,
        executable = function(path)
            if path == "./build/main.exe" then
                return 1
            end

            return 0
        end,
        exepath = function(path)
            if path == "objdump" or path == "objdump.exe" then
                return "C:/tools/objdump.exe"
            end

            return ""
        end,
        expand = function(path)
            return path
        end,
        cwd = function()
            return "C:/work/demo"
        end,
    }, function()
        local status = runtime.inspect({ config = {}, source_path = "src/main.c" })

        assert_eq(status.resolved_exec_path, "./build/main.exe", "windows auto-detect should resolve .exe output")
        assert_contains(status.detected_candidates, "./main.exe", "windows candidate list should include root .exe")
        assert_contains(status.detected_candidates, "./build/main.exe", "windows candidate list should include build .exe")
        assert_eq(status.objdump_backend.id, "gnu-objdump", "gnu objdump should be selected when available")
        assert_eq(status.objdump_backend.command, "C:/tools/objdump.exe", "gnu backend path should be resolved")
        assert_truthy(status.objdump_candidates[1].available, "status should expose available backend candidates")
    end)
end

local function test_inspect_keeps_unix_candidates_and_can_fall_back_to_llvm_backend()
    with_mocked_runtime_env({
        has = function()
            return 0
        end,
        executable = function(path)
            if path == "./build/main" then
                return 1
            end

            return 0
        end,
        exepath = function(path)
            if path == "llvm-objdump" or path == "llvm-objdump.exe" then
                return "/usr/bin/llvm-objdump"
            end

            return ""
        end,
        expand = function(path)
            return path
        end,
        cwd = function()
            return "/tmp/demo"
        end,
    }, function()
        local status = runtime.inspect({ config = {}, source_path = "src/main.c" })

        assert_eq(status.resolved_exec_path, "./build/main", "unix auto-detect should preserve extensionless executable")
        assert_not_contains(status.detected_candidates, "./build/main.exe", "unix candidate list should not add .exe variants")
        assert_eq(status.objdump_backend.id, "llvm-objdump", "llvm backend should be selected when GNU objdump is missing")

        local lines = runtime.status_lines(status)
        assert_contains(lines, "objdump: available", "status lines should keep legacy objdump availability output")
        assert_truthy(lines[5] and lines[5]:match("objdump backend: LLVM objdump"), "status lines should expose the selected backend")
    end)
end

local function test_get_objdump_output_uses_backend_specific_argument_shapes()
    with_mocked_runtime_env({
        has = function(name)
            if name == "win32" or name == "win64" then
                return 1
            end

            return 0
        end,
        executable = function()
            return 0
        end,
        exepath = function(path)
            if path == "llvm-objdump" or path == "llvm-objdump.exe" then
                return "C:/LLVM/bin/llvm-objdump.exe"
            end

            return ""
        end,
        expand = function(path)
            return path
        end,
        system = function(command)
            return command
        end,
    }, function()
        local command = runtime.get_objdump_output("C:/build/main.exe")

        assert_eq(command[1], "C:/LLVM/bin/llvm-objdump.exe", "llvm backend should run the resolved executable path")
        assert_eq(command[2], "-d", "llvm backend should disassemble")
        assert_eq(command[3], "-M", "llvm backend should use separated -M flag")
        assert_eq(command[4], "intel", "llvm backend should request intel syntax")
        assert_eq(command[#command], "C:/build/main.exe", "backend command should target the requested executable")
    end)
end

local function test_prepare_executable_reports_missing_backend_support_clearly()
    local captured_message = nil

    with_mocked_runtime_env({
        has = function(name)
            if name == "win32" or name == "win64" then
                return 1
            end

            return 0
        end,
        executable = function()
            return 0
        end,
        exepath = function()
            return ""
        end,
        expand = function(path)
            return path
        end,
        notify_once = function(message)
            captured_message = message
        end,
    }, function()
        captured_message = nil

        local result = runtime.prepare_executable({}, nil, "src/main.c")

        assert_eq(result, nil, "prepare_executable should stop when no backend is available")
        assert_truthy(captured_message, "missing backend should notify once")
        assert_truthy(
            captured_message:match("supported disassembler backend"),
            "missing backend message should explain the backend failure"
        )
        assert_truthy(
            captured_message:match("GNU objdump %[%s*objdump, objdump%.exe%s*%]"),
            "missing backend message should list GNU backend commands"
        )
        assert_truthy(
            captured_message:match("LLVM objdump %[%s*llvm%-objdump, llvm%-objdump%.exe%s*%]"),
            "missing backend message should list LLVM backend commands"
        )
        assert_truthy(
            captured_message:match("llvm%-objdump%.exe"),
            "missing backend message should include the Windows LLVM executable name"
        )
    end)
end

function M.run()
    test_inspect_prefers_windows_executable_candidates_and_tracks_gnu_backend()
    test_inspect_keeps_unix_candidates_and_can_fall_back_to_llvm_backend()
    test_get_objdump_output_uses_backend_specific_argument_shapes()
    test_prepare_executable_reports_missing_backend_support_clearly()
end

return M
