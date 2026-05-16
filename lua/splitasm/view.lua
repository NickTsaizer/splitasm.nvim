local M = {}
local parser = require("splitasm.parser")
local source_row_colors = require("splitasm.source_row_colors")

local BUF_NAME = "SplitAsm"

local function center_window(win)
    vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zz")
    end)
end

local function get_file_map(file_line_maps, source_path)
    local normalized_path = parser.normalize_source_path(source_path)
    return file_line_maps[normalized_path], normalized_path
end

function M.get_source_context(state)
    local current_win = vim.api.nvim_get_current_win()
    if current_win == state.asm_win and state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
        return state.source_win, vim.api.nvim_win_get_buf(state.source_win)
    end

    return current_win, vim.api.nvim_get_current_buf()
end

function M.ensure_asm_buffer(state)
    state.asm_buf = vim.fn.bufnr(BUF_NAME)
    if state.asm_buf ~= -1 then
        return state.asm_buf
    end

    state.asm_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(state.asm_buf, BUF_NAME)
    return state.asm_buf
end

function M.ensure_asm_window(state)
    if state.asm_win and vim.api.nvim_win_is_valid(state.asm_win) then
        return state.asm_win
    end

    if not state.source_win or not vim.api.nvim_win_is_valid(state.source_win) then
        return nil
    end

    vim.api.nvim_set_current_win(state.source_win)
    vim.cmd("rightbelow vsplit")
    state.asm_win = vim.api.nvim_get_current_win()
    return state.asm_win
end

function M.render_asm_buffer(state, asm_lines, config)
    config = config or {}
    local asm_win = M.ensure_asm_window(state)
    if not asm_win then
        return false
    end

    vim.api.nvim_win_set_buf(asm_win, M.ensure_asm_buffer(state))
    vim.wo[asm_win].number = config.show_line_numbers ~= false
    vim.wo[asm_win].relativenumber = false
    vim.wo[asm_win].signcolumn = "no"
    vim.wo[asm_win].foldcolumn = "0"

    vim.bo[state.asm_buf].modifiable = true
    vim.bo[state.asm_buf].readonly = false
    vim.api.nvim_buf_set_lines(state.asm_buf, 0, -1, false, asm_lines)
    vim.bo[state.asm_buf].filetype = "asm"
    pcall(vim.treesitter.start, state.asm_buf, "asm")
    vim.bo[state.asm_buf].modifiable = false
    vim.bo[state.asm_buf].readonly = true
    vim.bo[state.asm_buf].buftype = "nofile"
    vim.bo[state.asm_buf].buflisted = false
    vim.bo[state.asm_buf].swapfile = false
    source_row_colors.render(state.asm_buf, state.asm_metadata, {
        enabled = config.source_row_colors,
        show_line_numbers = config.show_line_numbers,
        hide_address = config.hide_address,
    })
    return true
end

function M.jump_to_initial_position(state, current_line)
    local file_map, normalized_path = get_file_map(state.file_line_maps, state.current_file)
    if not file_map then
        return
    end

    state.current_file = normalized_path

    local range = file_map[current_line]
    if not range or not state.asm_win or not vim.api.nvim_win_is_valid(state.asm_win) then
        return
    end

    vim.api.nvim_win_set_cursor(state.asm_win, { range.start_line, 0 })
    center_window(state.asm_win)
end

function M.ensure_source_window(state)
    if state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
        return state.source_win
    end

    if not state.asm_win or not vim.api.nvim_win_is_valid(state.asm_win) then
        return nil
    end

    local previous_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(state.asm_win)
    vim.cmd("leftabove vsplit")
    state.source_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(previous_win)
    return state.source_win
end

function M.focus_source_location(state, target_path, source_line)
    local source_win = M.ensure_source_window(state)
    if not source_win then
        return false
    end

    local current_buf = vim.api.nvim_win_get_buf(source_win)
    local current_path = parser.normalize_source_path(vim.fn.expand(vim.api.nvim_buf_get_name(current_buf)))
    local normalized_target_path = parser.normalize_source_path(target_path)
    if current_path ~= normalized_target_path then
        vim.api.nvim_win_call(source_win, function()
            vim.cmd("edit " .. vim.fn.fnameescape(normalized_target_path))
        end)
        state.source_buf = vim.api.nvim_win_get_buf(source_win)
    else
        state.source_buf = current_buf
    end

    state.current_file = normalized_target_path

    local line_count = vim.api.nvim_buf_line_count(state.source_buf)
    vim.api.nvim_win_set_cursor(source_win, { math.min(source_line, line_count), 0 })
    center_window(source_win)
    return true
end

function M.set_split_keymaps(state, callbacks)
    vim.keymap.set("n", "q", function()
        vim.cmd("close")
        if state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
            vim.api.nvim_set_current_win(state.source_win)
        end
    end, { buffer = state.asm_buf, silent = true, desc = "Close SplitAsm view" })

    vim.keymap.set("n", "r", callbacks.refresh, {
        buffer = state.asm_buf,
        silent = true,
        desc = "Refresh assembly view",
    })

    vim.keymap.set("n", "s", callbacks.toggle_sync, {
        buffer = state.asm_buf,
        silent = true,
        desc = "Toggle sync",
    })
end

return M
