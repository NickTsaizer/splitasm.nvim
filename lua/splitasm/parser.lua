local M = {}
local parse_source_marker

local function normalize_source_path(source_path)
    if type(source_path) ~= "string" then
        return source_path
    end

    local normalized_path = vim.trim(source_path):gsub("\\", "/")
    local unc_prefix, unc_remainder = normalized_path:match("^(//)(.*)$")
    if unc_prefix then
        normalized_path = unc_prefix .. unc_remainder:gsub("/+", "/")
    else
        normalized_path = normalized_path:gsub("/+", "/")
    end

    local drive_letter, remainder = normalized_path:match("^([a-zA-Z]):(.*)$")
    if drive_letter then
        return string.upper(drive_letter) .. ":" .. remainder
    end

    return normalized_path
end

M.normalize_source_path = normalize_source_path

local function trim_trailing_separator(path)
    if path == "/" or path:match("^[A-Z]:/$") then
        return path
    end

    return (path:gsub("/+$", ""))
end

local function slice_components(components, finish)
    local sliced = {}
    for index = 1, finish do
        sliced[index] = components[index]
    end
    return sliced
end

local function path_root_prefix(path)
    local drive = path:match("^([A-Z]:/)")
    if drive then
        return drive
    end

    local unc_root = path:match("^(//[^/]+/[^/]+)")
    if unc_root then
        return unc_root
    end

    if path:sub(1, 1) == "/" then
        return "/"
    end

    return ""
end

local function path_components(path)
    local root = path_root_prefix(path)
    local remainder = path:sub(#root + 1)
    local components = {}

    for component in remainder:gmatch("[^/]+") do
        components[#components + 1] = component
    end

    return {
        root = root,
        components = components,
    }
end

local function join_path(root, components)
    if #components == 0 then
        return root ~= "" and root or nil
    end

    if root == "" then
        return table.concat(components, "/")
    end

    if root == "/" then
        return root .. table.concat(components, "/")
    end

    return root .. "/" .. table.concat(components, "/")
end

local function shared_suffix_length(left_components, right_components)
    local matches = 0
    local left_index = #left_components
    local right_index = #right_components

    while left_index > 0 and right_index > 0 do
        if left_components[left_index] ~= right_components[right_index] then
            break
        end

        matches = matches + 1
        left_index = left_index - 1
        right_index = right_index - 1
    end

    return matches
end

local function path_has_prefix(path, prefix)
    if path == prefix then
        return true
    end

    if path:sub(1, #prefix) ~= prefix then
        return false
    end

    return path:sub(#prefix + 1, #prefix + 1) == "/"
end

local function find_best_mapping_match(source_path, source_path_mappings)
    if type(source_path) ~= "string" or type(source_path_mappings) ~= "table" then
        return nil
    end

    local normalized_path = normalize_source_path(source_path)
    local best_match = nil

    for _, mapping in ipairs(source_path_mappings) do
        local from_path = trim_trailing_separator(normalize_source_path(mapping.from))
        local to_path = trim_trailing_separator(normalize_source_path(mapping.to))
        if from_path and to_path and path_has_prefix(normalized_path, from_path) then
            if not best_match or #from_path > #best_match.from_path then
                best_match = {
                    from_path = from_path,
                    to_path = to_path,
                }
            end
        end
    end

    return best_match
end

function M.remap_source_path(source_path, source_path_mappings, fallback_source_path_mappings)
    local normalized_path = normalize_source_path(source_path)
    if type(normalized_path) ~= "string" then
        return normalized_path
    end

    local best_match = find_best_mapping_match(normalized_path, source_path_mappings)
    if not best_match then
        best_match = find_best_mapping_match(normalized_path, fallback_source_path_mappings)
    end

    if not best_match then
        return normalized_path
    end

    local suffix = normalized_path:sub(#best_match.from_path + 1)
    return normalize_source_path(best_match.to_path .. suffix)
end

function M.infer_source_path_mapping(source_path, local_source_path)
    local normalized_source_path = normalize_source_path(source_path)
    local normalized_local_path = normalize_source_path(local_source_path)
    if type(normalized_source_path) ~= "string" or type(normalized_local_path) ~= "string" then
        return nil
    end

    if normalized_source_path == normalized_local_path then
        return nil
    end

    local source_parts = path_components(normalized_source_path)
    local local_parts = path_components(normalized_local_path)
    if #source_parts.components == 0 or #local_parts.components == 0 then
        return nil
    end

    if source_parts.components[#source_parts.components] ~= local_parts.components[#local_parts.components] then
        return nil
    end

    local suffix_length = shared_suffix_length(source_parts.components, local_parts.components)
    if suffix_length == 0 then
        return nil
    end

    local from_prefix = join_path(source_parts.root, slice_components(source_parts.components, #source_parts.components - suffix_length))
    local to_prefix = join_path(local_parts.root, slice_components(local_parts.components, #local_parts.components - suffix_length))
    if not from_prefix or not to_prefix then
        return nil
    end

    return {
        from = from_prefix,
        to = to_prefix,
    }
end

function M.infer_source_path_mappings(asm_lines, local_source_path)
    if type(local_source_path) ~= "string" then
        return {}
    end

    local inferred_by_source = {}
    for _, line in ipairs(asm_lines or {}) do
        local marker = parse_source_marker(line)
        if marker then
            local mapping = M.infer_source_path_mapping(marker.source_path, local_source_path)
            if mapping then
                inferred_by_source[mapping.from] = mapping
            end
        end
    end

    local inferred = vim.tbl_values(inferred_by_source)
    table.sort(inferred, function(left, right)
        return #left.from > #right.from
    end)
    return inferred
end

local function build_source_id(source_path, source_line)
    return string.format("%s:%d", source_path, source_line)
end

local function looks_like_source_path(source_path)
    return source_path:match("^[a-zA-Z]:[\\/]")
        or source_path:match("^/")
        or source_path:match("^\\\\")
        or source_path:find("/", 1, true)
        or source_path:find("\\", 1, true)
end

parse_source_marker = function(line)
    local source_path, source_line_num = line:match("^%s*(.+):(%d+)%s*$")
    if not source_path or not source_line_num or not looks_like_source_path(source_path) then
        return nil
    end

    return {
        source_path = normalize_source_path(source_path),
        source_line = tonumber(source_line_num),
    }
end

local function is_source_marker(line)
    return parse_source_marker(line) ~= nil
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

function M.build_line_map(asm_lines, opts)
    opts = opts or {}

    local file_line_maps = {}
    local asm_to_source = {}
    local asm_to_file = {}
    local asm_metadata = {}
    local current_source_line = nil
    local current_source_file = nil
    local asm_start = nil
    local current_lane = 0

    for index, line in ipairs(asm_lines) do
        local marker = parse_source_marker(line)
        if marker then
            finalize_source_range(file_line_maps, current_source_file, current_source_line, asm_start, index - 1)
            current_source_file = M.remap_source_path(
                marker.source_path,
                opts.source_path_mappings,
                opts.inferred_source_path_mappings
            )
            current_source_line = marker.source_line
            asm_start = nil
            current_lane = 0
        elseif current_source_file and current_source_line and is_instruction_line(line) then
            asm_start = asm_start or index
            current_lane = current_lane + 1
            asm_to_source[index] = current_source_line
            asm_to_file[index] = current_source_file
            asm_metadata[index] = {
                source_file = current_source_file,
                source_line = current_source_line,
                source_id = build_source_id(current_source_file, current_source_line),
                lane_index = current_lane,
            }
        end
    end

    finalize_source_range(file_line_maps, current_source_file, current_source_line, asm_start, #asm_lines)

    return file_line_maps, asm_to_source, asm_to_file, asm_metadata
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

function M.remap_source_mappings(raw_file_line_maps, raw_asm_to_source, raw_asm_to_file, raw_asm_metadata, old_to_new)
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

    local asm_metadata = {}
    for old_line, metadata in pairs(raw_asm_metadata) do
        local new_line = old_to_new[old_line]
        if new_line then
            asm_metadata[new_line] = vim.deepcopy(metadata)
        end
    end

    return file_line_maps, asm_to_source, asm_to_file, asm_metadata
end

function M.parse(asm_lines, opts)
    opts = opts or {}
    local inferred_source_path_mappings = opts.inferred_source_path_mappings
        or M.infer_source_path_mappings(asm_lines, opts.current_source_path)

    local raw_file_line_maps, raw_asm_to_source, raw_asm_to_file, raw_asm_metadata = M.build_line_map(asm_lines, {
        source_path_mappings = opts.source_path_mappings,
        inferred_source_path_mappings = inferred_source_path_mappings,
    })
    local filtered_lines, old_to_new = M.normalize_asm_lines(asm_lines, opts.clean_asm)
    local file_line_maps, asm_to_source, asm_to_file, asm_metadata = M.remap_source_mappings(
        raw_file_line_maps,
        raw_asm_to_source,
        raw_asm_to_file,
        raw_asm_metadata,
        old_to_new
    )

    return {
        asm_lines = filtered_lines,
        file_line_maps = file_line_maps,
        asm_to_source = asm_to_source,
        asm_to_file = asm_to_file,
        asm_metadata = asm_metadata,
        old_to_new = old_to_new,
        inferred_source_path_mappings = inferred_source_path_mappings,
    }
end

return M
