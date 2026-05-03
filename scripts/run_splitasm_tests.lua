-- Run from the repo root:
--   XDG_CACHE_HOME=$PWD/.cache nvim --headless -u NONE -c "lua dofile('scripts/run_splitasm_tests.lua')"

local function current_script_path()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        return vim.fs.normalize(source:sub(2))
    end

    return vim.fs.normalize(source)
end

local function config_root_from_script()
    local script_dir = vim.fs.dirname(current_script_path())
    return vim.fs.normalize(vim.fs.joinpath(script_dir, ".."))
end

local function setup_runtime(root)
    vim.opt.rtp:prepend(root)
    package.path = table.concat({
        vim.fs.joinpath(root, "lua", "?.lua"),
        vim.fs.joinpath(root, "lua", "?", "init.lua"),
        package.path,
    }, ";")
end

setup_runtime(config_root_from_script())

local parser_tests = require("splitasm.tests.parser")
local runtime_tests = require("splitasm.tests.runtime")
local smoke_tests = require("splitasm.tests.smoke")

local function main()
    parser_tests.run()
    runtime_tests.run()
    smoke_tests.run()
    io.stdout:write("splitasm test suite passed\n")
    vim.cmd("qa!")
end

local ok, err = xpcall(main, debug.traceback)

if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
end
