local state_store = require("splitasm.state")

local M = {}

local function center_window(win)
    vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zz")
    end)
end

function M.sync_source_to_asm(state, get_config)
    if not get_config().auto_sync or state.is_updating then
        return
    end

    if not state.asm_buf or not vim.api.nvim_buf_is_valid(state.asm_buf) then
        return
    end

    if not state.asm_win or not vim.api.nvim_win_is_valid(state.asm_win) then
        return
    end

    local current_win = vim.api.nvim_get_current_win()
    if current_win == state.asm_win then
        return
    end

    local buf = vim.api.nvim_win_get_buf(current_win)
    local current_file = vim.api.nvim_buf_get_name(buf)
    local file_map = state.file_line_maps[current_file]
    if not file_map then
        return
    end

    state.source_win = current_win
    state.source_buf = buf

    local source_line = vim.api.nvim_win_get_cursor(state.source_win)[1]
    local range = file_map[source_line]
    if not range then
        return
    end

    state.is_updating = true
    vim.api.nvim_win_set_cursor(state.asm_win, { range.start_line, 0 })
    center_window(state.asm_win)
    vim.schedule(function()
        state.is_updating = false
    end)
end

function M.sync_asm_to_source(state, opts)
    if not opts.get_config().auto_sync or state.is_updating then
        return
    end

    local current_win = vim.api.nvim_get_current_win()
    if current_win ~= state.asm_win then
        return
    end

    local asm_line = vim.api.nvim_win_get_cursor(state.asm_win)[1]
    local source_line = state.asm_to_source[asm_line]
    if not source_line then
        return
    end

    local target_path = state.asm_to_file[asm_line] or state.current_file
    if vim.fn.filereadable(target_path) ~= 1 then
        vim.notify("Source file not found: " .. target_path, vim.log.levels.WARN)
        return
    end

    state.is_updating = true
    vim.schedule(function()
        if not state.asm_win or not vim.api.nvim_win_is_valid(state.asm_win) then
            state.is_updating = false
            return
        end

        opts.focus_source_location(state, target_path, source_line)
        state.is_updating = false
    end)
end

local function set_source_keymaps(state, augroup, toggle_auto_sync)
    vim.api.nvim_create_autocmd("BufEnter", {
        group = augroup,
        callback = function()
            local current_win = vim.api.nvim_get_current_win()
            if current_win == state.asm_win or not state.asm_win or not vim.api.nvim_win_is_valid(state.asm_win) then
                return
            end

            vim.keymap.set("n", "s", function()
                toggle_auto_sync(true)
            end, { buffer = vim.api.nvim_get_current_buf(), silent = true, desc = "Toggle SplitAsm sync" })
        end,
    })
end

function M.setup_autocmds(state, opts)
    local augroup = vim.api.nvim_create_augroup("SplitAsmSync", { clear = true })
    state.augroup = augroup

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = augroup,
        callback = function()
            if state.asm_win and vim.api.nvim_win_is_valid(state.asm_win) then
                local current_win = vim.api.nvim_get_current_win()
                if current_win ~= state.asm_win then
                    M.sync_source_to_asm(state, opts.get_config)
                end
            end
        end,
    })

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = augroup,
        buffer = state.asm_buf,
        callback = function()
            M.sync_asm_to_source(state, {
                get_config = opts.get_config,
                focus_source_location = opts.focus_source_location,
            })
        end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        group = augroup,
        buffer = state.asm_buf,
        callback = function()
            state_store.cleanup(augroup)
        end,
    })

    set_source_keymaps(state, augroup, opts.toggle_auto_sync)
end

return M
