-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description This file is part of MaCCLane

local D               = require "modules/defines"

local GRID            = require "modules/grid"
local UTILS           = require "modules/utils"
local PIANOROLL       = require "modules/piano_roll"
local CHUNK           = require "modules/chunk"
local VELLANE         = require "modules/vellane"
local PITCHSNAP       = require "modules/pitch_snap"

local TabParams       = require "modules/tab_params"

-- Sanitizers for every module.

local function _SanitizeDocking(params)
    params.docking                             = params.docking or {}
    params.docking.mode                        = TabParams.DockingMode:sanitize(params.docking.mode, 'bypass')

    params.docking.if_docked                   = params.docking.if_docked or {}
    params.docking.if_docked.mode              = TabParams.IfDockedMode:sanitize(params.docking.if_docked.mode, 'bypass')
    params.docking.if_docked.size              = params.docking.if_docked.size or 500

    params.docking.if_windowed                 = params.docking.if_windowed or {}
    params.docking.if_windowed.mode            = TabParams.IfWindowedMode:sanitize(params.docking.if_windowed.mode, 'bypass')
    params.docking.if_windowed.coords          = params.docking.if_windowed.coords or { x=0, y=0, w=800, h=600 }
end

local function _SanitizeTimeWindow(params)
    params.time_window                         = params.time_window or {}

    params.time_window.positioning             = params.time_window.positioning or {}
    params.time_window.positioning.mode        = TabParams.TimeWindowPosMode:sanitize(params.time_window.positioning.mode, 'bypass')
    params.time_window.positioning.anchoring   = TabParams.TimeWindowAnchoring:sanitize(params.time_window.positioning.anchoring, 'left')
    params.time_window.positioning.position    = params.time_window.positioning.position or '0'

    params.time_window.sizing                  = params.time_window.sizing or {}
    params.time_window.sizing.mode             = TabParams.TimeWindowSizingMode:sanitize(params.time_window.sizing.mode, 'bypass')
    params.time_window.sizing.size             = params.time_window.sizing.size or '1'
end

local function _SanitizeCCLanes(params)
    params.cc_lanes                            = params.cc_lanes          or {}
    params.cc_lanes.mode                       = TabParams.CCLaneMode:sanitize(params.cc_lanes.mode, 'bypass')
    params.cc_lanes.entries                    = params.cc_lanes.entries  or {}

    for i,v in pairs(params.cc_lanes.entries) do
        v.height                                    = v.height or 0
        v.inline_ed_height                          = v.inline_ed_height or 0
        v.zoom_factor                               = v.zoom_factor or 1
        v.zoom_offset                               = v.zoom_offset or 0
    end
end

local function _SanitizePianoRoll(params)
    params.piano_roll                          = params.piano_roll or {}
    params.piano_roll.mode                     = TabParams.PianoRollMode:sanitize(params.piano_roll.mode, 'bypass')
    params.piano_roll.low_note                 = params.piano_roll.low_note or 0
    params.piano_roll.high_note                = params.piano_roll.high_note or 127
    params.piano_roll.fit_time_scope           = TabParams.PianoRollFitTimeScope:sanitize(params.piano_roll.fit_time_scope , 'visible')
    params.piano_roll.fit_owner_scope          = TabParams.PianoRollFitOwnerScope:sanitize(params.piano_roll.fit_owner_scope , 'track')
    params.piano_roll.fit_chan_scope           = params.piano_roll.fit_chan_scope or -2
end

local function _SanitizeMIDIChans(params)
   params.midi_chans                          = params.midi_chans or {}
   params.midi_chans.mode                     = TabParams.MidiChanMode:sanitize(params.midi_chans.mode, 'bypass')
   params.midi_chans.bits                     = params.midi_chans.bits or 0
   params.midi_chans.current                  = params.midi_chans.current or 'bypass' -- 'bypass' or number. It's not an enum.
end

local function _SanitizeActions(params)
    params.actions                             = params.actions or {}
    params.actions.mode                        = TabParams.ActionMode:sanitize(params.actions.mode, 'bypass')
    params.actions.entries                     = params.actions.entries or {}

    for i,v in pairs(params.actions.entries) do
        v.section                                   = v.section or 'midi_editor'
        v.id                                        = v.id or 0
        v.when                                      = TabParams.ActionWhen:sanitize(v.when, 'after')
    end
end

local function _SanitizeGrid(params)
    params.grid                                = params.grid or {}
    params.grid.mode                           = TabParams.GridMode:sanitize(params.grid.mode, 'bypass')
    params.grid.val                            = params.grid.val      or '' -- save as string
    params.grid.type                           = TabParams.GridType:sanitize(params.grid.type, 'straight')
    params.grid.swing                          = params.grid.swing    or 0  -- save as number
end

local function _SanitizeColoring(params)
    params.coloring                            = params.coloring or {}
    params.coloring.mode                       = TabParams.MEColoringMode:sanitize(params.coloring.mode, 'bypass')
    params.coloring.type                       = TabParams.MEColoringType:sanitize(params.coloring.type, 'track')
end

local function Sanitize(tab)
    local params = tab.params

    params.title                               = params.title or "???"

    params.role                                = params.role or ''
    params.priority                            = params.priority or 0

    params.color                               = params.color or {}
    params.color.mode                          = TabParams.ColorMode:sanitize(params.color.mode, 'bypass')
    params.color.color                         = params.color.color or 0xFFFFFFFF

    params.margin                              = params.margin or {}
    params.margin.mode                         = TabParams.MarginMode:sanitize(params.margin.mode, 'bypass')
    params.margin.margin                       = params.margin.margin or 10

    _SanitizeDocking(params)
    _SanitizeTimeWindow(params)
    _SanitizeCCLanes(params)
    _SanitizePianoRoll(params)
    _SanitizeMIDIChans(params)
    _SanitizeActions(params)
    _SanitizeGrid(params)
    _SanitizeColoring(params)

    tab.state = tab.state or {}
end


local function ReadGrid(tab, is_state)
    local mec       = tab.mec
    local params    = (is_state) and (tab.state) or (tab.params)

    if not mec.take then return end

    local val, type, swing = GRID.GetMIDIEditorGrid(mec)

    local p, q, err = GRID.ToFrac(val)
    local str = "" .. p .. "/" .. q
    if q == 1 then str = "" .. p end

    _SanitizeGrid(params)
    params.grid.val      = str
    params.grid.type     = type
    params.grid.swing    = math.floor(swing * 100)
end

local function ReadDockingMode(tab, is_state)
    local params    = (is_state) and (tab.state) or (tab.params)

    _SanitizeDocking(params)
    local is_docked     = (reaper.GetToggleCommandStateEx(D.SECTION_MIDI_EDITOR, D.ACTION_ME_SET_DOCKED) == 1)

    if is_docked then   params.docking.mode = 'docked'
    else                params.docking.mode = 'windowed'
    end
end

local function ReadDockHeight(tab, is_state)
    local mec       = tab.mec
    local params    = (is_state) and (tab.state) or (tab.params)
    local bounds    = UTILS.JS_Window_GetBounds(mec.me, false)

    _SanitizeDocking(params)
    params.docking.if_docked.size = bounds.h + 20 -- For the bottom tab bar
end

local function ReadWindowBounds(tab, is_state)
    local mec       = tab.mec
    local params    = (is_state) and (tab.state) or (tab.params)
    local bounds    = UTILS.JS_Window_GetBounds(mec.me, true)

    _SanitizeDocking(params)
    params.docking.if_windowed.coords.x = bounds.l
    params.docking.if_windowed.coords.y = bounds.b
    params.docking.if_windowed.coords.w = bounds.w
    params.docking.if_windowed.coords.h = bounds.h
end

local function ReadCurrentPianoRollLowNote(tab, is_state)
    local mec       = tab.mec
    local params    = (is_state) and (tab.state) or (tab.params)

    _SanitizePianoRoll(params)
    local l, h = PIANOROLL.range(mec.me)
    if l and h then
        params.piano_roll.low_note  = l
    end
end

local function ReadCurrentPianoRollHighNote(tab, is_state)
    local mec       = tab.mec
    local params    = (is_state) and (tab.state) or (tab.params)

    _SanitizePianoRoll(params)
    local l, h = PIANOROLL.range(mec.me)
    if l and h then
        params.piano_roll.high_note  = h
    end
end

local function ReadMidiChans(tab, is_state)
    local params    = (is_state) and (tab.state) or (tab.params)

    params.midi_chans.bits  = tab:getActiveChanBits()
end

local function ReadColoring(tab, is_state)
    local mec       = tab.mec
    local params    = (is_state) and (tab.state) or (tab.params)

    if not mec.take then return end

    _SanitizeColoring(params)
    params.coloring.type = GRID.GetColoringType(mec)
end


-- Don't forget to call .entries on both dst and src table
local function PatchVellaneEntries(dst_table, src_table, mode)
    if mode == 'replace' then
        for k, v in pairs(dst_table) do dst_table[k] = nil end
        for k, v in pairs(src_table) do
            dst_table[#dst_table+1] = v
        end
    elseif mode == 'add_missing' then
        local lookup = {}
        for k, v in pairs(dst_table) do lookup[v.num] = v end
        for k, v in pairs(src_table) do
            local existing_entry = lookup[v.num]
            if not existing_entry then
                -- Add missing entry
                dst_table[#dst_table+1] = v
            end
        end
    elseif mode == 'merge' then
        local lookup = {}
        for k, v in pairs(dst_table) do lookup[v.num] = v end
        for k, v in pairs(src_table) do
            local existing_entry = lookup[v.num]
            if not existing_entry then
                -- Add missing entry
                dst_table[#dst_table+1] = v
            else
                -- Remplace all values in existing entry
                for kk, vv in pairs(v) do
                    existing_entry[kk] = vv
                end
            end
        end
    end
end

local function NewVirginVellane(num)
    return {
        num = num,
        height = 30,
        inline_ed_height = 10,
        zoom_offset = 0,
        zoom_factor = 1,
        lead = ''
    }
end

-- Format :
-- { entries: table, start_pos, end_pos, chunk }
local function ReadVellanes(tab)
    local mec       = tab.mec

    local ichunk    = CHUNK.getItemChunk(mec.item)
    local vellanes  = VELLANE.readVellanesFromChunk(ichunk)

    for _, e in ipairs(vellanes.entries) do
        if e.num == 128 then
            local tchunk = CHUNK.getTrackChunk(mec.track)
            e.snap = PITCHSNAP.hasPitchBendSnap(tchunk)
            break
        end
    end
    return vellanes
end

local function SnapShotVellanes(tab, is_state)
    local params   = (is_state) and (tab.state) or (tab.params)
    _SanitizeCCLanes(params)

    local vellanes = ReadVellanes(tab)
    PatchVellaneEntries(params.cc_lanes.entries, vellanes.entries, 'replace')
end
local function SnapShotGrid(tab)
    ReadGrid(tab, true)
end
local function SnapShotDockingMode(tab)
    ReadDockingMode(tab, true)
end
local function SnapShotDockHeight(tab)
    ReadDockHeight(tab,true)
end
local function SnapShotWindowBounds(tab)
    ReadWindowBounds(tab,true)
end
local function SnapShotPianoRoll(tab)
    ReadCurrentPianoRollHighNote(tab, true)
    ReadCurrentPianoRollLowNote(tab, true)
end
local function SnapShotMidiChans(tab)
    ReadMidiChans(tab, true)
end
local function SnapShotColoring(tab)
    ReadColoring(tab, true)
end

return {
    Sanitize                        = Sanitize,

    ReadGrid                        = ReadGrid,
    ReadDockHeight                  = ReadDockHeight,
    ReadWindowBounds                = ReadWindowBounds,
    ReadCurrentPianoRollLowNote     = ReadCurrentPianoRollLowNote,
    ReadCurrentPianoRollHighNote    = ReadCurrentPianoRollHighNote,
    ReadMidiChans                   = ReadMidiChans,
    ReadColoring                    = ReadColoring,
    ReadVellanes                    = ReadVellanes,

    SnapShotGrid                    = SnapShotGrid,
    SnapShotDockHeight              = SnapShotDockHeight,
    SnapShotWindowBounds            = SnapShotWindowBounds,
    SnapShotPianoRoll               = SnapShotPianoRoll,
    SnapShotMidiChans               = SnapShotMidiChans,
    SnapShotColoring                = SnapShotColoring,
    SnapShotVellanes                = SnapShotVellanes,
    SnapShotDockingMode             = SnapShotDockingMode,

    PatchVellaneEntries             = PatchVellaneEntries,
    NewVirginVellane                = NewVirginVellane
}
