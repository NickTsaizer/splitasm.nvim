local M = {}

local function is_source_marker(line)
    return line:match("^%s*(/.-):(%d+)$") ~= nil
end

local function parse_source_marker(line)
    local source_path, source_line_num = line:match("^%s*(/.-):(%d+)$")
    if not source_path or not source_line_num then
        return nil
    end

    return {
        source_path = source_path,
        source_line = tonumber(source_line_num),
    }
end

local function is_instruction_line(line)
    return line:match("^%s*[0-9a-fA-F]+:") ~= nil
end

local function finalize_source_range(file_line_maps, source_file, source_line, asm_start, asm_end)
    if not source_file or not source_line or not asm_start or asm_end < asm_start then
        return
    end

    file_line_maps[source_file] = file_line_maps[source_file] or {}
    local current_range = file_line_maps[source_file][source_line]
    if not current_range then
        file_line_maps[source_file][source_line] = {
            start_line = asm_start,
            end_line = asm_end,
        }
        return
    end

    current_range.end_line = asm_end
end

function M.build_line_map(asm_lines)
    local file_line_maps = {}
    local asm_to_source = {}
    local asm_to_file = {}
    local current_source_line = nil
    local current_source_file = nil
    local asm_start = nil

    for index, line in ipairs(asm_lines) do
        local marker = parse_source_marker(line)
        if marker then
            finalize_source_range(file_line_maps, current_source_file, current_source_line, asm_start, index - 1)
            current_source_file = marker.source_path
            current_source_line = marker.source_line
            asm_start = nil
        elseif current_source_file and current_source_line and is_instruction_line(line) then
            asm_start = asm_start or index
            asm_to_source[index] = current_source_line
            asm_to_file[index] = current_source_file
        end
    end

    finalize_source_range(file_line_maps, current_source_file, current_source_line, asm_start, #asm_lines)

    return file_line_maps, asm_to_source, asm_to_file
end

local function normalize_instruction_line(line)
    local indent, _, instruction = line:match("^(%s*)(%x+):%s+(.+)$")
    if not indent or not instruction then
        return line
    end

    instruction = instruction:gsub("%u+ PTR ", "")
    instruction = instruction:gsub(",(%S)", ", %1")
    return indent .. instruction
end

local function normalize_output_line(line, clean_asm)
    if is_source_marker(line) then
        return nil
    end

    if not clean_asm then
        return line
    end

    if line:match("^%S.*%(%):$") then
        return nil
    end

    local function_name = line:match("^%x+ <(.+)>:$")
    if function_name then
        return function_name .. ":"
    end

    return normalize_instruction_line(line)
end

function M.normalize_asm_lines(asm_lines, clean_asm)
    local filtered_lines = {}
    local old_to_new = {}

    for index, line in ipairs(asm_lines) do
        local normalized = normalize_output_line(line, clean_asm)
        if normalized then
            filtered_lines[#filtered_lines + 1] = normalized
            old_to_new[index] = #filtered_lines
        end
    end

    return filtered_lines, old_to_new
end

function M.remap_source_mappings(raw_file_line_maps, raw_asm_to_source, raw_asm_to_file, old_to_new)
    local file_line_maps = {}
    for path, line_map in pairs(raw_file_line_maps) do
        file_line_maps[path] = {}
        for source_line, range in pairs(line_map) do
            local new_start = old_to_new[range.start_line]
            local new_end = old_to_new[range.end_line]
            if new_start and new_end then
                file_line_maps[path][source_line] = {
                    start_line = new_start,
                    end_line = new_end,
                }
            end
        end
    end

    local asm_to_source = {}
    for old_line, source_line in pairs(raw_asm_to_source) do
        local new_line = old_to_new[old_line]
        if new_line then
            asm_to_source[new_line] = source_line
        end
    end

    local asm_to_file = {}
    for old_line, file_path in pairs(raw_asm_to_file) do
        local new_line = old_to_new[old_line]
        if new_line then
            asm_to_file[new_line] = file_path
        end
    end

    return file_line_maps, asm_to_source, asm_to_file
end

function M.parse(asm_lines, opts)
    opts = opts or {}

    local raw_file_line_maps, raw_asm_to_source, raw_asm_to_file = M.build_line_map(asm_lines)
    local filtered_lines, old_to_new = M.normalize_asm_lines(asm_lines, opts.clean_asm)
    local file_line_maps, asm_to_source, asm_to_file =
        M.remap_source_mappings(raw_file_line_maps, raw_asm_to_source, raw_asm_to_file, old_to_new)

    return {
        asm_lines = filtered_lines,
        file_line_maps = file_line_maps,
        asm_to_source = asm_to_source,
        asm_to_file = asm_to_file,
        old_to_new = old_to_new,
    }
end

return M
