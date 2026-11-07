-- DWD RankUp — Classic Era 1.15.x
-- 1) Upgrades lower-rank spells on your action bars to your highest rank.
-- 2) (Optional) When you learn a brand-new ability, adds it to the next empty action slot.
--    - Only on learn events (trainer/books), NOT on login and NOT on /dwdrank update.

local ADDON = ...
local RankUp = CreateFrame("Frame", "DWD_RankUpFrame")

-- ---------------- Saved Vars / Defaults ----------------
local function ensureDB()
  DWD_RankUpDB = DWD_RankUpDB or {}
  local db = DWD_RankUpDB
  if db.addNew == nil then db.addNew = true end          -- auto place new abilities on learn
  db.knownRanks = db.knownRanks or {}                     -- [spellName] = highestRankNum known last time
  return db
end
RankUp.db = ensureDB()

-- ---------------- Config ----------------
RankUp.enabled         = true
RankUp.debug           = false
RankUp.deferInCombat   = true
RankUp.debounceSeconds = 0.35   -- coalesce SPELLS_CHANGED bursts

-- ---------------- Slash ----------------
SLASH_DWDRANKUP1 = "/dwdrank"
SlashCmdList.DWDRANKUP = function(msg)
  msg = (msg or ""):lower():gsub("^%s+",""):gsub("%s+$","")
  if msg == "on" or msg == "enable" then
    RankUp.enabled = true; print("|cff00ff88DWD RankUp|r enabled.")
  elseif msg == "off" or msg == "disable" then
    RankUp.enabled = false; print("|cff00ff88DWD RankUp|r disabled.")
  elseif msg == "debug" then
    RankUp.debug = not RankUp.debug
    print("|cff00ff88DWD RankUp|r debug: "..tostring(RankUp.debug))
  elseif msg:match("^add") then
    local arg = msg:match("^add%s+(.*)$")
    if arg == "on" or arg == "enable" then RankUp.db.addNew = true
    elseif arg == "off" or arg == "disable" then RankUp.db.addNew = false
    else RankUp.db.addNew = not RankUp.db.addNew end
    print("|cff00ff88DWD RankUp|r auto-place new abilities: "..(RankUp.db.addNew and "|cff00ff00ON" or "|cffff0000OFF").."|r")
  elseif msg == "" or msg == "help" then
    print("|cff00ff88DWD RankUp|r commands:")
    print("  |cffffff00/dwdrank on|r, |cffffff00/dwdrank off|r  – enable/disable auto-upgrading")
    print("  |cffffff00/dwdrank update|r        – scan now and upgrade older ranks")
    print("  |cffffff00/dwdrank add [on|off]|r  – auto-place brand-new abilities on learn ("..(RankUp.db.addNew and "ON" or "OFF")..")")
    print("  |cffffff00/dwdrank debug|r         – toggle debug logs")
  else
    if msg == "update" or msg == "now" or msg == "scan" or msg == "fix" or msg == "rescan" then
      print("|cff00ff88DWD RankUp|r scanning action bars for outdated ranks...")
      RankUp:RunScan("manual") -- never auto-place in manual mode
    else
      print("|cff00ff88DWD RankUp|r unknown command. Try |cffffff00/dwdrank help|r.")
    end
  end
end

-- ---------------- Utils ----------------
local function dprint(...) if RankUp.debug then print("|cffaaaa88[RankUp]", ...) end end
local function cursorBusy() local t = GetCursorInfo(); return t ~= nil end
local function parseRankNum(rankStr) if not rankStr then return 0 end local n = rankStr:match("(%d+)"); return n and tonumber(n) or 0 end
local function getRankStrByID(id) return (GetSpellSubtext and GetSpellSubtext(id)) or select(2, GetSpellInfo(id)) end
local function isPassiveSpellSafe(id)
  if IsPassiveSpell then
    local ok = pcall(IsPassiveSpell, id)
    if ok then return IsPassiveSpell(id) end
  end
  return false
end

-- Highest-known per base name + spellID->bookslot
function RankUp:BuildHighestKnownMap()
  local highest, idToBook = {}, {}
  local tabs = GetNumSpellTabs()
  for t = 1, tabs do
    local _, _, offset, num = GetSpellTabInfo(t)
    for i = 1, num do
      local slot = offset + i
      local kind, id = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL)
      if kind == "SPELL" and id then
        local name = GetSpellInfo(id)
        if name then
          idToBook[id] = slot
          local r = parseRankNum(getRankStrByID(id))
          local cur = highest[name]
          if not cur or r > cur.rank then highest[name] = { id = id, rank = r } end
        end
      end
    end
  end
  return highest, idToBook
end

local function knownFromHighest(highest)
  local map = {}
  for name, info in pairs(highest) do map[name] = info.rank end
  return map
end

-- Compare slot rank vs. best rank
function RankUp:PlanUpgrades(highest)
  local plan = {}
  for slot = 1, 120 do
    local aType, aID = GetActionInfo(slot)
    if aType == "spell" and aID then
      local name = GetSpellInfo(aID)
      if name then
        local have = parseRankNum(getRankStrByID(aID))
        local best = highest[name]
        if best and have < best.rank then
          plan[slot] = { bestID = best.id, have = have, want = best.rank, name = name }
          dprint(("slot %d: %s %d -> %d"):format(slot, name, have, best.rank))
        end
      end
    end
  end
  return plan
end

-- Check if spell by base name is already on any action slot
function RankUp:IsOnBars(name)
  for slot = 1, 120 do
    local t, id = GetActionInfo(slot)
    if t == "spell" and id then
      local n = GetSpellInfo(id)
      if n == name then return true end
    end
  end
  return false
end

-- First empty slot (nil type)
function RankUp:FirstEmptySlot()
  for slot = 1, 120 do
    local t = GetActionInfo(slot)
    if not t then return slot end
  end
  return nil
end

-- Collect brand-new abilities since last time (by base name, not rank)
function RankUp:CollectNewAbilities(highest)
  local newList = {}
  for name, info in pairs(highest) do
    if not self.db.knownRanks[name] then
      if not isPassiveSpellSafe(info.id) then
        table.insert(newList, { name = name, id = info.id })
      end
    end
  end
  table.sort(newList, function(a,b) return a.name < b.name end)
  return newList
end

-- Robust pickup by ID -> name -> book slot
function RankUp:PickupBest(spellID, idToBook)
  ClearCursor()
  if PickupSpell then
    PickupSpell(spellID); if GetCursorInfo() == "spell" then return true end; ClearCursor()
    local name = GetSpellInfo(spellID)
    if name then PickupSpell(name); if GetCursorInfo() == "spell" then return true end; ClearCursor() end
  end
  local slot = idToBook[spellID]
  if slot then PickupSpellBookItem(slot, BOOKTYPE_SPELL); if GetCursorInfo() == "spell" then return true end; ClearCursor() end
  return false
end

-- Execute replacements. mode = "auto" (quiet unless changed) or "manual" (always summarize)
function RankUp:ExecuteUpgradePlan(plan, idToBook, mode)
  if InCombatLockdown() then
    if self.deferInCombat then
      self.deferPlan = self.deferPlan or {}
      self.deferPlan.upgrades = { plan = plan, idToBook = idToBook, mode = mode }
      self:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    return
  end
  if cursorBusy() then
    C_Timer.After(0.4, function() RankUp:ExecuteUpgradePlan(plan, idToBook, mode) end)
    return
  end

  local changed = 0
  for slot, info in pairs(plan) do
    if self:PickupBest(info.bestID, idToBook) then
      PlaceAction(slot); ClearCursor()
      changed = changed + 1
      print(("|cff00ff88DWD RankUp|r upgraded |cffffff00%s|r from |cffffff00Rank %d|r to |cffffff00Rank %d|r on slot %d.")
        :format(info.name, info.have, info.want, slot))
    end
  end

  if mode == "manual" then
    if changed > 0 then
      print(("|cff00ff88DWD RankUp|r updated %d slot(s)."):format(changed))
    else
      print("|cff00ff88DWD RankUp|r no outdated ranks found on your bars.")
    end
  else
    if changed > 0 then print(("|cff00ff88DWD RankUp|r updated %d slot(s)."):format(changed)) end
  end
end

-- Place newly learned abilities (auto mode only)
function RankUp:ExecuteAddNew(newList, idToBook, mode)
  if mode ~= "auto" or not self.db.addNew or #newList == 0 then return end
  if InCombatLockdown() then
    if self.deferInCombat then
      self.deferPlan = self.deferPlan or {}
      self.deferPlan.adds = { list = newList, idToBook = idToBook, mode = mode }
      self:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    return
  end
  if cursorBusy() then
    C_Timer.After(0.4, function() RankUp:ExecuteAddNew(newList, idToBook, mode) end)
    return
  end

  local placed = 0
  for _, entry in ipairs(newList) do
    if not self:IsOnBars(entry.name) then
      local slot = self:FirstEmptySlot()
      if not slot then break end
      if self:PickupBest(entry.id, idToBook) then
        PlaceAction(slot); ClearCursor()
        placed = placed + 1
        print(("|cff00ff88DWD RankUp|r added |cffffff00%s|r to slot %d."):format(entry.name, slot))
      end
    end
  end
  -- Quiet if nothing to add (since UI or another addon might already place it)
end

-- Run a full pass (upgrade ranks; optionally add new abilities)
function RankUp:RunScan(mode)
  if not self.enabled and mode ~= "manual" then return end
  C_Timer.After(0.20, function()
    local highest, idToBook = RankUp:BuildHighestKnownMap()
    local plan = RankUp:PlanUpgrades(highest)
    RankUp:ExecuteUpgradePlan(plan, idToBook, mode)
    -- Only auto mode considers adding new abilities
    if mode == "auto" then
      local newList = RankUp:CollectNewAbilities(highest)
      RankUp:ExecuteAddNew(newList, idToBook, mode)
    end
    -- Update snapshot of known ranks after we’re done
    RankUp.db.knownRanks = knownFromHighest(highest)
  end)
end

-- Debounce learn events
function RankUp:RequestAutoScan()
  if self._scanPending then return end
  self._scanPending = true
  C_Timer.After(self.debounceSeconds, function()
    self._scanPending = false
    RankUp:RunScan("auto")   -- quiet unless changed; may auto-add new abilities
  end)
end

-- ---------------- Events ----------------
RankUp:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    -- Take a snapshot so we don't treat existing spells as "new" on first load.
    local highest = select(1, self:BuildHighestKnownMap())
    self.db.knownRanks = knownFromHighest(highest)
    self:RunScan("manual")   -- first pass to upgrade ranks only (one summary line)
  elseif event == "LEARNED_SPELL_IN_TAB" or event == "SPELLS_CHANGED" then
    self:RequestAutoScan()
  elseif event == "PLAYER_REGEN_ENABLED" then
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local d = self.deferPlan; self.deferPlan = nil
    if d then
      if d.upgrades then self:ExecuteUpgradePlan(d.upgrades.plan, d.upgrades.idToBook, d.upgrades.mode) end
      if d.adds    then self:ExecuteAddNew(d.adds.list,        d.adds.idToBook,    d.adds.mode) end
    end
  end
end)

RankUp:RegisterEvent("PLAYER_LOGIN")
RankUp:RegisterEvent("LEARNED_SPELL_IN_TAB")
RankUp:RegisterEvent("SPELLS_CHANGED")
