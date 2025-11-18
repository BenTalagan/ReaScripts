-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description This file is part of Reannotate

local S       = require "modules/settings"
local JSON    = require "ext/json"

local Defines = {}

Defines.TT_DEFAULT_W = 300
Defines.TT_DEFAULT_H = 100
Defines.MAX_SLOTS    = 8 -- Slot 0 is counted

Defines.POST_IT_COLORS = {
    0xFFFFFF, -- WHITE      Slot 0
    0x40acff, -- BLUE
    0x753ffc, -- VIOLET
    0xff40e5, -- PINK
    0xffe240, -- YELLOW
    0x3cf048, -- GREEN
    0xff9640, -- ORANGE
    0xff4040, -- RED        Slot 7
}

function Defines.ActiveProject()
    local p, _ = reaper.EnumProjects(-1)
    return p
end

function Defines.RetrieveProjectSlotLabels()
    local _, str = reaper.GetSetMediaTrackInfo_String(reaper.GetMasterTrack(Defines.ActiveProject()), "P_EXT:Reannotate_ProjectSlotLabels", "", false)
    local slot_labels = {}
    if str == "" or str == nil then
    else
        slot_labels = JSON.decode(str)
    end

    -- Ensure labels have names by defaulting to global setting
    for i = 0, Defines.MAX_SLOTS -1 do
        slot_labels[i+1] = slot_labels[i+1] or S.getSetting("SlotLabel_" .. i)
    end

    Defines.slot_labels = slot_labels
end

function Defines.CommitProjectSlotLabels()
    if not Defines.slot_labels_dirty  then return end
    if not Defines.slot_labels        then Defines.RetrieveProjectSlotLabels() end

    local str = JSON.encode(Defines.slot_labels)
    reaper.GetSetMediaTrackInfo_String(reaper.GetMasterTrack(Defines.ActiveProject()), "P_EXT:Reannotate_ProjectSlotLabels", str, true)
    Defines.slot_labels_dirty = false
end

function Defines.SlotColor(slot)
    return Defines.POST_IT_COLORS[slot+1]
end

function Defines.SlotLabel(slot)
    if not Defines.slot_labels then Defines.RetrieveProjectSlotLabels() end
    return Defines.slot_labels[slot+1]
end

function Defines.SetSlotLabel(slot, label)
    if not Defines.slot_labels then Defines.RetrieveProjectSlotLabels() end
    Defines.slot_labels[slot+1] = label
    Defines.slot_labels_dirty = true
    Defines.CommitProjectSlotLabels()
end

function Defines.defaultTooltipSize()
    return Defines.TT_DEFAULT_W, Defines.TT_DEFAULT_H
end

return Defines

