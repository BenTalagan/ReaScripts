-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description This file is part of Legatool

-- Functions and defines
local S                   = require "modules/settings"
local UTILS               = require "modules/utils"
local LTContext           = require "modules/context"
local ImGui               = require "ext/imgui"
local ctx                 = nil

LTContext.snap_piano_roll = S.getSetting("PinToMidiEditor")
_,_,LTContext.sectionID, LTContext.cmdID,_,_,_ = reaper.get_action_context()

-----------------------

local function needsImGuiContext()
    return #LTContext.notes == 2
end

local function app()

    -- Watch tool status
    local current_state = reaper.GetToggleCommandStateEx(LTContext.sectionID, LTContext.cmdID)
    if current_state == 0 then
        LTContext.shouldQuit = true
        return
    end

    local me = reaper.MIDIEditor_GetActive()
    if not me then ctx = nil ; return end

    local take = reaper.MIDIEditor_GetTake(me)
    if not take then ctx = nil; return end

    local item = reaper.GetMediaItemTake_Item(take)
    local track = reaper.GetMediaItemTake_Track(take)

    LTContext.take = take

    local _, th = reaper.MIDI_GetHash(take, true)
    if th ~= LTContext.last_hash then
        LTContext.last_hash = th

        local ni = 0
        local notes = {}
        while true do
            local b, sel, _, startppq, endppq, _, _, _ = reaper.MIDI_GetNote(take, ni)

            if not b then break end

            if sel then
                notes[#notes+1] = {
                    ni        = ni,
                    startppq  = startppq,
                    endppq    = endppq
                }
            end

            ni = ni + 1
        end

        LTContext.notes = notes
    end

    if needsImGuiContext() then

        if not ctx then
            ctx = ImGui.CreateContext("Legatool", ImGui.ConfigFlags_NoKeyboard)
        end

        ImGui.SetNextWindowSizeConstraints(ctx,200,35,2000,35)

        local flags = ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoTitleBar

        if LTContext.snap_piano_roll then
            local piano_roll_hwnd   = reaper.JS_Window_FindChildByID(me, 1001)
            local pr_bounds         = UTILS.JS_Window_GetBounds(piano_roll_hwnd, true)
            local x,y = ImGui.PointConvertNative(ctx, pr_bounds.l, pr_bounds.t)
            ImGui.SetNextWindowSize(ctx, pr_bounds.w, 35)
            ImGui.SetNextWindowPos(ctx, x, y-2)
            flags = flags | ImGui.WindowFlags_NoResize
        end

        local visible, open = ImGui.Begin(ctx, "Legatool", true, flags)
        if visible then
            if ImGui.IsWindowFocused(ctx) then
                if not LTContext.focustimer or ImGui.IsAnyMouseDown(ctx) then
                    -- create or reset the timer when there's activity in the window
                    LTContext.focustimer = reaper.time_precise()
                end

                if (reaper.time_precise() - LTContext.focustimer > 0.1) then
                    reaper.JS_Window_SetFocus(reaper.MIDIEditor_GetActive())
                end
            else
                LTContext.focustimer = nil
            end

            local act_col = LTContext.snap_piano_roll

            if act_col then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x0091fbff)
            end

            if ImGui.Button(ctx, "P") then
                if (LTContext.snap_piano_roll == true) then
                    LTContext.snap_piano_roll = false
                else
                    LTContext.snap_piano_roll = true
                end
                S.setSetting("PinToMidiEditor", LTContext.snap_piano_roll)
            end

            if act_col then ImGui.PopStyleColor(ctx) end

            if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) then
                ImGui.SetTooltip(ctx, "Pin to the top of the MIDI Editor")
            end

            ImGui.SameLine(ctx)

            local w, _ = ImGui.GetContentRegionAvail(ctx)
            ImGui.SetNextItemWidth(ctx, w - 70)

            local n1, n2  = LTContext.notes[1], LTContext.notes[2]
            local p       = reaper.MIDI_GetProjTimeFromPPQPos(take, math.floor(0.5 + 0.5 * (n1.endppq + n2.startppq)))
            local s       = reaper.MIDI_GetProjTimeFromPPQPos(take, n1.startppq)
            local e       = reaper.MIDI_GetProjTimeFromPPQPos(take, n2.endppq)

            local tstr     = reaper.format_timestr_pos(p, '', 0)
            local bstr     = reaper.format_timestr_pos(p, '', 2)


            local b, v = ImGui.SliderDouble(ctx, " Legatool##slider", p, s + 0.00001, e - 0.00001, "Mid : " .. bstr .. " / " .. tstr)
            if b then
                --reaper.ShowConsoleMsg("YO " .. v .. "\n")
                if not LTContext.startState then
                    LTContext.startState = { notes = UTILS.deepcopy(LTContext.notes) }

                    local n1, n2 = LTContext.startState.notes[1], LTContext.startState.notes[2]

                    -- Calculate starting intervals
                    local m = math.floor(0.5 + 0.5 * (n1.endppq + n2.startppq) )
                    local l = n1.endppq
                    local r = n2.startppq

                    n1.diff = m - l
                    n2.diff = m - r

                    reaper.MIDI_DisableSort(take)
                end

                local n1, n2    = LTContext.notes[1], LTContext.notes[2]
                local ns1, ns2  = LTContext.startState.notes[1], LTContext.startState.notes[2]

                local vppq      = reaper.MIDI_GetPPQPosFromProjTime(take, v)

                reaper.MIDI_SetNote(take, n1.ni, nil, nil, nil, math.floor(0.5 + vppq - ns1.diff),  nil, nil, nil, true)
                reaper.MIDI_SetNote(take, n2.ni, nil, nil, math.floor(0.5 + vppq - ns2.diff), nil, nil, nil, nil, true)
            else
                if LTContext.startState then
                    LTContext.startState = nil
                    reaper.Undo_BeginBlock()
                    reaper.MIDI_Sort(take)
                    reaper.UpdateItemInProject(item)
                    reaper.MarkTrackItemsDirty(track, item)
                    reaper.Undo_EndBlock("Legatool - Adjusted two notes", -1)
                end
            end

            ImGui.End(ctx)
        end

        if not open then
            LTContext.shouldQuit = true
        end

    else
        ctx = nil
    end
end

local function _app()

    -- Performances on my imac when idle, for reference
    --    Averages during one second (perf.sec1)
    --    - total_ms        : 4.5ms
    --    - usage_perc      : 0.45 % (same value *1000 (ms->s) /100 (perc) )
    --    - frames skipped  : 31/34
    --    - forced redraws  : 1-2 (redraw at low pace or when needed only)
    aaa_perf = UTILS.perf_ms(
        function()
            app()
        end
    )

    if not LTContext.shouldQuit then
        reaper.defer(_app)
    end
end

local function run(args)
    local _,_,sectionID,cmdID,_,_,_ = reaper.get_action_context()
    reaper.SetToggleCommandState(sectionID, cmdID, 1)

    -- Define cleanup callbacks
    reaper.atexit(function()
        -- On exit, always clear the state
        reaper.SetToggleCommandState(sectionID, cmdID, 0)
    end)

    reaper.defer(_app)
end

return {
    run = run
}
