-- Run from the repo root:
--   XDG_CACHE_HOME=$PWD/.cache nvim --headless -u NONE -c "lua dofile('scripts/run_splitasm_tests.lua')"

local function current_source_path()
    local source = debug.getinfo(1, "S").source
    return source:sub(1, 1) == "@" and source:sub(2) or source
end

local repo_root = vim.fn.fnamemodify(current_source_path(), ":h:h")
package.path = table.concat({
    repo_root .. "/lua/?.lua",
    repo_root .. "/lua/?/init.lua",
    package.path,
}, ";")

local parser_tests = require("splitasm.tests.parser")
local smoke_tests = require("splitasm.tests.smoke")

local function main()
    parser_tests.run()
    smoke_tests.run()
    io.stdout:write("splitasm test suite passed\n")
    vim.cmd("qa!")
end

local ok, err = xpcall(main, debug.traceback)

if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
end
