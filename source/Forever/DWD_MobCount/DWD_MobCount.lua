-- DWD MobCount (WoW Forever)
-- Counts your mob kills, shows total on unit tooltip, provides a simple list UI,
-- and slash: /dwdmc list | config | debug | clear | restore | lock

-- ========================= SavedVariables =========================
DWD_MobCountDB         = DWD_MobCountDB         or {}
DWD_MobCountBackup     = DWD_MobCountBackup     or { _locks = {}, _meta = {} }
DWD_MobCountLastClear  = DWD_MobCountLastClear  or {}
DWD_MobCountConfig     = DWD_MobCountConfig     or {}

local function canonicalRealm(realm)
  return tostring(realm or "Unknown"):gsub("[%s%-']", "")
end

local function savedCharacterKey()
  return DWD_ForeverIdentity.Key(true)
end

-- Keep kill data on the same stable key on every load. UnitFullName can omit
-- the realm during early loading, so fall back to GetRealmName before giving
-- up rather than ever writing to an "Unknown" character.
local function countCharacterKey()
  local name, realm = DWD_ForeverIdentity.Get("player")
  if not name or name == "" or not realm or realm == "" then return nil end
  return canonicalRealm(realm) .. "-" .. name
end

local function copyConfig(dst, src)
  for k,v in pairs(src or {}) do
    if dst[k] == nil then
      if type(v) == "table" then
        dst[k] = {}
        copyConfig(dst[k], v)
      else
        dst[k] = v
      end
    end
  end
end

-- The kill database already separates data by charKey. Do the same for config
-- in the account file, avoiding Forever's unreliable per-character loader.
DWD_MobCountConfigByCharacter = DWD_MobCountConfigByCharacter or {}
local savedConfigKey = savedCharacterKey()
local characterConfig = DWD_ForeverIdentity.Adopt(DWD_MobCountConfigByCharacter, savedConfigKey)
if type(characterConfig) ~= "table" then
  characterConfig = {}
  local legacy = type(DWD_MobCountCharacterConfig) == "table"
    and DWD_MobCountCharacterConfig or DWD_MobCountConfig
  copyConfig(characterConfig, legacy)
  DWD_MobCountConfigByCharacter[savedConfigKey] = characterConfig
end
DWD_MobCountCharacterConfig = characterConfig
DWD_MobCountConfig = characterConfig

local function setdefault(t,k,v) if t[k]==nil then t[k]=v end end
local function setdefaultColor(t,k,r,g,b) t[k]=t[k] or { r=r, g=g, b=b } end

setdefault(DWD_MobCountConfig, "textStyle", "TOTAL_KILLED")
setdefaultColor(DWD_MobCountConfig, "labelColor", 1.00, 0.82, 0.00)
setdefaultColor(DWD_MobCountConfig, "valueColor", 1.00, 1.00, 1.00)
setdefault(DWD_MobCountConfig, "debug", false)
setdefault(DWD_MobCountConfig, "customTextEnabled", DWD_MobCountConfig.customTextEnabled or false)
setdefault(DWD_MobCountConfig, "customText", DWD_MobCountConfig.customText or "")

-- Repair colors saved by the pre-Forever picker callback, which could store
-- the complete color object inside the r field ({r={r=...,g=...,b=...}}).
local function repairSavedColor(key, defaultR, defaultG, defaultB)
  local color = DWD_MobCountConfig[key]
  if type(color) ~= "table" then color = {} end
  local nested = type(color.r) == "table" and color.r
              or type(color.g) == "table" and color.g
              or type(color.b) == "table" and color.b
  if nested then
    color.r, color.g, color.b = nested.r or nested[1], nested.g or nested[2], nested.b or nested[3]
  end
  color.r = tonumber(color.r) or defaultR
  color.g = tonumber(color.g) or defaultG
  color.b = tonumber(color.b) or defaultB
  DWD_MobCountConfig[key] = color
end

repairSavedColor("labelColor", 1.00, 0.82, 0.00)
repairSavedColor("valueColor", 1.00, 1.00, 1.00)

-- ========================= State =========================
local initialized, tooltipHooked = false, false
local charKey
local killsById, namesById, killsByName = {}, {}, {}
local recentKills = {}
local nextKillPrune = 0
local listFrame

local ShowList
local ClearCharacterData, RestoreData

-- ========================= Utils =========================
local function trim(s) return (s and s:gsub("^%s+",""):gsub("%s+$","")) or "" end
local function copyShallow(src) local d={}; if src then for k,v in pairs(src) do d[k]=v end end; return d end
local function clamp01(x) x=tonumber(x) or 1; if x<0 then return 0 elseif x>1 then return 1 else return x end end
local function toHex(c) local r=math.floor(clamp01(c.r or 1)*255+0.5) local g=math.floor(clamp01(c.g or 1)*255+0.5) local b=math.floor(clamp01(c.b or 1)*255+0.5) return string.format("%02X%02X%02X", r,g,b) end
local function paint(text, color) return ("|cFF%s%s|r"):format(toHex(color), tostring(text)) end
local function chat(msg) local cf = DEFAULT_CHAT_FRAME or ChatFrame1; if cf and cf.AddMessage then cf:AddMessage(msg) end end
local function dbg(...) if DWD_MobCountConfig and DWD_MobCountConfig.debug then chat("|cffffff00MobCount:|r "..table.concat({tostring((...)) , select(2, ...)}, " ")) end end
local function wipeTable(t) if t then for k in pairs(t) do t[k]=nil end end end

local function mergeMaximumCounts(target, source)
  if type(target) ~= "table" or type(source) ~= "table" then return end
  for key, value in pairs(source) do
    value = tonumber(value)
    if value and value > (tonumber(target[key]) or 0) then target[key] = value end
  end
end

local function mergeNames(target, source)
  if type(target) ~= "table" or type(source) ~= "table" then return end
  for id, name in pairs(source) do
    if name and name ~= "" then target[id] = name end
  end
end

-- ========================= Storage helpers =========================
local function snapshotToBackup()
  if not charKey then return end
  DWD_MobCountBackup = type(DWD_MobCountBackup) == "table" and DWD_MobCountBackup or {}
  local b=DWD_MobCountBackup; b._meta=b._meta or {}; b._locks=b._locks or {}; b[charKey]=b[charKey] or {}
  b[charKey].killsById   = copyShallow(killsById)
  b[charKey].namesById   = copyShallow(namesById)
  b[charKey].killsByName = copyShallow(killsByName)
  b._meta[charKey]={ t=time and time() or 0, ver=2, cleared=false }
end
local function snapshotLastClear()
  if not charKey then return end
  DWD_MobCountLastClear[charKey]={ killsById=copyShallow(killsById), namesById=copyShallow(namesById), killsByName=copyShallow(killsByName), t=time and time() or 0 }
end
local function ensureCharTables()
  charKey = charKey or countCharacterKey()
  if not charKey then return false end
  DWD_MobCountDB = type(DWD_MobCountDB) == "table" and DWD_MobCountDB or {}
  DWD_ForeverIdentity.Adopt(DWD_MobCountDB, charKey, true)
  DWD_ForeverIdentity.Adopt(DWD_MobCountBackup, charKey, true)
  DWD_ForeverIdentity.Adopt(DWD_MobCountBackup._meta, charKey, true)
  DWD_ForeverIdentity.Adopt(DWD_MobCountBackup._locks, charKey, true)
  DWD_ForeverIdentity.Adopt(DWD_MobCountLastClear, charKey, true)
  local b=DWD_MobCountDB[charKey]
  if not b then b={ killsById={}, namesById={}, killsByName={} }; DWD_MobCountDB[charKey]=b
  else b.killsById=b.killsById or {}; b.namesById=b.namesById or {}; b.killsByName=b.killsByName or {} end

  -- If another addon replaced the SavedVariables root, preserve any newer
  -- counts still held by MobCount's live references before reconnecting them.
  mergeMaximumCounts(b.killsById, killsById)
  mergeMaximumCounts(b.killsByName, killsByName)
  mergeNames(b.namesById, namesById)

  -- The independent mirror recovers from an interrupted/empty primary write.
  local backup = type(DWD_MobCountBackup) == "table" and DWD_MobCountBackup[charKey]
  local meta = type(DWD_MobCountBackup) == "table" and DWD_MobCountBackup._meta
    and DWD_MobCountBackup._meta[charKey]
  if type(backup) == "table" and not (meta and meta.cleared) then
    mergeMaximumCounts(b.killsById, backup.killsById)
    mergeMaximumCounts(b.killsByName, backup.killsByName)
    mergeNames(b.namesById, backup.namesById)
  end

  killsById, namesById, killsByName = b.killsById, b.namesById, b.killsByName
  return true
end

local function persistCurrentCounts()
  if not ensureCharTables() then return end
  -- Assign the live tables back to the SavedVariables root explicitly even if
  -- a profile addon inspected or replaced its root table.
  local store = DWD_MobCountDB[charKey]
  store.killsById, store.namesById, store.killsByName = killsById, namesById, killsByName
  snapshotToBackup()
end

-- ========================= GUID helpers =========================
local function npcIdFromGUID(guid)
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- ========================= Tooltip line (custom wording supported) =========================
local STYLE_MAP = {
  KILLED={label="Killed",order="label_first"}, TOTAL_KILLED={label="Total Killed",order="label_first"},
  COUNT_KILLED={label="Killed",order="count_first"}, SLAIN={label="Slain",order="label_first"},
  TOTAL_SLAIN={label="Total Slain",order="label_first"}, COUNT_SLAIN={label="Slain",order="count_first"},
  YEETED={label="Yeeted",order="label_first"}, TOTAL_YEETED={label="Total Yeeted",order="label_first"},
  COUNT_YEETED={label="Yeeted",order="count_first"},
}
local function BuildLine(styleID,count)
  local cfg = DWD_MobCountConfig
  if cfg.customTextEnabled and cfg.customText and cfg.customText ~= "" then
    local txt, out, pos = cfg.customText, "", 1
    while true do
      local i,j = txt:find("{count}", pos, true)
      if not i then
        local seg = txt:sub(pos); if seg~="" then out = out .. ("|cFF%s%s|r"):format(toHex(cfg.labelColor), seg) end
        break
      end
      local seg = txt:sub(pos, i-1)
      if seg~="" then out = out .. ("|cFF%s%s|r"):format(toHex(cfg.labelColor), seg) end
      out = out .. ("|cFF%s%s|r"):format(toHex(cfg.valueColor), tostring(count))
      pos = j + 1
    end
    return out
  end
  local s=STYLE_MAP[styleID] or STYLE_MAP.TOTAL_KILLED
  local L=paint(s.label, cfg.labelColor)
  local V=paint(count,   cfg.valueColor)
  return (s.order=="count_first") and (V.." "..L) or (L..": "..V)
end
_G.DWD_MobCount_BuildKillLine = BuildLine

-- ========================= Tooltip =========================
local function readableValue(value)
  if type(issecretvalue) == "function" and issecretvalue(value) then return false end
  if type(canaccessvalue) == "function" and not canaccessvalue(value) then return false end
  return true
end

local function readString(getter, argument)
  local ok, value = pcall(getter, argument)
  if ok and readableValue(value) and type(value) == "string" and value ~= "" then
    return value
  end
end

local function displayedTooltipUnit(tt)
  -- Only use the tooltip's own unit token. The selected target and mouseover
  -- can refer to completely different units (for example a party-frame hover).
  local getter = tt and tt.GetUnit
  if type(getter) == "function" then
    local ok, _, unit = pcall(getter, tt)
    if ok and readableValue(unit) and type(unit) == "string" and unit ~= "" then
      return unit
    end
  end
  getter = TooltipUtil and TooltipUtil.GetDisplayedUnit
  if type(getter) == "function" then
    local ok, _, unit = pcall(getter, tt)
    if ok and readableValue(unit) and type(unit) == "string" and unit ~= "" then
      return unit
    end
  end
end

local function TooltipUnit(tt)
  local unit = displayedTooltipUnit(tt)
  if not unit then return end
  -- Forever may hide unit identity. Only use the GUID of the displayed unit.
  local guid = readString(UnitGUID, unit)
  if not guid then return end
  local id = npcIdFromGUID(guid)
  if not id then return end
  local ok, canAttack = pcall(UnitCanAttack, "player", unit)
  if not ok or not readableValue(canAttack) or not canAttack then return end

  local count = killsById[id] or 0
  if count > 0 and not InCombatLockdown() and (not namesById[id] or namesById[id] == "") then
    -- A kill can expose the victim's GUID before its name is readable.
    namesById[id] = readString(UnitName, unit)
  end
  tt:AddLine(BuildLine(DWD_MobCountConfig.textStyle,count),1,1,1)
  -- This callback runs while Blizzard is already building and showing the
  -- tooltip. Calling Show again is re-entrant on Forever and taints an
  -- internal Frame:RegisterEvent operation.
end

-- Never invoke RefreshData/RebuildFromTooltipInfo from addon code. The shared
-- GameTooltip may have switched to a secret aura by the next timer tick.
-- Append kill counts only when Blizzard naturally builds a unit tooltip.

local function HookTooltipsOnce()
  if tooltipHooked then return end
  local installed = false
  -- Add the line during Blizzard's native tooltip processing so its layout
  -- includes our font string inside the NineSlice border. Do not call Show()
  -- from the callback; Blizzard completes layout after post-processing.
  if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall)=="function"
  and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    installed=pcall(TooltipDataProcessor.AddTooltipPostCall,Enum.TooltipDataType.Unit,function(tooltip)
      if tooltip==GameTooltip then TooltipUnit(tooltip) end
    end)
  -- Older tooltip implementations do not have TooltipDataProcessor. Retain a
  -- method hook only as a compatibility fallback on those clients.
  elseif type(hooksecurefunc) == "function" and GameTooltip then
    if type(GameTooltip.SetWorldCursor) == "function" then
      installed = pcall(hooksecurefunc, GameTooltip, "SetWorldCursor", function(tooltip)
        TooltipUnit(tooltip)
      end)
    elseif type(GameTooltip.SetUnit) == "function" then
      installed = pcall(hooksecurefunc, GameTooltip, "SetUnit", function(tooltip)
        TooltipUnit(tooltip)
      end)
    end
  end
  tooltipHooked = installed
  if not installed and C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(1, HookTooltipsOnce)
  end
end

-- ========================= Clear / Restore =========================
ClearCharacterData = function()
  if not ensureCharTables() then return end
  snapshotLastClear()
  local store = DWD_MobCountDB[charKey]
  wipeTable(store.killsById); wipeTable(store.namesById); wipeTable(store.killsByName)
  killsById, namesById, killsByName = store.killsById, store.namesById, store.killsByName
  DWD_MobCountBackup[charKey] = { killsById={}, namesById={}, killsByName={} }
  DWD_MobCountBackup._meta = DWD_MobCountBackup._meta or {}
  DWD_MobCountBackup._meta[charKey] = { t=time and time() or 0, ver=2, cleared=true }
  if listFrame and listFrame:IsShown() and ShowList then ShowList() end
  chat("|cffffff00MobCount:|r cleared")
end

RestoreData = function()
  if not ensureCharTables() then return end
  local src = (DWD_MobCountLastClear and DWD_MobCountLastClear[charKey])
          or (DWD_MobCountBackup and DWD_MobCountBackup[charKey])
  if not src then chat("|cffffff00MobCount:|r nothing to restore"); return end
  local store = DWD_MobCountDB[charKey]
  store.killsById   = copyShallow(src.killsById   or {})
  store.namesById   = copyShallow(src.namesById   or {})
  store.killsByName = copyShallow(src.killsByName or {})
  killsById, namesById, killsByName = store.killsById, store.namesById, store.killsByName
  persistCurrentCounts()
  if listFrame and listFrame:IsShown() and ShowList then ShowList() end
  chat("|cffffff00MobCount:|r restored")
end

-- ========================= List UI =========================
local function CreateListFrame()
  local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
  local f=CreateFrame("Frame","DWD_MobCountFrame",UIParent, template)
  f:SetSize(520,430); f:SetPoint("CENTER")
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
      tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4} })
    if f.SetBackdropColor then f:SetBackdropColor(0,0,0,0.85) end
  end

  local title=f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); title:SetPoint("TOP",0,-12); title:SetText("DWD MobCount")
  local close=CreateFrame("Button",nil,f,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-4,-4)

  local function Header(text,x)
    local b=CreateFrame("Frame",nil,f); b:SetSize(160,18); b:SetPoint("TOPLEFT",x,-36)
    local fs=b:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); fs:SetPoint("LEFT",0,0); fs:SetText(text)
    local ul=b:CreateTexture(nil,"BACKGROUND"); ul:SetTexture("Interface\\Buttons\\WHITE8x8"); ul:SetVertexColor(1,1,1,0.4); ul:SetHeight(1)
    ul:SetPoint("BOTTOMLEFT",b,"BOTTOMLEFT",0,-1); ul:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",0,-1)
    return b
  end
  Header("NPC ID / Name",12); Header("Kills",360)

  local scroll=CreateFrame("ScrollFrame","DWD_MobCountScroll",f,"UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",12,-56); scroll:SetPoint("BOTTOMRIGHT",-28,52)
  local content=CreateFrame("Frame","DWD_MobCountScrollChild",scroll); content:SetSize(480,360); scroll:SetScrollChild(content)
  f.content=content; content.rows={}

  local clear=CreateFrame("Button",nil,f,"UIPanelButtonTemplate"); clear:SetSize(180,22); clear:SetPoint("BOTTOM",0,12)
  clear:SetText("Clear (This Character)")
  clear:SetScript("OnClick", function()
    if DWD_MobCountBackup._locks and DWD_MobCountBackup._locks[charKey] then chat("|cffffff00MobCount:|r cannot clear while locked (/dwdmc lock off)"); return end
    ClearCharacterData()
  end)

  f.clearBtn=clear
  f:Hide(); return f
end

ShowList = function()
  ensureCharTables()
  if not listFrame or not listFrame.content then
    listFrame = _G.DWD_MobCountFrame or CreateListFrame()
  end
  local parent=listFrame.content
  parent.rows = parent.rows or {}

  local arr={}
  for id,c in pairs(killsById) do arr[#arr+1]={name=(namesById[id] and namesById[id] ~= "" and namesById[id] or ("NPC "..id)), cnt=c} end
  for nm,c in pairs(killsByName) do arr[#arr+1]={name=nm, cnt=c} end
  table.sort(arr,function(a,b) if a.cnt==b.cnt then return a.name<b.name end return a.cnt>b.cnt end)

  for i,row in ipairs(arr) do
    local line=parent.rows[i]
    if not line then
      line=CreateFrame("Frame",nil,parent); line:SetSize(480,18)
      local left=line:CreateFontString(nil,"OVERLAY","GameFontNormal"); left:SetPoint("LEFT",0,0); left:SetWidth(340); left:SetJustifyH("LEFT"); line.left=left
      local right=line:CreateFontString(nil,"OVERLAY","GameFontNormal"); right:SetPoint("LEFT",360,0); right:SetWidth(100); right:SetJustifyH("RIGHT"); line.right=right
      parent.rows[i]=line
    end
    line:SetPoint("TOPLEFT",0,-2-(i-1)*18); line.left:SetText(row.name); line.right:SetText(row.cnt); line:Show()
  end
  for j=#arr+1,#parent.rows do parent.rows[j]:Hide() end
  parent:SetSize(480, math.max(360, (#arr)*18+6))
  listFrame:Show()
end

-- ========================= Kill attribution =========================
local function CreditKillingBlow(attackerGUID, victimGUID)
  -- PARTY_KILL supplies both GUIDs. In restricted content either may be secret.
  if not readableValue(attackerGUID) or not readableValue(victimGUID) then return end
  if type(attackerGUID) ~= "string" or attackerGUID == "" or type(victimGUID) ~= "string" then return end
  local id = npcIdFromGUID(victimGUID)
  if not id then return end
  if attackerGUID ~= readString(UnitGUID, "player")
    and attackerGUID ~= readString(UnitGUID, "pet")
    and attackerGUID ~= readString(UnitGUID, "vehicle") then return end

  local now = GetTime()
  if now >= nextKillPrune then
    for guid, timestamp in pairs(recentKills) do
      if now - timestamp >= 2 then recentKills[guid] = nil end
    end
    nextKillPrune = now + 60
  end
  local previous = recentKills[victimGUID]
  if previous and now - previous < 2 then return end
  if not ensureCharTables() then return end

  recentKills[victimGUID] = now
  local name = readString(UnitNameFromGUID, victimGUID)
  if not name and readString(UnitGUID, "target") == victimGUID then
    name = readString(UnitName, "target")
  end
  if name then namesById[id] = name end
  killsById[id] = (killsById[id] or 0) + 1
  persistCurrentCounts()
  if listFrame and listFrame:IsShown() and ShowList then ShowList() end
  dbg("credit ID", id, "name", namesById[id] or "", "total", killsById[id])
end

-- ========================= Slash (ONLY /dwdmc) =========================
SLASH_DWDMOBCOUNT1="/dwdmc"
SlashCmdList["DWDMOBCOUNT"]=function(msg)
  local m=trim(msg or ""):lower()
  local cmd, rest = m:match("^(%S+)%s*(.*)$"); cmd = cmd or ""

  if cmd=="" or cmd=="list" or cmd=="show" then
    ShowList()

  elseif cmd=="config" then
    if type(DWD_MobCount_OpenConfig)=="function" then
      DWD_MobCount_OpenConfig()
    else
      local p=_G["DWD_MobCount_TooltipOptions"]
      if p and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(p); InterfaceOptionsFrame_OpenToCategory(p)
      end
    end

  elseif cmd=="debug" then
    local a=(rest or ""):lower()
    if a=="on" or a=="1" or a=="true" then DWD_MobCountConfig.debug=true
    elseif a=="off" or a=="0" or a=="false" then DWD_MobCountConfig.debug=false
    else DWD_MobCountConfig.debug=not DWD_MobCountConfig.debug end
    chat("|cffffff00MobCount:|r debug "..(DWD_MobCountConfig.debug and "ON" or "OFF"))

  elseif cmd=="clear" or cmd=="reset" then
    if not (DWD_MobCountBackup._locks and DWD_MobCountBackup._locks[charKey]) then ClearCharacterData() end

  elseif cmd=="restore" or cmd=="undo" or cmd=="restoreclear" then
    RestoreData()

  elseif cmd=="lock" then
    DWD_MobCountBackup._locks=DWD_MobCountBackup._locks or {}
    DWD_MobCountBackup._locks[charKey]= not (DWD_MobCountBackup._locks[charKey]) or nil
    chat("|cffffff00MobCount:|r Lock "..((DWD_MobCountBackup._locks[charKey] and "ENABLED") or "DISABLED"))
  end
end

-- ========================= Events =========================
local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("PARTY_KILL")
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event=="PLAYER_LOGIN" then
    if initialized then return end
    initialized=true
    charKey = countCharacterKey()
    if not charKey then
      local nm, rm = DWD_ForeverIdentity.Get("player")
      charKey = (rm or GetRealmName() or "UnknownRealm").."-"..(nm or UnitName("player") or "Unknown")
    end
    ensureCharTables()
    persistCurrentCounts()
    HookTooltipsOnce()
    if DWD_MobCountConfig.debug then chat("|cffffff00MobCount:|r init "..charKey) end
  elseif event=="PLAYER_LOGOUT" or event=="PLAYER_LEAVING_WORLD" then
    persistCurrentCounts()
  elseif event=="PARTY_KILL" and initialized then
    CreditKillingBlow(arg1, arg2)
  end
end)
