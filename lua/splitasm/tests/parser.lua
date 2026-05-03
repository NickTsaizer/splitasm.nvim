package.path = "/home/nick/.config/nvim/lua/?.lua;/home/nick/.config/nvim/lua/?/init.lua;" .. package.path

local parser = require("splitasm.parser")

local M = {}

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

local function assert_nil(value, message)
    if value ~= nil then
        error((message or "expected nil") .. string.format(" (actual=%s)", tostring(value)))
    end
end

local function assert_range(actual, start_line, end_line, message)
    assert_truthy(type(actual) == "table", (message or "range missing") .. " (table expected)")
    assert_eq(actual.start_line, start_line, (message or "range start mismatch") .. " start")
    assert_eq(actual.end_line, end_line, (message or "range end mismatch") .. " end")
end

local function test_build_line_map_tracks_multiple_source_ranges()
    -- Arrange
    local asm_lines = {
        "/tmp/example.c:10",
        "  0000: mov eax,ebx",
        "  0004: add eax,1",
        "/tmp/example.c:11",
        "  0008: ret",
        "/tmp/other.c:7",
        "  000c: nop",
    }

    -- Act
    local file_line_maps, asm_to_source, asm_to_file = parser.build_line_map(asm_lines)

    -- Assert
    assert_range(file_line_maps["/tmp/example.c"][10], 2, 3, "example.c:10")
    assert_range(file_line_maps["/tmp/example.c"][11], 5, 5, "example.c:11")
    assert_range(file_line_maps["/tmp/other.c"][7], 7, 7, "other.c:7")
    assert_eq(asm_to_source[2], 10, "line 2 source line")
    assert_eq(asm_to_source[5], 11, "line 5 source line")
    assert_eq(asm_to_file[7], "/tmp/other.c", "line 7 source file")
end

local function test_parse_remaps_filtered_output_for_public_open_flow()
    -- Arrange
    local asm_lines = {
        "/tmp/example.c:10",
        "0000000000000000 <main()>:",
        "  0000: MOV PTR [rbp-4],eax",
        "  0004: add eax,0x1",
        "/tmp/example.c:11",
        "  0008: ret",
    }

    -- Act
    local parsed = parser.parse(asm_lines, { clean_asm = true })

    -- Assert
    assert_eq(#parsed.asm_lines, 4, "filtered asm line count")
    assert_eq(parsed.asm_lines[1], "main():", "function label normalization")
    assert_eq(parsed.asm_lines[2], "  [rbp-4], eax", "normalized mov line")
    assert_eq(parsed.asm_lines[3], "  add eax, 0x1", "normalized add line")
    assert_eq(parsed.asm_lines[4], "  ret", "normalized ret line")
    assert_range(parsed.file_line_maps["/tmp/example.c"][10], 2, 3, "remapped example.c:10")
    assert_range(parsed.file_line_maps["/tmp/example.c"][11], 4, 4, "remapped example.c:11")
    assert_eq(parsed.asm_to_source[2], 10, "remapped source line 2")
    assert_eq(parsed.asm_to_source[4], 11, "remapped source line 4")
    assert_eq(parsed.asm_to_file[3], "/tmp/example.c", "remapped file line 3")
end

local function test_parse_without_cleaning_preserves_non_source_lines()
    -- Arrange
    local asm_lines = {
        "/tmp/example.c:10",
        "0000000000000000 <main()>:",
        "  0000: mov eax,ebx",
        "  note line",
    }

    -- Act
    local parsed = parser.parse(asm_lines, { clean_asm = false })

    -- Assert
    assert_eq(#parsed.asm_lines, 3, "asm lines preserved without cleaning")
    assert_eq(parsed.asm_lines[1], "0000000000000000 <main()>:", "function label preserved")
    assert_eq(parsed.asm_lines[3], "  note line", "non-source note preserved")
    assert_range(parsed.file_line_maps["/tmp/example.c"][10], 2, 3, "unclean mapping keeps instruction range")
end

local function test_parse_with_cleaning_drops_empty_source_ranges()
    -- Arrange
    local asm_lines = {
        "/tmp/example.c:10",
        "0000000000000000 <helper()>:",
        "/tmp/example.c:11",
        "  0008: ret",
    }

    -- Act
    local parsed = parser.parse(asm_lines, { clean_asm = true })

    -- Assert
    assert_eq(#parsed.asm_lines, 2, "clean asm output should keep label and instruction")
    assert_nil(parsed.file_line_maps["/tmp/example.c"][10], "line 10 should not map without instructions")
    assert_range(parsed.file_line_maps["/tmp/example.c"][11], 2, 2, "line 11 remap should survive cleaning")
end

function M.run()
    test_build_line_map_tracks_multiple_source_ranges()
    test_parse_remaps_filtered_output_for_public_open_flow()
    test_parse_without_cleaning_preserves_non_source_lines()
    test_parse_with_cleaning_drops_empty_source_ranges()
end

local function run_as_script()
    local ok, err = xpcall(M.run, debug.traceback)

    if ok then
        io.stdout:write("splitasm parser tests passed\n")
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
