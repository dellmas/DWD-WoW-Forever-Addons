-- DWD Party XP (Forever) — HUD-only player, party, and pet XP for WoW Forever 1.60.x.
-- Settings panel + Shift-Right-Click opener, with modern Settings UI and legacy fallback.
-- v1.4.10-forever: Live position watcher plus character-keyed account persistence.
-- Pet XP support (hunter pets with XP bars, warlock/other summons shown at level).

local ADDON, PREFIX = ..., "PXPS"

------------------------------------------------------------
-- Defaults / Config
------------------------------------------------------------
local MAX_ROWS  = 5
local ROW_H     = 18
local BAR_W     = 110
local BAR_H     = 10
local LABEL_W   = 150
local SEGMENTS  = 20
local PAD_RIGHT = 8
local BORDER_A  = 0.85

-- Colors
local XP_COLOR_PURPLE    = {0.58, 0.00, 0.55}
local XP_COLOR_RESTED    = {0.08, 0.45, 0.95}
local REST_OVERLAY_COLOR = {0.60, 0.85, 1.00, 0.75}
local XP_COLOR_PET       = {0.20, 0.70, 0.30}
local SEP_COLOR          = {0.45, 0.45, 0.45, 0.6}

local POOL_SIZE = 16   -- max row frames in the pool (players + pets)
local SEP_H     = 6    -- vertical space consumed by a separator line
local PET_HAPPINESS_POLL_SECONDS = 3
local PET_REFRESH_DELAYS = {0.2, 0.8, 2.0, 5.0}

local DEFAULTS = {
  scale     = 1.0,
  showText  = true,
  hudTextColor = {1,1,1},
  hudBarW   = BAR_W,
  hudBarH   = BAR_H,
  labelW    = LABEL_W,
  rowH      = ROW_H,
  maxRows   = MAX_ROWS,
  segments  = SEGMENTS,
  padRight  = PAD_RIGHT,
  borderA   = BORDER_A,

  pos       = nil,
  locked    = false,
  hidden    = false,
  petAlertPos = nil,
  petAlertSound = true,

  testMode  = false,
  showPets  = true,
  petDefaultsVersion = 0,
}

local function CopySavedTable(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for key, item in pairs(value) do
    copy[CopySavedTable(key, seen)] = CopySavedTable(item, seen)
  end
  return copy
end

local function CharacterKey()
  return DWD_ForeverIdentity.Key(false)
end

local function EnsureDefaults()
  -- Forever writes per-character SavedVariables but does not consistently
  -- restore them. Persist through the reliable account file while retaining
  -- strict per-character separation inside that file.
  DWD_PartyXP_Forever_Store = type(DWD_PartyXP_Forever_Store) == "table"
    and DWD_PartyXP_Forever_Store or {}
  DWD_PartyXP_Forever_Store.characters = type(DWD_PartyXP_Forever_Store.characters) == "table"
    and DWD_PartyXP_Forever_Store.characters or {}

  local key = CharacterKey()
  local characterDB = DWD_ForeverIdentity.Adopt(DWD_PartyXP_Forever_Store.characters, key)
  if type(characterDB) ~= "table" then
    local legacy = type(DWD_PartyXP_Forever_CharacterDB) == "table" and DWD_PartyXP_Forever_CharacterDB
      or (type(DWD_PartyXP_Forever_DB) == "table" and DWD_PartyXP_Forever_DB)
      or (type(DWD_PartyXP_DB) == "table" and DWD_PartyXP_DB)
      or (type(DWD_PartyXP_Forever_Seed) == "table" and DWD_PartyXP_Forever_Seed)
    characterDB = CopySavedTable(legacy or {})

    -- Recover the last position still present in Forever's backup. The live
    -- per-character file was overwritten with this exact default anchor.
    local p = characterDB.pos
    if p and p.point == "CENTER" and p.relativePoint == "CENTER"
      and (tonumber(p.x) or 0) == 0 and (tonumber(p.y) or 0) == -110 then
      characterDB.pos = {
        point = "TOP", relativePoint = "TOP",
        x = 62.49984359741211, y = -114.0001525878906,
      }
    end
    DWD_PartyXP_Forever_Store.characters[key] = characterDB
  end
  DWD_PartyXP_Forever_CharacterDB = characterDB
  DWD_PartyXP_Forever_DB = characterDB
  DWD_PartyXP_DB = characterDB

  for k,v in pairs(DEFAULTS) do
    if DWD_PartyXP_DB[k] == nil then
      if type(v) == "table" then
        local t = {}; for i=1,#v do t[i]=v[i] end; DWD_PartyXP_DB[k] = t
      else
        DWD_PartyXP_DB[k] = v
      end
    end
  end
end

local function InitializeDatabase()
  -- ADDON_LOADED fires after this addon's SavedVariables have been restored.
  -- Initializing here avoids replacing a save that Forever loads later than
  -- the addon's main Lua chunk.
  EnsureDefaults()

  -- v1.2.5 migration: older saved variables may have pet rows disabled.
  -- Flip them on once, but preserve the user's choice after this migration.
  if (DWD_PartyXP_DB.petDefaultsVersion or 0) < 1 then
    DWD_PartyXP_DB.showPets = true
    DWD_PartyXP_DB.petDefaultsVersion = 1
  end
end

-- Quick getters (read current DB every time so sliders apply live)
local function CFG_HUD_W()    return DWD_PartyXP_DB.hudBarW end
local function CFG_HUD_H()    return DWD_PartyXP_DB.hudBarH end
local function CFG_LABEL_W()  return DWD_PartyXP_DB.labelW end
local function CFG_ROW_H()    return DWD_PartyXP_DB.rowH end
local function CFG_MAX_ROWS() return DWD_PartyXP_DB.maxRows end
local function CFG_SEGMENTS() return DWD_PartyXP_DB.segments end
local function CFG_PAD()      return DWD_PartyXP_DB.padRight end
local function CFG_BORDER_A() return DWD_PartyXP_DB.borderA end

------------------------------------------------------------
-- State / Utils
------------------------------------------------------------
local f = CreateFrame("Frame", "DWD_PartyXP_ForeverFrame", UIParent, "BackdropTemplate")
local PANEL -- will hold the options panel frame
local Roster, lastSent, sendCD = {}, 0, 3
local FAKE_KEY, FAKE_NAME, FAKE_REALM = "__FAKE1__", "Testy", "Sandbox"
local HELLO_MSG = "HELLO"
local heartbeatTicker
local positionTicker

-- Forever is a new client branch. Keep the small number of API touchpoints
-- behind compatibility wrappers so beta builds can add/remove legacy aliases
-- without preventing the whole add-on from loading.
local Transport = {sent=0, received=0, matched=0, unmatched=0}

local function RegisterAddonPrefix()
  local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
  if type(register) ~= "function" then
    Transport.registration = "API unavailable"
    return false
  end
  local ok, result = pcall(register, PREFIX)
  Transport.registration = ok and (result == false and "rejected" or "registered") or "failed"
  if not ok then Transport.lastError = tostring(result) end
  return ok and result ~= false
end

local function SendAddonMessageCompat(message, channel)
  local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
  if type(send) ~= "function" then Transport.lastError = "Send API unavailable"; return false end
  Transport.sent = Transport.sent + 1
  local ok, result = pcall(send, PREFIX, message, channel)
  Transport.lastSendResult = ok and tostring(result) or "error"
  if not ok then Transport.lastError = tostring(result) end
  return ok, result
end

local function RegisterEventIfAvailable(event)
  local ok = pcall(f.RegisterEvent, f, event)
  if not ok and type(DWD_PartyXP_DB) == "table" and DWD_PartyXP_DB.debug then
    print("|cffffaa00DWD Party XP (Forever):|r event unavailable: " .. event)
  end
  return ok
end

local function Now() return GetTime() end
local function isGrouped() return IsInGroup() or IsInRaid() end

-- Returns a safe realm string even very early at login
local function SafeRealm()
  local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
  if r == "" or r == nil then
    return "UnknownRealm"
  end
  -- strip spaces and punctuation (apostrophes, spaces, etc.) so addon messages are consistent
  r = r:gsub("[%s%p]+", "")
  return r
end

local function UnitFullName(unit)
  local name = DWD_ForeverIdentity.Get(unit)
  if not name then return nil end
  return name .. "-" .. SafeRealm(), name
end

local function MyFullName()
  return UnitFullName("player") or ("Unknown-" .. SafeRealm())
end

-- Forever party members can occupy different internal realms. Match the
-- complete character name, including surname, then store data under the local
-- HUD key. The remote realm must not decide whether a visible party row matches.
local function ResolveRosterKey(messageName, sender)
  local function matches(text, key, name)
    return type(text) == "string" and (text == key or text == name
      or text:sub(1, #name + 1) == name .. "-")
  end
  local function find(text)
    for i=0,4 do
      local unit = i == 0 and "player" or ("party" .. i)
      if UnitExists(unit) then
        local key, name = UnitFullName(unit)
        if key and matches(text, key, name) then return key end
      end
    end
  end
  return find(sender) or find(messageName)
end

local function SendChannel()
  if IsInRaid() then return nil end
  if IsInGroup() then return "PARTY" end
  return nil
end

local function numfmt(n)
  if not n then return "0" end
  local s = tostring(n)
  local left,num,right = s:match("^([^%d]*%d)(%d*)(.-)$")
  return left..num:reverse():gsub("(%d%d%d)","%1,"):reverse()..right
end

------------------------------------------------------------
-- Distance helpers (yards to party members) + in-combat name strobe
-- NOTE:
--   * UnitDistanceSquared only works for group units and is unavailable in many instanced situations.
--   * "XP range" is not directly exposed; we only display yards so you can apply thresholds as you like.
------------------------------------------------------------
local function Round(n)
  if not n then return 0 end
  return math.floor(n + 0.5)
end

local DIST_RED_THRESHOLD = 240 -- yards: distance text turns red at/above this value

local function IsPartyUnit(unit)
  return type(unit) == "string" and unit:match("^party%d$") ~= nil
end

local function GetUnitDistanceYards(unit)
  if not unit or not UnitExists(unit) then return nil end
  if type(UnitDistanceSquared) ~= "function" then return nil end
  -- Values may be unavailable (or protected on newer clients) in instances.
  local ok, yards = pcall(function()
    local dsq, valid = UnitDistanceSquared(unit)
    if not valid or not dsq or dsq < 0 then return nil end
    return math.sqrt(dsq)
  end)
  if ok then return yards end
  return nil
end

-- Strobe phase: toggles about twice per second (red <-> white)
local function StrobeOn()
  return (math.floor(GetTime() * 2) % 2) == 0
end

local function ClassColor(name, class)
  if not name then return "?" end
  if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
    local c = RAID_CLASS_COLORS[class]
    return ("|cff%02x%02x%02x%s|r"):format(c.r*255, c.g*255, c.b*255, name)
  end
  return name
end

local function FormatNameForLabel(name, unit, class)
  if not name then return "?" end
  local colored = ClassColor(name, class)
  if unit == "player" or unit == FAKE_KEY then
    return colored
  end

  -- Party member name strobes red while they are in combat.
  if UnitExists(unit) and UnitAffectingCombat and UnitAffectingCombat(unit) then
    if StrobeOn() then
      return "|cffff0000" .. name .. "|r"
    else
      return colored
    end
  end

  return colored
end

local function LabelFits(fontString, text, extraText)
  if not fontString or not fontString.SetText or not fontString.GetStringWidth then
    return true
  end

  local maxW = (fontString.GetWidth and fontString:GetWidth()) or CFG_LABEL_W()
  fontString:SetText((text or "") .. (extraText or ""))
  return (fontString:GetStringWidth() or 0) <= math.max(1, maxW - 2)
end

local function FitNameInLabel(fontString, rawName, buildLabel, extraText)
  rawName = rawName or "?"
  local full = buildLabel(rawName)
  if LabelFits(fontString, full, extraText) then
    return full
  end

  local len = #rawName
  if len <= 1 then
    return buildLabel(rawName)
  end

  local best
  local lo, hi = 1, len - 1
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local candidate = buildLabel(rawName:sub(1, mid) .. "...")
    if LabelFits(fontString, candidate, extraText) then
      best = candidate
      lo = mid + 1
    else
      hi = mid - 1
    end
  end

  return best or buildLabel("...")
end

local function BuildBaseLabel(row, extraText)
  if not row then return "" end
  local lvl = row._lvl or 0
  local p = row._percentStr
  local pct = p and ("  " .. p .. "%") or (row._showUnknownPercent and "  ...%" or "")
  return FitNameInLabel(row.text, row._shortName, function(name)
    local n = FormatNameForLabel(name, row._unit, row._class)
    return string.format("%s (%d)%s", n, lvl, pct)
  end, extraText)
end

local function FormatDistanceForLabel(unit)
  -- Player row should not show distance.
  if unit == "player" or unit == FAKE_KEY then return "" end

  if IsPartyUnit(unit) then
    if UnitIsConnected and UnitExists(unit) and not UnitIsConnected(unit) then
      return ""
    end

    local yards = GetUnitDistanceYards(unit)
    if yards then
      local y = Round(yards)
      local color = (y >= DIST_RED_THRESHOLD) and "ffff0000" or "ffffffff"
      return ("  |c%s%dy|r"):format(color, y)
    end
    return "  |cffaaaaaa??y|r"
  end

  return ""
end

-- Lightweight ticker to keep distances + strobing live as you move / fight.
local distTicker

local function StartDistanceTicker()
  if distTicker then distTicker:Cancel() end
  if C_Timer and C_Timer.NewTicker then
    distTicker = C_Timer.NewTicker(0.35, function()
      if not f or not f.rows then return end
      if IsInRaid() or (DWD_PartyXP_DB and DWD_PartyXP_DB.hidden) then return end

      for _, row in ipairs(f.rows) do
        if row and row:IsShown() and row._unit and row._shortName and not row._isPet then
          local distance = FormatDistanceForLabel(row._unit)
          local base = BuildBaseLabel(row, distance)
          row._baseLabel = base

          local label = base .. distance
          if row.text and row.text.GetText and row.text.SetText and row.text:GetText() ~= label then
            row.text:SetText(label)
          end
        end
      end
    end)
  end
end

------------------------------------------------------------
-- Scale / Position
------------------------------------------------------------
local function ApplyScale()
  if f and DWD_PartyXP_DB and DWD_PartyXP_DB.scale then
    f:SetScale(DWD_PartyXP_DB.scale)
  end
end

local function SavePosition()
  if not f or type(DWD_PartyXP_DB) ~= "table" then return end
  local point, _, relativePoint, x, y = f:GetPoint(1)
  if not point then return end
  DWD_PartyXP_DB.pos = {
    point = point,
    relativePoint = relativePoint or point,
    x = tonumber(x) or 0,
    y = tonumber(y) or 0,
  }
end

-- DWD Profiles calls this immediately before taking a named snapshot so a
-- just-finished drag is captured even before the periodic watcher runs.
_G.DWD_PartyXP_Forever_SavePosition = SavePosition

local function PositionChanged()
  if not f or type(DWD_PartyXP_DB) ~= "table" then return false end
  local point, _, relativePoint, x, y = f:GetPoint(1)
  if not point then return false end
  local saved = DWD_PartyXP_DB.pos
  if type(saved) ~= "table" then return true end
  if saved.point ~= point or (saved.relativePoint or saved.point) ~= (relativePoint or point) then
    return true
  end
  return math.abs((tonumber(saved.x) or 0) - (tonumber(x) or 0)) > 0.01
    or math.abs((tonumber(saved.y) or 0) - (tonumber(y) or 0)) > 0.01
end

local function StartPositionWatcher()
  if positionTicker or not C_Timer or type(C_Timer.NewTicker) ~= "function" then return end
  C_Timer.After(3, function()
    if positionTicker then return end
    positionTicker = C_Timer.NewTicker(0.5, function()
      -- Capture the frame's real anchor even on Forever builds that omit the
      -- final drag-stop callback. Delaying startup avoids recording UIParent's
      -- temporary login layout before RestorePosition has run.
      if f._dwdInitialized and not f._dwdRestoringPosition and PositionChanged() then
        SavePosition()
      end
    end)
  end)
end

local function RestorePosition()
  if not f then return end
  f._dwdRestoringPosition = true
  f:ClearAllPoints()
  local p = DWD_PartyXP_DB.pos
  if p then
    f:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or p.point or "CENTER", p.x or 0, p.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -110)
  end
  f._dwdRestoringPosition = false
end

------------------------------------------------------------
-- Forward declarations
------------------------------------------------------------
local OpenConfig
local CreateOptionsPanel
local sendMine
local seedSelf
local SafeUnitPetXP
local GetOwnPetData
local PetUnitForOwner
local IsPetUnit
local RunPetDebug
local StartPetHappinessTicker
local ShowPetAlert
local SetPetAlertMoveMode
local ResetPetAlertPosition
local HandlePetAlertCommand

------------------------------------------------------------
-- HUD rows / geometry
------------------------------------------------------------
local function ensureTicks(row)
  row.bar.ticks = row.bar.ticks or {}
  for i=1, CFG_SEGMENTS()-1 do
    local t = row.bar.ticks[i] or row.bar:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(0,0,0,0.70)
    local x = (CFG_HUD_W()/CFG_SEGMENTS())*i
    t:ClearAllPoints()
    t:SetPoint("LEFT", row.bar, "LEFT", x-0.5, 0)
    t:SetSize(1, CFG_HUD_H())
    t:Show()
    row.bar.ticks[i] = t
  end
  for i=CFG_SEGMENTS(), #row.bar.ticks do
    if row.bar.ticks[i] then row.bar.ticks[i]:Hide() end
  end
end

local function makeRow(parent, idx)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(CFG_HUD_W() + CFG_LABEL_W() + 20, CFG_ROW_H())
  row:SetPoint("TOPLEFT", 8, -6 - CFG_ROW_H()*idx)

  -- Separator line (shown above this row when a visual break is needed)
  row.separator = row:CreateTexture(nil, "OVERLAY")
  row.separator:SetHeight(1)
  row.separator:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 2)
  row.separator:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", -CFG_PAD(), 2)
  row.separator:SetColorTexture(unpack(SEP_COLOR))
  row.separator:Hide()

  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT")
  row.text:SetWidth(CFG_LABEL_W())
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)
  row.text:SetMaxLines(1)

  -- rested underlay
  row.rest = CreateFrame("StatusBar", nil, row)
  row.rest:SetPoint("RIGHT", -CFG_PAD(), 0)
  row.rest:SetSize(CFG_HUD_W(), CFG_HUD_H())
  row.rest:SetMinMaxValues(0, 1)
  row.rest:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  row.rest:SetStatusBarColor(unpack(REST_OVERLAY_COLOR))
  row.rest:SetFrameStrata("LOW")

  -- main fill
  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetPoint("RIGHT", -CFG_PAD(), 0)
  row.bar:SetSize(CFG_HUD_W(), CFG_HUD_H())
  row.bar:SetMinMaxValues(0, 1)
  row.bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  row.bar:SetStatusBarColor(unpack(XP_COLOR_PURPLE))
  row.bar:SetFrameStrata("LOW")
  row.rest:SetFrameLevel(row.bar:GetFrameLevel() - 1)

  row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
  row.bar.bg:SetAllPoints(); row.bar.bg:SetColorTexture(0,0,0,0.35)

  row.border = CreateFrame("Frame", nil, row)
  row.border:SetPoint("RIGHT", -CFG_PAD(), 0)
  row.border:SetSize(CFG_HUD_W()+2, CFG_HUD_H()+2)
  row.border:SetFrameStrata("LOW")
  row.border.tex = row.border:CreateTexture(nil, "ARTWORK")
  row.border.tex:SetAllPoints()
  row.border.tex:SetTexture("Interface/Tooltips/UI-StatusBar-Border")
  row.border.tex:SetVertexColor(0,0,0,CFG_BORDER_A())

  ensureTicks(row)
  row.restMark = row.bar:CreateTexture(nil, "OVERLAY")
  row.restMark:SetColorTexture(1,1,1,0.9)
  row.restMark:SetSize(1, CFG_HUD_H())
  row.restMark:Hide()

  row.bar.valueText = row.bar:CreateFontString(nil, "OVERLAY")
  row.bar.valueText:SetFont(STANDARD_TEXT_FONT, 11, "THICKOUTLINE")
  row.bar.valueText:SetPoint("CENTER")
  do
    local c = DWD_PartyXP_DB.hudTextColor
    row.bar.valueText:SetTextColor(c[1], c[2], c[3], 1)
  end

  row:SetFrameStrata("LOW")
  return row
end

local function titleText()
  if IsInRaid() then return "" end
  if DWD_PartyXP_DB.testMode and not isGrouped() then return "Party XP (Test)" end
  return isGrouped() and "Party XP" or "Player XP"
end

local function RefreshRowGeometry(row)
  row:SetSize(CFG_HUD_W() + CFG_LABEL_W() + 20, CFG_ROW_H())
  row.text:SetWidth(CFG_LABEL_W())
  row.rest:SetSize(CFG_HUD_W(), CFG_HUD_H())
  row.bar:SetSize(CFG_HUD_W(), CFG_HUD_H())
  row.border:SetSize(CFG_HUD_W()+2, CFG_HUD_H()+2)
  row.border.tex:SetVertexColor(0,0,0,CFG_BORDER_A())
  ensureTicks(row)
  row.restMark:SetSize(1, CFG_HUD_H())
  if row.separator then
    row.separator:ClearAllPoints()
    row.separator:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 2)
    row.separator:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", -CFG_PAD(), 2)
  end
end

local function RefreshGeometry()
  if not f.rows then return end
  for _, row in ipairs(f.rows) do RefreshRowGeometry(row) end
end

local function listUnitsHUD()
  local t = {"player"}
  if not IsInRaid() then
    for i=1,4 do
      local u = "party"..i
      if UnitExists(u) then
        t[#t+1] = u
      end
    end
  end
  if DWD_PartyXP_DB.testMode and not isGrouped() then t[#t+1] = FAKE_KEY end
  return t
end

local function updateHUD()
  if IsInRaid() then f:Hide(); return end
  if DWD_PartyXP_DB.hidden then f:Hide(); return end
  f:Show()
  f.title:SetText(titleText())

  local units = listUnitsHUD()
  local isParty = #units > 1
  local rowIdx = 0
  local yOff = -20    -- start below the title

  for u = 1, math.min(#units, CFG_MAX_ROWS()) do
    local unit = units[u]
    if rowIdx >= POOL_SIZE then break end

    -- Separator before non-first player group
    local wantSep = isParty and u > 1

    -- ── Player row ──
    rowIdx = rowIdx + 1
    local row = f.rows[rowIdx]
    if not row then break end

    if wantSep then row.separator:Show(); yOff = yOff - SEP_H
    else row.separator:Hide() end

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 8, yOff)
    row._isPet = false

    local full, short, lvl, online, info
    if unit == FAKE_KEY then
      full = FAKE_NAME.."-"..FAKE_REALM; short = FAKE_NAME
      info = Roster[full]; lvl = (info and info.level) or 22; online = true
    else
      full, short = UnitFullName(unit)
      lvl = UnitLevel(unit)
      online = UnitIsConnected(unit); info = full and Roster[full] or nil
    end

    local xp, xpMax, rested, percent = 0, 0, 0, nil
    if info and info.xpMax and info.xpMax > 0 then
      xp, xpMax = info.xp or 0, info.xpMax
      rested    = info.rested or 0
      percent   = math.floor((xp/xpMax)*100 + 0.5)
    end

    local cls = (info and info.class)
                or (unit ~= FAKE_KEY and unit ~= "player" and select(2, UnitClass(unit)))
                or select(2, UnitClass("player"))
    row._unit = unit
    row._shortName = short or "?"
    row._lvl = lvl or 0
    row._class = cls
    row._percentStr = (percent ~= nil) and tostring(percent) or nil
    row._showUnknownPercent = online and percent == nil

    local distance = FormatDistanceForLabel(unit)
    local baseLabel = BuildBaseLabel(row, distance)
    row._baseLabel = baseLabel
    row.text:SetText(baseLabel .. distance)

    if online and info and info.xpMax and info.xpMax > 0 then
      row.rest:SetMinMaxValues(0, xpMax)
      row.bar:SetMinMaxValues(0, xpMax)
      if (rested or 0) > 0 then
        row.bar:SetStatusBarColor(unpack(XP_COLOR_RESTED))
        local restedTo = math.min(xp + rested, xpMax)
        row.rest:SetValue(restedTo); row.rest:Show()
        local px = (restedTo / xpMax) * CFG_HUD_W()
        row.restMark:ClearAllPoints()
        row.restMark:SetPoint("LEFT", row.bar, "LEFT", px-0.5, 0)
        row.restMark:Show()
      else
        row.bar:SetStatusBarColor(unpack(XP_COLOR_PURPLE))
        row.rest:SetValue(0); row.rest:Hide(); row.restMark:Hide()
      end
      row.bar:SetValue(xp)
      row.bar.valueText:SetText(("XP: %s / %s"):format(numfmt(xp), numfmt(xpMax)))
      row.bar.valueText:SetShown(DWD_PartyXP_DB.showText ~= false)
    else
      row.rest:SetMinMaxValues(0,1); row.rest:SetValue(0); row.rest:Hide()
      row.bar:SetMinMaxValues(0,1);  row.bar:SetValue(0)
      row.restMark:Hide()
      row.bar.valueText:SetText(online and "XP: … / …" or "Offline")
      row.bar.valueText:SetShown(DWD_PartyXP_DB.showText ~= false)
    end

    row:Show()
    yOff = yOff - CFG_ROW_H()

    -- ── Pet row (if enabled and a pet exists) ──
    if DWD_PartyXP_DB.showPets ~= false and rowIdx < POOL_SIZE then
      local petName, petLvl, petXP, petXPMax, petLoyalty, petHappiness, petDamage, petLoyaltyRate
      if info then
        petName        = info.petName
        petLvl         = info.petLevel
        petXP          = info.petXP
        petXPMax       = info.petXPMax
        petLoyalty     = info.petLoyalty
        petHappiness   = info.petHappiness
        petDamage      = info.petDamage
        petLoyaltyRate = info.petLoyaltyRate
      end

      -- Determine the pet unit id for direct queries
      local petUnit = PetUnitForOwner(unit)

      -- If we know a pet exists from the unit API, grab live data even if no roster data arrived yet.
      if petUnit and UnitExists(petUnit) then
        if unit == "player" then
          local liveName, liveLvl, liveXP, liveXPMax, liveLoy, liveHappy, liveDmg, liveLoyRate = GetOwnPetData()
          if liveName and liveName ~= "" and liveName ~= "NONE" then
            petName        = liveName
            petLvl         = liveLvl
            petXP          = liveXP
            petXPMax       = liveXPMax
            petLoyalty     = liveLoy
            petHappiness   = liveHappy
            petDamage      = liveDmg
            petLoyaltyRate = liveLoyRate
          end
        else
          if not petName or petName == "" or petName == "NONE" then
            petName = UnitName(petUnit) or "Pet"
          end
          if not petLvl or petLvl == 0 then
            petLvl = UnitLevel(petUnit) or 0
          end

          if not petXPMax or petXPMax <= 0 then
            local liveXP, liveXPMax = SafeUnitPetXP(petUnit)
            if liveXPMax > 0 then
              petXP = liveXP
              petXPMax = liveXPMax
            end
          end
        end
      end

      local hasPet = petName and petName ~= "" and petName ~= "NONE"

      if hasPet then
        rowIdx = rowIdx + 1
        local petRow = f.rows[rowIdx]
        if petRow then
          petRow.separator:Hide()
          petRow:ClearAllPoints()
          petRow:SetPoint("TOPLEFT", 8, yOff)
          petRow._isPet = true
          petRow._unit  = petUnit
          petRow._class = nil

          petXP      = petXP or 0
          petXPMax   = petXPMax or 0
          petLvl     = petLvl or 0
          petLoyalty = petLoyalty or 0
          petHappiness = petHappiness or 0
          petDamage = petDamage or 0
          petLoyaltyRate = petLoyaltyRate or 0
          local petPct = (petXPMax > 0) and math.floor((petXP / petXPMax) * 100 + 0.5) or nil
          local loyStr = (petLoyalty > 0) and (" LL" .. petLoyalty) or ""

          -- Build indented label:  - PetName (Lvl)  XX% LL#
          local petLabel = FitNameInLabel(petRow.text, petName, function(name)
            if petPct then
              return string.format("  |cff666666-|r |cff33bb55%s|r (%d)  %d%%%s", name, petLvl, petPct, loyStr)
            end
            return string.format("  |cff666666-|r |cff33bb55%s|r (%d)%s", name, petLvl, loyStr)
          end)
          petRow._shortName  = petName
          petRow._lvl        = petLvl
          petRow._percentStr = petPct and tostring(petPct) or ""
          petRow._baseLabel  = petLabel
          petRow.text:SetText(petLabel)

          -- Fill the XP bar
          if petXPMax > 0 then
            petRow.rest:SetMinMaxValues(0, petXPMax)
            petRow.bar:SetMinMaxValues(0, petXPMax)
            petRow.bar:SetStatusBarColor(unpack(XP_COLOR_PET))
            petRow.rest:SetValue(0); petRow.rest:Hide()
            petRow.restMark:Hide()
            petRow.bar:SetValue(petXP)
            petRow.bar.valueText:SetText(("XP: %s / %s"):format(numfmt(petXP), numfmt(petXPMax)))
            petRow.bar.valueText:SetShown(DWD_PartyXP_DB.showText ~= false)
          else
            -- Pet exists but has no XP tracking (warlock minion, etc.)
            petRow.rest:SetMinMaxValues(0,1); petRow.rest:SetValue(0); petRow.rest:Hide()
            petRow.bar:SetMinMaxValues(0,1);  petRow.bar:SetValue(0)
            petRow.bar:SetStatusBarColor(unpack(XP_COLOR_PET))
            petRow.restMark:Hide()
            petRow.bar.valueText:SetText("|cff888888No XP|r")
            petRow.bar.valueText:SetShown(DWD_PartyXP_DB.showText ~= false)
          end

          petRow:Show()
          yOff = yOff - CFG_ROW_H()
        end
      end
    end
  end

  -- Hide unused rows
  for i = rowIdx + 1, POOL_SIZE do
    if f.rows[i] then
      f.rows[i]:Hide()
      f.rows[i].separator:Hide()
    end
  end

  f:SetSize(CFG_HUD_W() + CFG_LABEL_W() + 28, math.abs(yOff) + 4)
end

------------------------------------------------------------
-- Pet loyalty helper
------------------------------------------------------------
local LOYALTY_MAP = {
  ["Rebellious"]=1, ["Unruly"]=2, ["Submissive"]=3,
  ["Dependable"]=4, ["Faithful"]=5, ["Best Friend"]=6,
}
local function GetPetLoyaltyNum()
  if not GetPetLoyalty then return 0 end
  local s = GetPetLoyalty()
  if not s or s == "" then return 0 end
  local n = s:match("(%d+)")
  if n then return tonumber(n) end
  return LOYALTY_MAP[s] or 0
end

local PetHappinessState = {
  value = nil,
  petGUID = nil,
}

local function PetHappinessLabel(happiness)
  happiness = tonumber(happiness) or 0
  if happiness == 3 then return "Happy" end
  if happiness == 2 then return "Content" end
  if happiness == 1 then return "Unhappy" end
  return "Unknown"
end

local function ResetPetHappinessTracking()
  PetHappinessState.value = nil
  PetHappinessState.petGUID = nil
end

local function GetOwnPetHappinessData(petUnit)
  petUnit = petUnit or "pet"
  if type(GetPetHappiness) ~= "function" then
    return 0, 0, 0
  end

  if not UnitExists(petUnit) and not UnitExists("pet") and not UnitExists("playerpet") then
    return 0, 0, 0
  end

  local ok, happiness, damagePercentage, loyaltyRate = pcall(GetPetHappiness)
  if not ok then return 0, 0, 0 end

  happiness = tonumber(happiness) or 0
  damagePercentage = tonumber(damagePercentage) or 0
  loyaltyRate = tonumber(loyaltyRate) or 0
  return happiness, damagePercentage, loyaltyRate
end

local petAlertFrame

local function PlayPetAlertSound()
  if DWD_PartyXP_DB.petAlertSound == false then
    return
  end

  if type(PlaySoundFile) == "function" then
    local soundFile = "Interface\\AddOns\\DWD_PartyXP_Forever\\media\\s-growl.mp3"
    local ok, didPlay = pcall(PlaySoundFile, soundFile, "Master")
    if ok and didPlay ~= false then
      return
    end

    ok, didPlay = pcall(PlaySoundFile, soundFile)
    if ok and didPlay ~= false then
      return
    end
  end

  if type(PlaySound) ~= "function" then
    return
  end

  local sound = (SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN) or 844
  local ok = pcall(PlaySound, sound, "Master")
  if not ok then
    pcall(PlaySound, sound)
  end
end

local function SavePetAlertPosition()
  if not petAlertFrame then return end
  local point, _, relativePoint, x, y = petAlertFrame:GetPoint(1)
  DWD_PartyXP_DB.petAlertPos = {
    point = point or "CENTER",
    relativePoint = relativePoint or point or "CENTER",
    x = x or 0,
    y = y or 0,
  }
end

local function RestorePetAlertPosition()
  if not petAlertFrame then return end
  petAlertFrame:ClearAllPoints()
  local p = DWD_PartyXP_DB.petAlertPos
  if p then
    petAlertFrame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or p.point or "CENTER", p.x or 0, p.y or 0)
  else
    petAlertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
  end
end

local function EnsurePetAlertFrame()
  if petAlertFrame then return petAlertFrame end

  petAlertFrame = CreateFrame("Frame", "DWD_PartyXP_PetAlertFrame", UIParent, "BackdropTemplate")
  petAlertFrame:SetSize(360, 42)
  petAlertFrame:SetFrameStrata("HIGH")
  petAlertFrame:SetClampedToScreen(true)
  petAlertFrame:SetMovable(true)
  petAlertFrame:EnableMouse(false)
  petAlertFrame:RegisterForDrag("LeftButton")
  petAlertFrame:SetScript("OnDragStart", function(self)
    if self._moveMode then self:StartMoving() end
  end)
  petAlertFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePetAlertPosition()
  end)

  petAlertFrame.text = petAlertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  petAlertFrame.text:SetPoint("CENTER", 0, 4)
  petAlertFrame.text:SetJustifyH("CENTER")
  petAlertFrame.text:SetFont(STANDARD_TEXT_FONT, 20, "THICKOUTLINE")
  petAlertFrame.text:SetTextColor(1.0, 0.82, 0.0, 1)

  petAlertFrame.hint = petAlertFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  petAlertFrame.hint:SetPoint("TOP", petAlertFrame.text, "BOTTOM", 0, -2)
  petAlertFrame.hint:SetTextColor(0.85, 0.85, 0.85, 1)
  petAlertFrame.hint:SetText("Drag to move. /dwdxp alert lock when done.")
  petAlertFrame.hint:Hide()

  RestorePetAlertPosition()
  petAlertFrame:Hide()
  return petAlertFrame
end

ShowPetAlert = function(message, r, g, b, playSound)
  local frame = EnsurePetAlertFrame()
  if frame._moveMode then return end

  if playSound then
    PlayPetAlertSound()
  end

  frame.text:SetText(message or "")
  frame.text:SetTextColor(r or 1.0, g or 0.82, b or 0.0, 1)
  frame.hint:Hide()
  frame:SetBackdrop(nil)
  frame:SetAlpha(1)
  frame:Show()
  frame._hideToken = (frame._hideToken or 0) + 1
  local token = frame._hideToken
  if C_Timer and C_Timer.After then
    C_Timer.After(4, function()
      if petAlertFrame and petAlertFrame._hideToken == token and not petAlertFrame._moveMode then
        petAlertFrame:Hide()
      end
    end)
  end
end

SetPetAlertMoveMode = function(enabled)
  local frame = EnsurePetAlertFrame()
  frame._moveMode = enabled and true or false
  frame:EnableMouse(frame._moveMode)

  if frame._moveMode then
    frame.text:SetText("Pet mood alert")
    frame.text:SetTextColor(1.0, 0.82, 0.0, 1)
    frame.hint:Show()
    frame:SetBackdrop({
      bgFile="Interface/Tooltips/UI-Tooltip-Background",
      edgeFile="Interface/Tooltips/UI-Tooltip-Border",
      edgeSize=12
    })
    frame:SetBackdropColor(0, 0, 0, 0.45)
    frame:SetBackdropBorderColor(1.0, 0.82, 0.0, 0.85)
    frame:Show()
    print("|cff00ff88DWD Party XP|r: pet alert move mode ON. Drag the sample text, then use |cffffff00/dwdxp alert lock|r.")
  else
    SavePetAlertPosition()
    frame.hint:Hide()
    frame:SetBackdrop(nil)
    frame:Hide()
    print("|cff00ff88DWD Party XP|r: pet alert position saved.")
  end
end

ResetPetAlertPosition = function()
  DWD_PartyXP_DB.petAlertPos = nil
  local frame = EnsurePetAlertFrame()
  frame._moveMode = false
  frame:EnableMouse(false)
  frame.hint:Hide()
  frame:SetBackdrop(nil)
  RestorePetAlertPosition()
  ShowPetAlert("Pet alert reset.", 1.0, 0.82, 0.0)
end

local function PrintPetAlertStatus()
  local petUnit = PetUnitForOwner and (PetUnitForOwner("player") or "pet") or "pet"
  local currentHappy = select(1, GetOwnPetHappinessData(petUnit))
  local frame = EnsurePetAlertFrame()
  print("|cff00ff88DWD Party XP|r pet alert status:")
  print("  petUnit=" .. tostring(petUnit)
    .. " exists=" .. ((UnitExists(petUnit) or UnitExists("pet") or UnitExists("playerpet")) and "Y" or "N"))
  print("  current=" .. PetHappinessLabel(currentHappy) .. " (" .. tostring(currentHappy or 0) .. ")"
    .. " tracked=" .. PetHappinessLabel(PetHappinessState.value) .. " (" .. tostring(PetHappinessState.value or 0) .. ")")
  print("  moveMode=" .. (frame._moveMode and "Y" or "N"))
  print("  sound=" .. (DWD_PartyXP_DB.petAlertSound == false and "OFF" or "ON"))
end

HandlePetAlertCommand = function(val)
  val = (val or "test"):lower():gsub("^%s+",""):gsub("%s+$","")
  local subcmd, subval = val:match("^(%S+)%s+(.*)$")

  if val == "move" or val == "unlock" then
    SetPetAlertMoveMode(true)
  elseif val == "lock" or val == "done" then
    SetPetAlertMoveMode(false)
  elseif val == "reset" then
    ResetPetAlertPosition()
  elseif val == "status" then
    PrintPetAlertStatus()
  elseif val == "sound" then
    PlayPetAlertSound()
    print("|cff00ff88DWD Party XP|r: pet alert sound " .. (DWD_PartyXP_DB.petAlertSound == false and "OFF" or "ON") .. ".")
  elseif subcmd == "sound" then
    subval = (subval or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    if subval == "on" or subval == "1" or subval == "true" then
      DWD_PartyXP_DB.petAlertSound = true
      PlayPetAlertSound()
      print("|cff00ff88DWD Party XP|r: pet alert sound ON.")
    elseif subval == "off" or subval == "0" or subval == "false" then
      DWD_PartyXP_DB.petAlertSound = false
      print("|cff00ff88DWD Party XP|r: pet alert sound OFF.")
    else
      print("|cffff5555Invalid sound option.|r Use |cffffff00/dwdxp alert sound on|r or |cffffff00off|r.")
    end
  elseif val == "test" or val == "" then
    ShowPetAlert("Pet is now Content. Feed soon.", 1.0, 0.82, 0.0, true)
  else
    print("|cffff5555Invalid alert option.|r Use |cffffff00/dwdxp alert move|r, |cffffff00lock|r, |cffffff00test|r, |cffffff00sound|r, |cffffff00status|r, or |cffffff00reset|r.")
  end
end

local function TrackPetHappiness(happiness, petUnit)
  happiness = tonumber(happiness) or 0
  if happiness <= 0 then return end

  local petGUID = petUnit and UnitGUID and UnitGUID(petUnit) or nil
  if petGUID and PetHappinessState.petGUID and PetHappinessState.petGUID ~= petGUID then
    ResetPetHappinessTracking()
  end

  local prev = PetHappinessState.value
  if prev ~= happiness then
    PetHappinessState.value = happiness
    PetHappinessState.petGUID = petGUID

    if DWD_PartyXP_DB.debug then
      print("|cff00ff88DWD Party XP|r: pet happiness "
        .. PetHappinessLabel(prev) .. " -> " .. PetHappinessLabel(happiness))
    end

    if prev == 3 and happiness == 2 then
      ShowPetAlert("Pet is now Content. Feed soon.", 1.0, 0.82, 0.0, true)
    end
  end
end

SafeUnitPetXP = function(unit)
  if not unit or not UnitExists(unit) or not UnitXP or not UnitXPMax then
    return 0, 0
  end

  local okXP, xp = pcall(UnitXP, unit)
  local okMax, xpMax = pcall(UnitXPMax, unit)
  if not okXP or not okMax then return 0, 0 end

  return tonumber(xp) or 0, tonumber(xpMax) or 0
end

GetOwnPetData = function()
  local pName, pLvl, pXP, pXPMax, pLoy = "NONE", 0, 0, 0, 0
  local pHappy, pDmg, pLoyRate = 0, 0, 0
  local petUnit = PetUnitForOwner("player") or "pet"
  if UnitExists(petUnit) then
    pName = UnitName(petUnit) or "Pet"
    pLvl  = UnitLevel(petUnit) or 0
    pLoy  = GetPetLoyaltyNum()
    pHappy, pDmg, pLoyRate = GetOwnPetHappinessData(petUnit)
    TrackPetHappiness(pHappy, petUnit)

    if type(GetPetExperience) == "function" then
      local ok, cx, mx = pcall(GetPetExperience)
      if ok then
        pXP    = tonumber(cx) or 0
        pXPMax = tonumber(mx) or 0
      end
    end

    if pXPMax <= 0 then
      pXP, pXPMax = SafeUnitPetXP(petUnit)
    end
  else
    ResetPetHappinessTracking()
  end
  return pName, pLvl, pXP, pXPMax, pLoy, pHappy, pDmg, pLoyRate
end

PetUnitForOwner = function(unit)
  if unit == "player" then
    if UnitExists("pet") then return "pet" end
    if UnitExists("playerpet") then return "playerpet" end
    return "pet"
  end

  local n = type(unit) == "string" and unit:match("^party(%d)$")
  if n then
    local primary = "partypet" .. n
    local alternate = "party" .. n .. "pet"
    if UnitExists(primary) then return primary end
    if UnitExists(alternate) then return alternate end
    return primary
  end
  return nil
end

IsPetUnit = function(unit)
  return unit == "pet"
    or unit == "playerpet"
    or (type(unit) == "string" and unit:match("^partypet%d$") ~= nil)
    or (type(unit) == "string" and unit:match("^party%dpet$") ~= nil)
end

------------------------------------------------------------
-- Messaging / self seeding
------------------------------------------------------------
local function serialize()
  local xp, xpMax = UnitXP("player"), UnitXPMax("player")
  local lvl = UnitLevel("player")
  local rested = GetXPExhaustion() or 0
  local class = select(2, UnitClass("player")) or "WARRIOR"
  local pName, pLvl, pXP, pXPMax, pLoy, pHappy, pDmg, pLoyRate = GetOwnPetData()
  return string.format("%s;%d;%d;%d;%s;%d;%s;%d;%d;%d;%d;%d;%d;%d",
    MyFullName(), lvl, xp, xpMax, class, rested, pName, pLvl, pXP, pXPMax, pLoy,
    pHappy or 0, pDmg or 0, pLoyRate or 0)
end

local function handleMessage(msg, sender)
  Transport.received = Transport.received + 1
  Transport.lastSender = sender
  if type(msg) ~= "string" then return end
  -- Handshake: respond to HELLO with our own XP data
  if msg == HELLO_MSG then
    seedSelf()
    sendMine(true)
    if DWD_PartyXP_DB.debug then print("|cff00ff88PXPS|r: received HELLO, sending our data back.") end
    return
  end
  -- Split message into parts (supports old 6-field, 10/11-field pet XP, and 14-field pet happiness formats)
  -- NOTE: [^;]+ (not [^;]*) — the * variant matches empty strings at every semicolon,
  -- interleaving phantom "" entries and breaking all field positions.
  local parts = {}
  for v in msg:gmatch("([^;]+)") do
    if #parts < 14 then parts[#parts+1] = v end
  end
  local full   = parts[1]
  local lvl    = tonumber(parts[2])
  local xp     = tonumber(parts[3])
  local xmax   = tonumber(parts[4])
  local class  = parts[5]
  local rested = tonumber(parts[6])
  if not (full and full ~= "" and lvl and xp and xmax and class and rested) then
    if DWD_PartyXP_DB.debug then
      print("|cff00ff88PXPS|r: |cffff5555parse failed|r — got " .. #parts .. " parts from: " .. (msg or "nil"):sub(1,60))
    end
    return
  end

  local matchedKey = ResolveRosterKey(full, sender)
  if not matchedKey then
    Transport.unmatched = Transport.unmatched + 1
    Transport.lastUnmatched = full
    return
  end
  Transport.matched = Transport.matched + 1
  full = matchedKey
  local t = Roster[full] or {}
  t.level = lvl; t.xp = xp; t.xpMax = xmax
  t.class = class; t.rested = rested; t.last = Now()

  -- Pet data (fields 7-11, optional for backward compat)
  local pName = parts[7]
  t.petName    = (pName and pName ~= "" and pName ~= "NONE") and pName or "NONE"
  t.petLevel   = tonumber(parts[8]) or 0
  t.petXP      = tonumber(parts[9]) or 0
  t.petXPMax   = tonumber(parts[10]) or 0
  t.petLoyalty = tonumber(parts[11]) or 0
  t.petHappiness   = tonumber(parts[12]) or 0
  t.petDamage      = tonumber(parts[13]) or 0
  t.petLoyaltyRate = tonumber(parts[14]) or 0

  Roster[full] = t
  if DWD_PartyXP_DB.debug then print("|cff00ff88PXPS|r: got XP from " .. full .. " (Lv" .. lvl .. ")") end
  updateHUD()
  StartDistanceTicker()
end

sendMine = function(force)
  local chan = SendChannel()
  if not chan then
    if DWD_PartyXP_DB.debug then print("|cff00ff88PXPS|r: no channel (not in party or in raid).") end
    return
  end
  if force or (Now() - lastSent) > sendCD then
    SendAddonMessageCompat(serialize(), chan)
    lastSent = Now()
    if DWD_PartyXP_DB.debug then print("|cff00ff88PXPS|r: sent our XP on " .. chan) end
  end
end

seedSelf = function()
  local pName, pLvl, pXP, pXPMax, pLoy, pHappy, pDmg, pLoyRate = GetOwnPetData()
  Roster[MyFullName()] = {
    level=UnitLevel("player"), xp=UnitXP("player"), xpMax=UnitXPMax("player"),
    rested=GetXPExhaustion() or 0, class=select(2, UnitClass("player")), last=Now(),
    petName=pName, petLevel=pLvl, petXP=pXP, petXPMax=pXPMax, petLoyalty=pLoy,
    petHappiness=pHappy, petDamage=pDmg, petLoyaltyRate=pLoyRate,
  }
end

local function yn(v)
  return v and "Y" or "N"
end

local function safeUnitText(unit, fn)
  if not unit or type(fn) ~= "function" then return "?" end
  local ok, a = pcall(fn, unit)
  if not ok or a == nil or a == "" then return "?" end
  return tostring(a)
end

local function PrintPetToken(token)
  local exists = UnitExists(token) and true or false
  local xp, xpMax = SafeUnitPetXP(token)
  local family = safeUnitText(token, UnitCreatureFamily)
  local creatureType = safeUnitText(token, UnitCreatureType)
  print(string.format("  %s exists=%s name=%s lvl=%s type=%s family=%s xp=%d/%d",
    token, yn(exists), safeUnitText(token, UnitName), safeUnitText(token, UnitLevel),
    creatureType, family, xp or 0, xpMax or 0))
end

RunPetDebug = function()
  seedSelf()
  print("|cff00ff88DWD Party XP petdebug|r showPets=" .. yn(DWD_PartyXP_DB.showPets ~= false)
    .. " grouped=" .. yn(isGrouped()) .. " raid=" .. yn(IsInRaid())
    .. " maxRows=" .. tostring(CFG_MAX_ROWS()))
  if DWD_PartyXP_DB.showPets == false then
    print("|cffff5555DWD Party XP petdebug: pet rows are disabled.|r Run |cffffff00/dwdxp pets on|r.")
  end

  local owners = {"player"}
  for i = 1, 4 do owners[#owners + 1] = "party" .. i end

  for _, owner in ipairs(owners) do
    if UnitExists(owner) then
      local full, short = UnitFullName(owner)
      local info = full and Roster[full] or nil
      local _, class = UnitClass(owner)
      print(string.format("%s owner=%s class=%s connected=%s chosenPet=%s",
        owner, short or "?", class or "?",
        yn(UnitIsConnected(owner)), PetUnitForOwner(owner) or "?"))

      if owner == "player" then
        PrintPetToken("pet")
        PrintPetToken("playerpet")
      else
        local n = owner:match("^party(%d)$")
        PrintPetToken("partypet" .. n)
        PrintPetToken("party" .. n .. "pet")
      end

      if info then
        print(string.format("  roster pet name=%s lvl=%s xp=%s/%s loyalty=%s happy=%s dmg=%s loyaltyRate=%s",
          tostring(info.petName), tostring(info.petLevel), tostring(info.petXP),
          tostring(info.petXPMax), tostring(info.petLoyalty), tostring(info.petHappiness),
          tostring(info.petDamage), tostring(info.petLoyaltyRate)))
      else
        print("  roster pet none")
      end
    end
  end
end

local function CleanRoster()
  if not isGrouped() then
    local myName = MyFullName()
    local fakeKey = FAKE_NAME.."-"..FAKE_REALM
    for k in pairs(Roster) do
      if k ~= myName and k ~= fakeKey then Roster[k] = nil end
    end
    return
  end
  local current = { [MyFullName()] = true }
  for i = 1, 4 do
    local u = "party"..i
    if UnitExists(u) then
      local full = UnitFullName(u)
      if full then current[full] = true end
    end
  end
  for k in pairs(Roster) do
    if not current[k] then Roster[k] = nil end
  end
end

local function SendHello()
  if not isGrouped() then return end
  local chan = SendChannel()
  if chan then
    SendAddonMessageCompat(HELLO_MSG, chan)
  end
end

local function StartHeartbeat()
  if heartbeatTicker then heartbeatTicker:Cancel() end
  heartbeatTicker = C_Timer.NewTicker(30, function()
    if isGrouped() then
      seedSelf()
      sendMine(true)
    end
  end)
end

local function StopHeartbeat()
  if heartbeatTicker then heartbeatTicker:Cancel(); heartbeatTicker = nil end
end

local function RefreshPetState(forceSend, localOnly)
  local prevHappiness = PetHappinessState.value
  seedSelf()
  local happinessChanged = prevHappiness and PetHappinessState.value and PetHappinessState.value ~= prevHappiness
  if not localOnly and isGrouped() and (forceSend == true or happinessChanged == true) then
    sendMine(true)
  end
  updateHUD()
end

local petRefreshToken = 0
local function QueuePetRefresh(forceSend)
  RefreshPetState(forceSend)
  if C_Timer and C_Timer.After then
    petRefreshToken = petRefreshToken + 1
    local token = petRefreshToken
    for _, delay in ipairs(PET_REFRESH_DELAYS) do
      C_Timer.After(delay, function()
        if token == petRefreshToken then
          RefreshPetState(false)
        end
      end)
    end
  end
end

local petHappinessTicker
StartPetHappinessTicker = function()
  if petHappinessTicker then petHappinessTicker:Cancel() end
  if C_Timer and C_Timer.NewTicker then
    petHappinessTicker = C_Timer.NewTicker(PET_HAPPINESS_POLL_SECONDS, function()
      if not IsInRaid() and not (DWD_PartyXP_DB and DWD_PartyXP_DB.hidden) then
        RefreshPetState(false)
      end
    end)
  end
end

-- Test mode ticker
local fakeTicker
local function StartFake()
  local key = FAKE_NAME.."-"..FAKE_REALM
  Roster[key] = {
    level=22, xp=15245, xpMax=26410, rested=8000, class="HUNTER", last=Now(),
    petName="Bristleback", petLevel=21, petXP=4200, petXPMax=24800, petLoyalty=5,
    petHappiness=3, petDamage=125, petLoyaltyRate=1,
  }
  if fakeTicker then fakeTicker:Cancel() end
  fakeTicker = C_Timer.NewTicker(2.0, function()
    local t = Roster[key]; if not t then return end
    local gain = math.random(120, 420)
    t.xp = t.xp + gain
    if t.xp >= t.xpMax then
      t.level = t.level + 1
      t.xp = t.xp - t.xpMax
      t.xpMax = math.floor(t.xpMax * 1.05)
    end
    t.rested = math.max(0, t.rested - gain*0.5)
    -- Animate pet XP too
    if t.petXPMax and t.petXPMax > 0 then
      local petGain = math.floor(gain * 0.7)
      t.petXP = t.petXP + petGain
      if t.petXP >= t.petXPMax then
        t.petLevel = t.petLevel + 1
        t.petXP = t.petXP - t.petXPMax
        t.petXPMax = math.floor(t.petXPMax * 1.05)
      end
    end
    updateHUD()
  end)
end
local function StopFake()
  if fakeTicker then fakeTicker:Cancel() end
  fakeTicker=nil; Roster[FAKE_NAME.."-"..FAKE_REALM]=nil; updateHUD()
end

------------------------------------------------------------
-- Options Panel (created later, opened via OpenConfig)
------------------------------------------------------------
function CreateOptionsPanel()
  PANEL = CreateFrame("Frame", "DWD_PartyXP_Forever_Options", UIParent, "BackdropTemplate")
  PANEL.name = "DWD Party XP (Forever)"

  -- Dark background so the panel is always readable regardless of what's behind it
  PANEL:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  PANEL:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
  PANEL:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

  -- ── Layout constants ──
  local LEFT_COL   = 20
  local RIGHT_COL  = 310
  local SLIDER_W   = 220
  local SLIDER_H   = 17
  local ROW_GAP    = 50            -- vertical spacing between slider rows
  local SECTION_GAP = 18          -- extra gap before a section header
  local TRACK_COLOR = {0.25, 0.25, 0.25, 1}
  local TRACK_BORDER = {0.45, 0.45, 0.45, 1}

  -- ── Helper: section header ──
  local function mkHeader(parent, text, anchor, xOff, yOff)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOff, yOff)
    fs:SetText("|cff00cc66" .. text .. "|r")
    -- thin separator line below the header text
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    line:SetColorTexture(0.35, 0.35, 0.35, 0.8)
    return fs
  end

  -- ── Helper: checkbox ──
  local function mkCheck(parent, label, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb.Text:SetText("|cffffffff" .. label .. "|r")
    cb.Text:SetFontObject("GameFontHighlight")
    if tooltip then cb.tooltipText = label; cb.tooltipRequirement = tooltip end
    return cb
  end

  -- ── Helper: slider with visible track, value readout, and formatted label ──
  local function mkSlider(globalName, parent, label, minV, maxV, step, fmt)
    fmt = fmt or "%d"
    local s = CreateFrame("Slider", globalName, parent, "OptionsSliderTemplate")
    s:SetSize(SLIDER_W, SLIDER_H)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)

    -- Track background (dark inset bar behind the thumb)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(8)
    track:SetColorTexture(unpack(TRACK_COLOR))
    -- Thin border around the track
    local tBorder = CreateFrame("Frame", nil, s, "BackdropTemplate")
    tBorder:SetPoint("LEFT", track, -1, 0)
    tBorder:SetPoint("RIGHT", track, 1, 0)
    tBorder:SetHeight(10)
    tBorder:SetBackdrop({edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=10,
                          insets={left=2,right=2,top=2,bottom=2}})
    tBorder:SetBackdropBorderColor(unpack(TRACK_BORDER))

    -- Label above the slider
    local titleText = _G[globalName.."Text"]
    titleText:ClearAllPoints()
    titleText:SetPoint("BOTTOM", s, "TOP", 0, 3)
    titleText:SetText("|cffffd200" .. label .. "|r")

    -- Min / Max labels
    local lo = _G[globalName.."Low"];  lo:SetText("|cff888888"..tostring(minV).."|r")
    local hi = _G[globalName.."High"]; hi:SetText("|cff888888"..tostring(maxV).."|r")

    -- Live value readout (right of slider)
    local val = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("LEFT", s, "RIGHT", 8, 0)
    val:SetTextColor(0.9, 0.9, 0.9)
    s._valText = val
    s._valFmt  = fmt

    s:SetScript("OnValueChanged", function(self, v)
      self._valText:SetText(self._valFmt:format(v))
    end)

    return s
  end

  -- ═══════════════════════════════════════════════════════
  -- Title
  -- ═══════════════════════════════════════════════════════
  local title = PANEL:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("|cff00ff88DWD Party XP|r  |cff999999Forever|r")

  local note = PANEL:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  note:SetTextColor(0.6, 0.6, 0.6)
  note:SetText("Shift+Right-Click the HUD to open this panel.  Changes apply immediately.")

  -- ═══════════════════════════════════════════════════════
  -- Section: General
  -- ═══════════════════════════════════════════════════════
  local hGeneral = mkHeader(PANEL, "General", note, 0, -SECTION_GAP)

  local cbLock = mkCheck(PANEL, "Lock position", "Prevent dragging the HUD.")
  cbLock:SetPoint("TOPLEFT", hGeneral, "BOTTOMLEFT", 0, -8)
  cbLock:SetScript("OnShow", function(self) self:SetChecked(DWD_PartyXP_DB.locked) end)
  cbLock:SetScript("OnClick", function(self)
    DWD_PartyXP_DB.locked = self:GetChecked() and true or false
    f:SetMovable(not DWD_PartyXP_DB.locked)
  end)

  local cbText = mkCheck(PANEL, "Show text on bars", "Toggles the centered 'XP: X / Y' text.")
  cbText:SetPoint("LEFT", cbLock, "RIGHT", 160, 0)
  cbText:SetScript("OnShow", function(self) self:SetChecked(DWD_PartyXP_DB.showText ~= false) end)
  cbText:SetScript("OnClick", function(self)
    DWD_PartyXP_DB.showText = self:GetChecked() and true or false
    for _,row in ipairs(f.rows or {}) do
      if row.bar and row.bar.valueText then row.bar.valueText:SetShown(DWD_PartyXP_DB.showText) end
    end
  end)

  local cbTest = mkCheck(PANEL, "Test mode  (solo preview)", "Adds a fake party row when not grouped.")
  cbTest:SetPoint("TOPLEFT", cbLock, "BOTTOMLEFT", 0, -4)
  cbTest:SetScript("OnShow", function(self) self:SetChecked(DWD_PartyXP_DB.testMode) end)
  cbTest:SetScript("OnClick", function(self)
    DWD_PartyXP_DB.testMode = self:GetChecked() and true or false
    if DWD_PartyXP_DB.testMode and not isGrouped() then StartFake() else StopFake() end
    updateHUD()
  end)

  local cbPets = mkCheck(PANEL, "Show pets", "Show pet XP bars beneath their owners.")
  cbPets:SetPoint("LEFT", cbTest, "RIGHT", 160, 0)
  cbPets:SetScript("OnShow", function(self) self:SetChecked(DWD_PartyXP_DB.showPets ~= false) end)
  cbPets:SetScript("OnClick", function(self)
    DWD_PartyXP_DB.showPets = self:GetChecked() and true or false
    updateHUD()
  end)

  -- ═══════════════════════════════════════════════════════
  -- Section: HUD Layout  (two-column slider grid)
  -- ═══════════════════════════════════════════════════════
  local hLayout = mkHeader(PANEL, "HUD Layout", cbTest, 0, -SECTION_GAP)

  -- Row 1
  local sScale = mkSlider("DWD_PXP_Scale", PANEL, "Scale", 0.7, 3.0, 0.05, "%.2f")
  sScale:SetPoint("TOPLEFT", hLayout, "BOTTOMLEFT", 10, -30)
  sScale:HookScript("OnValueChanged", function(_, val)
    DWD_PartyXP_DB.scale = tonumber(("%.2f"):format(val)); ApplyScale()
  end)
  sScale:SetScript("OnShow", function(self) self:SetValue(DWD_PartyXP_DB.scale) end)

  local sBarW = mkSlider("DWD_PXP_BarW", PANEL, "Bar Width", 80, 240, 1)
  sBarW:SetPoint("TOPLEFT", hLayout, "BOTTOMLEFT", RIGHT_COL - LEFT_COL, -30)
  sBarW:HookScript("OnValueChanged", function(_, val)
    DWD_PartyXP_DB.hudBarW = math.floor(val + 0.5); RefreshGeometry(); updateHUD()
  end)
  sBarW:SetScript("OnShow", function(self) self:SetValue(CFG_HUD_W()) end)

  -- Row 2
  local sSeg = mkSlider("DWD_PXP_Segments", PANEL, "Segments", 4, 40, 1)
  sSeg:SetPoint("TOPLEFT", sScale, "BOTTOMLEFT", 0, -ROW_GAP)
  sSeg:HookScript("OnValueChanged", function(_, val)
    DWD_PartyXP_DB.segments = math.floor(val + 0.5); RefreshGeometry(); updateHUD()
  end)
  sSeg:SetScript("OnShow", function(self) self:SetValue(CFG_SEGMENTS()) end)

  local sBarH = mkSlider("DWD_PXP_BarH", PANEL, "Bar Height", 8, 18, 1)
  sBarH:SetPoint("TOPLEFT", sBarW, "BOTTOMLEFT", 0, -ROW_GAP)
  sBarH:HookScript("OnValueChanged", function(_, val)
    DWD_PartyXP_DB.hudBarH = math.floor(val + 0.5); RefreshGeometry(); updateHUD()
  end)
  sBarH:SetScript("OnShow", function(self) self:SetValue(CFG_HUD_H()) end)

  -- Row 3
  local sMax = mkSlider("DWD_PXP_MaxRows", PANEL, "Max Visible Rows", 1, 8, 1)
  sMax:SetPoint("TOPLEFT", sSeg, "BOTTOMLEFT", 0, -ROW_GAP)
  sMax:HookScript("OnValueChanged", function(_, val)
    DWD_PartyXP_DB.maxRows = math.floor(val + 0.5)
    RefreshGeometry(); updateHUD()
  end)
  sMax:SetScript("OnShow", function(self) self:SetValue(CFG_MAX_ROWS()) end)

  local sLabelW = mkSlider("DWD_PXP_LabelW", PANEL, "Label Width", 96, 360, 2)
  sLabelW:SetPoint("TOPLEFT", sBarH, "BOTTOMLEFT", 0, -ROW_GAP)
  sLabelW:HookScript("OnValueChanged", function(_, val)
    DWD_PartyXP_DB.labelW = math.floor(val + 0.5); RefreshGeometry(); updateHUD()
  end)
  sLabelW:SetScript("OnShow", function(self) self:SetValue(CFG_LABEL_W()) end)

  -- Row 4
  local sRowH = mkSlider("DWD_PXP_RowH", PANEL, "Row Height", 14, 30, 1)
  sRowH:SetPoint("TOPLEFT", sMax, "BOTTOMLEFT", 0, -ROW_GAP)
  sRowH:HookScript("OnValueChanged", function(_, val)
    DWD_PartyXP_DB.rowH = math.floor(val + 0.5); RefreshGeometry(); updateHUD()
  end)
  sRowH:SetScript("OnShow", function(self) self:SetValue(CFG_ROW_H()) end)

  local sBorderA = mkSlider("DWD_PXP_BorderA", PANEL, "Border Opacity", 0, 1, 0.05, "%.2f")
  sBorderA:SetPoint("TOPLEFT", sLabelW, "BOTTOMLEFT", 0, -ROW_GAP)
  sBorderA:HookScript("OnValueChanged", function(_, val)
    DWD_PartyXP_DB.borderA = tonumber(("%.2f"):format(val)); RefreshGeometry(); updateHUD()
  end)
  sBorderA:SetScript("OnShow", function(self) self:SetValue(CFG_BORDER_A()) end)

  -- ═══════════════════════════════════════════════════════
  -- Section: Actions
  -- ═══════════════════════════════════════════════════════
  local hActions = mkHeader(PANEL, "Actions", sRowH, 0, -(ROW_GAP + 6))

  local BTN_W, BTN_H = 150, 24
  local resetBtn = CreateFrame("Button", nil, PANEL, "UIPanelButtonTemplate")
  resetBtn:SetSize(BTN_W, BTN_H)
  resetBtn:SetPoint("TOPLEFT", hActions, "BOTTOMLEFT", 2, -10)
  resetBtn:SetText("Reset Position")
  resetBtn:SetScript("OnClick", function()
    DWD_PartyXP_DB.pos = nil; RestorePosition()
    print("|cff00ff88DWD Party XP|r: position reset.")
  end)

  local defaultsBtn = CreateFrame("Button", nil, PANEL, "UIPanelButtonTemplate")
  defaultsBtn:SetSize(BTN_W, BTN_H)
  defaultsBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
  defaultsBtn:SetText("Restore Defaults")
  defaultsBtn:SetScript("OnClick", function()
    local pos, hidden = DWD_PartyXP_DB.pos, DWD_PartyXP_DB.hidden
    wipe(DWD_PartyXP_DB); EnsureDefaults()
    DWD_PartyXP_DB.pos = pos; DWD_PartyXP_DB.hidden = hidden
    ApplyScale(); RefreshGeometry(); RestorePosition(); updateHUD()
    cbLock:SetChecked(DWD_PartyXP_DB.locked)
    cbText:SetChecked(DWD_PartyXP_DB.showText ~= false)
    cbTest:SetChecked(DWD_PartyXP_DB.testMode)
    cbPets:SetChecked(DWD_PartyXP_DB.showPets ~= false)
    sScale:SetValue(DWD_PartyXP_DB.scale)
    sSeg:SetValue(CFG_SEGMENTS())
    sMax:SetValue(CFG_MAX_ROWS())
    sBarW:SetValue(CFG_HUD_W())
    sBarH:SetValue(CFG_HUD_H())
    sLabelW:SetValue(CFG_LABEL_W())
    sRowH:SetValue(CFG_ROW_H())
    sBorderA:SetValue(CFG_BORDER_A())
    print("|cff00ff88DWD Party XP|r: defaults restored.")
  end)

  local syncBtn = CreateFrame("Button", nil, PANEL, "UIPanelButtonTemplate")
  syncBtn:SetSize(BTN_W, BTN_H)
  syncBtn:SetPoint("LEFT", defaultsBtn, "RIGHT", 10, 0)
  syncBtn:SetText("Sync Party Now")
  syncBtn:SetScript("OnClick", function()
    if isGrouped() then
      seedSelf(); SendHello()
      print("|cff00ff88DWD Party XP|r: sync requested.")
    else
      print("|cff00ff88DWD Party XP|r: not in a group.")
    end
  end)

  -- ═══════════════════════════════════════════════════════
  -- Register with Interface Options
  -- ═══════════════════════════════════════════════════════
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(PANEL, PANEL.name)
    Settings.RegisterAddOnCategory(category)
    PANEL._category = category
    if category then
      if type(category.GetID) == "function" then
        PANEL._categoryID = category:GetID()
      elseif type(category.ID) == "number" then
        PANEL._categoryID = category.ID
      end
    end
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(PANEL)
  end
end

-- Open the panel (new Settings or legacy)
function OpenConfig()
  if not PANEL then return end
  if Settings and Settings.OpenToCategory then
    local id = PANEL._categoryID
    if type(id) ~= "number" and PANEL._category then
      if type(PANEL._category.GetID) == "function" then
        id = PANEL._category:GetID()
      elseif type(PANEL._category.ID) == "number" then
        id = PANEL._category.ID
      end
    end
    if type(id) == "number" then
      Settings.OpenToCategory(id)
      return
    end
  end
  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(PANEL)
  else
    print("|cffff5555DWD Party XP:|r cannot open settings on this client.")
  end
end

------------------------------------------------------------
-- HUD create (uses OpenConfig in right-click handler)
------------------------------------------------------------
local function createHUD()
  f:SetSize(CFG_HUD_W() + CFG_LABEL_W() + 28, 24 + CFG_MAX_ROWS()*CFG_ROW_H())
  -- Forever's UIParent layout pass can reapply its own cached position after
  -- ADDON_LOADED. Keep one source of truth: DWD_PartyXP_DB.pos.
  if type(f.SetDontSavePosition) == "function" then
    pcall(f.SetDontSavePosition, f, true)
  end
  f:SetMovable(not DWD_PartyXP_DB.locked)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")

  f:SetScript("OnDragStart", function(self) if self:IsMovable() then self:StartMoving() end end)
  f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing(); SavePosition() end)
  f:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
      -- OnDragStop is the primary save path; this also covers clients that do
      -- not reliably deliver OnDragStop after StartMoving.
      SavePosition()
    elseif button == "RightButton" and IsShiftKeyDown() then
      OpenConfig()
    end
  end)

  f:SetBackdrop({
    bgFile="Interface/Tooltips/UI-Tooltip-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border",
    edgeSize=12
  })
  f:SetBackdropColor(0,0,0,0.6)
  f:SetFrameStrata("LOW"); f:SetFrameLevel(1)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 8, -6)
  f.title:SetText(titleText())

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  -- Forever's UIPanelCloseButton template is substantially larger than the
  -- Classic version. Give it explicit dimensions so it remains proportional
  -- as the HUD itself is scaled up.
  closeBtn:SetSize(24, 24)
  closeBtn:SetPoint("TOPRIGHT", 1, 1)
  closeBtn:SetScale(0.7)
  closeBtn:SetScript("OnClick", function()
    DWD_PartyXP_DB.hidden = true
    f:Hide()
    print("|cff00ff88DWD Party XP|r hidden. Use |cffffff00/dwdxp show|r to show.")
  end)

  f.rows = {}
  for i=1, POOL_SIZE do f.rows[i] = makeRow(f, i) end

  ApplyScale()
  RestorePosition()
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
local function onInit()
  if f._dwdInitialized then return end
  f._dwdInitialized = true
  InitializeDatabase()
  RegisterAddonPrefix()
  createHUD()
  CreateOptionsPanel()
  ApplyScale(); RestorePosition()
  if DWD_PartyXP_DB.hidden then f:Hide() else f:Show() end
  updateHUD()
  StartPetHappinessTicker()
  StartPositionWatcher()
end

local function onEnteringWorld()
  -- Forever performs another UIParent layout pass after login/reload. Reapply
  -- the persisted placement after both the immediate and delayed passes.
  C_Timer.After(0, function()
    if f._dwdInitialized then ApplyScale(); RestorePosition() end
  end)
  C_Timer.After(1, function()
    if f._dwdInitialized then ApplyScale(); RestorePosition() end
  end)

  seedSelf()
  if isGrouped() then
    -- Staggered handshake: on /reload the addon channel may not be ready instantly
    C_Timer.After(0.5, function()
      if isGrouped() then SendHello() end
    end)
    C_Timer.After(1.5, function()
      if isGrouped() then RefreshPetState(true) end
    end)
    StartHeartbeat()
  end
  if DWD_PartyXP_DB.testMode and not isGrouped() then StartFake() end
  C_Timer.After(0.05, updateHUD)
  QueuePetRefresh(false)
end

RegisterEventIfAvailable("ADDON_LOADED")
RegisterEventIfAvailable("VARIABLES_LOADED")
RegisterEventIfAvailable("PLAYER_LOGIN")
RegisterEventIfAvailable("PLAYER_ENTERING_WORLD")
RegisterEventIfAvailable("PLAYER_LOGOUT")
RegisterEventIfAvailable("PLAYER_XP_UPDATE")
RegisterEventIfAvailable("PLAYER_LEVEL_UP")
RegisterEventIfAvailable("UPDATE_EXHAUSTION")
RegisterEventIfAvailable("GROUP_ROSTER_UPDATE")
RegisterEventIfAvailable("UNIT_CONNECTION")
RegisterEventIfAvailable("UNIT_PET")
RegisterEventIfAvailable("UNIT_PET_EXPERIENCE")
RegisterEventIfAvailable("UNIT_HAPPINESS")
RegisterEventIfAvailable("PET_BAR_UPDATE")
RegisterEventIfAvailable("PET_UI_UPDATE")
RegisterEventIfAvailable("UNIT_LEVEL")
RegisterEventIfAvailable("UNIT_NAME_UPDATE")
RegisterEventIfAvailable("CHAT_MSG_ADDON")

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON then
      f._dwdAddonLoaded = true
      if f._dwdVariablesLoaded then onInit() end
    end
  elseif event == "VARIABLES_LOADED" then
    f._dwdVariablesLoaded = true
    if f._dwdAddonLoaded then onInit() end
  elseif event == "PLAYER_LOGIN" then
    -- Fallback for Forever builds that omit VARIABLES_LOADED. PLAYER_LOGIN is
    -- still late enough that account SavedVariables have been restored.
    onInit()
    ApplyScale(); RestorePosition()
  elseif event == "PLAYER_ENTERING_WORLD" then
    onEnteringWorld()
  elseif event == "PLAYER_LOGOUT" then
    -- Save the final anchor even if this client failed to send OnDragStop.
    SavePosition()
  elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "UPDATE_EXHAUSTION" then
    seedSelf(); sendMine(false); updateHUD()
  elseif event == "GROUP_ROSTER_UPDATE" then
    if not isGrouped() then
      StopFake(); StopHeartbeat(); CleanRoster()
    else
      CleanRoster(); StartHeartbeat()
      -- Request data from (possibly new) members after a short delay
      C_Timer.After(0.5, function()
        if isGrouped() then SendHello() end
      end)
    end
    seedSelf(); sendMine(true); updateHUD()
  elseif event == "UNIT_CONNECTION" then
    local unit = ...
    if unit and (unit=="player" or unit:match("^party%d$")) then updateHUD() end
  elseif event == "UNIT_PET" then
    local unit = ...
    if not unit or unit == "player" then
      ResetPetHappinessTracking()
      QueuePetRefresh(true)
    elseif IsPartyUnit(unit) then
      updateHUD()
    end
  elseif event == "UNIT_PET_EXPERIENCE" then
    RefreshPetState(true)
  elseif event == "UNIT_HAPPINESS" then
    local unit = ...
    if not unit or IsPetUnit(unit) then
      QueuePetRefresh(true)
    end
  elseif event == "PET_BAR_UPDATE" then
    QueuePetRefresh(false)
  elseif event == "PET_UI_UPDATE" then
    QueuePetRefresh(false)
  elseif event == "UNIT_LEVEL" or event == "UNIT_NAME_UPDATE" then
    local unit = ...
    if unit == "player" then
      seedSelf(); sendMine(false); updateHUD()
    elseif IsPetUnit(unit) then
      if unit == "pet" then seedSelf(); sendMine(true) end
      updateHUD()
    elseif IsPartyUnit(unit) then
      updateHUD()
    end
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    if prefix == PREFIX then handleMessage(msg, sender) end
  end
end)

------------------------------------------------------------
-- Slash
------------------------------------------------------------
local function PrintSyncStatus()
  print("|cff00ff88DWD Party XP 1.4.12-forever|r sync status")
  print("  prefix=" .. tostring(Transport.registration or "not initialized")
    .. " channel=" .. tostring(SendChannel() or "none")
    .. " send attempts=" .. Transport.sent .. " received=" .. Transport.received
    .. " matched=" .. Transport.matched .. " unmatched=" .. Transport.unmatched)
  print("  self=" .. MyFullName() .. " send result=" .. tostring(Transport.lastSendResult))
  if Transport.lastError then print("  last send/register error: " .. Transport.lastError) end
  if Transport.lastUnmatched then print("  last unmatched identity: " .. Transport.lastUnmatched) end
  for i=1,4 do
    local unit="party"..i
    if UnitExists(unit) then
      local key, name=UnitFullName(unit)
      local info=key and Roster[key]
      print("  " .. tostring(name) .. ": " .. (info and info.xpMax and info.xpMax > 0
        and ("XP received " .. math.floor(Now() - (info.last or Now())) .. "s ago")
        or "waiting for XP message"))
    end
  end
end

SLASH_DWDXP1 = "/dwdxp"
SLASH_DWDXP2 = "/dwdxpforever"
SlashCmdList.DWDXP = function(msg)
  msg = (msg or ""):lower():gsub("^%s+",""):gsub("%s+$","")
  if msg == "" or msg == "help" then
    print("|cff00ff88DWD Party XP (Forever)|r — commands:")
    print("  |cffffff00/dwdxp show|r  — show HUD")
    print("  |cffffff00/dwdxp hide|r  — hide HUD")
    print("  |cffffff00/dwdxp lock|r  — lock position")
    print("  |cffffff00/dwdxp unlock|r  — unlock (drag to move)")
    print("  |cffffff00/dwdxp scale 1.0|r — set scale (0.7–3.0)")
    print("  |cffffff00/dwdxp sync|r  — request XP from party members")
    print("  |cffffff00/dwdxp status|r — show sync diagnostics")
    print("  |cffffff00/dwdxp debug|r — toggle debug messages in chat")
    print("  |cffffff00/dwdxp pets on|r — show pet rows")
    print("  |cffffff00/dwdxp pets off|r — hide pet rows")
    print("  |cffffff00/dwdxp alert move|r — move pet mood alert text")
    print("  |cffffff00/dwdxp alert test|r — preview pet mood alert")
    print("  |cffffff00/dwdxp alert sound|r — test pet mood alert sound")
    print("  |cffffff00/dwdxp alert status|r — inspect pet mood alert tracking")
    print("  |cffffff00/dwdxp petdebug|r — print pet unit diagnostics")
    print("  |cffffff00/dwdxp test toggle|r — toggle solo test row")
    print("  |cffffff00/dwdxp config|r — open settings")
    print("  |cffffff00/dwdxp reset|r — reset position/scale")
    return
  end

  if msg == "status" then PrintSyncStatus(); return end
  if msg == "config" then OpenConfig(); return end
  if msg == "debug" then
    DWD_PartyXP_DB.debug = not DWD_PartyXP_DB.debug
    print("|cff00ff88DWD Party XP|r: debug " .. (DWD_PartyXP_DB.debug and "ON" or "OFF"))
    return
  end
  if msg == "petdebug" then
    RunPetDebug()
    return
  end
  if msg == "sync" then
    if isGrouped() then
      seedSelf(); SendHello()
      print("|cff00ff88DWD Party XP|r: sync requested.")
    else
      print("|cff00ff88DWD Party XP|r: not in a group.")
    end
    return
  end

  if msg == "show" then DWD_PartyXP_DB.hidden=false; f:Show(); updateHUD(); return end
  if msg == "hide" then DWD_PartyXP_DB.hidden=true; f:Hide(); return end

  if msg == "lock" then
    SavePosition()
    DWD_PartyXP_DB.locked = true
    f:SetMovable(false)
    print("|cff00ff88DWD Party XP|r locked.")
    return
  elseif msg == "unlock" then
    DWD_PartyXP_DB.locked = false
    f:SetMovable(true)
    print("|cff00ff88DWD Party XP|r unlocked. Drag with Left-Click.")
    return
  end

  if msg == "alert" then
    HandlePetAlertCommand("test")
    return
  end

  local cmd, val = msg:match("^(%S+)%s+(.*)$")
  if cmd == "alert" then
    HandlePetAlertCommand(val)
    return
  end

  if cmd == "pets" then
    val = (val or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    if val == "on" or val == "show" or val == "1" or val == "true" then
      DWD_PartyXP_DB.showPets = true
    elseif val == "off" or val == "hide" or val == "0" or val == "false" then
      DWD_PartyXP_DB.showPets = false
    elseif val == "toggle" or val == "" then
      DWD_PartyXP_DB.showPets = not (DWD_PartyXP_DB.showPets ~= false)
    else
      print("|cffff5555Invalid pets option.|r Use |cffffff00/dwdxp pets on|r, |cffffff00off|r, or |cffffff00toggle|r.")
      return
    end

    seedSelf()
    updateHUD()
    if isGrouped() then sendMine(true) end
    print("|cff00ff88DWD Party XP|r pet rows " .. ((DWD_PartyXP_DB.showPets ~= false) and "ON" or "OFF") .. ".")
    return
  end

  if cmd == "scale" then
    local s = tonumber(val)
    if s and s >= 0.7 and s <= 3.0 then
      DWD_PartyXP_DB.scale = s; ApplyScale()
      print(string.format("|cff00ff88DWD Party XP|r scale set to %.2f", s))
    else
      print("|cffff5555Invalid scale.|r Use 0.7–3.0, e.g. |cffffff00/dwdxp scale 2.0|r")
    end
    return
  end

  if msg == "test toggle" or msg == "test" then
    DWD_PartyXP_DB.testMode = not DWD_PartyXP_DB.testMode
    if DWD_PartyXP_DB.testMode and not isGrouped() then StartFake() else StopFake() end
    updateHUD()
    print("|cff00ff88DWD Party XP|r Test Mode: "..(DWD_PartyXP_DB.testMode and "ON" or "OFF"))
    return
  end

  if msg == "reset" then
    DWD_PartyXP_DB.pos = nil
    DWD_PartyXP_DB.scale = DEFAULTS.scale
    RestorePosition(); ApplyScale(); updateHUD()
    print("|cff00ff88DWD Party XP|r: position/scale reset.")
    return
  end

  print("|cffff5555Unknown command.|r Type |cffffff00/dwdxp|r for help.")
end
