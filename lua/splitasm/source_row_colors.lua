local M = {}

local HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("splitasm.source-row-colors")
local HIGHLIGHT_PREFIX = "SplitAsmSourceRow"
local PALETTE = {
    { weak = "#9b8bb0", strong = "#bdb0cd" },
    { weak = "#8ba2bf", strong = "#aec6de" },
    { weak = "#7baead", strong = "#9fd0cf" },
    { weak = "#b09d7d", strong = "#d2bea0" },
    { weak = "#b08a99", strong = "#d1afbc" },
    { weak = "#89ad91", strong = "#aed2b5" },
}

local function stable_hash(text)
    local hash = 2166136261
    for index = 1, #text do
        hash = bit.bxor(hash, text:byte(index))
        hash = (hash * 16777619) % 4294967296
    end
    return hash
end

local function palette_group_name(index, tone)
    return string.format("%s%d%s", HIGHLIGHT_PREFIX, index, tone)
end

local function text_group_name(index, tone)
    return palette_group_name(index, tone) .. "Text"
end

local function number_group_name(index, tone)
    return palette_group_name(index, tone) .. "Number"
end

local function address_group_name(index, tone)
    return palette_group_name(index, tone) .. "Address"
end

local function contrast_foreground(color)
    local red, green, blue = color:match("^#?(%x%x)(%x%x)(%x%x)$")
    if not red then
        return "#000000"
    end

    red = tonumber(red, 16)
    green = tonumber(green, 16)
    blue = tonumber(blue, 16)
    local luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
    return luminance >= 140 and "#1a1a1a" or "#f2f2f2"
end

local function darken_channel(value, amount)
    return math.max(0, value - amount)
end

local function darken_background(color, amount)
    local red, green, blue = color:match("^#?(%x%x)(%x%x)(%x%x)$")
    if not red then
        return color
    end

    red = darken_channel(tonumber(red, 16), amount)
    green = darken_channel(tonumber(green, 16), amount)
    blue = darken_channel(tonumber(blue, 16), amount)
    return string.format("#%02x%02x%02x", red, green, blue)
end

local function ensure_highlight_groups()
    for index, palette_entry in ipairs(PALETTE) do
        vim.api.nvim_set_hl(0, text_group_name(index, "Weak"), {
            fg = palette_entry.weak,
            default = true,
        })
        vim.api.nvim_set_hl(0, text_group_name(index, "Strong"), {
            fg = palette_entry.strong,
            default = true,
        })
        vim.api.nvim_set_hl(0, number_group_name(index, "Weak"), {
            fg = contrast_foreground(palette_entry.weak),
            bg = darken_background(palette_entry.weak, 24),
            default = true,
        })
        vim.api.nvim_set_hl(0, number_group_name(index, "Strong"), {
            fg = contrast_foreground(palette_entry.strong),
            bg = darken_background(palette_entry.strong, 24),
            default = true,
        })
        vim.api.nvim_set_hl(0, address_group_name(index, "Weak"), {
            fg = contrast_foreground(palette_entry.weak),
            bg = darken_background(palette_entry.weak, 24),
            default = true,
        })
        vim.api.nvim_set_hl(0, address_group_name(index, "Strong"), {
            fg = contrast_foreground(palette_entry.strong),
            bg = darken_background(palette_entry.strong, 24),
            default = true,
        })
    end
end

function M.get_namespace()
    return HIGHLIGHT_NAMESPACE
end

function M.group_for_source_line(source_id, source_line)
    local palette_index = (stable_hash(source_id) % #PALETTE) + 1
    local tone = (source_line or 1) % 2 == 0 and "Strong" or "Weak"
    return {
        text = text_group_name(palette_index, tone),
        number = number_group_name(palette_index, tone),
        address = address_group_name(palette_index, tone),
    }
end

function M.clear(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.api.nvim_buf_clear_namespace(bufnr, HIGHLIGHT_NAMESPACE, 0, -1)
end

function M.render(bufnr, asm_metadata, opts)
    opts = opts or {}
    M.clear(bufnr)

    if not opts.enabled or not asm_metadata or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local show_line_numbers = opts.show_line_numbers
    local hide_address = opts.hide_address

    ensure_highlight_groups()

    for asm_line, metadata in pairs(asm_metadata) do
        if metadata and metadata.source_id then
            local line = vim.api.nvim_buf_get_lines(bufnr, asm_line - 1, asm_line, false)[1] or ""
            local group = M.group_for_source_line(metadata.source_id, metadata.source_line)

            if show_line_numbers then
                -- line number bg fill, text color on full line
                vim.api.nvim_buf_set_extmark(bufnr, HIGHLIGHT_NAMESPACE, asm_line - 1, 0, {
                    end_row = asm_line - 1,
                    end_col = #line,
                    hl_group = group.text,
                    number_hl_group = group.number,
                    priority = 140,
                })
            elseif not hide_address then
                -- line numbers off, addresses visible: bg fill on address, text color on instruction
                local match_start, match_end = line:find("^%s*[0-9a-fA-F]+:")
                if match_start then
                    local hex_start = line:find("[0-9a-fA-F]", match_start)
                    -- one space before hex, one space after colon
                    local hl_start = math.max(0, hex_start - 3)   -- -1 for 0-indexed, -2 for two leading spaces
                    local hl_end = match_end + 1               -- cover colon + one trailing space (end_col exclusive)
                    vim.api.nvim_buf_set_extmark(bufnr, HIGHLIGHT_NAMESPACE, asm_line - 1, hl_start, {
                        end_row = asm_line - 1,
                        end_col = hl_end,
                        hl_group = group.address,
                        priority = 140,
                    })
                    vim.api.nvim_buf_set_extmark(bufnr, HIGHLIGHT_NAMESPACE, asm_line - 1, hl_end, {
                        end_row = asm_line - 1,
                        end_col = #line,
                        hl_group = group.text,
                        priority = 140,
                    })
                else
                    -- fallback: no address found, text color on full line
                    vim.api.nvim_buf_set_extmark(bufnr, HIGHLIGHT_NAMESPACE, asm_line - 1, 0, {
                        end_row = asm_line - 1,
                        end_col = #line,
                        hl_group = group.text,
                        priority = 140,
                    })
                end
            else
                -- line numbers off, addresses hidden: single bg-filled placeholder at col 0
                vim.api.nvim_buf_set_extmark(bufnr, HIGHLIGHT_NAMESPACE, asm_line - 1, 0, {
                    end_row = asm_line - 1,
                    end_col = 1,
                    hl_group = group.address,
                    priority = 140,
                })
                vim.api.nvim_buf_set_extmark(bufnr, HIGHLIGHT_NAMESPACE, asm_line - 1, 1, {
                    end_row = asm_line - 1,
                    end_col = #line,
                    hl_group = group.text,
                    priority = 140,
                })
            end
        end
    end
end

return M
