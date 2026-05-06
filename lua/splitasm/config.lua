local M = {}

local defaults = {
    compiler_cmd = nil,
    executable_path = nil,
    source_path_mappings = {},
    auto_sync = true,
    clean_asm = false,
    source_row_colors = true,
}

local state = {
    config = vim.deepcopy(defaults),
}

local function normalize_string(value, field_name)
    if value == nil then
        return nil
    end

    if type(value) ~= "string" then
        error(string.format("splitasm: %s must be a string or nil", field_name))
    end

    local normalized = vim.trim(value)
    if normalized == "" then
        return nil
    end

    return normalized
end

local function normalize_boolean(value, field_name)
    if value == nil then
        return nil
    end

    if type(value) ~= "boolean" then
        error(string.format("splitasm: %s must be a boolean", field_name))
    end

    return value
end

local function normalize_source_path_mapping(entry, index)
    if type(entry) ~= "table" then
        error(string.format("splitasm: source_path_mappings[%d] must be a table", index))
    end

    local from = normalize_string(entry.from, string.format("source_path_mappings[%d].from", index))
    local to = normalize_string(entry.to, string.format("source_path_mappings[%d].to", index))
    if not from then
        error(string.format("splitasm: source_path_mappings[%d].from is required", index))
    end

    if not to then
        error(string.format("splitasm: source_path_mappings[%d].to is required", index))
    end

    return {
        from = from,
        to = to,
    }
end

local function normalize_source_path_mappings(value)
    if value == nil then
        return nil
    end

    if type(value) ~= "table" then
        error("splitasm: source_path_mappings must be a list of { from, to } mappings")
    end

    local normalized = {}
    for index, entry in ipairs(value) do
        normalized[index] = normalize_source_path_mapping(entry, index)
    end

    return normalized
end

local function normalize_config(user_config)
    if user_config == nil then
        return {}
    end

    if type(user_config) ~= "table" then
        error("splitasm: setup() expects a table or nil")
    end

    return {
        compiler_cmd = normalize_string(user_config.compiler_cmd, "compiler_cmd"),
        executable_path = normalize_string(user_config.executable_path, "executable_path"),
        source_path_mappings = normalize_source_path_mappings(user_config.source_path_mappings),
        auto_sync = normalize_boolean(user_config.auto_sync, "auto_sync"),
        clean_asm = normalize_boolean(user_config.clean_asm, "clean_asm"),
        source_row_colors = normalize_boolean(user_config.source_row_colors, "source_row_colors"),
    }
end

function M.defaults()
    return vim.deepcopy(defaults)
end

function M.get()
    return state.config
end

function M.describe(config)
    local active_config = config or state.config
    return {
        string.format("Build command: %s", active_config.compiler_cmd or "not set"),
        string.format("Executable path: %s", active_config.executable_path or "auto-detect from cwd"),
        string.format("Source path mappings: %d configured", #(active_config.source_path_mappings or {})),
        string.format("Auto-sync: %s", active_config.auto_sync and "enabled" or "disabled"),
        string.format("Clean assembly: %s", active_config.clean_asm and "enabled" or "disabled"),
        string.format("Source row colors: %s", active_config.source_row_colors and "enabled" or "disabled"),
    }
end

function M.has_user_configuration(config)
    local active_config = config or state.config
    return active_config.compiler_cmd ~= nil or active_config.executable_path ~= nil
end

function M.normalize_path(value)
    return normalize_string(value, "path")
end

function M.setup(user_config)
    state.config = vim.tbl_deep_extend("force", M.defaults(), normalize_config(user_config))
    return state.config
end

function M.update(partial_config)
    state.config = vim.tbl_deep_extend("force", state.config, normalize_config(partial_config))
    return state.config
end

function M.toggle_auto_sync()
    state.config.auto_sync = not state.config.auto_sync
    return state.config.auto_sync
end

return M
