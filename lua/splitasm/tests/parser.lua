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

local function assert_source_metadata(actual, expected_file, expected_line, expected_id, expected_lane, message)
    assert_truthy(type(actual) == "table", (message or "metadata missing") .. " (table expected)")
    assert_eq(actual.source_file, expected_file, (message or "source file mismatch") .. " file")
    assert_eq(actual.source_line, expected_line, (message or "source line mismatch") .. " line")
    assert_eq(actual.source_id, expected_id, (message or "source id mismatch") .. " id")
    assert_eq(actual.lane_index, expected_lane, (message or "lane mismatch") .. " lane")
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
    local file_line_maps, asm_to_source, asm_to_file, asm_metadata = parser.build_line_map(asm_lines)

    -- Assert
    assert_range(file_line_maps["/tmp/example.c"][10], 2, 3, "example.c:10")
    assert_range(file_line_maps["/tmp/example.c"][11], 5, 5, "example.c:11")
    assert_range(file_line_maps["/tmp/other.c"][7], 7, 7, "other.c:7")
    assert_eq(asm_to_source[2], 10, "line 2 source line")
    assert_eq(asm_to_source[5], 11, "line 5 source line")
    assert_eq(asm_to_file[7], "/tmp/other.c", "line 7 source file")
    assert_source_metadata(asm_metadata[2], "/tmp/example.c", 10, "/tmp/example.c:10", 1, "line 2 metadata")
    assert_source_metadata(asm_metadata[3], "/tmp/example.c", 10, "/tmp/example.c:10", 2, "line 3 metadata")
    assert_source_metadata(asm_metadata[7], "/tmp/other.c", 7, "/tmp/other.c:7", 1, "line 7 metadata")
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
    assert_source_metadata(parsed.asm_metadata[2], "/tmp/example.c", 10, "/tmp/example.c:10", 1, "remapped metadata line 2")
    assert_source_metadata(parsed.asm_metadata[3], "/tmp/example.c", 10, "/tmp/example.c:10", 2, "remapped metadata line 3")
    assert_source_metadata(parsed.asm_metadata[4], "/tmp/example.c", 11, "/tmp/example.c:11", 1, "remapped metadata line 4")
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
    assert_eq(parsed.asm_lines[1], "main():", "function label simplified")
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
    assert_nil(parsed.asm_metadata[1], "label line should stay unmapped after cleaning")
    assert_source_metadata(parsed.asm_metadata[2], "/tmp/example.c", 11, "/tmp/example.c:11", 1, "line 11 metadata should survive cleaning")
end

local function test_build_line_map_normalizes_windows_source_markers()
    -- Arrange
    local asm_lines = {
        [[C:\work\demo\main.c:12]],
        "  0000: mov eax,ebx",
        [[c:/work/demo\\util.c:7]],
        "  0004: ret",
    }

    -- Act
    local file_line_maps, asm_to_source, asm_to_file, asm_metadata = parser.build_line_map(asm_lines)

    -- Assert
    assert_range(file_line_maps["C:/work/demo/main.c"][12], 2, 2, "normalized main.c range")
    assert_range(file_line_maps["C:/work/demo/util.c"][7], 4, 4, "normalized util.c range")
    assert_eq(asm_to_source[2], 12, "windows marker source line should map")
    assert_eq(asm_to_file[2], "C:/work/demo/main.c", "drive-letter path should normalize for asm mapping")
    assert_eq(asm_to_file[4], "C:/work/demo/util.c", "backslash path should normalize for asm mapping")
    assert_source_metadata(asm_metadata[2], "C:/work/demo/main.c", 12, "C:/work/demo/main.c:12", 1, "normalized metadata")
    assert_source_metadata(asm_metadata[4], "C:/work/demo/util.c", 7, "C:/work/demo/util.c:7", 1, "mixed separator metadata")
end

local function test_parse_normalizes_windows_paths_in_public_results()
    -- Arrange
    local asm_lines = {
        [[c:\work\demo\main.c:3]],
        "0000000000000000 <main()>:",
        "  0000: MOV PTR [rbp-4],eax",
        [[C:/work/demo\\main.c:4]],
        "  0004: ret",
    }

    -- Act
    local parsed = parser.parse(asm_lines, { clean_asm = true })

    -- Assert
    assert_range(parsed.file_line_maps["C:/work/demo/main.c"][3], 2, 2, "line 3 should map with normalized windows key")
    assert_range(parsed.file_line_maps["C:/work/demo/main.c"][4], 3, 3, "line 4 should preserve normalized marker key")
    assert_eq(parsed.asm_to_file[2], "C:/work/demo/main.c", "clean parse should normalize first windows path")
    assert_eq(parsed.asm_to_file[3], "C:/work/demo/main.c", "clean parse should normalize mixed windows path")
    assert_source_metadata(parsed.asm_metadata[2], "C:/work/demo/main.c", 3, "C:/work/demo/main.c:3", 1, "line 3 windows metadata")
    assert_source_metadata(parsed.asm_metadata[3], "C:/work/demo/main.c", 4, "C:/work/demo/main.c:4", 1, "line 4 windows metadata")
end

local function test_build_line_map_remaps_container_paths_to_local_paths()
    -- Arrange
    local asm_lines = {
        "/work/src/main.cpp:6",
        "  0000: mov eax,ebx",
        "/work/src/lib/helper.cpp:9",
        "  0004: ret",
    }

    -- Act
    local file_line_maps, asm_to_source, asm_to_file, asm_metadata = parser.build_line_map(asm_lines, {
        source_path_mappings = {
            { from = "/work/src", to = "/home/nick/project/src" },
        },
    })

    -- Assert
    assert_range(file_line_maps["/home/nick/project/src/main.cpp"][6], 2, 2, "main.cpp should remap to host path")
    assert_range(file_line_maps["/home/nick/project/src/lib/helper.cpp"][9], 4, 4, "nested helper path should remap to host path")
    assert_eq(asm_to_source[2], 6, "remapped source line should stay intact")
    assert_eq(asm_to_file[2], "/home/nick/project/src/main.cpp", "asm mapping should store host path")
    assert_eq(asm_to_file[4], "/home/nick/project/src/lib/helper.cpp", "nested asm mapping should store host path")
    assert_source_metadata(
        asm_metadata[2],
        "/home/nick/project/src/main.cpp",
        6,
        "/home/nick/project/src/main.cpp:6",
        1,
        "metadata should use remapped host path"
    )
end

local function test_parse_prefers_longest_matching_source_path_mapping()
    -- Arrange
    local asm_lines = {
        "/work/src/generated/main.cpp:4",
        "  0000: ret",
    }

    -- Act
    local parsed = parser.parse(asm_lines, {
        clean_asm = true,
        source_path_mappings = {
            { from = "/work/src", to = "/host/src" },
            { from = "/work/src/generated", to = "/host/generated" },
        },
    })

    -- Assert
    assert_range(parsed.file_line_maps["/host/generated/main.cpp"][4], 1, 1, "longest matching mapping should win")
    assert_eq(parsed.asm_to_file[1], "/host/generated/main.cpp", "asm file map should use longest mapping result")
    assert_source_metadata(parsed.asm_metadata[1], "/host/generated/main.cpp", 4, "/host/generated/main.cpp:4", 1, "metadata should keep longest-match path")
end

local function test_infer_source_path_mapping_uses_shared_filename_suffix()
    -- Arrange + Act
    local inferred = parser.infer_source_path_mapping("/work/src/main.cpp", "/home/nick/project/src/main.cpp")

    -- Assert
    assert_truthy(inferred, "inference should produce a mapping for shared file suffixes")
    assert_eq(inferred.from, "/work", "inference should trim the shared suffix from the debug path")
    assert_eq(inferred.to, "/home/nick/project", "inference should trim the shared suffix from the local path")
end

local function test_parse_infers_fallback_source_mapping_from_current_file()
    -- Arrange
    local asm_lines = {
        "/work/src/main.cpp:8",
        "  0000: ret",
    }

    -- Act
    local parsed = parser.parse(asm_lines, {
        clean_asm = true,
        current_source_path = "/home/nick/project/src/main.cpp",
    })

    -- Assert
    assert_range(parsed.file_line_maps["/home/nick/project/src/main.cpp"][8], 1, 1, "inferred mappings should remap markers to the current file")
    assert_eq(parsed.asm_to_file[1], "/home/nick/project/src/main.cpp", "asm mapping should use the inferred host path")
    assert_eq(#parsed.inferred_source_path_mappings, 1, "parse should report inferred mappings for the session")
    assert_eq(parsed.inferred_source_path_mappings[1].from, "/work", "session mapping should keep the inferred debug prefix")
end

local function test_parse_prefers_explicit_mapping_over_inferred_fallback()
    -- Arrange
    local asm_lines = {
        "/work/src/main.cpp:8",
        "  0000: ret",
    }

    -- Act
    local parsed = parser.parse(asm_lines, {
        clean_asm = true,
        current_source_path = "/home/nick/project/src/main.cpp",
        source_path_mappings = {
            { from = "/work/src", to = "/explicit/src" },
        },
    })

    -- Assert
    assert_range(parsed.file_line_maps["/explicit/src/main.cpp"][8], 1, 1, "explicit mapping should override inferred fallback")
    assert_nil(parsed.file_line_maps["/home/nick/project/src/main.cpp"], "inferred fallback should not win over explicit mapping")
    assert_eq(parsed.asm_to_file[1], "/explicit/src/main.cpp", "asm file mapping should prefer explicit remaps")
end

function M.run()
    test_build_line_map_tracks_multiple_source_ranges()
    test_parse_remaps_filtered_output_for_public_open_flow()
    test_parse_without_cleaning_preserves_non_source_lines()
    test_parse_with_cleaning_drops_empty_source_ranges()
    test_build_line_map_normalizes_windows_source_markers()
    test_parse_normalizes_windows_paths_in_public_results()
    test_build_line_map_remaps_container_paths_to_local_paths()
    test_parse_prefers_longest_matching_source_path_mapping()
    test_infer_source_path_mapping_uses_shared_filename_suffix()
    test_parse_infers_fallback_source_mapping_from_current_file()
    test_parse_prefers_explicit_mapping_over_inferred_fallback()
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
