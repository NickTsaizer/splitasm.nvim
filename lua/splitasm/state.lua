local M = {}

local state = {
    source_buf = nil,
    source_win = nil,
    asm_buf = nil,
    asm_win = nil,
    file_line_maps = {},
    asm_to_source = {},
    asm_to_file = {},
    asm_metadata = {},
    current_file = nil,
    is_updating = false,
    augroup = nil,
}

function M.get()
    return state
end

function M.reset_open_state()
    state.file_line_maps = {}
    state.asm_to_source = {}
    state.asm_to_file = {}
    state.asm_metadata = {}
    state.current_file = nil
    state.is_updating = false
end

function M.apply_parsed_asm(parsed)
    state.file_line_maps = parsed.file_line_maps
    state.asm_to_source = parsed.asm_to_source
    state.asm_to_file = parsed.asm_to_file
    state.asm_metadata = parsed.asm_metadata or {}
    return parsed.asm_lines
end

function M.cleanup(augroup)
    pcall(vim.api.nvim_del_augroup_by_id, augroup or state.augroup)
    state.source_buf = nil
    state.source_win = nil
    state.asm_buf = nil
    state.asm_win = nil
    state.file_line_maps = {}
    state.asm_to_source = {}
    state.asm_to_file = {}
    state.asm_metadata = {}
    state.current_file = nil
    state.is_updating = false
    state.augroup = nil
end

return M
