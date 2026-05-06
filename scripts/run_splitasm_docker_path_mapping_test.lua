-- Run from the repo root:
--   XDG_CACHE_HOME=$PWD/.cache nvim --headless -u NONE -c "lua dofile('scripts/run_splitasm_docker_path_mapping_test.lua')"
-- Optional override:
--   SPLITASM_DOCKER_TEST_IMAGE=gcc:14 XDG_CACHE_HOME=$PWD/.cache nvim --headless -u NONE -c "lua dofile('scripts/run_splitasm_docker_path_mapping_test.lua')"

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

local ROOT = config_root_from_script()
setup_runtime(ROOT)

local runtime = require("splitasm.runtime")
local splitasm = require("splitasm")
local splitasm_state = require("splitasm.state")

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

local function run_command(command)
    local output = vim.fn.system(command)
    if vim.v.shell_error ~= 0 then
        error(output)
    end

    return output
end

local function try_run_command(command)
    local output = vim.fn.system(command)
    return {
        ok = vim.v.shell_error == 0,
        output = output,
    }
end

local function skip(message)
    io.stdout:write("splitasm docker path-mapping test skipped: " .. message .. "\n")
    vim.cmd("qa!")
end

local function fixture_paths()
    local fixture_dir = vim.fs.joinpath(ROOT, "tests", "fixtures", "docker-path-map")
    return {
        fixture_dir = fixture_dir,
        source_path = vim.fs.joinpath(fixture_dir, "main.cpp"),
    }
end

local function build_container_binary(fixture_dir, output_dir, binary_path)
    local image = select_docker_image()
    return run_command({
        "docker",
        "run",
        "--rm",
        "-v",
        fixture_dir .. ":/host-src:ro",
        "-v",
        output_dir .. ":/out",
        "-w",
        "/work",
        image,
        "bash",
        "-lc",
        "mkdir -p /work/src && cp -R /host-src/. /work/src/ && g++ -std=c++17 -O0 -g /work/src/main.cpp -o /out/" .. vim.fs.basename(binary_path),
    })
end

local function configured_docker_images()
    local override = vim.trim(vim.env.SPLITASM_DOCKER_TEST_IMAGE or "")
    if override ~= "" then
        return { override }
    end

    return {
        "gcc:14",
        "gcc:latest",
        "debian:stable-slim",
    }
end

local function image_has_compiler(image)
    local probe = try_run_command({
        "docker",
        "run",
        "--rm",
        image,
        "bash",
        "-lc",
        "command -v g++ >/dev/null 2>&1",
    })
    return probe.ok
end

local function can_use_local_image(image)
    local inspect = try_run_command({ "docker", "image", "inspect", image })
    if not inspect.ok then
        return false
    end

    return image_has_compiler(image)
end

function select_docker_image()
    for _, image in ipairs(configured_docker_images()) do
        if can_use_local_image(image) then
            return image
        end
    end

    local override = vim.trim(vim.env.SPLITASM_DOCKER_TEST_IMAGE or "")
    if override ~= "" then
        skip("configured image is unavailable locally or lacks g++: " .. override)
    end

    skip("no local Docker compiler image found; set SPLITASM_DOCKER_TEST_IMAGE to a pre-pulled image with g++")
end

local function first_mapped_source_line(line_map)
    local source_lines = vim.tbl_keys(line_map)
    table.sort(source_lines)
    return source_lines[1]
end

local function main()
    if vim.fn.executable("docker") ~= 1 then
        skip("docker is not installed")
    end

    local fixture = fixture_paths()
    local tmp_root = vim.fs.joinpath(vim.fn.stdpath("data"), "splitasm-docker-tests")
    local output_dir = vim.fs.joinpath(tmp_root, tostring(vim.uv.hrtime()))
    local binary_path = vim.fs.joinpath(output_dir, "docker-path-map-demo")
    vim.fn.mkdir(output_dir, "p")

    local docker_info = try_run_command({ "docker", "info" })
    if not docker_info.ok then
        skip("docker daemon is unavailable")
    end

    build_container_binary(fixture.fixture_dir, output_dir, binary_path)
    assert_truthy(vim.fn.filereadable(binary_path) == 1, "container build should produce a host-visible binary")

    local objdump_output = runtime.get_objdump_output(binary_path)
    assert_truthy(type(objdump_output) == "string" and objdump_output ~= "", "objdump output should be available for the built binary")
    assert_truthy(objdump_output:match("/work/src/main%.cpp:%d+"), "raw objdump output should retain the in-container source path")

    vim.cmd("edit " .. vim.fn.fnameescape(fixture.source_path))
    splitasm.setup({
        executable_path = binary_path,
        clean_asm = true,
        auto_sync = true,
        source_path_mappings = {
            { from = "/work/src", to = fixture.fixture_dir },
        },
    })
    splitasm.open(binary_path)

    local state = splitasm_state.get()
    local line_map = assert_truthy(state.file_line_maps[fixture.source_path], "splitasm should remap container debug paths to the local fixture")
    local source_line = assert_truthy(first_mapped_source_line(line_map), "at least one local source line should map from the docker-built binary")
    local asm_line = assert_truthy(line_map[source_line].start_line, "mapped source line should point at an asm row")

    vim.api.nvim_set_current_win(state.asm_win)
    vim.api.nvim_win_set_cursor(state.asm_win, { asm_line, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = state.asm_buf, modeline = false })

    assert_eq(vim.api.nvim_buf_get_name(state.source_buf), fixture.source_path, "asm-to-source sync should open the local fixture path")
    assert_eq(vim.api.nvim_win_get_cursor(state.source_win)[1], source_line, "asm-to-source sync should jump to the remapped local line")

    io.stdout:write("splitasm docker path-mapping test passed\n")
    vim.cmd("qa!")
end

local ok, err = xpcall(main, debug.traceback)

if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
end
