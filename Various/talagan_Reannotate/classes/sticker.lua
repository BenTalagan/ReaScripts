-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description This file is part of Reannotate

local ImGui         = require "ext/imgui"
local AppContext    = require "classes/app_context"
local EmojImGui     = require "emojimgui"

local Sticker = {}
Sticker.Types = {
    SPECIAL   = 0,
    STANDARD  = 1
}

Sticker.__index = Sticker

function Sticker:new(desc)
    local instance = {}
    setmetatable(instance, self)
    instance:_initialize(desc)
    return instance
end

function Sticker:_initialize(desc)
    self.desc       = desc
    local ret       = self:_parseHelper(self.desc)

    local fname = "OpenMoji"
    if ret.icon_font == 1 then fname = "TweMoji" end

    self.type       = ret.type
    self.icon       = EmojImGui.Asset.CharInfo(fname, ret.icon)
    self.text       = ret.text
end

function Sticker:_parseHelper(str)

    local function next_token(s)
        local colon_pos   = s:find(":")
        local token       = s:sub(1, colon_pos - 1)
        local rest        = s:sub(colon_pos + 1)
        return token, rest
    end

    local token, rest = next_token(str)
    local type = tonumber(token)

    if type == Sticker.Types.SPECIAL then
        return {
            type = type,
            text = rest
        }
    elseif type == Sticker.Types.STANDARD then
        token, rest       = next_token(rest)
        local font        = tonumber(token)
        token, rest       = next_token(rest)

        return {
            type      = type,
            icon_font = font,
            icon      = token,
            text      = rest
        }
    end
end

function Sticker:renderBackground(draw_list, render_params)
    local istop     = render_params.metrics.icon_stop
    local min_x     = render_params.metrics.min_x
    local min_y     = render_params.metrics.min_y
    local max_x     = render_params.metrics.max_x
    local max_y     = render_params.metrics.max_y
    local v_pad     = render_params.metrics.v_pad
    local has_text  = (self.text and self.text ~= '')

    if self.icon then
        ImGui.DrawList_AddRectFilled(draw_list, min_x, min_y - v_pad, max_x, max_y + v_pad, (render_params.color & 0xFFFFFF00) | 0x40, 2)
        if has_text then
            ImGui.DrawList_PushClipRect (draw_list, min_x + istop , min_y - v_pad, max_x, max_y + v_pad)
        end
    end

    -- Flashing background
    if has_text then
        ImGui.DrawList_AddRectFilled  (draw_list, min_x, min_y - v_pad, max_x, max_y + v_pad, render_params.color, 2)
    end

    if self.icon then
        if has_text then
            ImGui.DrawList_PopClipRect(draw_list)
        end
    end
end

function Sticker:renderForeground(draw_list, render_params)
    local istop     = render_params.metrics.icon_stop
    local min_x     = render_params.metrics.min_x
    local min_y     = render_params.metrics.min_y
    local max_x     = render_params.metrics.max_x
    local max_y     = render_params.metrics.max_y
    local v_pad     = render_params.metrics.v_pad
    local has_text  = (self.text and self.text ~= '')

    local function _fullBorder(color)
        ImGui.DrawList_AddRect(draw_list, min_x, min_y - v_pad, max_x, max_y + v_pad, color, 1, 0, 1)
    end

    if self.icon then
        if has_text then
            --[[
            ImGui.DrawList_PushClipRect(draw_list, min_x, min_y - v_pad, min_x + istop , max_y + v_pad)
            _fullBorder(render_params.color)
            ImGui.DrawList_PopClipRect(draw_list)

            ImGui.DrawList_PushClipRect(draw_list, min_x + istop , min_y - v_pad, max_x, max_y + v_pad)
            _fullBorder(render_params.text_color)
            ImGui.DrawList_PopClipRect(draw_list)
            ]]
            _fullBorder(render_params.color)
        else
            _fullBorder(render_params.color)
        end
    else
        _fullBorder(render_params.color)
    end
end


-- First call to calculate metrics
-- Second call to draw
function Sticker:_renderPass(ctx, font_size, should_render, render_params)

    local sticker           = self

    local app_ctx           = AppContext.instance()
    local draw_list         = ImGui.GetWindowDrawList(ctx)

    local has_text          = sticker.text and sticker.text ~= ''
    local icon_font_size    = font_size + 4

    local icon_text_spacing = math.floor(font_size / 4.0 + 0.5)
    local h_pad             = math.floor(font_size / 2   + 0.5)
    local v_pad             = font_size/20.0
    local sticker_spacing   = 1 * font_size - 2

    ImGui.PushFont(ctx, app_ctx.arial_font, font_size)
    local base_text_height  = ImGui.GetTextLineHeightWithSpacing(ctx)
    local widget_height     = base_text_height + 2 * v_pad
    ImGui.PopFont(ctx)

    local metrics           = nil

    -- Those params should only be used in render mode
    local min_x, min_y      = 0, 0
    local max_x, max_y      = 0, 0
    local istop             = 0

    if should_render then
        metrics         = render_params.metrics
        min_x, min_y    = render_params.xstart, render_params.ystart
        max_x, max_y    = min_x + metrics.width, min_y + metrics.height
        metrics.min_x   = min_x
        metrics.min_y   = min_y
        metrics.max_x   = max_x
        metrics.max_y   = max_y
    end

    local xcursor = 0

    local  _textPass = function(_font, _font_size, _txt)
        ImGui.PushFont(ctx, _font, _font_size)
        local www, hhh    = ImGui.CalcTextSize(ctx, _txt)
        local diff_height = (hhh - base_text_height)

        if should_render then
            ImGui.DrawList_AddText(draw_list, min_x + xcursor, min_y + v_pad - diff_height * 0.5 + 0.5, render_params.text_color, _txt)
        end

        xcursor = xcursor + www
        ImGui.PopFont(ctx)
    end

    if should_render then
        self:renderBackground(draw_list, render_params)
    end

    if sticker.type == Sticker.Types.SPECIAL then
        -- Left blank padding
        xcursor = xcursor + h_pad

        _textPass(app_ctx.arial_font, font_size, "TODO")

        -- Right blank padding
        xcursor = xcursor + h_pad
    else
        if sticker.icon then
            local font = EmojImGui.Asset.Font(ctx, sticker.icon.font_name)

            xcursor = xcursor + icon_text_spacing

            -- Draw the icon
            _textPass(font, icon_font_size, sticker.icon.utf8)
            xcursor = xcursor + icon_text_spacing
            istop   = xcursor

            if has_text then
                xcursor = xcursor + icon_text_spacing
            end
        else
            xcursor = xcursor + h_pad
        end
    end

    -- Render / Measure main text
    if has_text then
        _textPass(app_ctx.arial_font, font_size, sticker.text)
        xcursor = xcursor + h_pad
    end

    local widget_width  = xcursor
    local max_x, max_y  = min_x + widget_width, min_y + widget_height

    if should_render then
        self:renderForeground(draw_list, render_params)
    end

    if should_render then
        ImGui.SetCursorScreenPos(ctx, max_x, min_y)
    end

    -- Return metrics
    return {
        width       = widget_width,
        height      = widget_height,
        spacing     = sticker_spacing,
        icon_stop   = istop,
        v_pad       = v_pad,
        h_pad       = h_pad,
        font_size   = font_size
    }
end

-- Should be called to calculate the widget metrics, that will be passed to render
function Sticker:PreRender(ctx, font_size)
    return self:_renderPass(ctx, font_size, false)
end

-- Render. Call pre-render to get metrics.
function Sticker:Render(ctx, pre_render_metrics, xstart, ystart, color, text_color)
    return self:_renderPass(ctx, pre_render_metrics.font_size, true, { metrics = pre_render_metrics, xstart = xstart, ystart = ystart, color = color, text_color = text_color } )
end

return Sticker
