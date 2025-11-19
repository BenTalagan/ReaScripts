-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description This file is part of Reannotate

local Notes = require 'classes/notes'

local MemCache = {}
MemCache.__index = MemCache

function MemCache:new()
  local instance = {}
  setmetatable(instance, self)
  instance:_initialize()
  return instance
end

function MemCache:_initialize()
  self._repo = {}

  MemCache.__singleton = self
end

function MemCache:getObjectCache(object)
  local guid = ''
  local name = ''
  local type = ''
  if reaper.ValidatePtr(object, "MediaTrack*") then
    local tguid = reaper.GetTrackGUID(object)
    local _, tname = reaper.GetTrackName(object)
    guid = tguid
    name = tname
    type = 'track'
  elseif reaper.ValidatePtr(object,"MediaItem*") then
    local _, tguid = reaper.GetSetMediaItemInfo_String(object, "GUID", "", false)
    local take = reaper.GetActiveTake(object)
    if take then
      name = reaper.GetTakeName(take)
    end
    guid = tguid
    type = 'item'
  elseif reaper.ValidatePtr(object, "TrackEnvelope*") then
    local _, tguid = reaper.GetSetEnvelopeInfo_String(object, "GUID", "", false)
    local _, ename = reaper.GetEnvelopeName(object)
    guid = tguid
    name = ename
    type = 'env'
  elseif reaper.ValidatePtr(object, "ReaProject*") then
    local _, tguid = reaper.GetSetProjectInfo_String(object, "PROJECT_NAME", "", false)
    guid = tguid
    name = "Project"
    type = 'project'
  else
    error("Unhandled type for object")
  end

  if not self._repo[guid] then
    -- Cache miss, pull info from object
    self._repo[guid] = {
      guid    = guid,
      object  = object,
      name    = name,
      type    = type,
      -- Notes cache
      notes   = Notes:new(object)
    }
  end

  return self._repo[guid]
end

function MemCache.instance()
  if not MemCache.__singleton then
    MemCache.__singleton = MemCache:new()
  end

  return MemCache.__singleton
end

return MemCache
