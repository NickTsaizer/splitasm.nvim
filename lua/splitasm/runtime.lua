local splitasm_config = require("splitasm.config")

local M = {}

local EXECUTABLE_SEARCH_DIRS = { ".", "build", "bin", "out", "dist" }
local FALLBACK_EXECUTABLE_NAMES = { "a.out", "main" }
local OBJDUMP_CMD = "objdump"

local function notify(message, level)
    vim.notify(message, level, { title = "splitasm" })
end

local function notify_once(message, level)
    vim.notify_once(message, level, { title = "splitasm" })
end

local function run_system_command(command)
    local output = vim.fn.system(command)
    return {
        ok = vim.v.shell_error == 0,
        output = output,
    }
end

local function normalize_candidate(value)
    return splitasm_config.normalize_path(value)
end

local function executable_help_lines()
    return {
        "Recover by doing one of the following:",
        "- Run :SplitAsmSetup for guided configuration",
        "- Run :SplitAsmConfig to update the saved build command or executable path",
        "- Run :SplitAsmOpen ./path/to/program to inspect a specific executable once",
    }
end

local function executable_origin_label(status)
    if status.exec_path_override then
        return "override"
    end

    if status.configured_path then
        return "configured"
    end

    return "auto-detected"
end

local function format_command_error(prefix, output)
    local details = vim.trim(output or "")
    if details == "" then
        return prefix
    end

    return prefix .. "\n\nDetails:\n" .. details
end

local function add_candidate(candidates, seen, candidate)
    local normalized = normalize_candidate(candidate)
    if not normalized or seen[normalized] then
        return
    end

    seen[normalized] = true
    candidates[#candidates + 1] = normalized
end

local function get_source_stem(source_path)
    local normalized_path = normalize_candidate(source_path)
    if not normalized_path then
        return nil
    end

    return vim.fn.fnamemodify(normalized_path, ":t:r")
end

local function build_detected_candidates(source_path, cwd)
    local candidates = {}
    local seen = {}
    local project_name = vim.fn.fnamemodify(cwd, ":t")
    local source_stem = get_source_stem(source_path)
    local executable_names = { source_stem, project_name }

    for _, fallback_name in ipairs(FALLBACK_EXECUTABLE_NAMES) do
        executable_names[#executable_names + 1] = fallback_name
    end

    for _, name in ipairs(executable_names) do
        if name then
            for _, dir in ipairs(EXECUTABLE_SEARCH_DIRS) do
                local prefix = dir == "." and "./" or ("./" .. dir .. "/")
                add_candidate(candidates, seen, prefix .. name)
            end
        end
    end

    return candidates
end

local function first_executable_candidate(candidates)
    for _, candidate in ipairs(candidates) do
        local full_path = vim.fn.expand(candidate)
        if vim.fn.executable(full_path) == 1 then
            return candidate
        end
    end
end

function M.resolve_executable_path(config, exec_path_override, source_path)
    local configured_path = normalize_candidate(exec_path_override) or normalize_candidate(config.executable_path)
    if configured_path then
        return configured_path
    end

    return first_executable_candidate(build_detected_candidates(source_path, vim.uv.cwd()))
end

function M.inspect(opts)
    local config = opts.config or {}
    local source_path = normalize_candidate(opts.source_path)
    local cwd = vim.uv.cwd()
    local exec_path_override = normalize_candidate(opts.exec_path_override)
    local configured_path = normalize_candidate(config.executable_path)
    local detected_candidates = build_detected_candidates(source_path, cwd)
    local resolved_exec_path = M.resolve_executable_path(config, exec_path_override, source_path)
    local full_exec_path = resolved_exec_path and vim.fn.expand(resolved_exec_path) or nil
    local executable_exists = full_exec_path ~= nil
        and (vim.fn.filereadable(full_exec_path) == 1 or vim.fn.executable(full_exec_path) == 1)

    return {
        config = config,
        cwd = cwd,
        source_path = source_path,
        exec_path_override = exec_path_override,
        configured_path = configured_path,
        detected_candidates = detected_candidates,
        resolved_exec_path = resolved_exec_path,
        full_exec_path = full_exec_path,
        executable_exists = executable_exists,
        objdump_available = vim.fn.executable(OBJDUMP_CMD) == 1,
    }
end

function M.status_lines(status)
    local lines = {
        string.format("Working directory: %s", status.cwd),
        string.format("Source file: %s", status.source_path or "current buffer is not a file yet"),
        string.format("Build command: %s", status.config.compiler_cmd or "not set"),
        string.format("objdump: %s", status.objdump_available and "available" or "missing from PATH"),
    }

    if status.resolved_exec_path and status.executable_exists then
        lines[#lines + 1] = string.format(
            "Executable (%s): %s",
            executable_origin_label(status),
            status.resolved_exec_path
        )
    elseif status.resolved_exec_path then
        lines[#lines + 1] = string.format(
            "Executable (%s): missing at %s",
            executable_origin_label(status),
            status.resolved_exec_path
        )
    else
        lines[#lines + 1] = "Executable: not resolved yet"
        if #status.detected_candidates > 0 then
            lines[#lines + 1] = "Auto-detect candidates: " .. table.concat(status.detected_candidates, ", ")
        end
    end

    return lines
end

function M.compile_if_needed(config)
    if not config.compiler_cmd then
        return true
    end

    notify("Running SplitAsm build command: " .. config.compiler_cmd, vim.log.levels.INFO)

    local compile_result = run_system_command(config.compiler_cmd)
    if compile_result.ok then
        notify("SplitAsm build command completed successfully.", vim.log.levels.INFO)
        return true
    end

    notify(
        format_command_error(
            "SplitAsm could not build your project. Fix the build command or executable path with :SplitAsmConfig, then try :SplitAsmOpen again.",
            compile_result.output
        ),
        vim.log.levels.ERROR
    )
    return false
end

function M.ensure_executable_exists(exec_path)
    local full_exec_path = vim.fn.expand(exec_path)
    if vim.fn.filereadable(full_exec_path) == 1 or vim.fn.executable(full_exec_path) == 1 then
        return full_exec_path
    end

    local lines = {
        "SplitAsm could not find the configured executable.",
        "Configured path: " .. exec_path,
        "Expanded path: " .. full_exec_path,
    }
    vim.list_extend(lines, executable_help_lines())

    notify(table.concat(lines, "\n"), vim.log.levels.ERROR)
end

function M.prepare_executable(config, exec_path_override, source_path)
    if vim.fn.executable(OBJDUMP_CMD) ~= 1 then
        notify_once(
            "SplitAsm requires `objdump` to read assembly output. Install GNU binutils (or an equivalent package that provides objdump), then run :SplitAsmOpen again.",
            vim.log.levels.ERROR
        )
        return nil
    end

    if not M.compile_if_needed(config) then
        return nil
    end

    local status = M.inspect({
        config = config,
        exec_path_override = exec_path_override,
        source_path = source_path,
    })

    if not status.resolved_exec_path then
        local lines = {
            "SplitAsm did not find an executable to inspect.",
            "Auto-detection looked in the current working directory plus ./build, ./bin, ./out, and ./dist.",
            "You can still use SplitAsm without saved config by passing a path directly.",
        }
        vim.list_extend(lines, executable_help_lines())

        notify(table.concat(lines, "\n"), vim.log.levels.ERROR)
        return nil
    end

    return M.ensure_executable_exists(status.resolved_exec_path)
end

function M.get_objdump_output(full_exec_path)
    if vim.fn.executable(OBJDUMP_CMD) ~= 1 then
        notify_once(
            "SplitAsm requires `objdump` to read assembly output. Install GNU binutils (or an equivalent package that provides objdump), then run :SplitAsmOpen again.",
            vim.log.levels.ERROR
        )
        return nil
    end

    local objdump_cmd = string.format(
        "objdump -d -Mintel --no-show-raw-insn -l -C %s 2>&1",
        vim.fn.shellescape(full_exec_path)
    )
    local dump_result = run_system_command(objdump_cmd)
    if dump_result.ok then
        return dump_result.output
    end

    notify(
        format_command_error(
            "SplitAsm failed to read assembly with objdump. Confirm the executable exists, is readable, and was built for your current toolchain.",
            dump_result.output
        ),
        vim.log.levels.ERROR
    )
end

function M.load_asm_output(opts)
    local full_exec_path = M.prepare_executable(opts.config, opts.exec_path_override, opts.source_path)
    if not full_exec_path then
        return nil
    end

    return M.get_objdump_output(full_exec_path)
end

function M.load_asm_session(opts)
    local full_exec_path = M.prepare_executable(opts.config, opts.exec_path_override, opts.source_path)
    if not full_exec_path then
        return nil
    end

    local asm_output = M.get_objdump_output(full_exec_path)
    if not asm_output then
        return nil
    end

    return {
        asm_output = asm_output,
        full_exec_path = full_exec_path,
    }
end

return M
