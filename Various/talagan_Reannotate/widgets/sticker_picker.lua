-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description This file is part of Reannotate

local ImGui         = require "ext/imgui"
local AppContext    = require "classes/app_context"
local Sticker       = require "classes/sticker"

local StickerPicker = {}
StickerPicker.__index = StickerPicker

function StickerPicker:new()
  local instance = {}
  setmetatable(instance, self)
  instance:_initialize()
  return instance
end

function StickerPicker:_initialize()
  self.draw_count  = 0
  self.rand        = math.random()
  self.open        = true
end

function StickerPicker:setPosition(x,y)
  self.x, self.y = x, y
end

function StickerPicker:setSize(w,h)
  self.w, self.h = w, h
end

function StickerPicker:GrabFocus()
  self.grab_focus = true
end

function StickerPicker:title()
  return "Sticker Picker"
end

function StickerPicker:renderStickerZone(ctx, stickers)

    local base_font_size  = 10
    local num_on_line     = 0
    local xc, yc          = ImGui.GetCursorScreenPos(ctx)
    local last_vspacing   = nil

    for _, v in ipairs(stickers) do
      local sticker           = Sticker:new(v)
      local metrics           = sticker:PreRender(ctx, base_font_size)
      local estimated_width   = metrics.width
      local estimated_spacing = metrics.spacing

      xc, yc    = ImGui.GetCursorScreenPos(ctx)

      if num_on_line ~= 0 then
        estimated_width = estimated_spacing + estimated_width
      end

      local rw, _ = ImGui.GetContentRegionAvail(ctx)
      if estimated_width > rw and num_on_line ~= 0 then
        ImGui.NewLine(ctx)
        xc, yc  = ImGui.GetCursorScreenPos(ctx)
        yc      = yc + estimated_spacing
        ImGui.SetCursorScreenPos(ctx, xc, yc)
        num_on_line = 0
      elseif num_on_line ~= 0 then
        -- Add spacing for separation
        xc = xc + estimated_spacing
        ImGui.SetCursorScreenPos(ctx, xc, yc)
      end
      -- 0x40acffFF   0xffe240FF 0x753ffc
      sticker:Render(ctx, metrics, xc, yc, 0x753ffcFF, 0x000000FF)
      num_on_line = num_on_line + 1
      last_vspacing = estimated_spacing
    end

    if last_vspacing then
      local fpx, fpy = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
      ImGui.NewLine(ctx)
      xc, yc  = ImGui.GetCursorScreenPos(ctx)
      yc      = yc + fpy
      ImGui.SetCursorScreenPos(ctx, xc, yc)
      num_on_line = 0
      -- Ensure window extension by calling dummy
      ImGui.Dummy(ctx,0,0)
    end
end


function StickerPicker:draw()
  local app_ctx     = AppContext.instance()
  local ctx         = app_ctx.imgui_ctx


  ---ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0x753ffc40)
  -- Don't save the settings
  local b, is_open = ImGui.Begin(ctx, self:title() .. "##sticker_picker", true, ImGui.WindowFlags_TopMost | ImGui.WindowFlags_NoDocking)
  ---ImGui.PopStyleColor(ctx)

  if b then

    ImGui.PushID(ctx, "sticker_picker")

    if ImGui.IsWindowAppearing(ctx) or self.grab_focus then
      ImGui.SetKeyboardFocusHere(ctx)
      ImGui.SetWindowFocus(ctx)
    end

    if ImGui.IsWindowAppearing(ctx) then
      self.draw_count = 0
    end

    -- Type 0 : special, 1 : standard (icon+text)
    -- Type:icon:font:icon id:text. If no icon, no font / icon id at all.
    local list = { "1:::Thing", "1:1:1F3F4-E0067-E0062-E0077-E006C-E0073-E007F:That stuff", "0:category", "0:checkboxes", "1:0:1F616:Hopla", "1:1:1F616:Hoplu",  "1:1:1F616:",  "1:1:1F495:", "1:1:1F525:"  }

    ImGui.SeparatorText(ctx, "First stickers")
    self:renderStickerZone(ctx,list)

    ImGui.SeparatorText(ctx, "Second stickers")
    self:renderStickerZone(ctx,list)

    ImGui.PopID(ctx)
    ImGui.End(ctx)

    self.grab_focus = false
    self.draw_count = self.draw_count + 1
  end

  self.open = is_open
end

return StickerPicker
