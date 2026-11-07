local ADDON, A = ...
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local controls, refreshing = {}, false

local function label(parent, value, x, y, width, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width or 320)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(color or {0.85, 0.9, 0.9}))
    fs:SetText(value)
    return fs
end

local function fill(parent, color)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(WHITE)
    bg:SetVertexColor(unpack(color))
    return bg
end

local function button(parent, title, x, y, width, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 160, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(title)
    b:SetScript("OnClick", callback)
    return b
end

local function refreshControls()
    refreshing = true
    for _, update in ipairs(controls) do update() end
    refreshing = false
end

local function checkbox(parent, title, x, y, getter, setter)
    local b = CreateFrame("CheckButton", nil, parent)
    b:SetSize(24, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    b:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    label(b, title, 28, -5, 320)
    b:SetScript("OnClick", function(self)
        setter(not not self:GetChecked())
        A:Refresh()
    end)
    controls[#controls + 1] = function() b:SetChecked(getter()) end
    return b
end

local function slider(parent, title, x, y, low, high, step, getter, setter)
    label(parent, title, x, y, 235)
    local value = label(parent, "", x + 244, y, 70)
    value:SetJustifyH("RIGHT")
    local s = CreateFrame("Slider", nil, parent)
    s:SetSize(310, 16)
    s:SetPoint("TOPLEFT", x, y - 23)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(low, high)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = fill(s, {0.12, 0.2, 0.21, 1})
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(10, 18)
    thumb:SetVertexColor(0.12, 0.9, 0.7, 1)
    s:SetScript("OnValueChanged", function(_, v)
        local rounded = math.floor(v / step + 0.5) * step
        value:SetText(step < 1 and string.format("%.2f", rounded) or tostring(rounded))
        if not refreshing then setter(rounded) A:Refresh() end
    end)
    controls[#controls + 1] = function() s:SetValue(getter()) end
    return s
end

local function cycle(parent, title, x, y, choices, getter, setter)
    label(parent, title, x, y, 310)
    local b
    b = button(parent, "", x, y - 21, 310, function()
        local nextIndex = 1
        for i, choice in ipairs(choices) do
            if choice == getter() then nextIndex = i % #choices + 1 break end
        end
        setter(choices[nextIndex])
        b:SetText(getter() .. "  >")
        A:Refresh()
    end)
    controls[#controls + 1] = function() b:SetText(getter() .. "  >") end
end

local function edit(parent, title, x, y, width, getter, setter)
    label(parent, title, x, y, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 24)
    box:SetPoint("TOPLEFT", x + 5, y - 24)
    box:SetAutoFocus(false)
    box:SetMaxLetters(96)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not refreshing then setter(A.CleanText(self:GetText())) A:Refresh() end
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    controls[#controls + 1] = function()
        if not box:HasFocus() then box:SetText(getter()) end
    end
    return box
end

local function colorButton(parent, title, x, y, getter, setter)
    local swatch
    local b
    b = button(parent, title, x, y, 180, function()
        local current = getter()
        if ColorPickerFrame and type(ColorPickerFrame.SetupColorPickerAndShow) == "function" then
            local old = {current[1], current[2], current[3]}
            ColorPickerFrame:SetupColorPickerAndShow({r = old[1], g = old[2], b = old[3], hasOpacity = false,
                swatchFunc = function()
                    local r, g, blue = ColorPickerFrame:GetColorRGB()
                    setter({r, g, blue})
                    refreshControls()
                    A:Refresh()
                end,
                cancelFunc = function() setter(old) refreshControls() A:Refresh() end,
            })
        else
            -- Still usable when the modern color picker has not loaded.
            local palette = {{0.12, 0.95, 0.75}, {0.3, 0.7, 1}, {1, 0.6, 0.12}, {0.85, 0.4, 1}, {1, 1, 1}}
            b.paletteIndex = (b.paletteIndex or 0) % #palette + 1
            setter(palette[b.paletteIndex])
            refreshControls()
            A:Refresh()
        end
    end)
    swatch = b:CreateTexture(nil, "OVERLAY")
    swatch:SetTexture(WHITE)
    swatch:SetPoint("RIGHT", b, "RIGHT", -9, 0)
    swatch:SetSize(13, 13)
    controls[#controls + 1] = function()
        local c = getter()
        swatch:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

local function getter(scope, key)
    return function() return A:DB()[scope][key] end
end
local function setter(scope, key)
    return function(v) A:DB()[scope][key] = v end
end

function A:RefreshPreview(db)
    if not self.preview or not self.options:IsShown() then return end
    local member1 = {index = 1, name = "Party Member", role = "TANK", classColor = {0.41, 0.8, 0.94}}
    local member3 = {index = 3, name = "Second Member", role = "DAMAGER"}
    self:RenderTargets(self.preview.target.visuals, self.preview.target, {member1, member3}, db)
    self:RenderFriend(self.preview.friend.visuals, self.preview.friend, member1, db)
end

local function previewPlate(parent, x, y, name, color)
    local plate = CreateFrame("Frame", nil, parent)
    plate:SetPoint("TOPLEFT", x, y)
    plate:SetSize(150, 20)
    plate.unitFrame = CreateFrame("Frame", nil, plate)
    plate.unitFrame:SetAllPoints()
    plate.unitFrame.healthBar = CreateFrame("Frame", nil, plate.unitFrame)
    plate.unitFrame.healthBar:SetAllPoints()
    fill(plate.unitFrame.healthBar, color)
    local n = label(plate, name, 0, 18, 200, 12, {1, 1, 1})
    plate.visuals = A:CreateVisuals(plate)
    return plate
end

local function buildGeneral(p)
    label(p, "Two independent overlays", 18, -8, 650, 17, {0.2, 1, 0.8})
    label(p, "Target markers show which mob each party member selected. Party decorations add a design and label around the party member's own nameplate.", 18, -38, 680)
    checkbox(p, "Enable DWD Party Highlight", 18, -89, function() return A:DB().enabled end,
        function(v) A:DB().enabled = v end)
    checkbox(p, "Show party members' target markers", 18, -121, getter("targets", "enabled"), setter("targets", "enabled"))
    checkbox(p, "Decorate party members' own nameplates", 18, -153, getter("friends", "enabled"), setter("friends", "enabled"))
    label(p, "Friendly player nameplates must be enabled in WoW (normally Shift+V). Hidden, out-of-range, phased-out and forbidden plates cannot be decorated. No nameplate settings are changed by this addon.", 18, -197, 680)
    label(p, "LIVE STYLE PREVIEW  (sample plates)", 18, -267, 680, 13, {0.5, 0.75, 0.7})
    local area = CreateFrame("Frame", nil, p)
    area:SetPoint("TOPLEFT", 18, -295)
    area:SetSize(680, 170)
    fill(area, {0.035, 0.075, 0.08, 1})
    label(area, "Two party members targeting one mob", 25, -13, 300, 11)
    label(area, "Added to a party member's plate", 355, -13, 300, 11)
    A.preview = {
        target = previewPlate(area, 85, -112, "Targeted mob", {0.5, 0.12, 0.13, 1}),
        friend = previewPlate(area, 420, -112, "Party Member", {0.13, 0.36, 0.6, 1}),
    }
    label(p, "Both party members need this addon only if they each want to see highlights. It does not require addon messaging or change anyone's selected target.", 18, -482, 680, 11)
end

local function buildTargets(p)
    label(p, "Party target markers", 18, -8, 680, 17, {0.2, 1, 0.8})
    label(p, "Every party member on the same mob gets a separate colored marker. P1-P4 follow your current party order.", 18, -38, 680)
    checkbox(p, "Show arrows", 18, -77, getter("targets", "arrow"), setter("targets", "arrow"))
    checkbox(p, "Show labels", 380, -77, getter("targets", "text"), setter("targets", "text"))
    cycle(p, "Arrow design (click to cycle)", 18, -121, A.arrows, getter("targets", "arrowType"), setter("targets", "arrowType"))
    edit(p, "Target label template", 380, -121, 310, getter("targets", "template"), setter("targets", "template"))
    slider(p, "Arrow size", 18, -190, 10, 64, 1, getter("targets", "size"), setter("targets", "size"))
    slider(p, "Label font size", 380, -190, 8, 30, 1, getter("targets", "fontSize"), setter("targets", "fontSize"))
    slider(p, "Marker left / right", 18, -253, -150, 150, 1, getter("targets", "offsetX"), setter("targets", "offsetX"))
    slider(p, "Label up / down", 380, -253, -60, 60, 1, getter("targets", "textY"), setter("targets", "textY"))
    slider(p, "Marker up / down", 18, -316, -80, 120, 1, getter("targets", "offsetY"), setter("targets", "offsetY"))
    slider(p, "Space between markers", 380, -316, 0, 40, 1, getter("targets", "spacing"), setter("targets", "spacing"))
    checkbox(p, "Pulse markers", 18, -384, getter("targets", "pulse"), setter("targets", "pulse"))
    checkbox(p, "Glow behind the plate", 380, -384, getter("targets", "glow"), setter("targets", "glow"))
    slider(p, "Glow opacity", 380, -425, 0, 1, 0.05, getter("targets", "glowAlpha"), setter("targets", "glowAlpha"))
    label(p, "Template tokens: {slot}, {name}, {role}. Example: P{slot} or {name}. Markers disappear when a member changes or clears their target.", 18, -495, 680, 11)
end

local function buildFriends(p)
    label(p, "Party member decorations", 18, -8, 680, 17, {0.2, 1, 0.8})
    label(p, "Only addon-owned lines and text are drawn. Existing health bars, names, textures, colors and targeting behavior stay under WoW / Plater's control.", 18, -38, 680)
    cycle(p, "Surrounding design (click to cycle)", 18, -82, A.styles, getter("friends", "style"), setter("friends", "style"))
    cycle(p, "Decoration color source", 380, -82, {"Custom", "Party slot", "Class"}, getter("friends", "colorMode"), setter("friends", "colorMode"))
    slider(p, "Design width", 18, -145, 50, 350, 1, getter("friends", "width"), setter("friends", "width"))
    slider(p, "Design height", 380, -145, 10, 100, 1, getter("friends", "height"), setter("friends", "height"))
    slider(p, "Left / right", 18, -208, -150, 150, 1, getter("friends", "offsetX"), setter("friends", "offsetX"))
    slider(p, "Up / down", 380, -208, -100, 100, 1, getter("friends", "offsetY"), setter("friends", "offsetY"))
    slider(p, "Line thickness", 18, -271, 1, 6, 1, getter("friends", "thickness"), setter("friends", "thickness"))
    slider(p, "Space around design", 380, -271, 0, 25, 1, getter("friends", "padding"), setter("friends", "padding"))
    slider(p, "Opacity", 18, -334, 0.1, 1, 0.05, getter("friends", "alpha"), setter("friends", "alpha"))
    colorButton(p, "Custom color", 380, -334, getter("friends", "color"), setter("friends", "color"))
    checkbox(p, "Pulse decoration", 380, -374, getter("friends", "pulse"), setter("friends", "pulse"))
    label(p, "Use design 'None' for text-only markers. Party labels and per-slot overrides are on the next tab. You can preview every design on the General tab without joining a party.", 18, -432, 680)
end

local function buildLabels(p)
    label(p, "Party labels and slot colors", 18, -8, 680, 17, {0.2, 1, 0.8})
    checkbox(p, "Show added text above party plates", 18, -43, getter("friends", "text"), setter("friends", "text"))
    edit(p, "Default party label", 18, -88, 310, getter("friends", "template"), setter("friends", "template"))
    label(p, "Tokens: {name}, {slot}, {role}\nExamples: Cousin, PARTY {slot}, >> {name} <<", 380, -88, 310)
    slider(p, "Text size", 18, -158, 8, 30, 1, getter("friends", "fontSize"), setter("friends", "fontSize"))
    slider(p, "Text left / right", 380, -158, -150, 150, 1, getter("friends", "textX"), setter("friends", "textX"))
    slider(p, "Text up / down", 18, -221, -80, 100, 1, getter("friends", "textY"), setter("friends", "textY"))
    label(p, "Optional labels follow slots P1-P4 as the roster changes. Leave blank to use the default party label. Slot colors also color the target arrows.", 18, -287, 680, 11)
    for i = 1, 4 do
        local index = i
        local y = -338 - (i - 1) * 48
        colorButton(p, "P" .. i .. " color", 18, y, function() return A:DB().colors[index] end,
            function(v) A:DB().colors[index] = v end)
        edit(p, "", 228, y + 24, 452, function() return A:DB().labels[index] end,
            function(v) A:DB().labels[index] = v end)
    end
end

function A:OpenOptions(tab)
    if not self.options then
        local p = CreateFrame("Frame", "DWDPartyHighlightForeverOptions", UIParent)
        self.options = p
        p:SetSize(760, 680)
        p:SetPoint("CENTER")
        p:SetScale(math.min(1, (UIParent:GetHeight() - 60) / 680))
        p:SetFrameStrata("DIALOG")
        p:SetClampedToScreen(true)
        p:SetMovable(true)
        p:EnableMouse(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", p.StartMoving)
        p:SetScript("OnDragStop", p.StopMovingOrSizing)
        fill(p, {0.035, 0.06, 0.065, 0.98})
        label(p, "DWD Party Highlight - Forever", 20, -17, 640, 20, {0.2, 1, 0.8})
        label(p, self.version, 20, -45, 180, 10, {0.5, 0.7, 0.7})
        button(p, "X", 710, -12, 30, function() p:Hide() end)
        local tabs, pages = {}, {}
        local builders = {buildGeneral, buildTargets, buildFriends, buildLabels}
        local names = {"General / Preview", "Target Markers", "Party Members", "Labels / Colors"}
        self.SelectTab = function(_, index)
            for i, page in ipairs(pages) do page:SetShown(i == index) end
            for i, b in ipairs(tabs) do
                b:SetAlpha(i == index and 1 or 0.65)
            end
            A.selectedTab = index
            refreshControls()
            A:RefreshPreview(A:DB())
        end
        for i, title in ipairs(names) do
            local index = i
            local page = CreateFrame("Frame", nil, p)
            page:SetPoint("TOPLEFT", 12, -98)
            page:SetSize(736, 540)
            page:Hide()
            pages[i] = page
            tabs[i] = button(p, title, 18 + (i - 1) * 182, -66, 178, function() A:SelectTab(index) end)
            builders[i](page)
        end
        -- Reset never reloads the game or changes any other addon.
        local armed = false
        local reset
        reset = button(p, "Reset this addon", 548, -643, 190, function()
            if not armed then armed = true reset:SetText("Click again to reset") return end
            armed = false
            A:Reset()
            refreshControls()
            reset:SetText("Reset this addon")
        end)
        p:SetScript("OnShow", function() armed = false reset:SetText("Reset this addon") refreshControls() A:Refresh() end)
        p:SetScript("OnHide", function()
            -- Stop preview animations while the panel is closed.
            for _, plate in pairs(A.preview or {}) do
                plate.visuals.targets.animation:Stop()
                plate.visuals.friend.animation:Stop()
            end
        end)
        if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "DWDPartyHighlightForeverOptions" end
        self:SelectTab(1)
    elseif self.options:IsShown() and not tab then self.options:Hide() return end
    if tab then self:SelectTab(tab) end
    self.options:Show()
    self:RefreshPreview(self:DB())
end
