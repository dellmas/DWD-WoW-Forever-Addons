-- DWD Bagnon Helper - Forever
-- Only the inventory window is guarded. No Blizzard bag/UI functions or
-- Bagnon source files are replaced, and no bag settings or item data are saved.
local ADDON = ...
local controller = CreateFrame("Frame")
local states = setmetatable({}, {__mode = "k"})
local bagnon, attachedManager
local leavingWorld, loggingOut = false, false

local function chat(message)
  print("|cff00c0ffDWD Bagnon Helper:|r " .. message)
end

local function removeEscapeEntry(frame)
  local name = frame:GetName()
  if not name or type(UISpecialFrames) ~= "table" then return end
  -- Otherwise CloseSpecialWindows considers the bag closed even when Hide is
  -- blocked, consuming every Escape press instead of opening the game menu.
  for index = #UISpecialFrames, 1, -1 do
    if UISpecialFrames[index] == name then table.remove(UISpecialFrames, index) end
  end
end

local function shouldHold(state)
  return state.keepOpen and not leavingWorld and not loggingOut
end

local function restore(state)
  if not shouldHold(state) or state.frame:IsShown() then return end
  -- A cached native Hide can bypass an instance's Lua method. Restore only
  -- after Bagnon's OnHide cleanup; never force protected frames during combat.
  if InCombatLockdown() and state.frame.IsProtected and state.frame:IsProtected() then
    state.pending = true
    return
  end
  state.pending = false
  state.frame:Show()
end

local function queueRestore(state)
  if state.queued or not shouldHold(state) then return end
  state.queued = true
  C_Timer.After(0, function()
    state.queued = false
    restore(state)
  end)
end

local function bindCloseButton(state)
  local button = state.frame.CloseButton
  if not button then return end
  local original = button:GetScript("OnClick")
  if original ~= state.closeHandler then
    state.closeHandler = function(self, ...)
      -- One explicit X click releases this window, including any queued
      -- restoration. Its next normal open arms the guard again.
      state.keepOpen, state.pending = false, false
      if original then return original(self, ...) end
      return state.hide(state.frame)
    end
    button:SetScript("OnClick", state.closeHandler)
  end
  -- Some skins hide the regular X; it must remain accessible in X-only mode.
  button:Show()
end

local function attachFrame(frame)
  if not frame or frame.id ~= "inventory" or not frame[0] then return end
  local state = states[frame]
  if state then
    removeEscapeEntry(frame)
    bindCloseButton(state)
    return
  end
  state = {frame = frame, hide = frame.Hide, setShown = frame.SetShown,
    keepOpen = bagnon.Ready and frame:IsShown() or false}
  states[frame] = state

  -- Guard the actual frame: this also covers HIDE_ALL signals, Escape,
  -- interaction callbacks, bag-key toggles and direct inventory:Hide calls.
  frame.Hide = function(self, ...)
    if not shouldHold(state) then return state.hide(self, ...) end
  end
  if type(state.setShown) == "function" then
    frame.SetShown = function(self, shown)
      if shown or not shouldHold(state) then return state.setShown(self, shown) end
    end
  end
  frame:HookScript("OnShow", function(self)
    -- Bagnon briefly shows/hides inventory before Ready to build item buttons.
    -- Do not mistake that initialization for the user opening their bags.
    if bagnon.Ready and not loggingOut then state.keepOpen = true end
    removeEscapeEntry(self)
    bindCloseButton(state)
    if self.RegisterSignal then self:RegisterSignal("HIDE_ALL", "Hide") end
  end)
  frame:HookScript("OnHide", function(self)
    -- IsShown remains true when only an ancestor (e.g. Alt-Z's UIParent) hides.
    if not self:IsShown() then queueRestore(state) end
  end)
  if type(frame.UpdateVisuals) == "function" then
    hooksecurefunc(frame, "UpdateVisuals", function() bindCloseButton(state) end)
  end
  removeEscapeEntry(frame)
  bindCloseButton(state)
  if frame:IsShown() and frame.RegisterSignal then frame:RegisterSignal("HIDE_ALL", "Hide") end
end

local function attachExisting()
  for _, frame in ipairs(bagnon.Frames.Registry or {}) do attachFrame(frame) end
end

local function initialize()
  bagnon = _G.Bagnon
  if not bagnon or not bagnon.Frames or type(bagnon.Frames.New) ~= "function" then return end
  if not attachedManager then
    attachedManager = bagnon.Frames
    -- Runs after registration but before Frames:Show calls frame:Show, so the
    -- first real open is guarded without creating/opening a window ourselves.
    hooksecurefunc(attachedManager, "New", attachExisting)
    attachExisting()
  end
end

controller:RegisterEvent("ADDON_LOADED")
controller:RegisterEvent("PLAYER_LOGIN")
controller:RegisterEvent("PLAYER_ENTERING_WORLD")
controller:RegisterEvent("PLAYER_LEAVING_WORLD")
controller:RegisterEvent("PLAYER_REGEN_ENABLED")
controller:RegisterEvent("PLAYER_LOGOUT")
controller:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_LOGOUT" then
    loggingOut = true
  elseif event == "PLAYER_LEAVING_WORLD" then
    leavingWorld = true
  elseif event == "PLAYER_ENTERING_WORLD" then
    leavingWorld = false
    initialize()
    if bagnon then
      attachExisting()
      for _, state in pairs(states) do queueRestore(state) end
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    for _, state in pairs(states) do if state.pending then queueRestore(state) end end
  elseif event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and (name == ADDON or name == "Bagnon")) then
    initialize()
  end
end)

SLASH_DWDBAGNONHELPER1 = "/dwdbags"
SlashCmdList.DWDBAGNONHELPER = function()
  if not attachedManager then
    chat("Bagnon is not ready. Enable Bagnon and restart WoW.")
  else
    chat("X-only closing is active for inventory. Map, Escape and bag toggles keep it open. Click its X to close.")
  end
end

initialize()
