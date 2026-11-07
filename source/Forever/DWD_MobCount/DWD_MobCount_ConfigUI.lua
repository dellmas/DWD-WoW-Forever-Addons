-- DWD MobCount — Tooltip Options (Classic 1.15.7)

DWD_MobCountConfig = DWD_MobCountConfig or {
  textStyle  = "TOTAL_KILLED",
  labelColor = { r=1, g=0.82, b=0 },
  valueColor = { r=1, g=1,    b=1 },
  customTextEnabled = false,
  customText = "",
}

-- ---------- forward declarations ----------
local preview      -- sample line at the bottom
local customBox    -- edit box for custom wording
local dropdown

-- ---------- Color picker helpers ----------
local function EnsureColorPicker()
  if not ColorPickerFrame or not ColorPickerFrame.GetColorRGB then
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn or UIParentLoadAddOn
    if type(load) == "function" then pcall(load, "Blizzard_ColorPicker") end
  end
end

-- Classic callbacks return r, g, b separately; Forever's modern picker passes
-- a single color table to cancelFunc. Accept both layouts.
local function NormalizeColor(r, g, b, fallback)
  if type(r) == "table" then
    local color = r
    r, g, b = color.r or color[1], color.g or color[2], color.b or color[3]
  end
  fallback = fallback or { r=1, g=1, b=1 }
  return tonumber(r) or fallback.r, tonumber(g) or fallback.g, tonumber(b) or fallback.b
end

local function OpenPicker(current, onPicked, onCancel)
  EnsureColorPicker()
  if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({
      r=current.r, g=current.g, b=current.b, hasOpacity=false,
      swatchFunc=function()
        local r,g,b=ColorPickerFrame:GetColorRGB()
        r,g,b=NormalizeColor(r,g,b,current)
        onPicked(r,g,b)
      end,
      cancelFunc=function(pr,pg,pb)
        if onCancel then
          pr,pg,pb=NormalizeColor(pr,pg,pb,current)
          onCancel(pr,pg,pb)
        end
      end,
    })
  else
    ColorPickerFrame.hasOpacity=false
    ColorPickerFrame.previousValues={ r=current.r,g=current.g,b=current.b }
    ColorPickerFrame.func=function()
      local r,g,b=ColorPickerFrame:GetColorRGB()
      r,g,b=NormalizeColor(r,g,b,current)
      onPicked(r,g,b)
    end
    ColorPickerFrame.cancelFunc=function(prev)
      if onCancel then
        local r,g,b=NormalizeColor(prev,nil,nil,current)
        onCancel(r,g,b)
      end
    end
    ColorPickerFrame:SetColorRGB(current.r,current.g,current.b); ColorPickerFrame:Show()
  end
end

-- Fallback builder if core hasn’t loaded yet
if not DWD_MobCount_BuildKillLine then
  local function toHex(c) local r=math.floor(((c.r or 1)*255)+0.5) local g=math.floor(((c.g or 1)*255)+0.5) local b=math.floor(((c.b or 1)*255)+0.5) return string.format("%02X%02X%02X", r,g,b) end
  local MAP={
    KILLED={label="Killed",order="label_first"}, TOTAL_KILLED={label="Total Killed",order="label_first"},
    COUNT_KILLED={label="Killed",order="count_first"}, SLAIN={label="Slain",order="label_first"},
    TOTAL_SLAIN={label="Total Slain",order="label_first"}, COUNT_SLAIN={label="Slain",order="count_first"},
    YEETED={label="Yeeted",order="label_first"}, TOTAL_YEETED={label="Total Yeeted",order="label_first"},
    COUNT_YEETED={label="Yeeted",order="count_first"},
  }
  function DWD_MobCount_BuildKillLine(styleID,count)
    local s=MAP[styleID] or MAP.TOTAL_KILLED
    local L=("|cFF%s%s|r"):format(toHex(DWD_MobCountConfig.labelColor), s.label)
    local V=("|cFF%s%s|r"):format(toHex(DWD_MobCountConfig.valueColor), tostring(count))
    return (s.order=="count_first") and (V.." "..L) or (L..": "..V)
  end
end

-- ---------- Panel ----------
local PANEL_NAME = "DWD MobCount - Tooltip"
-- Keep the Settings canvas anonymous. DWD Profiles intentionally discovers
-- conventional *Options globals for future addons; a globally named Frame can
-- otherwise be mistaken for serializable settings and restored as a Lua table.
local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
panel.name = PANEL_NAME
panel:SetSize(470,300)
panel:SetPoint("CENTER")
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart",panel.StartMoving)
panel:SetScript("OnDragStop",panel.StopMovingOrSizing)
panel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,insets={left=8,right=8,top=8,bottom=8}})
local close=CreateFrame("Button",nil,panel,"UIPanelCloseButton")
close:SetPoint("TOPRIGHT",-4,-4)
panel:Hide()

-- Title
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("DWD MobCount — Tooltip Options")

-- Wording dropdown
local ddLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
ddLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
ddLabel:SetText("Tooltip Wording")

dropdown = CreateFrame("Frame", "DWD_MobCount_WordingDD", panel, "UIDropDownMenuTemplate")
dropdown:SetPoint("TOPLEFT", ddLabel, "BOTTOMLEFT", -16, -6)

local STYLE_OPTIONS = {
  { key="KILLED",        label="Killed: {count}"       },
  { key="TOTAL_KILLED",  label="Total Killed: {count}" },
  { key="COUNT_KILLED",  label="{count} Killed"        },
  { key="SLAIN",         label="Slain: {count}"        },
  { key="TOTAL_SLAIN",   label="Total Slain: {count}"  },
  { key="COUNT_SLAIN",   label="{count} Slain"         },
  { key="YEETED",        label="Yeeted: {count}"       },
  { key="TOTAL_YEETED",  label="Total Yeeted: {count}" },
  { key="COUNT_YEETED",  label="{count} Yeeted"        },
}

local function SetDDText(text)
  local fs=_G[dropdown:GetName().."Text"]; if fs then fs:SetText(text) end
end

local function OnSelect(_, key)
  DWD_MobCountConfig.textStyle = key
  for _,opt in ipairs(STYLE_OPTIONS) do if opt.key==key then SetDDText(opt.label) break end end
  if preview then preview:SetText(DWD_MobCount_BuildKillLine(DWD_MobCountConfig.textStyle, 123)) end
end

local function InitializeDropdown(_, level)
  for _,opt in ipairs(STYLE_OPTIONS) do
    local info=UIDropDownMenu_CreateInfo()
    info.text, info.value, info.func, info.arg1, info.checked =
      opt.label, opt.key, OnSelect, opt.key, (DWD_MobCountConfig.textStyle==opt.key)
    UIDropDownMenu_AddButton(info, level)
  end
end

UIDropDownMenu_Initialize(dropdown, InitializeDropdown)
dropdown:SetScript("OnShow", function() UIDropDownMenu_Initialize(dropdown, InitializeDropdown) end)
do
  local shown="Total Killed: {count}"
  for _,o in ipairs(STYLE_OPTIONS) do if o.key==DWD_MobCountConfig.textStyle then shown=o.label break end end
  SetDDText(shown)
end

-- Label color
local labelTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
labelTitle:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 32, -14)
labelTitle:SetText("Label Color (e.g., 'Total Killed')")

local labelSwatch = CreateFrame("Button", "DWD_MobCount_LabelSwatch", panel)
labelSwatch:SetPoint("TOPLEFT", labelTitle, "BOTTOMLEFT", 0, -6)
labelSwatch:SetSize(16, 16)
labelSwatch:SetNormalTexture("Interface\\ChatFrame\\ChatFrameColorSwatch")
labelSwatch:GetNormalTexture():SetVertexColor(DWD_MobCountConfig.labelColor.r, DWD_MobCountConfig.labelColor.g, DWD_MobCountConfig.labelColor.b)
labelSwatch:SetScript("OnClick", function()
  local c = DWD_MobCountConfig.labelColor
  OpenPicker(c,
    function(r,g,b) DWD_MobCountConfig.labelColor={r=r,g=g,b=b}; labelSwatch:GetNormalTexture():SetVertexColor(r,g,b); if preview then preview:SetText(DWD_MobCount_BuildKillLine(DWD_MobCountConfig.textStyle,123)) end end,
    function(r,g,b) DWD_MobCountConfig.labelColor={r=r,g=g,b=b}; labelSwatch:GetNormalTexture():SetVertexColor(r,g,b); if preview then preview:SetText(DWD_MobCount_BuildKillLine(DWD_MobCountConfig.textStyle,123)) end end
  )
end)

-- Value color
local valueTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
valueTitle:SetPoint("TOPLEFT", labelSwatch, "BOTTOMLEFT", 0, -16)
valueTitle:SetText("Number Color (e.g., '0')")

local valueSwatch = CreateFrame("Button", "DWD_MobCount_ValueSwatch", panel)
valueSwatch:SetPoint("TOPLEFT", valueTitle, "BOTTOMLEFT", 0, -6)
valueSwatch:SetSize(16, 16)
valueSwatch:SetNormalTexture("Interface\\ChatFrame\\ChatFrameColorSwatch")
valueSwatch:GetNormalTexture():SetVertexColor(DWD_MobCountConfig.valueColor.r, DWD_MobCountConfig.valueColor.g, DWD_MobCountConfig.valueColor.b)
valueSwatch:SetScript("OnClick", function()
  local c = DWD_MobCountConfig.valueColor
  OpenPicker(c,
    function(r,g,b) DWD_MobCountConfig.valueColor={r=r,g=g,b=b}; valueSwatch:GetNormalTexture():SetVertexColor(r,g,b); if preview then preview:SetText(DWD_MobCount_BuildKillLine(DWD_MobCountConfig.textStyle,123)) end end,
    function(r,g,b) DWD_MobCountConfig.valueColor={r=r,g=g,b=b}; valueSwatch:GetNormalTexture():SetVertexColor(r,g,b); if preview then preview:SetText(DWD_MobCount_BuildKillLine(DWD_MobCountConfig.textStyle,123)) end end
  )
end)

-- Custom wording toggle + input
local customChk = CreateFrame("CheckButton", "DWD_MobCount_CustomEnable", panel, "InterfaceOptionsCheckButtonTemplate")
customChk:SetPoint("TOPLEFT", valueSwatch, "BOTTOMLEFT", -2, -18)
_G[customChk:GetName().."Text"]:SetText("Use custom wording")
customChk:SetChecked(DWD_MobCountConfig.customTextEnabled or false)
customChk:SetScript("OnClick", function(self)
  local on = self:GetChecked() and true or false
  DWD_MobCountConfig.customTextEnabled = on
  if customBox then customBox:SetEnabled(on) end
  if preview and DWD_MobCount_BuildKillLine then
    preview:SetText(DWD_MobCount_BuildKillLine(DWD_MobCountConfig.textStyle, 123))
  end
end)

local customLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
customLbl:SetPoint("TOPLEFT", customChk, "BOTTOMLEFT", 4, -8)
customLbl:SetText("Custom text (use {count})")

customBox = CreateFrame("EditBox", "DWD_MobCount_CustomText", panel, "InputBoxTemplate")
customBox:SetAutoFocus(false)
customBox:SetPoint("TOPLEFT", customLbl, "BOTTOMLEFT", 0, -6)
customBox:SetSize(320, 24)
customBox:SetMaxLetters(128)
customBox:SetText(DWD_MobCountConfig.customText or "")
customBox:SetCursorPosition(0)
customBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
customBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
customBox:SetScript("OnShow", function(self)
  self:SetText(DWD_MobCountConfig.customText or "")
  self:SetEnabled(DWD_MobCountConfig.customTextEnabled and true or false)
end)
customBox:SetScript("OnTextChanged", function(self)
  if not self:IsEnabled() then return end
  DWD_MobCountConfig.customText = self:GetText() or ""
  if preview and DWD_MobCount_BuildKillLine then
    preview:SetText(DWD_MobCount_BuildKillLine(DWD_MobCountConfig.textStyle, 123))
  end
end)

-- Sample preview (bottom)
preview = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
preview:SetPoint("TOPLEFT", customBox, "BOTTOMLEFT", 0, -20)
preview:SetText(DWD_MobCount_BuildKillLine(DWD_MobCountConfig.textStyle, 123))

-- Register the completed canvas with the same modern Settings API used by
-- PartyXP Forever.  Earlier versions only created this frame, so it could be
-- opened as a loose window but never appeared under Options -> AddOns.
if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" then
  local category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME)
  Settings.RegisterAddOnCategory(category)
  panel._category = category
  if category then
    if type(category.GetID) == "function" then
      panel._categoryID = category:GetID()
    elseif type(category.ID) == "number" then
      panel._categoryID = category.ID
    end
  end

  -- The Settings window owns panel placement and closing when embedded.
  panel:SetMovable(false)
  panel:SetScript("OnDragStart", nil)
  panel:SetScript("OnDragStop", nil)
  close:Hide()
elseif InterfaceOptions_AddCategory then
  InterfaceOptions_AddCategory(panel)
end

function DWD_MobCount_OpenConfig()
  if Settings and type(Settings.OpenToCategory) == "function" then
    local id = panel._categoryID
    if type(id) ~= "number" and panel._category then
      if type(panel._category.GetID) == "function" then
        id = panel._category:GetID()
      elseif type(panel._category.ID) == "number" then
        id = panel._category.ID
      end
    end
    if type(id) == "number" then
      Settings.OpenToCategory(id)
      return
    end
  end

  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
  else
    panel:Show()
  end
end
