-- DWD Tooltip Mover (Classic Era 1.15.x)
-- Move, scale, and restyle the main GameTooltip, with a small in-game GUI.

local ADDON = ...
local db

-- LibSharedMedia (optional)
local LSM = rawget(_G, "LibStub") and LibStub("LibSharedMedia-3.0", true)

-- Defaults
local DEFAULTS = {
  locked    = false,                           -- when false you can drag the anchor
  scale     = 1.00,                            -- overall tooltip scale
  fontSize  = 12,                              -- normal line font size
  fontKey   = "Friz Quadrata TT",              -- display name (LSM or builtin)
  anchor    = { point = "BOTTOMRIGHT", x = -20, y = 160 }, -- starting spot
  messageAnchor = { x = 0, y = -250 },       -- quest/error text, relative to top-center
}

-- Built-in fallback fonts (client paths)
local BUILTIN_FONTS = {
  ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
  ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
  ["Morpheus"]         = "Fonts\\MORPHEUS_CYR.TTF",
  ["Skurri"]           = "Fonts\\SKURRI.TTF",
}

-- ---------- utils ----------
local function copyInto(dst, src)
  for k,v in pairs(src) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      copyInto(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local function characterKey()
  return DWD_ForeverIdentity.Key(false)
end

-- SavedVariables are available before an addon's Lua files execute.  Initialize
-- synchronously because other addons can request a tooltip before ADDON_LOADED.
-- Keep character separation inside an account SavedVariables store because
-- Forever does not restore physical per-character files consistently.
local function initializeDatabase()
  local store = type(_G.DWD_TooltipMoverForeverStore) == "table"
    and _G.DWD_TooltipMoverForeverStore or {}
  store.characters = type(store.characters) == "table" and store.characters or {}
  _G.DWD_TooltipMoverForeverStore = store
  local key = characterKey()
  db = DWD_ForeverIdentity.Adopt(store.characters, key)
  if type(db) ~= "table" then
    db = {}
    local legacy = type(_G.DWD_TooltipMoverCharacterDB) == "table"
      and _G.DWD_TooltipMoverCharacterDB or _G.DWD_TooltipMoverDB
    if type(legacy) == "table" then copyInto(db, legacy) end
    store.characters[key] = db
  end
  _G.DWD_TooltipMoverCharacterDB = db
  _G.DWD_TooltipMoverDB = db
  copyInto(db, DEFAULTS)
end

initializeDatabase()

local function printMsg(msg)
  print("|cff00c0ffDWD Tooltip Mover:|r "..(msg or ""))
end

local function getFontPath()
  if LSM and db.fontKey then
    local p = LSM:Fetch("font", db.fontKey)
    if p then return p end
  end
  return BUILTIN_FONTS[db.fontKey] or BUILTIN_FONTS["Friz Quadrata TT"]
end

-- ---------- anchor ----------
local anchor = CreateFrame("Frame", "DWD_TooltipMover_Anchor", UIParent, "BackdropTemplate")
anchor:SetSize(200, 24)
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")
anchor:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
anchor:SetBackdropColor(0, 0.6, 1, 0.15)
anchor:Hide()

anchor.title = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
anchor.title:SetPoint("CENTER")
anchor.title:SetText("Tooltip Anchor (drag me)")

anchor:SetScript("OnDragStart", function(self)
  if not db.locked then self:StartMoving() end
end)
anchor:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, _, x, y = self:GetPoint(1)
  db.anchor.point, db.anchor.x, db.anchor.y = point, x, y
  -- IMPORTANT: do NOT SetPoint(GameTooltip) here (avoids family conflict)
end)

local function placeAnchor()
  anchor:ClearAllPoints()
  anchor:SetPoint(db.anchor.point or "BOTTOMRIGHT", UIParent, db.anchor.point or "BOTTOMRIGHT", db.anchor.x or -20, db.anchor.y or 160)
  if db.locked then anchor:Hide() else anchor:Show() end
end

-- ---------- styling ----------
local function positiveNumber(value)
  return not (type(issecretvalue) == "function" and issecretvalue(value))
    and type(value) == "number" and value > 0
end

local function effectiveScale(frame)
  local value = frame.GetEffectiveScale and frame:GetEffectiveScale()
  if positiveNumber(value) then return value end
  value = frame.GetScale and frame:GetScale() or 1
  if not positiveNumber(value) then value = 1 end
  return frame == UIParent and value or value * effectiveScale(UIParent)
end

local function applyScale(preservePosition)
  local tooltip = GameTooltip
  local oldScale = effectiveScale(tooltip)
  local points = {}
  if preservePosition and tooltip.GetNumPoints then
    for index = 1, tooltip:GetNumPoints() do
      local point, relativeTo, relativePoint, x, y = tooltip:GetPoint(index)
      if type(point) == "string" and type(x) == "number" and type(y) == "number"
        and not (type(issecretvalue) == "function" and (issecretvalue(x) or issecretvalue(y))) then
        points[#points + 1] = {point, relativeTo, relativePoint, x, y}
      end
    end
  end
  tooltip:SetScale(db.scale or 1.0)
  local newScale = effectiveScale(tooltip)
  if preservePosition and oldScale ~= newScale and #points > 0 then
    -- SetPoint offsets use the tooltip's own scaled units. Adjust only those
    -- offsets so the existing anchor stays at the same screen position.
    tooltip:ClearAllPoints()
    for _, point in ipairs(points) do
      tooltip:SetPoint(point[1], point[2], point[3], point[4] * oldScale / newScale, point[5] * oldScale / newScale)
    end
  end
end

local function setTooltipPoint(tooltip, point, x, y)
  -- Our saved anchor and cursor offsets use UIParent units, not tooltip units.
  local factor = effectiveScale(UIParent) / effectiveScale(tooltip)
  tooltip:SetPoint(point, UIParent, "BOTTOMLEFT", x * factor, y * factor)
end

-- SetFont helper — Classic can error if flags is nil, so coerce to ""
local function setFont(fs, path, size, flags)
  if not (fs and path and size) then return end
  local success, applied = pcall(fs.SetFont, fs, path, size, flags or "")
  if not success or not applied then
    pcall(fs.SetFont, fs, BUILTIN_FONTS["Friz Quadrata TT"], size, flags or "")
  end
end

-- ---------- quest/error message anchor ----------
-- Quest objective progress (for example "Lost Book: 5/6") is displayed by
-- Blizzard's UIErrorsFrame. It is unrelated to GameTooltip and has no native
-- Edit Mode control, so give it a separate, normally hidden drag anchor.
local messageAnchor = CreateFrame("Frame", "DWD_UIMessageMover_Anchor", UIParent, "BackdropTemplate")
messageAnchor:SetSize(360, 48)
messageAnchor:SetClampedToScreen(true)
messageAnchor:SetMovable(true)
messageAnchor:EnableMouse(true)
messageAnchor:RegisterForDrag("LeftButton")
messageAnchor:SetFrameStrata("DIALOG")
messageAnchor:SetBackdrop({
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets = {left=3, right=3, top=3, bottom=3},
})
messageAnchor:SetBackdropColor(0.08, 0.08, 0.08, 0.82)
messageAnchor:SetBackdropBorderColor(1, 0.82, 0, 0.9)
messageAnchor:Hide()

messageAnchor.title = messageAnchor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
messageAnchor.title:SetPoint("CENTER")
messageAnchor.title:SetText("Quest Progress Text - drag me (right-click to hide)")

local function placeMessageFrame()
  if not db then return end
  db.messageAnchor = type(db.messageAnchor) == "table" and db.messageAnchor or {}
  local x = tonumber(db.messageAnchor.x) or DEFAULTS.messageAnchor.x
  local y = tonumber(db.messageAnchor.y) or DEFAULTS.messageAnchor.y
  messageAnchor:ClearAllPoints()
  messageAnchor:SetPoint("CENTER", UIParent, "TOP", x, y)
  if UIErrorsFrame then
    pcall(UIErrorsFrame.ClearAllPoints, UIErrorsFrame)
    pcall(UIErrorsFrame.SetPoint, UIErrorsFrame, "TOP", UIParent, "TOP", x, y)
  end
end

local function testMessage()
  if UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
    UIErrorsFrame:AddMessage("Quest progress text appears here", 1, 0.82, 0, 1, 4)
  end
end

local function toggleMessageAnchor(forceShown)
  placeMessageFrame()
  local show = forceShown
  if show == nil then show = not messageAnchor:IsShown() end
  if show then
    messageAnchor:Show()
    testMessage()
  else
    messageAnchor:Hide()
  end
end

messageAnchor:SetScript("OnDragStart", function(self)
  self:StartMoving()
end)
messageAnchor:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local centerX, centerY = self:GetCenter()
  if centerX and centerY then
    db.messageAnchor.x = centerX - (UIParent:GetWidth() / 2)
    db.messageAnchor.y = centerY - UIParent:GetHeight()
  end
  placeMessageFrame()
  testMessage()
end)
messageAnchor:SetScript("OnMouseUp", function(_, button)
  if button == "RightButton" then messageAnchor:Hide() end
end)

local function scheduleMessagePosition()
  placeMessageFrame()
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(1, placeMessageFrame)
    C_Timer.After(3, placeMessageFrame)
  end
end

-- Iterate every FontString in a tooltip (catches addon-added lines too)
local function ForEachTooltipFontString(tt, fn)
  if not tt then return end
  local regions = { tt:GetRegions() }
  for _, r in ipairs(regions) do
    if r and r.GetObjectType and r:GetObjectType() == "FontString" then
      fn(r)
    end
  end
end

-- Re-style only completed tooltip line regions. Never alter Blizzard's shared
-- GameTooltip font objects: Forever uses them while processing secret data.
local function restyleTooltip(tt, base, path)
  if not tt then return end
  ForEachTooltipFontString(tt, function(fs) setFont(fs, path, base, nil) end)
end

local function applyFonts()
  local base = db.fontSize or 12
  local path = getFontPath()

  -- Main tooltip
  restyleTooltip(GameTooltip, base, path)
  -- Also style linked and shopping tooltips for consistency
  if ItemRefTooltip then restyleTooltip(ItemRefTooltip, base, path) end
  if ShoppingTooltip1 then restyleTooltip(ShoppingTooltip1, base, path) end
  if ShoppingTooltip2 then restyleTooltip(ShoppingTooltip2, base, path) end
end

-- ---------- anchoring (family-safe) ----------
-- Never connect GameTooltip's anchor family to our drag frame. Forever keeps
-- that relationship beyond ClearAllPoints and Blizzard's next world-tooltip
-- anchor then fails. Read the drag frame's coordinates, but anchor the tooltip
-- directly to UIParent so Blizzard can freely replace the point afterward.
local function isWithinFrame(candidate, root)
  if not candidate or not root then return false end
  local current = candidate
  for _ = 1, 24 do
    if current == root then return true end
    if type(current.GetParent) ~= "function" then return false end
    local ok, parent = pcall(current.GetParent, current)
    if not ok or not parent or parent == current then return false end
    current = parent
  end
  return false
end

local function isMapOrMinimapFrame(candidate)
  if not candidate then return false end
  local worldMap = rawget(_G, "WorldMapFrame")
  local minimap = rawget(_G, "Minimap")
  local minimapCluster = rawget(_G, "MinimapCluster")
  return isWithinFrame(candidate, worldMap)
    or isWithinFrame(candidate, minimap)
    or isWithinFrame(candidate, minimapCluster)
end

local function isMapTooltipContext(tt)
  if tt and type(tt.GetOwner) == "function" then
    local ok, owner = pcall(tt.GetOwner, tt)
    if ok and isMapOrMinimapFrame(owner) then return true end
  end

  -- Map-pin tooltips are not consistent about their owner. The actual mouse
  -- focus still belongs to the map/minimap hierarchy, so use it as a fallback.
  if type(GetMouseFoci) == "function" then
    local ok, targets = pcall(function() return {GetMouseFoci()} end)
    if ok then
      for _, target in ipairs(targets) do
        if isMapOrMinimapFrame(target) then return true end
      end
    end
  elseif type(GetMouseFocus) == "function" then
    local ok, target = pcall(GetMouseFocus)
    if ok and isMapOrMinimapFrame(target) then return true end
  end
  return false
end

local function applyCursorPosition(tt)
  if type(GetCursorPosition) ~= "function" then return false end
  local ok, cursorX, cursorY = pcall(GetCursorPosition)
  if not ok or not tonumber(cursorX) or not tonumber(cursorY) then return false end

  local uiScale = effectiveScale(UIParent)
  cursorX, cursorY = cursorX / uiScale, cursorY / uiScale

  applyScale()
  local tooltipScale = effectiveScale(tt) / uiScale
  local tooltipWidth = (type(tt.GetWidth) == "function" and tt:GetWidth() or 0) * tooltipScale
  local tooltipHeight = (type(tt.GetHeight) == "function" and tt:GetHeight() or 0) * tooltipScale
  local screenWidth = type(UIParent.GetWidth) == "function" and UIParent:GetWidth() or 0
  local screenHeight = type(UIParent.GetHeight) == "function" and UIParent:GetHeight() or 0
  local offset = 18
  local placeLeft = screenWidth > 0 and cursorX + tooltipWidth + offset > screenWidth
  local placeBelow = screenHeight > 0 and cursorY + tooltipHeight + offset > screenHeight

  tt:ClearAllPoints()
  if placeLeft and placeBelow then
    setTooltipPoint(tt, "TOPRIGHT", cursorX - offset, cursorY - offset)
  elseif placeLeft then
    setTooltipPoint(tt, "BOTTOMRIGHT", cursorX - offset, cursorY + offset)
  elseif placeBelow then
    setTooltipPoint(tt, "TOPLEFT", cursorX + offset, cursorY - offset)
  else
    setTooltipPoint(tt, "BOTTOMLEFT", cursorX + offset, cursorY + offset)
  end
  return true
end

local function applyTooltipPosition(tt)
  if tt ~= GameTooltip or not db then return end
  if isMapTooltipContext(tt) and applyCursorPosition(tt) then return end
  local left, bottom = anchor:GetLeft(), anchor:GetBottom()
  if not left or not bottom then return end
  applyScale()
  tt:ClearAllPoints()
  setTooltipPoint(tt, "TOPLEFT", left, bottom - 6)
end

local worldUnitTooltipActive = false
local worldUnitTooltipElapsed = 0

local function hasWorldTooltipOwner(tt)
  if not tt or type(tt.GetOwner) ~= "function" then return false end
  local ok, owner = pcall(tt.GetOwner, tt)
  if not ok then return false end
  return owner == UIParent or owner == rawget(_G, "WorldFrame") or owner == nil
end

local function updateWorldUnitTooltip(tt, elapsed)
  if not worldUnitTooltipActive or not tt or not tt:IsShown() then return end
  worldUnitTooltipElapsed = worldUnitTooltipElapsed + (tonumber(elapsed) or 0)
  if worldUnitTooltipElapsed < 0.10 then return end
  worldUnitTooltipElapsed = 0
  if isMapTooltipContext(tt) or not hasWorldTooltipOwner(tt) then return end

  -- World-unit tooltips have no ordinary button/frame OnLeave. If Blizzard no
  -- longer exposes a mouseover unit, the cursor has left the creature and a
  -- retained tooltip is stale. Keep this check out of all other tooltip types.
  local ok, mouseoverExists = pcall(UnitExists, "mouseover")
  if ok and not mouseoverExists then
    worldUnitTooltipActive = false
    pcall(tt.Hide, tt)
  end
end

-- Style only after Blizzard has finished consuming secret tooltip data.
if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
and Enum and Enum.TooltipDataType then
  local function refreshTooltip(tooltip, isUnitType)
    if tooltip == GameTooltip then
      worldUnitTooltipActive = isUnitType and not isMapTooltipContext(tooltip) or false
      worldUnitTooltipElapsed = 0
      applyTooltipPosition(tooltip)
      applyFonts()
    end
  end
  local registeredTypes = {}
  for _, dataType in pairs(Enum.TooltipDataType) do
    if type(dataType) == "number" and not registeredTypes[dataType] then
      registeredTypes[dataType] = true
      local registeredType = dataType
      local isUnitType = registeredType == Enum.TooltipDataType.Unit
      pcall(TooltipDataProcessor.AddTooltipPostCall, registeredType, function(tooltip)
        refreshTooltip(tooltip, isUnitType)
      end)
    end
  end
else
  -- Classic fallback. Unsupported script types fail inside pcall instead of
  -- aborting addon initialization.
  for _, scriptName in ipairs({"OnTooltipSetItem", "OnTooltipSetUnit", "OnTooltipSetSpell"}) do
    pcall(GameTooltip.HookScript, GameTooltip, scriptName, applyFonts)
  end
end

-- Some non-item world tooltips do not pass through TooltipDataProcessor.
-- OnShow is late enough for Blizzard to establish its safe default anchor.
if GameTooltip and type(GameTooltip.HookScript) == "function" then
  pcall(GameTooltip.HookScript, GameTooltip, "OnShow", applyTooltipPosition)
  pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function()
    worldUnitTooltipActive = false
    worldUnitTooltipElapsed = 0
  end)
  pcall(GameTooltip.HookScript, GameTooltip, "OnUpdate", updateWorldUnitTooltip)
end

-- ---------- GUI ----------
local gui -- forward ref

local function CreateLabeledSlider(parent, label, minV, maxV, step, width)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step or 0.01)
  s:SetObeyStepOnDrag(true)
  s:SetWidth(width or 220)
  s.Text:ClearAllPoints()
  s.Text:SetPoint("TOP", s, "BOTTOM", 0, -2)
  s.Text:SetText("")
  s.Low:SetText(tostring(minV))
  s.High:SetText(tostring(maxV))

  local l = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  l:SetText(label)
  l:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
  s.ValueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  s.ValueText:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 2)
  return s, l
end

local function CreateCheck(parent, text)
  local c = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  c.Text:SetText(text)
  return c
end

local function BuildFontList()
  local names = {}
  if LSM then
    for _, n in ipairs(LSM:List("font")) do table.insert(names, n) end
    table.sort(names, function(a,b) return a:lower() < b:lower() end)
  else
    for n in pairs(BUILTIN_FONTS) do table.insert(names, n) end
    table.sort(names, function(a,b) return a:lower() < b:lower() end)
  end
  return names
end

local function showGUI()
  if gui then
    gui:Show()
    gui:RefreshValues()
    return
  end

  gui = CreateFrame("Frame", "DWD_TooltipMover_Config", UIParent, "BackdropTemplate")
  gui:SetSize(420, 380)
  gui:SetPoint("CENTER")
  gui:SetMovable(true)
  gui:EnableMouse(true)
  gui:RegisterForDrag("LeftButton")
  gui:SetScript("OnDragStart", gui.StartMoving)
  gui:SetScript("OnDragStop",  gui.StopMovingOrSizing)
  gui:SetBackdrop({
    bgFile  = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile= "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile    = true, tileSize = 32, edgeSize = 32,
    insets  = {left=10,right=10,top=10,bottom=10}
  })

  -- Title
  local title = gui:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("DWD Tooltip Mover")

  -- LOCK (no separate Show Anchor button; unlock shows anchor)
  local lockCheck = CreateCheck(gui, "Lock position (hide drag anchor)")
  lockCheck:SetPoint("TOPLEFT", 24, -50)
  lockCheck:SetScript("OnClick", function(self)
    db.locked = self:GetChecked() and true or false
    placeAnchor()
  end)

  local refreshingValues = false

  -- SCALE
  local scaleSlider = CreateLabeledSlider(gui, "Tooltip Scale", 0.5, 3.0, 0.01, 340)
  scaleSlider:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 0, -28)
  scaleSlider:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v*100+0.5)/100
    self.ValueText:SetText(string.format("%.2fx (%d%%)", v, math.floor(v * 100 + 0.5)))
    if not refreshingValues then
      db.scale = v
      applyScale(true)
    end
  end)

  -- FONT SIZE
  local sizeSlider = CreateLabeledSlider(gui, "Font Size", 8, 28, 1, 340)
  sizeSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -32)
  sizeSlider:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v+0.5)
    self.ValueText:SetText(tostring(v) .. " pt")
    if not refreshingValues then
      db.fontSize = v
      applyFonts()
    end
  end)

  -- FONT DROPDOWN
  local fontLabel = gui:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fontLabel:SetText("Font:")
  fontLabel:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -26)

  local fontDD = CreateFrame("Frame", "DWD_TooltipMover_FontDropDown", gui, "UIDropDownMenuTemplate")
  fontDD:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -4)
  UIDropDownMenu_SetWidth(fontDD, 220)

  local fontNames = BuildFontList()
  local function SetFontByName(name)
    if not name then return end
    db.fontKey = name
    applyFonts()
    UIDropDownMenu_SetText(fontDD, name)
  end

  UIDropDownMenu_Initialize(fontDD, function(self, level)
    level = level or 1
    for _, name in ipairs(fontNames) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = name
      info.func = function() SetFontByName(name) end
      info.checked = (db.fontKey == name)
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  local messageBtn = CreateFrame("Button", nil, gui, "UIPanelButtonTemplate")
  messageBtn:SetSize(230, 26)
  messageBtn:SetPoint("TOPLEFT", fontDD, "BOTTOMLEFT", 16, -18)
  messageBtn:SetText("Move Quest Progress Text")
  messageBtn:SetScript("OnClick", function()
    toggleMessageAnchor()
  end)

  -- Defaults / Close (aligned, no backdrop bleed)
  local defaultsBtn = CreateFrame("Button", nil, gui, "UIPanelButtonTemplate")
  defaultsBtn:SetSize(100, 24)
  defaultsBtn:SetPoint("BOTTOMLEFT", 24, 20)
  defaultsBtn:SetText("Defaults")
  defaultsBtn:SetScript("OnClick", function()
    for k in pairs(db) do db[k] = nil end
    copyInto(db, DEFAULTS)
    placeAnchor(); applyScale(); applyFonts(); placeMessageFrame()
    gui:RefreshValues()
    printMsg("Settings reset to defaults.")
  end)

  local closeBtn = CreateFrame("Button", nil, gui, "UIPanelButtonTemplate")
  closeBtn:SetSize(100, 24)
  closeBtn:SetPoint("BOTTOMRIGHT", -24, 20)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function() gui:Hide() end)

  -- Sync widgets with DB whenever GUI opens
  function gui:RefreshValues()
    refreshingValues = true
    lockCheck:SetChecked(db.locked and true or false)
    scaleSlider:SetValue(db.scale or DEFAULTS.scale)
    sizeSlider:SetValue(db.fontSize or DEFAULTS.fontSize)
    -- SetValue need not fire OnValueChanged when the value is unchanged.
    scaleSlider.ValueText:SetText(string.format("%.2fx (%d%%)", db.scale or DEFAULTS.scale,
      math.floor((db.scale or DEFAULTS.scale) * 100 + 0.5)))
    sizeSlider.ValueText:SetText(tostring(db.fontSize or DEFAULTS.fontSize) .. " pt")
    fontNames = BuildFontList()
    UIDropDownMenu_SetText(fontDD, db.fontKey or DEFAULTS.fontKey)
    refreshingValues = false
    placeAnchor()
  end

  gui:SetScript("OnShow", function() gui:RefreshValues() end)
  -- Newly created frames may already be shown, so Show alone can skip OnShow.
  gui:RefreshValues()
  gui:Show()
end

-- ---------- slash ----------
SLASH_DWDTM1, SLASH_DWDTM2 = "/ttmove", "/tooltipmove"
SlashCmdList["DWDTM"] = function(msg)
  msg = (msg or ""):lower()
  if msg == "config" or msg == "gui" or msg == "options" then
    showGUI()
  elseif msg == "lock" then
    db.locked = true; placeAnchor(); printMsg("locked anchor.")
  elseif msg == "unlock" then
    db.locked = false; placeAnchor(); printMsg("unlocked anchor (drag to reposition).")
  elseif msg == "messages" or msg == "message" or msg == "questtext" then
    toggleMessageAnchor()
    printMsg("quest progress text anchor toggled; drag it, then right-click to hide.")
  elseif msg == "messagetest" or msg == "testmessage" then
    placeMessageFrame(); testMessage()
  elseif msg == "messagereset" then
    db.messageAnchor = {x = DEFAULTS.messageAnchor.x, y = DEFAULTS.messageAnchor.y}
    placeMessageFrame(); testMessage()
    printMsg("quest progress text position reset.")
  elseif msg:match("^scale%s+") then
    local s = tonumber(msg:match("^scale%s+([%d%.]+)"))
    if s and s >= 0.5 and s <= 3.0 then db.scale = s; applyScale(true); printMsg(("scale set to %.2f"):format(s)) end
  elseif msg:match("^fontsize%s+") then
    local n = tonumber(msg:match("^fontsize%s+([%d]+)"))
    if n and n >= 8 and n <= 28 then db.fontSize = n; applyFonts(); printMsg(("font size set to %d"):format(n)) end
  elseif msg:match("^font%s+") then
    local name = msg:match("^font%s+(.+)")
    if name and #name > 0 then db.fontKey = name; applyFonts(); printMsg("font set to "..db.fontKey) end
  elseif msg == "reset" then
    for k in pairs(db) do db[k] = nil end
    copyInto(db, DEFAULTS)
    placeAnchor(); applyScale(); applyFonts(); placeMessageFrame()
    printMsg("settings reset.")
  else
    print("|cff00c0ffDWD Tooltip Mover|r commands:")
    print("  /ttmove config    - open GUI")
    print("  /ttmove unlock    - show and drag the anchor")
    print("  /ttmove lock      - hide anchor and lock position")
    print("  /ttmove messages  - show/hide quest progress text anchor")
    print("  /ttmove messagetest")
    print("  /ttmove messagereset")
    print("  /ttmove scale N.N   (0.5–3.0)")
    print("  /ttmove fontsize NN (8–28)")
    print("  /ttmove font <Font Name> (LSM or built-in)")
    print("  /ttmove reset")
  end
  if gui and gui:IsShown() then gui:RefreshValues() end
end

-- ---------- init ----------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
f:RegisterEvent("UI_SCALE_CHANGED")
f:SetScript("OnEvent", function(_, ev, arg1)
  if ev == "ADDON_LOADED" and arg1 == ADDON then
    initializeDatabase()
  elseif ev == "PLAYER_LOGIN" then
    if not LSM and not BUILTIN_FONTS[db.fontKey] then
      db.fontKey = DEFAULTS.fontKey
    end
    placeAnchor()
    applyScale()
    applyFonts()
    scheduleMessagePosition()
  elseif ev == "PLAYER_ENTERING_WORLD" or ev == "DISPLAY_SIZE_CHANGED" or ev == "UI_SCALE_CHANGED" then
    scheduleMessagePosition()
  end
end)
